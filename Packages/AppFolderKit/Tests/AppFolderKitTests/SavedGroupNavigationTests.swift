import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group navigation")
struct SavedGroupNavigationTests {
    private let folder = UUID()
    private let child = UUID()
    private let key = "group-revision-grid-actions"

    @Test("Entering nested folders and returning preserves the requested parent page")
    func nestedNavigation() {
        let store = memoryStore()
        let path = SavedGroupNavigation.encodePath([folder])
        let childPath = SavedGroupNavigation.encodePath([folder, child])
        #expect(store.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: path, targetPage: 0))
        #expect(store.navigate(key: key, expectedPath: path, expectedPage: 0, targetPath: path, targetPage: 2))
        #expect(store.navigate(key: key, expectedPath: path, expectedPage: 2, targetPath: childPath, targetPage: 0))
        #expect(store.state(for: key) == .init(path: [folder, child], page: 0))
        #expect(store.navigate(key: key, expectedPath: childPath, expectedPage: 0, targetPath: path, targetPage: 2))
        #expect(store.state(for: key) == .init(path: [folder], page: 2))
    }

    @Test("A replayed tap and a tap from an earlier page are ignored")
    func staleControlsDoNothing() {
        let store = memoryStore()
        let path = SavedGroupNavigation.encodePath([folder])
        #expect(store.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: path, targetPage: 0))
        var acknowledged = false
        #expect(!store.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: path, targetPage: 0) {
            acknowledged = true
        })
        #expect(!acknowledged, "a stale control cannot consume a pending collapse request")
        #expect(store.navigate(key: key, expectedPath: path, expectedPage: 0, targetPath: path, targetPage: 1))
        #expect(!store.navigate(key: key, expectedPath: path, expectedPage: 0, targetPath: path, targetPage: 1))
        #expect(store.state(for: key).page == 1)
    }

    @Test("Other layouts start at root and cannot inherit another layout's folder")
    func separateKeys() {
        let store = memoryStore()
        let path = SavedGroupNavigation.encodePath([folder])
        #expect(store.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: path, targetPage: 1))
        #expect(store.state(for: "different") == .root)
        #expect(!store.navigate(key: "different", expectedPath: path, expectedPage: 1, targetPath: "", targetPage: 0))
        #expect(store.navigate(key: "different", expectedPath: "", expectedPage: 0, targetPath: path, targetPage: 0))
        #expect(store.state(for: key) == .root)
    }

    @Test("Malformed path, repeated ancestor and invalid page cannot be stored")
    func rejectsInvalidTargets() {
        let store = memoryStore()
        let badPaths = ["not-a-uuid", "\(folder)/", "/\(folder)",
                        SavedGroupNavigation.encodePath([folder, folder]),
                        SavedGroupNavigation.encodePath((0..<5).map { _ in UUID() })]
        for path in badPaths {
            #expect(!store.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: path, targetPage: 0))
        }
        for page in [-1, 10_001] {
            #expect(!store.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: "", targetPage: page))
        }
        #expect(!store.navigate(key: "", expectedPath: "", expectedPage: 0, targetPath: "", targetPage: 1))
        #expect(!store.navigate(key: key, expectedPath: "", expectedPage: -1, targetPath: "", targetPage: 1))
        #expect(store.state(for: key) == .root)
    }

    @Test("Unreadable storage refuses changes and no-op navigation spends no reload")
    func unavailableAndNoOp() {
        let defaults = MemoryDefaults()
        let unavailable = SavedGroupNavigationStore(defaults: defaults, isAvailable: false)
        #expect(!unavailable.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: "", targetPage: 1))
        #expect(defaults.values.isEmpty)
        let store = SavedGroupNavigationStore(defaults: defaults, isAvailable: true)
        var acknowledged = false
        #expect(!store.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: "", targetPage: 0) {
            acknowledged = true
        })
        #expect(!acknowledged)
        defaults.refusesWrites = true
        #expect(!store.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: "", targetPage: 1))
        #expect(store.state(for: key) == .root)
    }

    @Test("One stored record survives a new reader and reset returns every key to root")
    func persistenceAndReset() {
        let defaults = MemoryDefaults()
        let first = SavedGroupNavigationStore(defaults: defaults, isAvailable: true)
        let path = SavedGroupNavigation.encodePath([folder])
        #expect(first.navigate(key: key, expectedPath: "", expectedPage: 0, targetPath: path, targetPage: 3))
        #expect(defaults.values.count == 1)
        let second = SavedGroupNavigationStore(defaults: defaults, isAvailable: true)
        #expect(second.state(for: key) == .init(path: [folder], page: 3))
        second.reset()
        #expect(first.state(for: key) == .root)
        #expect(defaults.values.isEmpty)
    }

    @Test("Corrupt, future-schema and oversized navigation data safely read as root")
    func corruptRecords() throws {
        let defaults = MemoryDefaults()
        let store = SavedGroupNavigationStore(defaults: defaults, isAvailable: true)
        let record = SavedGroupNavigationStore.Record(key: key, snapshot: .init(path: [folder], page: 2))
        let data = try JSONEncoder().encode(record)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 999
        let fixtures = [Data("broken".utf8), try JSONSerialization.data(withJSONObject: json), Data(repeating: 0, count: 8_193)]
        for fixture in fixtures {
            defaults.set(fixture, forKey: SavedGroupNavigationStore.storageKey)
            #expect(store.state(for: key) == .root)
        }
    }

    private func memoryStore() -> SavedGroupNavigationStore {
        SavedGroupNavigationStore(defaults: MemoryDefaults(), isAvailable: true)
    }

    private final class MemoryDefaults: UserDefaults {
        var values: [String: Data] = [:]
        var refusesWrites = false

        override func data(forKey defaultName: String) -> Data? { values[defaultName] }
        override func set(_ value: Any?, forKey defaultName: String) {
            if !refusesWrites { values[defaultName] = value as? Data }
        }
        override func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
    }
}
