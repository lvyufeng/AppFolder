import Darwin
import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group configuration reports")
struct SavedGroupBindingReportTests {
    @Test("All required names are checked once, including off-page nested actions")
    func reportsActualBindingFailures() throws {
        let group = SavedGroup(name: "Daily", items: [
            .action(name: "Maps"), .action(name: " maps "),
            .folder(name: "Work", children: [.action(name: "Calendar"), .action(name: "Mail")]),
            .spacer(),
        ])
        let report = try #require(SavedGroupBindingReport(group: group, configurationKey: "a", grid: .four,
                                                          familyRawValue: 0, actionNames: ["MAPS", "Mail", " mail "]))
        #expect(report.requiredNames == ["Maps", "Calendar", "Mail"])
        #expect(report.actions.first?.status == .ready)
        #expect(report.missingNames == ["Calendar"])
        #expect(report.ambiguousNames == ["Mail"])
        #expect(!report.isReady)
        #expect(report.matches(group))
        let empty = try #require(SavedGroupBindingReport(group: SavedGroup(name: "Empty"), configurationKey: "b",
                                                         grid: .nine, familyRawValue: 0, actionNames: []))
        #expect(!empty.isReady, "an empty layout must not show a successful action check")
    }

    @Test("Different configurations remain separate and survive a new process reader")
    func isolatesConfigurations() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedGroupBindingReportRepository(directory: directory)
        let group = sampleGroup()
        let ready = try report(group, key: "four-ready", names: ["Maps"], at: 10)
        let missing = try report(group, key: "nine-missing", names: [], grid: .nine, at: 20)
        #expect(store.record(ready))
        #expect(store.record(missing))
        let restored = SavedGroupBindingReportRepository(directory: directory).all
        #expect(restored == [missing, ready])
        #expect(restored.filter(\.isReady).count == 1)
        #expect(restored.map(\.grid) == [.nine, .four])
        let earlier = try report(group, key: "nine-missing", names: ["Maps"], grid: .nine, at: 5)
        #expect(store.record(earlier))
        #expect(store.all == restored, "an earlier timeline cannot replace newer diagnostics")
    }

    @Test("Changed layouts and incomplete records never validate a current group")
    func invalidatesRevisions() throws {
        let group = sampleGroup()
        let ready = try report(group, key: "a", names: ["Maps"])
        #expect(ready.isReady && ready.matches(group))
        var draft = group
        draft.items.append(.action(name: "Calendar"))
        #expect(!ready.matches(draft))
        draft = group
        draft.name = "Renamed"
        #expect(!ready.matches(draft))
        draft = group
        draft.updatedAt = .now.addingTimeInterval(500)
        #expect(ready.matches(draft), "a no-op save should not invalidate identical content")

        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ready)) as? [String: Any])
        json["actions"] = []
        let incomplete = try JSONDecoder().decode(SavedGroupBindingReport.self,
                                                  from: JSONSerialization.data(withJSONObject: json))
        #expect(!incomplete.matches(group))
        #expect(!incomplete.isReady)
    }

    @Test("Only the latest 24 configurations are retained, with bounded on-disk data")
    func boundsHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedGroupBindingReportRepository(directory: directory)
        let names = (0..<200).map { String(repeating: "😀", count: 76) + String($0) }
        let group = SavedGroup(name: "Large", items: names.map { .action(name: $0) })
        for index in 0..<28 {
            #expect(store.record(try report(group, key: "configuration-\(index)", names: names, at: Double(index))))
        }
        #expect(store.all.count == SavedGroupBindingReportStore.maximumReports)
        #expect(store.all.first?.configurationKey == "configuration-27")
        #expect(store.all.last?.configurationKey == "configuration-4")
        #expect(store.all.allSatisfy { $0.isReady && $0.actions.count == 200 })
        let data = try Data(contentsOf: directory.appendingPathComponent("reports.json"))
        #expect(data.count <= SavedGroupBindingReportRepository.maximumFileBytes)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("SystemShortcut"))
        #expect(!text.contains("appStoreID"))
    }

    @Test("Corrupt, oversized and unavailable storage cannot produce ready results")
    func invalidStorage() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SavedGroupBindingReportRepository(directory: directory)
        let file = directory.appendingPathComponent("reports.json")
        let ready = try report(sampleGroup(), key: "a", names: ["Maps"])
        for data in [Data("broken JSON".utf8), Data(repeating: 0, count: SavedGroupBindingReportRepository.maximumFileBytes + 1)] {
            try data.write(to: file)
            #expect(store.all.isEmpty)
            #expect(store.record(ready), "diagnostic history can recover without touching durable layouts")
            #expect(store.all == [ready])
        }
        let unavailable = SavedGroupBindingReportRepository(directory: nil)
        #expect(!unavailable.record(ready))
        #expect(unavailable.all.isEmpty)
        #expect(SavedGroupBindingReport(group: sampleGroup(), configurationKey: "", grid: .four,
                                        familyRawValue: 0, actionNames: []) == nil)
    }

    @Test("A busy writer skips diagnostics without corrupting the previous report")
    func concurrentWriterIsNonblocking() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedGroupBindingReportRepository(directory: directory)
        let group = sampleGroup()
        let first = try report(group, key: "first", names: ["Maps"])
        #expect(store.record(first))
        let descriptor = open(directory.appendingPathComponent("write.lock").path, O_RDWR)
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        let other = SavedGroupBindingReportRepository(directory: directory)
        let second = try report(group, key: "second", names: [])
        #expect(!other.record(second))
        #expect(other.all == [first])
        #expect(flock(descriptor, LOCK_UN) == 0)
        #expect(other.record(second))
        #expect(other.all.count == 2)
    }

    private func sampleGroup() -> SavedGroup { SavedGroup(name: "Daily", items: [.action(name: "Maps")]) }
    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func report(_ group: SavedGroup, key: String, names: [String], grid: FolderGrid = .four,
                        at: Double = 10) throws -> SavedGroupBindingReport {
        try #require(SavedGroupBindingReport(group: group, configurationKey: key, grid: grid,
                                            familyRawValue: 0, actionNames: names,
                                            checkedAt: Date(timeIntervalSince1970: at)))
    }
}
