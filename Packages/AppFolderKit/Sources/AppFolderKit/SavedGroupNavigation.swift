import Foundation

/// Transient navigation for a saved layout. Group content stays in its own store.
/// A complete record is written under one defaults key so path and page cannot
/// be observed halfway through an update. The lock serializes calls within this
/// process; UserDefaults does not provide a cross-process compare-and-set.
public enum SavedGroupNavigation {
    public struct Snapshot: Codable, Sendable, Equatable {
        public let path: [UUID]
        public let page: Int

        public init(path: [UUID] = [], page: Int = 0) {
            self.path = path
            self.page = page
        }

        public static let root = Snapshot()
    }

    public static let maximumDepth = 4
    private static let lock = NSLock()

    public static func state(for key: String) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return store.state(for: key)
    }

    public static func encodePath(_ path: [UUID]) -> String {
        path.map(\.uuidString).joined(separator: "/")
    }

    /// Acts only on the path/page the button actually displayed. A second tap
    /// from the same old snapshot cannot advance or enter a different folder.
    /// The provider validates the target's ancestry against the current layout.
    @discardableResult
    public static func navigate(
        key: String,
        expectedPath: String,
        expectedPage: Int,
        targetPath: String,
        targetPage: Int
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return store.navigate(
            key: key, expectedPath: expectedPath, expectedPage: expectedPage,
            targetPath: targetPath, targetPage: targetPage
        ) {
            // A deliberate new tap wins over an older foreground collapse that
            // WidgetKit has not rendered yet. Do not consume it for a stale tap.
            WidgetState.seenCollapseRequest = WidgetState.collapseRequest
        }
    }

    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        store.reset()
    }

    private static var store: SavedGroupNavigationStore {
        SavedGroupNavigationStore(defaults: WidgetState.widgetDefaults,
                                  isAvailable: WidgetState.widgetStateIsAvailable)
    }
}

/// Injectable storage for navigation regressions, independent of real preferences.
struct SavedGroupNavigationStore {
    static let storageKey = "widget.savedGroupNavigation"
    private static let maximumBytes = 8_192
    private static let maximumPage = 10_000
    let defaults: UserDefaults
    let isAvailable: Bool

    struct Record: Codable, Equatable {
        let version: Int
        let key: String
        let snapshot: SavedGroupNavigation.Snapshot

        init(key: String, snapshot: SavedGroupNavigation.Snapshot) {
            version = 1
            self.key = key
            self.snapshot = snapshot
        }
    }

    func state(for key: String) -> SavedGroupNavigation.Snapshot {
        guard isAvailable, Self.validKey(key), let record = read(), record.key == key else { return .root }
        return record.snapshot
    }

    @discardableResult
    func navigate(
        key: String,
        expectedPath: String,
        expectedPage: Int,
        targetPath: String,
        targetPage: Int,
        willCommit: () -> Void = {}
    ) -> Bool {
        guard isAvailable, Self.validKey(key),
              let expected = Self.snapshot(path: expectedPath, page: expectedPage),
              let target = Self.snapshot(path: targetPath, page: targetPage),
              state(for: key) == expected, expected != target
        else { return false }
        let record = Record(key: key, snapshot: target)
        guard let data = try? JSONEncoder().encode(record), data.count <= Self.maximumBytes else { return false }
        willCommit()
        defaults.set(data, forKey: Self.storageKey)
        return defaults.data(forKey: Self.storageKey) == data
    }

    func reset() {
        guard isAvailable else { return }
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func read() -> Record? {
        guard let data = defaults.data(forKey: Self.storageKey), data.count <= Self.maximumBytes,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 1, Self.validKey(record.key), Self.valid(record.snapshot)
        else { return nil }
        return record
    }

    private static func validKey(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 2_048
    }

    private static func valid(_ snapshot: SavedGroupNavigation.Snapshot) -> Bool {
        snapshot.path.count <= SavedGroupNavigation.maximumDepth
            && Set(snapshot.path).count == snapshot.path.count
            && (0...maximumPage).contains(snapshot.page)
    }

    private static func snapshot(path: String, page: Int) -> SavedGroupNavigation.Snapshot? {
        guard path.utf8.count <= SavedGroupNavigation.maximumDepth * 37 else { return nil }
        let parts = path.isEmpty ? [] : path.split(separator: "/", omittingEmptySubsequences: false)
        let ids = parts.compactMap { UUID(uuidString: String($0)) }
        guard ids.count == parts.count else { return nil }
        let snapshot = SavedGroupNavigation.Snapshot(path: ids, page: page)
        return valid(snapshot) ? snapshot : nil
    }
}
