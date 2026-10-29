import Foundation
import Testing
@testable import AppFolderKit

@Suite("Widget shared storage")
struct WidgetStorageTests {
    private let container = URL(fileURLWithPath: "/test/app-group", isDirectory: true)

    @Test("Without a group container, writable defaults do not imply shared storage")
    func missingContainerRefusesPrivateFallback() {
        var requestedDefaults = false
        let storage = WidgetState.sharedStorage(groupContainer: nil) {
            requestedDefaults = true
            return MemoryDefaults()
        }

        #expect(!storage.isAvailable)
        #expect(!requestedDefaults, "missing entitlement must be rejected before opening a suite")
        storage.defaults.set("private-grid", forKey: "widget.directLaunchKey")
        storage.defaults.set(3, forKey: "widget.expandedPage")
        storage.defaults.set(["app": 123], forKey: "widget.directLaunchOverrides")
        storage.defaults.set(Data([1, 2, 3]), forKey: "widget.directLaunchSlots")
        #expect(storage.defaults.object(forKey: "widget.directLaunchKey") == nil)
        #expect(storage.defaults.string(forKey: "widget.directLaunchKey") == nil)
        #expect(storage.defaults.integer(forKey: "widget.expandedPage") == 0)
        #expect(storage.defaults.dictionary(forKey: "widget.directLaunchOverrides") == nil)
        #expect(storage.defaults.data(forKey: "widget.directLaunchSlots") == nil)
    }

    @Test("A group container alone does not make a missing defaults suite available")
    func missingSuiteIsUnavailable() {
        let storage = WidgetState.sharedStorage(groupContainer: container) { nil }
        #expect(!storage.isAvailable)
    }

    @Test("A failed defaults roundtrip is unavailable and cleans up its probe")
    func failedRoundtripIsUnavailable() {
        let defaults = MemoryDefaults()
        defaults.allowsReads = false
        let storage = WidgetState.sharedStorage(groupContainer: container) { defaults }

        #expect(!storage.isAvailable)
        #expect(defaults.values.isEmpty)
        #expect(storage.defaults !== defaults, "a failed suite must not leak through the fallback")
    }

    @Test("A real container and successful roundtrip select exactly the shared suite")
    func workingSharedStorageIsSelected() {
        let defaults = MemoryDefaults()
        defaults.set("existing-value", forKey: "existing-key")
        let storage = WidgetState.sharedStorage(groupContainer: container) { defaults }

        #expect(storage.isAvailable)
        #expect(storage.defaults === defaults)
        #expect(defaults.values.count == 1, "the probe is temporary and preserves existing state")
        #expect(storage.defaults.string(forKey: "existing-key") == "existing-value")
    }

    /// Only the methods exercised by the resolver are needed; no test writes a
    /// real preferences suite or requires an App Group entitlement on the host.
    private final class MemoryDefaults: UserDefaults {
        var values: [String: Any] = [:]
        var allowsReads = true

        override func set(_ value: Any?, forKey defaultName: String) {
            values[defaultName] = value
        }

        override func removeObject(forKey defaultName: String) {
            values.removeValue(forKey: defaultName)
        }

        override func string(forKey defaultName: String) -> String? {
            allowsReads ? values[defaultName] as? String : nil
        }
    }
}
