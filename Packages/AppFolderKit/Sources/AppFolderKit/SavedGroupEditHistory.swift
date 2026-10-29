/// Bounded undo/redo for an editor draft. Snapshots retain raw input, identities,
/// aliases and appearance; history never validates or normalizes user edits.
public struct SavedGroupEditHistory: Sendable {
    public let capacity: Int
    private var undoSnapshots: [SavedGroup] = []
    private var redoSnapshots: [SavedGroup] = []
    private var coalescing: Coalescing?

    private struct Coalescing: Sendable {
        let key: String
        let after: SavedGroup
    }

    /// A nonpositive capacity disables recording while preserving normal edit
    /// behavior. The limit applies to retained undo steps, including merged edits.
    public init(capacity: Int = 50) {
        self.capacity = max(0, capacity)
    }

    public var canUndo: Bool { !undoSnapshots.isEmpty }
    public var canRedo: Bool { !redoSnapshots.isEmpty }

    /// The editor combines these with its current draft when updating its asset
    /// lease. Snapshots hold only digests, never photo bytes.
    public var coverAssetIDs: Set<FolderCoverAssetID> {
        (undoSnapshots + redoSnapshots).reduce(into: Set<FolderCoverAssetID>()) {
            $0.formUnion($1.coverAssetIDs)
        }
    }

    /// Returns whether the snapshots differ. A genuine edit clears redo even
    /// when it merges into an existing step or history recording is disabled.
    /// No-ops leave both stacks and the current coalescing session unchanged.
    @discardableResult
    public mutating func record(
        before: SavedGroup,
        after: SavedGroup,
        coalescingKey: String? = nil
    ) -> Bool {
        guard before != after else { return false }
        redoSnapshots.removeAll(keepingCapacity: true)
        guard capacity > 0 else {
            endCoalescing()
            return true
        }

        if let key = coalescingKey, let previous = coalescing,
           previous.key == key, previous.after == before, let original = undoSnapshots.last {
            if after == original {
                // A drag or typing session that returns to its starting value
                // should not leave a redundant undo step behind.
                undoSnapshots.removeLast()
                endCoalescing()
            } else {
                coalescing = Coalescing(key: key, after: after)
            }
            return true
        }

        undoSnapshots.append(before)
        if undoSnapshots.count > capacity {
            undoSnapshots.removeFirst(undoSnapshots.count - capacity)
        }
        coalescing = coalescingKey.map { Coalescing(key: $0, after: after) }
        return true
    }

    public mutating func endCoalescing() {
        coalescing = nil
    }

    /// Captures the actual current draft for redo, including any raw text the
    /// caller is holding outside its otherwise-valid model.
    public mutating func undo(current: SavedGroup) -> SavedGroup? {
        endCoalescing()
        guard let previous = undoSnapshots.popLast() else { return nil }
        redoSnapshots.append(current)
        return previous
    }

    public mutating func redo(current: SavedGroup) -> SavedGroup? {
        endCoalescing()
        guard let next = redoSnapshots.popLast() else { return nil }
        undoSnapshots.append(current)
        return next
    }
}
