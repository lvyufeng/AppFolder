import Foundation
import Testing
@testable import AppFolderKit

@Suite("Local date icon configuration")
struct CustomIconDateTests {
    @Test("Date artwork stores only its explicit kind and color; malformed static text or photo data is rejected")
    func strictWireFormat() throws {
        let icon = try #require(CustomIcon.date(backgroundHex: "aabbcc"))
        #expect(icon.kind == .date && icon.value.isEmpty && icon.pngData == nil && icon.backgroundHex == "#AABBCC")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let expected = Data(##"{"backgroundHex":"#AABBCC","kind":"date","value":""}"##.utf8)
        #expect(try encoder.encode(icon) == expected)
        #expect(try JSONDecoder().decode(CustomIcon.self, from: expected) == icon)
        for value in ["1", "2026-10-29", "calendar", " "] {
            let data = try JSONSerialization.data(withJSONObject: ["kind": "date", "value": value, "backgroundHex": "#AABBCC"])
            #expect(throws: (any Error).self) { try JSONDecoder().decode(CustomIcon.self, from: data) }
        }
        for pngData in [Data(), Data("not an image".utf8)] {
            let data = try JSONSerialization.data(withJSONObject: ["kind": "date", "value": "", "backgroundHex": "#AABBCC",
                                                                   "pngData": pngData.base64EncodedString()])
            #expect(throws: (any Error).self) { try JSONDecoder().decode(CustomIcon.self, from: data) }
        }
        #expect(CustomIcon.date(backgroundHex: "#gg0000") == nil)
        #expect(CustomIcon.date(backgroundHex: "#fff") == nil)
        let calendar = try #require(CustomIcon.symbol("calendar"))
        #expect(calendar.kind == .symbol && calendar.value == "calendar")
        #expect(try JSONDecoder().decode(CustomIcon.self, from: encoder.encode(calendar)) == calendar)
    }

    @Test("Both appearances are scanned while dark-only and fallback behavior remain unchanged")
    func appearances() throws {
        let date = try #require(CustomIcon.date())
        let symbol = try #require(CustomIcon.symbol("calendar"))
        for pair in [CustomIconVariants(standard: date), .init(dark: date), .init(standard: symbol, dark: date), .init(standard: date, dark: symbol)] {
            #expect(pair.isValid && pair.containsDate && !pair.containsPhoto)
            #expect(try JSONDecoder().decode(CustomIconVariants.self, from: JSONEncoder().encode(pair)) == pair)
            #expect(pair.thumbnail(maxSide: 32) == pair)
        }
        let darkOnly = CustomIconVariants(dark: date)
        #expect(darkOnly.resolved(isDark: false) == nil && darkOnly.resolved(isDark: true) == date)
        #expect(CustomIconVariants(standard: date).resolved(isDark: true) == date)
        #expect(!CustomIconVariants(standard: symbol).containsDate)
        #expect(!CustomIconVariants().containsDate)
    }

    @Test("Thumbnail and immutable asset identity retain date configuration without rasterizing it")
    func assetIdentity() throws {
        let date = try #require(CustomIcon.date(backgroundHex: "#AA00FF"))
        let normalized = try #require(CustomIcon.date(backgroundHex: "aa00ff"))
        let changed = try #require(CustomIcon.date(backgroundHex: "#123456"))
        let calendar = try #require(CustomIcon.symbol("calendar", backgroundHex: "#AA00FF"))
        let id = try #require(FolderCoverAssetRepository.id(for: date))
        #expect(FolderCoverAssetRepository.id(for: normalized) == id)
        #expect(FolderCoverAssetRepository.id(for: changed) != id)
        #expect(FolderCoverAssetRepository.id(for: calendar) != id)
        for side in [1, 16, 32, 96, 256] {
            #expect(date.thumbnail(maxSide: side) == date && date.limited(to: side) == date)
            #expect(date.decodedPhoto(maxSide: side) == nil)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Date-assets-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = FolderCoverAssetRepository(directory: root.appendingPathComponent("FolderCoverAssets"),
                                                groupDirectory: root.appendingPathComponent("SavedGroups"))
        #expect(assets.save(date, id: id))
        #expect(assets.icon(id: id) == date)
        #expect(!assets.save(changed, id: id))
        #expect(assets.icon(id: id)?.pngData == nil)
    }

    @Test("Saved action variants keep their revision and exact configuration across reopening")
    func actionPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Date-icons-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CustomIconRepository(directory: root)
        let standard = try #require(CustomIcon.date(backgroundHex: "#AA00FF"))
        let dark = try #require(CustomIcon.date(backgroundHex: "#000000"))
        let pair = CustomIconVariants(standard: standard, dark: dark)
        #expect(repository.setVariants(pair, name: "Calendar action"))
        let revision = repository.revision
        let reopened = CustomIconRepository(directory: root)
        #expect(reopened.variants(name: "calendar action") == pair && reopened.revision == revision)
        #expect(repository.setVariants(pair.thumbnail(maxSide: 32), name: "Calendar action"))
        #expect(repository.revision == revision)
        #expect(repository.setVariants(.init(standard: dark), name: "Calendar action"))
        #expect(repository.revision != revision)
    }

    @Test("Date covers survive staging, undo, redo and commit without changing leaf targets")
    func historyLifecycle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Date-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("SavedGroups")
        let assets = FolderCoverAssetRepository(directory: root.appendingPathComponent("FolderCoverAssets"), groupDirectory: directory)
        let groups = SavedGroupRepository(directory: directory)
        let target = try #require(ContactTarget(operation: .message, number: "+12025550100"))
        let original = SavedGroup(name: "Dates", items: [.folder(name: "Folder", children: [
            .action(name: "Calendar", displayName: "Agenda"), .website(name: "Website", url: "https://example.com"),
            .contact(name: "Contact", target: target)
        ])])
        #expect(groups.save(original))
        let session = try FolderCoverEditSession(group: original, repository: assets)
        let date = try #require(CustomIcon.date())
        let dark = try #require(CustomIcon.date(backgroundHex: "#000000"))
        let cover = try session.stage(variants: .init(standard: date, dark: dark))
        var changed = original
        changed.items[0].folderCover = cover
        changed.items[0].children[1].websiteIcon = cover
        changed.items[0].children[2].contactIcon = cover
        var history = SavedGroupEditHistory()
        history.record(before: original, after: changed)
        session.retain(changed.coverAssetIDs.union(history.coverAssetIDs))
        #expect(changed.coverAssetIDs.count == 2 && changed.revision != original.revision)
        let undo = history.undo(current: changed)
        #expect(undo == original)
        session.retain(original.coverAssetIDs.union(history.coverAssetIDs))
        #expect(try session.load(cover)?.containsDate == true)
        let redo = history.redo(current: original)
        #expect(redo == changed)
        try session.commit(changed)
        #expect(groups.group(id: original.id) == changed)
        #expect(changed.allActionNames == original.allActionNames)
        #expect(changed.items[0].children[1].websiteURL == original.items[0].children[1].websiteURL)
        #expect(changed.items[0].children[2].contactTarget == target)
        #expect(try assets.collectGarbage() == 0)
    }
}
