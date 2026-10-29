import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppFolderKit

@Suite("Folder cover references")
struct FolderCoverTests {
    @Test("Legacy folder JSON keeps its exact revision and omits the new field")
    func legacyRevision() throws {
        let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","items":[{"children":[],"id":"00000000-0000-0000-0000-000000000002","kind":"folder","name":"Tools"}],"name":"Legacy","updatedAt":0}
        """.utf8)
        let group = try JSONDecoder().decode(SavedGroup.self, from: data)
        #expect(group.items[0].folderCover == nil)
        #expect(group.coverAssetIDs.isEmpty)
        #expect(group.revision == "7b78d3b5a5267b25a3bdb0478b214b008275709ea6bd1382c0c006fb59a62cff")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(group) == data)
    }

    @Test("Only folders accept nonempty covers and the cover changes navigation revision")
    func modelValidation() throws {
        let icon = try #require(CustomIcon.symbol("moon.fill"))
        let id = try #require(FolderCoverAssetRepository.id(for: icon))
        let cover = FolderCover(dark: id)
        #expect(cover.resolved(isDark: false) == nil)
        #expect(cover.resolved(isDark: true) == id)
        #expect(FolderCover(standard: id).resolved(isDark: true) == id)
        let folder = GroupItem.folder(name: "Tools")
        var group = SavedGroup(name: "Group", items: [folder])
        let revision = group.revision
        group.items[0].folderCover = cover
        #expect(group.isValid)
        #expect(group.revision != revision)
        #expect(group.coverAssetIDs == [id])
        #expect(try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group)) == group)
        for kind in [GroupItem.Kind.action, .spacer] {
            let invalid = SavedGroup(name: "Invalid", items: [.init(kind: kind, name: kind == .action ? "Mail" : "", folderCover: cover)])
            #expect(!invalid.isValid)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(invalid)) }
        }
        group.items[0].folderCover = .init()
        #expect(!group.isValid)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group)) }
    }

    @Test("Asset identifiers cannot encode paths or noncanonical digests", arguments: [
        "", "../image", String(repeating: "A", count: 64), String(repeating: "f", count: 63),
        String(repeating: "a", count: 63) + "/", String(repeating: "é", count: 64),
    ])
    func invalidIDs(value: String) throws {
        #expect(FolderCoverAssetID(rawValue: value) == nil)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(FolderCoverAssetID.self, from: JSONEncoder().encode(value)) }
    }

    @Test("Two hundred folder photos retain only references inside the bounded layout")
    func layoutPayload() throws {
        let photo = try makeCoverPhoto()
        let id = try #require(FolderCoverAssetRepository.id(for: photo))
        let cover = FolderCover(standard: id, dark: id)
        let group = SavedGroup(name: "Photos", items: (1...200).map { .folder(name: "Folder \($0)", folderCover: cover) })
        #expect(group.isValid)
        let data = try JSONEncoder().encode(group)
        #expect(data.count < SavedGroupRepository.maximumFileBytes)
        #expect(!String(decoding: data, as: UTF8.self).contains("pngData"))
        #expect(group.coverAssetIDs == [id])
    }
}

@Suite("Folder cover storage and editor transactions")
struct FolderCoverAssetTests {
    @Test("Content-addressed assets deduplicate, verify identity and never overwrite corrupt existing data")
    func immutableAssets() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        let photo = try makeCoverPhoto()
        let id = try #require(FolderCoverAssetRepository.id(for: photo))
        #expect(fixture.assets.save(photo, id: id))
        let url = fixture.assetURL(id)
        let bytes = try Data(contentsOf: url)
        #expect(fixture.assets.save(photo, id: id))
        #expect(try Data(contentsOf: url) == bytes)
        #expect(fixture.assets.icon(id: id) == photo)
        let photoBytes = try #require(photo.pngData)
        let recolored = try #require(CustomIcon.photo(pngData: photoBytes, backgroundHex: "#FF0000"))
        #expect(FolderCoverAssetRepository.id(for: recolored) != id)
        #expect(!fixture.assets.save(recolored, id: id))
        let corrupt = Data("damaged".utf8)
        try corrupt.write(to: url)
        #expect(fixture.assets.contains(id: id))
        #expect(fixture.assets.icon(id: id) == nil)
        #expect(!fixture.assets.save(photo, id: id))
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test("Missing references cannot replace an existing saved group")
    func missingReferencesRejectSave() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        let original = SavedGroup(name: "Original", items: [.folder(name: "Tools")])
        #expect(fixture.groups.save(original))
        var changed = original
        let symbol = try #require(CustomIcon.symbol("star.fill"))
        let id = try #require(FolderCoverAssetRepository.id(for: symbol))
        changed.items[0].folderCover = FolderCover(standard: id)
        #expect(!fixture.groups.save(changed))
        #expect(fixture.groups.group(id: original.id) == original)
    }

    @Test("Editor staging leaves committed state untouched and preserves original photo bytes")
    func stageAndCancel() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        let original = SavedGroup(name: "Original", items: [.folder(name: "Tools")])
        #expect(fixture.groups.save(original))
        let session = try FolderCoverEditSession(group: original, repository: fixture.assets)
        #expect(!FileManager.default.fileExists(atPath: fixture.drafts.path))
        let photo = try makeCoverPhoto()
        let dark = try #require(CustomIcon.symbol("moon.fill"))
        let pair = CustomIconVariants(standard: photo, dark: dark)
        let cover = try #require(try session.stage(variants: pair))
        #expect(try session.load(cover) == pair)
        #expect(cover.assetIDs.allSatisfy { !fixture.assets.contains(id: $0) })
        #expect(fixture.groups.group(id: original.id) == original)
        let preview = try #require(session.variants(for: cover, maxSide: 32))
        #expect(preview.standard?.decodedPhoto()?.width == 32)
        #expect(preview.standard?.backgroundHex == photo.backgroundHex)
        #expect(try session.load(cover)?.standard?.pngData == photo.pngData)
        #expect(try session.stage(variants: nil) == nil)
        #expect(throws: FolderCoverAssetError.invalidArtwork) { try session.stage(variants: .init()) }
        session.discard()
        #expect(fixture.draftDirectories.isEmpty)
        #expect(fixture.groups.group(id: original.id) == original)
        #expect(throws: FolderCoverAssetError.closedSession) { try session.load(cover) }
    }

    @Test("Dark-only commit persists one asset and clearing it restores the content preview")
    func commitAndClear() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        var group = SavedGroup(name: "Group", items: [.folder(name: "Tools")])
        let session = try FolderCoverEditSession(group: group, repository: fixture.assets)
        let dark = try #require(CustomIcon.symbol("moon.fill"))
        group.items[0].folderCover = try session.stage(variants: .init(dark: dark))
        session.retain(group.coverAssetIDs)
        try session.commit(group)
        #expect(fixture.groups.group(id: group.id) == group)
        let cover = try #require(group.items[0].folderCover)
        #expect(cover.standard == nil)
        let darkID = try #require(cover.dark)
        #expect(fixture.assets.icon(id: darkID) == dark)
        #expect(fixture.draftDirectories.isEmpty)
        let next = try FolderCoverEditSession(group: group, repository: fixture.assets)
        group.items[0].folderCover = try next.stage(variants: nil)
        next.retain(group.coverAssetIDs)
        #expect(try fixture.assets.collectGarbage() == 0, "original saved artwork stays pinned during editing")
        try next.commit(group)
        #expect(fixture.groups.group(id: group.id)?.items[0].folderCover == nil)
        #expect(!fixture.assets.contains(id: darkID))
    }

    @Test("Repeated failures writing the second appearance never accumulate new staging or leases")
    func secondAppearanceFailure() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        let session = try FolderCoverEditSession(group: SavedGroup(name: "Group"), repository: fixture.assets)
        let original = try session.stage(variants: .init(standard: CustomIcon.emoji("C")))
        let directory = try #require(fixture.draftDirectories.first)
        let second = try #require(CustomIcon.emoji("B"))
        let secondID = try #require(FolderCoverAssetRepository.id(for: second))
        let obstruction = directory.appendingPathComponent(secondID.rawValue + ".json")
        try FileManager.default.createDirectory(at: obstruction, withIntermediateDirectories: true)
        let originalLease = try fixture.assets.protectedAssetIDs()
        for attempt in 0..<10 {
            let first = try #require(CustomIcon.emoji("A\(attempt)"))
            let firstID = try #require(FolderCoverAssetRepository.id(for: first))
            #expect(throws: FolderCoverAssetError.writeFailed) {
                try session.stage(variants: .init(standard: first, dark: second))
            }
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(firstID.rawValue + ".json").path))
            #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count == 2)
            #expect(try fixture.assets.protectedAssetIDs() == originalLease)
            #expect(!fixture.assets.contains(id: firstID))
        }
        #expect(try session.load(original)?.standard?.value == "C")
        session.discard()
    }

    @Test("Missing or corrupt covers can be cleared, undone and redone without losing folder contents",
          arguments: [false, true], [false, true])
    func recoverUnavailableCover(isCorrupt: Bool, saves: Bool) throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        let artwork = try makeCoverPhoto()
        let id = try #require(FolderCoverAssetRepository.id(for: artwork))
        #expect(fixture.assets.save(artwork, id: id))
        let original = SavedGroup(name: "Recover", items: [
            .folder(name: "Tools", children: [
                .action(name: "Mail", displayName: "Inbox"), .spacer(),
                .folder(name: "Nested", children: [.action(name: "Calendar")]),
            ], folderCover: .init(standard: id, dark: id)),
        ])
        #expect(fixture.groups.save(original))
        let groupURL = fixture.groupDirectory.appendingPathComponent(original.id.uuidString.lowercased() + ".json")
        let originalBytes = try Data(contentsOf: groupURL)
        let corruptBytes = Data("corrupted photo asset".utf8)
        if isCorrupt { try corruptBytes.write(to: fixture.assetURL(id)) }
        else { #expect(fixture.assets.remove(id: id)) }
        #expect(fixture.assets.icon(id: id) == nil)

        let reopened = try #require(fixture.groups.group(id: original.id))
        let session = try FolderCoverEditSession(group: reopened, repository: fixture.assets)
        defer { session.discard() }
        #expect(throws: FolderCoverAssetError.missingAsset(id)) { try session.load(reopened.items[0].folderCover) }
        var draft = reopened
        var replacement = draft.items
        // Recovery does not load the damaged artwork and records one tree edit.
        replacement[0].folderCover = try session.stage(variants: nil)
        let replaced = draft.replaceItems(replacement, at: [])
        #expect(replaced)
        var history = SavedGroupEditHistory()
        let recorded = history.record(before: reopened, after: draft)
        #expect(recorded)
        session.retain(draft.coverAssetIDs.union(history.coverAssetIDs))
        let undone = history.undo(current: draft)
        draft = try #require(undone)
        session.retain(draft.coverAssetIDs.union(history.coverAssetIDs))
        #expect(draft == reopened, "undo preserves the exact original reference and every child identity")
        #expect(!history.canUndo)
        #expect(history.canRedo)
        let redone = history.redo(current: draft)
        draft = try #require(redone)
        session.retain(draft.coverAssetIDs.union(history.coverAssetIDs))
        #expect(draft.items[0].folderCover == nil)
        #expect(draft.items[0].children == original.items[0].children)
        #expect(draft.allActionNames == original.allActionNames)
        #expect(try Data(contentsOf: groupURL) == originalBytes, "recovery remains a draft before Save")

        if saves {
            try session.commit(draft)
            #expect(fixture.groups.group(id: original.id) == draft)
            #expect(draft.revision != original.revision)
            #expect(!fixture.assets.contains(id: id))
        } else {
            session.discard()
            #expect(try Data(contentsOf: groupURL) == originalBytes)
            #expect(fixture.groups.group(id: original.id) == original)
            if isCorrupt { #expect(try Data(contentsOf: fixture.assetURL(id)) == corruptBytes) }
            else { #expect(!fixture.assets.contains(id: id)) }
        }
    }

    @Test("Undo and redo pin staged artwork and eviction releases only unreachable staging")
    func undoRedoResources() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        var group = SavedGroup(name: "Group", items: [.folder(name: "Tools")])
        let session = try FolderCoverEditSession(group: group, repository: fixture.assets)
        var history = SavedGroupEditHistory(capacity: 2)
        let first = try #require(try session.stage(variants: .init(standard: CustomIcon.emoji("A"))))
        var next = group
        next.items[0].folderCover = first
        let recordedFirst = history.record(before: group, after: next)
        #expect(recordedFirst)
        group = next
        session.retain(group.coverAssetIDs.union(history.coverAssetIDs))
        let second = try #require(try session.stage(variants: .init(dark: CustomIcon.emoji("B"))))
        next.items[0].folderCover = second
        let recordedSecond = history.record(before: group, after: next)
        #expect(recordedSecond)
        group = next
        session.retain(group.coverAssetIDs.union(history.coverAssetIDs))
        let undone = history.undo(current: group)
        group = try #require(undone)
        session.retain(group.coverAssetIDs.union(history.coverAssetIDs))
        #expect(try session.load(first)?.standard?.value == "A")
        #expect(try session.load(second)?.dark?.value == "B")
        let redone = history.redo(current: group)
        group = try #require(redone)
        session.retain(group.coverAssetIDs.union(history.coverAssetIDs))
        #expect(group.items[0].folderCover == second)
        // With history gone, only current artwork remains staged.
        session.retain(group.coverAssetIDs)
        #expect(throws: (any Error).self) { try session.load(first) }
        #expect(try session.load(second)?.dark?.value == "B")
        session.discard()
    }

    @Test("Failed group writes preserve the session, previous layout and artwork for retry")
    func writeFailureCanRetry() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        let original = SavedGroup(name: "Original", items: [.folder(name: "Tools")])
        #expect(fixture.groups.save(original))
        let session = try FolderCoverEditSession(group: original, repository: fixture.assets)
        var changed = original
        changed.items[0].folderCover = try session.stage(variants: .init(standard: CustomIcon.emoji("A")))
        session.retain(changed.coverAssetIDs)
        let held = fixture.root.appendingPathComponent("HeldGroups")
        try FileManager.default.moveItem(at: fixture.groupDirectory, to: held)
        try Data("unwritable group directory".utf8).write(to: fixture.groupDirectory)
        #expect(throws: FolderCoverAssetError.writeFailed) { try session.commit(changed) }
        #expect(SavedGroupRepository(directory: held).group(id: original.id) == original)
        #expect(try session.load(changed.items[0].folderCover)?.standard?.value == "A")
        #expect(throws: (any Error).self) { try fixture.assets.collectGarbage() }
        #expect(changed.coverAssetIDs.allSatisfy { fixture.assets.contains(id: $0) })
        try FileManager.default.removeItem(at: fixture.groupDirectory)
        try FileManager.default.moveItem(at: held, to: fixture.groupDirectory)
        try session.commit(changed)
        #expect(fixture.groups.group(id: original.id) == changed)
    }

    @Test("Copied groups and the delete-undo lease protect shared assets until the final reference ends")
    func copiesAndDeleteUndo() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        let icon = try #require(CustomIcon.symbol("heart.fill"))
        let id = try #require(FolderCoverAssetRepository.id(for: icon))
        #expect(fixture.assets.save(icon, id: id))
        let original = SavedGroup(name: "Original", items: [.folder(name: "Tools", folderCover: .init(standard: id))])
        let copy = SavedGroup(name: "Copy", items: original.items)
        #expect(fixture.groups.save(original))
        #expect(fixture.groups.save(copy))
        let lease = try FolderCoverAssetLease(repository: fixture.assets, retaining: original.coverAssetIDs)
        #expect(fixture.groups.remove(id: original.id))
        #expect(fixture.groups.remove(id: copy.id))
        #expect(try fixture.assets.collectGarbage() == 0)
        #expect(fixture.groups.save(original), "undo-delete can restore after both copies were removed")
        lease.close()
        #expect(try fixture.assets.collectGarbage() == 0)
        #expect(fixture.groups.remove(id: original.id))
        #expect(try fixture.assets.collectGarbage() == 1)
        #expect(!fixture.assets.contains(id: id))
    }

    @Test("A single corrupt layout aborts all garbage deletion before the first file is removed")
    func failClosedCollection() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        let first = try #require(CustomIcon.emoji("A"))
        let second = try #require(CustomIcon.emoji("B"))
        let ids = try [first, second].map { try #require(FolderCoverAssetRepository.id(for: $0)) }
        #expect(fixture.assets.save(first, id: ids[0]))
        #expect(fixture.assets.save(second, id: ids[1]))
        try FileManager.default.createDirectory(at: fixture.groupDirectory, withIntermediateDirectories: true)
        let corrupt = fixture.groupDirectory.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
        try Data("{broken".utf8).write(to: corrupt)
        #expect(throws: (any Error).self) { try fixture.assets.collectGarbage() }
        #expect(ids.allSatisfy { fixture.assets.contains(id: $0) })
        try FileManager.default.removeItem(at: corrupt)
        #expect(try fixture.assets.collectGarbage() == 2)
    }

    @Test("New sessions clean abandoned staging while preserving all live sessions")
    func abandonedStaging() throws {
        let fixture = CoverFixture()
        defer { fixture.remove() }
        let abandoned = fixture.drafts.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try Data("old draft".utf8).write(to: abandoned.appendingPathComponent("old"))
        let group = SavedGroup(name: "Group")
        let first = try FolderCoverEditSession(group: group, repository: fixture.assets)
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        let cover = try first.stage(variants: .init(standard: CustomIcon.emoji("A")))
        let second = try FolderCoverEditSession(group: group, repository: fixture.assets)
        #expect(try first.load(cover)?.standard?.value == "A")
        second.discard()
        #expect(try first.load(cover)?.standard?.value == "A")
        first.discard()
        #expect(fixture.draftDirectories.isEmpty)
    }

    @Test("Unavailable storage refuses to create an editor or collect resources")
    func unavailableStorage() throws {
        let unavailable = FolderCoverAssetRepository(directory: nil, groupDirectory: nil)
        #expect(throws: FolderCoverAssetError.storageUnavailable) {
            try FolderCoverEditSession(group: SavedGroup(name: "Group"), repository: unavailable)
        }
        #expect(throws: FolderCoverAssetError.storageUnavailable) { try unavailable.collectGarbage() }
    }
}

private struct CoverFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolderCover-test-\(UUID())")
    var groupDirectory: URL { root.appendingPathComponent("SavedGroups", isDirectory: true) }
    var drafts: URL { root.appendingPathComponent("FolderCoverDrafts", isDirectory: true) }
    var groups: SavedGroupRepository { .init(directory: groupDirectory) }
    var assets: FolderCoverAssetRepository {
        .init(directory: root.appendingPathComponent("FolderCoverAssets", isDirectory: true), groupDirectory: groupDirectory)
    }
    func assetURL(_ id: FolderCoverAssetID) -> URL { assets.directory!.appendingPathComponent(id.rawValue + ".json") }
    var draftDirectories: [URL] { (try? FileManager.default.contentsOfDirectory(at: drafts, includingPropertiesForKeys: nil)) ?? [] }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func makeCoverPhoto() throws -> CustomIcon {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
                                         bytesPerRow: 1_024, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.clear(CGRect(x: 0, y: 0, width: 256, height: 256))
    context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 64, y: 64, width: 128, height: 128))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return try #require(CustomIcon.photo(pngData: data as Data, backgroundHex: "#A020F0"))
}
