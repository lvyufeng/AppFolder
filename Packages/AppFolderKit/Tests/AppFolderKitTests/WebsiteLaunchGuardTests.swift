import Testing
@testable import AppFolderKit

@Suite("Website launch guard")
struct WebsiteLaunchGuardTests {
    @Test("Cold routes wait for activation, claim synchronously once and expire while awaiting a saved-node read")
    func coldRouteAndDeadline() throws {
        var state = WebsiteLaunchGuard()
        #expect(state.begin(automatically: true, automaticAllowed: true, age: .zero, isActive: true) == nil)
        state.appeared(isActive: false)
        state.sceneChanged(isActive: false, isBackground: false)
        #expect(state.begin(automatically: true, automaticAllowed: true, age: .seconds(1), isActive: false) == nil)
        state.sceneChanged(isActive: true, isBackground: false)
        let attemptClaim = state.begin(automatically: true, automaticAllowed: true, age: .seconds(14), isActive: true)
        let attempt = try #require(attemptClaim)
        #expect(state.isOpening && state.canOpen(attempt, age: .seconds(15), isActive: true))
        #expect(state.begin(automatically: false, automaticAllowed: true, age: .seconds(14), isActive: true) == nil)
        #expect(!state.canOpen(attempt, age: .seconds(15) + .nanoseconds(1), isActive: true))
        #expect(!state.canOpen(attempt, age: .nanoseconds(-1), isActive: true))
        state.finish(attempt)
        #expect(state.begin(automatically: true, automaticAllowed: true, age: .seconds(14), isActive: true) == nil)
        let retryClaim = state.begin(automatically: false, automaticAllowed: false, age: .seconds(3_600), isActive: true)
        let retry = try #require(retryClaim)
        state.finish(attempt)
        #expect(state.isOpening && state.canOpen(retry, age: .seconds(3_601), isActive: true))
        state.finish(retry)
        #expect(!state.isOpening)
    }

    @Test("Queued, expired and future-dated automatic requests require an explicit retry")
    func automaticEligibility() throws {
        for (allowed, age): (Bool, Duration) in [(false, .zero), (true, .seconds(16)), (true, .nanoseconds(-1))] {
            var state = WebsiteLaunchGuard()
            state.appeared(isActive: true)
            #expect(state.begin(automatically: true, automaticAllowed: allowed, age: age, isActive: true) == nil)
            #expect(state.begin(automatically: true, automaticAllowed: true, age: .zero, isActive: true) == nil)
            let manualClaim = state.begin(automatically: false, automaticAllowed: false, age: .seconds(100), isActive: true)
            let manual = try #require(manualClaim)
            #expect(state.canOpen(manual, age: .seconds(101), isActive: true))
        }
    }

    @Test("Scene interruptions and disappearance revoke in-flight claims without releasing the double-tap latch")
    func interruptions() throws {
        for automatic in [false, true] {
            for interruption in 0...2 {
                var state = WebsiteLaunchGuard()
                state.appeared(isActive: true)
                let attemptClaim = state.begin(automatically: automatic, automaticAllowed: true, age: .zero, isActive: true)
                let attempt = try #require(attemptClaim)
                if interruption == 2 { state.disappeared() }
                else { state.sceneChanged(isActive: false, isBackground: interruption == 1) }
                state.appeared(isActive: true)
                state.sceneChanged(isActive: true, isBackground: false)
                #expect(state.isOpening && !state.canOpen(attempt, age: .seconds(1), isActive: true))
                #expect(state.begin(automatically: false, automaticAllowed: true, age: .seconds(1), isActive: true) == nil)
                state.finish(attempt)
                #expect(state.begin(automatically: true, automaticAllowed: true, age: .seconds(1), isActive: true) == nil)
                #expect(state.begin(automatically: false, automaticAllowed: false, age: .seconds(1), isActive: true) != nil)
            }
        }
        var cold = WebsiteLaunchGuard()
        cold.appeared(isActive: false)
        cold.sceneChanged(isActive: false, isBackground: true)
        cold.sceneChanged(isActive: true, isBackground: false)
        #expect(cold.begin(automatically: true, automaticAllowed: true, age: .zero, isActive: true) == nil)
    }

    @Test("Disabling automatic permission revokes only automatic claims; foreign completions release neither")
    func cancellationAndForeignClaims() throws {
        var other = WebsiteLaunchGuard()
        other.appeared(isActive: true)
        let foreignClaim = other.begin(automatically: false, automaticAllowed: false, age: .zero, isActive: true)
        let foreign = try #require(foreignClaim)
        for automatic in [false, true] {
            var state = WebsiteLaunchGuard()
            state.appeared(isActive: true)
            let attemptClaim = state.begin(automatically: automatic, automaticAllowed: true, age: .zero, isActive: true)
            let attempt = try #require(attemptClaim)
            state.disableAutomatic()
            state.finish(foreign)
            #expect(state.isOpening && !state.canOpen(foreign, age: .zero, isActive: true))
            #expect(state.canOpen(attempt, age: .zero, isActive: true) == !automatic)
            state.finish(attempt)
            #expect(state.begin(automatically: true, automaticAllowed: true, age: .zero, isActive: true) == nil)
        }
    }
}
