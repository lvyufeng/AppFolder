import Foundation

/// Coordinates one website-launch view's explicit or fresh automatic request.
/// Callers claim before re-reading the saved node and check `canOpen` immediately
/// before presenting Safari or asking the system to open an external browser.
public struct WebsiteLaunchGuard: Sendable {
    public struct Attempt: Sendable, Equatable {
        fileprivate let id: UUID
        fileprivate let generation: UUID
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
            hasBeenActive = true
        }
    }

    public mutating func disappeared() {
        isVisible = false
        invalidate()
    }

    /// Queueing or replacing a request also revokes an automatic claim already
    /// awaiting a read, while preserving a separate explicit retry's claim.
    public mutating func disableAutomatic() {
        automaticPending = false
        if currentAttempt?.automatically == true { generation = UUID() }
    }

    public mutating func begin(
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
            guard automaticAllowed, Self.allowsAutomatic(age: age) else { return nil }
        } else {
            automaticPending = false
        }
        let attempt = Attempt(id: UUID(), generation: generation, automatically: automatically)
        currentAttempt = attempt
        return attempt
    }

    public func canOpen(_ attempt: Attempt, age: Duration, isActive: Bool) -> Bool {
        guard currentAttempt == attempt, isVisible, isActive, generation == attempt.generation else { return false }
        return !attempt.automatically || Self.allowsAutomatic(age: age)
    }

    /// A completion for an invalidated request cannot release a newer claim.
    public mutating func finish(_ attempt: Attempt) {
        if currentAttempt == attempt { currentAttempt = nil }
    }

    private mutating func invalidate() {
        automaticPending = false
        generation = UUID()
        // Keep the in-flight latch until its owner finishes, even if a scene
        // change or dismissal has invalidated the claim's permission to open.
    }

    private static func allowsAutomatic(age: Duration) -> Bool {
        age >= .zero && age <= .seconds(15)
    }
}
