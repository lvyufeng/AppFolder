import Foundation
import Testing
@testable import AppFolderKit

@Suite("Website inbox draft import")
struct ShareInboxImportTests {
    @Test("A batch appends in selection order with stable IDs and one reversible tree edit")
    func orderedBatchAndHistory() throws {
        let first = try entry("https://example.com/first", title: "First")
        let second = try entry("https://example.com/second", title: "Second")
        let folder = GroupItem.folder(name: "Sites", children: [.spacer()])
        let original = SavedGroup(name: "Daily", items: [folder, .action(name: "Maps")])
        let result = try ShareInboxImport.apply(entries: [second, first, second], to: original,
                                                path: [folder.id], fallbackName: "Website")
        #expect(result.addedCount == 2)
        #expect(result.selectedIDs == [first.id, second.id])
        #expect(result.nextGroup.items[0].children.map(\.id) == [folder.children[0].id, second.id, first.id])
        #expect(result.nextGroup.items[0].children.dropFirst().map(\.websiteURL) == [second.url, first.url])
        #expect(result.nextGroup.items[1] == original.items[1])
        var history = SavedGroupEditHistory()
        let recorded = history.record(before: original, after: result.nextGroup)
        #expect(recorded)
        let undoResult = history.undo(current: result.nextGroup)
        let undone = try #require(undoResult)
        #expect(undone == original && !history.canUndo)
        #expect(ShareInboxImport.consumableIDs(selectedIDs: result.selectedIDs, in: undone).isEmpty)
        let redoResult = history.redo(current: undone)
        let redone = try #require(redoResult)
        #expect(redone == result.nextGroup)
        #expect(ShareInboxImport.consumableIDs(selectedIDs: result.selectedIDs, in: redone) == result.selectedIDs)
    }

    @Test("Retry finds nested stable IDs and preserves subsequently edited website content")
    func preservesExistingNestedWebsite() throws {
        let incoming = try entry("https://example.com/original", title: "Original")
        let asset = try #require(FolderCoverAssetID(rawValue: String(repeating: "a", count: 64)))
        let icon = FolderCover(standard: asset)
        let saved = GroupItem(id: incoming.id, kind: .website, name: "Renamed after import",
                             websiteURL: "https://example.org/edited", websiteIcon: icon)
        let nested = GroupItem.folder(name: "Nested", children: [saved])
        let original = SavedGroup(name: "Daily", items: [.folder(name: "Outer", children: [nested])])
        let result = try ShareInboxImport.apply(entries: [incoming], to: original, fallbackName: "Website")
        #expect(result.nextGroup == original)
        #expect(result.addedCount == 0 && result.selectedIDs == [incoming.id])
        #expect(ShareInboxImport.consumableIDs(selectedIDs: result.selectedIDs, in: original) == [incoming.id])
        var history = SavedGroupEditHistory()
        let recorded = history.record(before: original, after: result.nextGroup)
        #expect(!recorded)
        #expect(!history.canUndo)
    }

    @Test("Identity collisions reject the entire batch instead of converting existing nodes")
    func collisionsAreAtomic() throws {
        let first = try entry("https://example.com/first", title: "First")
        let conflicting = try entry("https://example.com/conflict", title: "Conflict")
        let action = GroupItem(id: conflicting.id, kind: .action, name: "Maps")
        let group = SavedGroup(name: "Daily", items: [.folder(name: "Work", children: [action])])
        let before = group
        #expect(throws: ShareInboxImport.Error.identityConflict) {
            try ShareInboxImport.apply(entries: [first, conflicting], to: group, fallbackName: "Website")
        }
        #expect(group == before)
        let altered = try ShareInboxEntry(id: first.id, url: "https://other.example.com", title: "Different", createdAt: first.createdAt)
        #expect(throws: ShareInboxImport.Error.identityConflict) {
            try ShareInboxImport.apply(entries: [first, altered], to: SavedGroup(name: "Empty"), fallbackName: "Website")
        }
    }

    @Test("Capacity and stale paths fail as a whole, while the deepest legal folder accepts websites")
    func treeBoundaries() throws {
        let incoming = try [entry("https://example.com/one"), entry("https://example.com/two")]
        let group = SavedGroup(name: "Nearly full", items: (0..<199).map { _ in .spacer() })
        #expect(throws: ShareInboxImport.Error.capacityExceeded) {
            try ShareInboxImport.apply(entries: incoming, to: group, fallbackName: "Website")
        }
        #expect(group.items.count == 199)
        let first = try ShareInboxImport.apply(entries: [incoming[0]], to: group, fallbackName: "Website")
        #expect(first.nextGroup.items.count == 200)
        #expect(throws: ShareInboxImport.Error.invalidPath) {
            try ShareInboxImport.apply(entries: incoming, to: group, path: [UUID()], fallbackName: "Website")
        }
        let fourth = GroupItem.folder(name: "Four", children: [])
        let third = GroupItem.folder(name: "Three", children: [fourth])
        let second = GroupItem.folder(name: "Two", children: [third])
        let outer = GroupItem.folder(name: "One", children: [second])
        let deep = SavedGroup(name: "Deep", items: [outer])
        let path = [outer.id, second.id, third.id, fourth.id]
        let result = try ShareInboxImport.apply(entries: incoming, to: deep, path: path, fallbackName: "Website")
        #expect(result.nextGroup.items(at: path)?.map(\.id) == incoming.map(\.id))
        #expect(result.nextGroup.isValid)
    }

    @Test("Long hosts use an explicit localized fallback without truncating manual titles")
    func fallbackNames() throws {
        let plain = try entry("https://example.com/Path")
        #expect(try ShareInboxImport.title(for: plain, fallbackName: "网站") == "example.com")
        let host = String(repeating: "a", count: 63) + "." + String(repeating: "b", count: 30) + ".com"
        let untitled = try entry("https://\(host)/Path")
        #expect(try ShareInboxImport.title(for: untitled, fallbackName: " 网站 ") == "网站")
        let manual = try entry(untitled.url, title: String(repeating: "A", count: 80))
        #expect(try ShareInboxImport.title(for: manual, fallbackName: "网站") == manual.title)
        for invalid in ["", "\nWebsite", String(repeating: "a", count: 81)] {
            #expect(throws: ShareInboxImport.Error.invalidFallbackName) {
                try ShareInboxImport.title(for: untitled, fallbackName: invalid)
            }
        }
    }

    @Test("Draft conversion never consumes inbox data and only remaining saved website IDs are eligible")
    func explicitAcknowledgementBoundary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox: any ShareInboxStorage = ShareInboxRepository(directory: directory)
        let first = try inbox.enqueue(url: "https://example.com/first", title: "First")
        let second = try inbox.enqueue(url: "https://example.com/second", title: "Second")
        let selection = try ShareInboxImport.apply(entries: [first, second], to: SavedGroup(name: "Daily"), fallbackName: "Website")
        #expect(Set(inbox.snapshot.entries.map(\.id)) == [first.id, second.id])
        var final = selection.nextGroup
        final.items.removeAll { $0.id == second.id }
        final.items[0].name = "Edited before saving"
        final.items[0].websiteURL = "https://example.org/edited"
        let eligible = ShareInboxImport.consumableIDs(selectedIDs: selection.selectedIDs, in: final)
        #expect(eligible == [first.id])
        #expect(inbox.snapshot.recordCount == 2, "determining eligibility is not a successful group save")
        for id in eligible { _ = try inbox.remove(id: id) }
        #expect(inbox.snapshot.entries == [second])
        final.name = ""
        #expect(ShareInboxImport.consumableIDs(selectedIDs: selection.selectedIDs, in: final).isEmpty)
    }

    private func entry(_ url: String, title: String? = nil) throws -> ShareInboxEntry {
        try ShareInboxEntry(id: UUID(), url: url, title: title, createdAt: .now)
    }
}
