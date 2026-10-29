import Foundation

/// Coordinates one contact-launch view's explicit or fresh automatic request.
/// This value performs no I/O and never opens a URL. Callers re-read the saved
/// endpoint, then check `canOpen` immediately before handing it to the system.
public struct ContactLaunchGuard: Sendable {
    /// An opaque claim that cannot be constructed or modified by callers.
    public struct Attempt: Sendable, Equatable {
        fileprivate let id: UUID
        fileprivate let generation: UUID
        fileprivate let operation: ContactTarget.Operation
        fileprivate let automatically: Bool
    }

    public private(set) var isVisible = false
    public var isOpening: Bool { currentAttempt != nil }
    private var automaticPending = true
    private var hasBeenActive = false
    private var generation = UUID()
    private var currentAttempt: Attempt?

    public init() {}

    public mutating func appeared(isActive: Bool) {
        isVisible = true
        if isActive { hasBeenActive = true }
    }

    public mutating func sceneChanged(isActive: Bool, isBackground: Bool) {
        if isBackground || (!isActive && hasBeenActive) {
            invalidate()
        } else if isActive {
            // A cold route may arrive while its scene is still inactive.
            hasBeenActive = true
        }
    }

    public mutating func disappeared() {
        isVisible = false
        invalidate()
    }

    /// Also invalidates an automatic claim already waiting on a read. A manual
    /// claim remains valid, and neither case releases the in-flight latch.
    public mutating func disableAutomatic() {
        automaticPending = false
        if currentAttempt?.automatically == true { generation = UUID() }
    }

    /// Claims synchronously before an asynchronous read. Failed automatic
    /// eligibility is consumed once; first cold activation is still allowed
    /// when an earlier call was invisible, inactive, or busy.
    public mutating func begin(
        operation: ContactTarget.Operation,
        automatically: Bool,
        automaticAllowed: Bool,
        age: Duration,
        isActive: Bool
    ) -> Attempt? {
        guard isVisible, isActive, currentAttempt == nil else { return nil }
        hasBeenActive = true
        if automatically {
            guard automaticPending else { return nil }
            automaticPending = false
            guard automaticAllowed, Self.allowsAutomatic(operation: operation, age: age) else { return nil }
        } else {
            automaticPending = false
        }
        let attempt = Attempt(id: UUID(), generation: generation, operation: operation, automatically: automatically)
        currentAttempt = attempt
        return attempt
    }

    public func canOpen(_ attempt: Attempt, age: Duration, isActive: Bool) -> Bool {
        guard currentAttempt == attempt, isVisible, isActive, generation == attempt.generation else { return false }
        return !attempt.automatically || Self.allowsAutomatic(operation: attempt.operation, age: age)
    }

    /// A stale completion must never release a newer request's latch.
    public mutating func finish(_ attempt: Attempt) {
        if currentAttempt == attempt { currentAttempt = nil }
    }

    private mutating func invalidate() {
        automaticPending = false
        generation = UUID()
        // Keep the claim until its owner finishes, even when cancellation or a
        // scene transition makes it ineligible to open.
    }

    private static func allowsAutomatic(operation: ContactTarget.Operation, age: Duration) -> Bool {
        (operation == .phone || operation == .message) && age >= .zero && age <= .seconds(15)
    }
}
