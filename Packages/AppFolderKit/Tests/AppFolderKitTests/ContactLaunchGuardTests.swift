import Testing
@testable import AppFolderKit

@Suite("Contact launch guard")
struct ContactLaunchGuardTests {
    @Test("A fresh cold route waits for first activation and can claim automatic opening only once")
    func firstActivation() throws {
        var state = ContactLaunchGuard()
        #expect(!state.isVisible && !state.isOpening)
        let hidden = state.begin(operation: .phone, automatically: true, automaticAllowed: true, age: .zero, isActive: true)
        #expect(hidden == nil)
        state.appeared(isActive: false)
        state.sceneChanged(isActive: false, isBackground: false)
        let inactive = state.begin(operation: .phone, automatically: true, automaticAllowed: true, age: .seconds(1), isActive: false)
        #expect(inactive == nil && !state.isOpening)
        state.sceneChanged(isActive: true, isBackground: false)
        let claimed = state.begin(operation: .phone, automatically: true, automaticAllowed: true, age: .seconds(2), isActive: true)
        let attempt = try #require(claimed)
        #expect(state.isVisible && state.isOpening)
        #expect(state.canOpen(attempt, age: .seconds(3), isActive: true))
        state.finish(attempt)
        let again = state.begin(operation: .phone, automatically: true, automaticAllowed: true, age: .seconds(4), isActive: true)
        #expect(again == nil && !state.isOpening)
    }

    @Test("Automatic opening is restricted to fresh phone and message requests", arguments: ContactTarget.Operation.allCases)
    func operationEligibility(operation: ContactTarget.Operation) throws {
        var state = ContactLaunchGuard()
        state.appeared(isActive: true)
        let automatic = state.begin(operation: operation, automatically: true, automaticAllowed: true, age: .seconds(15), isActive: true)
        if operation == .phone || operation == .message {
            let attempt = try #require(automatic)
            #expect(state.canOpen(attempt, age: .seconds(15), isActive: true))
            #expect(!state.canOpen(attempt, age: .nanoseconds(-1), isActive: true))
            #expect(!state.canOpen(attempt, age: .seconds(15) + .nanoseconds(1), isActive: true))
            state.finish(attempt)
        } else {
            #expect(automatic == nil && !state.isOpening)
        }
        let retryAuto = state.begin(operation: .phone, automatically: true, automaticAllowed: true, age: .seconds(1), isActive: true)
        #expect(retryAuto == nil)
        let manual = state.begin(operation: operation, automatically: false, automaticAllowed: false, age: .seconds(3_600), isActive: true)
        let attempt = try #require(manual)
        #expect(state.canOpen(attempt, age: .seconds(3_601), isActive: true))
    }

    @Test("Queued, expired and future-dated requests consume automatic eligibility but allow an explicit retry")
    func rejectedAutomatic() throws {
        for (allowed, age): (Bool, Duration) in [(false, .zero), (true, .seconds(16)), (true, .nanoseconds(-1))] {
            var state = ContactLaunchGuard()
            state.appeared(isActive: true)
            let rejected = state.begin(operation: .message, automatically: true, automaticAllowed: allowed, age: age, isActive: true)
            #expect(rejected == nil && !state.isOpening)
            let cannotRequalify = state.begin(operation: .message, automatically: true, automaticAllowed: true, age: .zero, isActive: true)
            #expect(cannotRequalify == nil)
            let retry = state.begin(operation: .message, automatically: false, automaticAllowed: false, age: .seconds(86_400), isActive: true)
            let attempt = try #require(retry)
            #expect(state.canOpen(attempt, age: .seconds(86_401), isActive: true))
        }
    }

    @Test("Leaving active while reading prevents opening after reactivation and does not release the latch", arguments: [false, true])
    func sceneInterruptions(background: Bool) throws {
        for automatic in [false, true] {
            var state = ContactLaunchGuard()
            state.appeared(isActive: true)
            let claimed = state.begin(operation: .phone, automatically: automatic, automaticAllowed: true, age: .zero, isActive: true)
            let attempt = try #require(claimed)
            state.sceneChanged(isActive: false, isBackground: background)
            #expect(state.isOpening && !state.canOpen(attempt, age: .seconds(1), isActive: false))
            state.sceneChanged(isActive: true, isBackground: false)
            #expect(!state.canOpen(attempt, age: .seconds(2), isActive: true))
            let whileBusy = state.begin(operation: .phone, automatically: false, automaticAllowed: false, age: .seconds(2), isActive: true)
            #expect(whileBusy == nil && state.isOpening)
            state.finish(attempt)
            #expect(!state.isOpening)
            let cannotResume = state.begin(operation: .phone, automatically: true, automaticAllowed: true, age: .seconds(3), isActive: true)
            #expect(cannotResume == nil)
            let explicitRetry = state.begin(operation: .phone, automatically: false, automaticAllowed: false, age: .seconds(3), isActive: true)
            #expect(explicitRetry != nil)
        }
    }

    @Test("Background before first active and disappear/reappear never revive automatic eligibility")
    func earlyBackgroundAndDismissal() throws {
        for background in [false, true] {
            var state = ContactLaunchGuard()
            state.appeared(isActive: false)
            if background { state.sceneChanged(isActive: false, isBackground: true) }
            else { state.disappeared() }
            state.appeared(isActive: true)
            state.sceneChanged(isActive: true, isBackground: false)
            let automatic = state.begin(operation: .message, automatically: true, automaticAllowed: true, age: .zero, isActive: true)
            #expect(automatic == nil)
            let manual = state.begin(operation: .message, automatically: false, automaticAllowed: false, age: .zero, isActive: true)
            let attempt = try #require(manual)
            state.disappeared()
            #expect(!state.isVisible && state.isOpening)
            state.appeared(isActive: true)
            #expect(!state.canOpen(attempt, age: .zero, isActive: true))
            state.finish(attempt)
            #expect(!state.isOpening)
        }
    }

    @Test("Synchronous claims prevent double taps; old and foreign completions cannot clear a newer attempt")
    func synchronousClaim() throws {
        var state = ContactLaunchGuard()
        state.appeared(isActive: true)
        let firstClaim = state.begin(operation: .faceTimeVideo, automatically: false, automaticAllowed: false, age: .zero, isActive: true)
        let first = try #require(firstClaim)
        let doubleTap = state.begin(operation: .faceTimeVideo, automatically: false, automaticAllowed: false, age: .zero, isActive: true)
        #expect(doubleTap == nil && state.isOpening)
        #expect(!state.canOpen(first, age: .zero, isActive: false))
        state.finish(first)
        let secondClaim = state.begin(operation: .faceTimeVideo, automatically: false, automaticAllowed: false, age: .seconds(30), isActive: true)
        let second = try #require(secondClaim)
        #expect(first != second)
        state.finish(first)
        #expect(state.isOpening && state.canOpen(second, age: .seconds(31), isActive: true))
        #expect(!state.canOpen(first, age: .seconds(31), isActive: true))
        var other = ContactLaunchGuard()
        other.appeared(isActive: true)
        let otherClaim = other.begin(operation: .faceTimeVideo, automatically: false, automaticAllowed: false, age: .zero, isActive: true)
        let foreign = try #require(otherClaim)
        state.finish(foreign)
        #expect(state.isOpening && !state.canOpen(foreign, age: .zero, isActive: true))
        state.finish(second)
        #expect(!state.isOpening && !state.canOpen(second, age: .zero, isActive: true))
    }

    @Test("Disabling automatic operation cancels its pending or reading claim without cancelling manual intent")
    func disableAutomatic() throws {
        var pending = ContactLaunchGuard()
        pending.appeared(isActive: true)
        pending.disableAutomatic()
        let disabled = pending.begin(operation: .phone, automatically: true, automaticAllowed: true, age: .zero, isActive: true)
        #expect(disabled == nil)
        for automatic in [false, true] {
            var state = ContactLaunchGuard()
            state.appeared(isActive: true)
            let claimed = state.begin(operation: .message, automatically: automatic, automaticAllowed: true, age: .zero, isActive: true)
            let attempt = try #require(claimed)
            state.disableAutomatic()
            #expect(state.isOpening)
            #expect(state.canOpen(attempt, age: .zero, isActive: true) == !automatic)
            state.finish(attempt)
            let cannotRestart = state.begin(operation: .message, automatically: true, automaticAllowed: true, age: .zero, isActive: true)
            #expect(cannotRestart == nil)
        }
    }
}
