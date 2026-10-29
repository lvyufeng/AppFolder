import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group websites")
struct SavedGroupWebsiteTests {
    private let address = "https://example.com/Case?Q=Ab#Fragment"

    @Test("Website titles do not become action bindings or custom-icon lookup names")
    func independentIdentity() throws {
        let website = GroupItem.website(name: "Maps", url: address)
        let group = SavedGroup(name: "Mixed", items: [website, .action(name: "Camera", displayName: "Maps")])
        #expect(group.isValid)
        #expect(group.allActionNames == ["Camera"])
        #expect(website.displayTitle == "Maps" && website.previewActionNames.isEmpty)
        let report = try #require(SavedGroupBindingReport(group: group, configurationKey: "test", grid: .nine,
                                                        familyRawValue: 0, actionNames: ["Camera"]))
        #expect(report.isReady && report.requiredNames == ["Camera"])
        let websitesOnly = SavedGroup(name: "Websites", items: [website])
        #expect(websitesOnly.isValid && websitesOnly.allActionNames.isEmpty)
        #expect(try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group)) == group)
    }

    @Test("Mixed miniature leaves preserve depth-first order and website identity, while old action queries stay compatible")
    func mixedPreviews() {
        let first = GroupItem.website(name: "One", url: address)
        let second = GroupItem.website(name: "Two", url: "https://example.org/")
        let action = GroupItem.action(name: "Camera", displayName: "Photo")
        let other = GroupItem.action(name: "Maps")
        let folder = GroupItem.folder(name: "Mixed", children: [
            .spacer(), first, .folder(name: "Nested", children: [action, second]),
            other, .action(name: "Calendar"), .action(name: "Notes")
        ])
        #expect(folder.previewLeafItems == [first, action, second, other])
        #expect(folder.previewActionNames == ["Camera", "Maps", "Calendar", "Notes"])
        #expect(first.previewLeafItems == [first])
        #expect(GroupItem.spacer().previewLeafItems.isEmpty)

        var deepest = first
        for depth in (1...SavedGroup.maximumDepth).reversed() {
            deepest = .folder(name: "Level \(depth)", children: [deepest])
        }
        #expect(SavedGroup(name: "Deep website", items: [deepest]).isValid)
        #expect(deepest.previewLeafItems == [first])
        let spaces = (0..<(SavedGroup.maximumItems - 2)).map { _ in GroupItem.spacer() }
        #expect(GroupItem.folder(name: "Boundary", children: spaces + [first]).previewLeafItems == [first])
        #expect(GroupItem.folder(name: "Beyond boundary", children: spaces + [.spacer(), first]).previewLeafItems.isEmpty)
    }

    @Test("Website fields are exclusive to leaf websites and decoding cannot repair invalid saved input")
    func schemaValidation() throws {
        let asset = try #require(FolderCoverAssetID(rawValue: String(repeating: "a", count: 64)))
        let artwork = FolderCover(dark: asset)
        let valid = GroupItem.website(name: "Website", url: address, icon: artwork)
        var invalid: [GroupItem] = []
        for kind in [GroupItem.Kind.action, .folder, .spacer] {
            invalid.append(.init(kind: kind, name: kind == .spacer ? "" : "Title", websiteURL: address))
            invalid.append(.init(kind: kind, name: kind == .spacer ? "" : "Title", websiteIcon: artwork))
        }
        var item = valid; item.websiteURL = nil; invalid.append(item)
        item = valid; item.websiteURL = "example.com"; invalid.append(item)
        item = valid; item.websiteURL = "https://example.com/" + String(repeating: "a", count: 2_048); invalid.append(item)
        item = valid; item.websiteIcon = .init(); invalid.append(item)
        item = valid; item.folderCover = artwork; invalid.append(item)
        item = valid; item.displayName = "Alias"; invalid.append(item)
        item = valid; item.children = [.action(name: "Hidden")]; invalid.append(item)
        item = valid; item.name = ""; invalid.append(item)
        for value in invalid {
            let group = SavedGroup(name: "Invalid", items: [value])
            #expect(!group.isValid)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group))
            }
        }
        let group = SavedGroup(name: "Valid", items: [valid])
        #expect(group.isValid && group.coverAssetIDs == [asset])
        #expect(valid.artworkReference == artwork)
    }

    @Test("URLs and website artwork change revisions; legacy JSON remains byte-for-byte unchanged")
    func revisionAndLegacy() throws {
        let legacy = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","items":[{"children":[],"id":"00000000-0000-0000-0000-000000000002","kind":"folder","name":"Tools"}],"name":"Legacy","updatedAt":0}
        """.utf8)
        let old = try JSONDecoder().decode(SavedGroup.self, from: legacy)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(old) == legacy)
        #expect(old.revision == "7b78d3b5a5267b25a3bdb0478b214b008275709ea6bd1382c0c006fb59a62cff")
        var group = SavedGroup(name: "Website", items: [.website(name: "Example", url: address)])
        let first = group.revision
        group.items[0].websiteURL = "https://example.com/Case?Q=Other#Fragment"
        #expect(group.revision != first)
        let second = group.revision
        let id = try #require(FolderCoverAssetID(rawValue: String(repeating: "a", count: 64)))
        group.items[0].websiteIcon = .init(dark: id)
        #expect(group.revision != second)
        #expect(try JSONDecoder().decode(SavedGroup.self, from: encoder.encode(group)).revision == group.revision)
    }

    @Test("Two hundred maximum-length URLs fit the enlarged bounded group file")
    func fullSizedGroupStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WebsiteGroup-size-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefix = "https://example.com/"
        let url = prefix + String(repeating: "/", count: 2_048 - prefix.utf8.count)
        let group = SavedGroup(name: "Many websites", items: (0..<200).map { _ in
            .website(name: String(repeating: "a", count: 80), url: url)
        })
        #expect(group.isValid)
        let data = try JSONEncoder().encode(group)
        #expect(data.count > 256 * 1_024 && data.count <= SavedGroupRepository.maximumFileBytes)
        #expect(SavedGroupRepository.maximumFileBytes == 1_024 * 1_024)
        let repository = SavedGroupRepository(directory: directory)
        #expect(repository.save(group))
        #expect(SavedGroupRepository(directory: directory).group(id: group.id) == group)
        var invalid = group
        invalid.items[0].websiteURL = "example.com"
        #expect(!repository.save(invalid))
        #expect(repository.group(id: group.id) == group)
        let path = directory.appendingPathComponent(group.id.uuidString.lowercased() + ".json")
        try Data(repeating: 0, count: SavedGroupRepository.maximumFileBytes + 1).write(to: path)
        #expect(repository.group(id: group.id) == nil)
    }

    @Test("Existing artwork sessions commit and retain website assets through history without action-icon records")
    func artworkLifecycle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WebsiteGroup-artwork-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("SavedGroups")
        let assets = FolderCoverAssetRepository(directory: root.appendingPathComponent("FolderCoverAssets"), groupDirectory: directory)
        let groups = SavedGroupRepository(directory: directory)
        let original = SavedGroup(name: "Sites", items: [.website(name: "Site", url: address)])
        #expect(groups.save(original))
        let session = try FolderCoverEditSession(group: original, repository: assets)
        let icon = try #require(CustomIcon.symbol("globe"))
        var changed = original
        changed.items[0].websiteIcon = try session.stage(variants: .init(dark: icon))
        var history = SavedGroupEditHistory()
        let recorded = history.record(before: original, after: changed)
        #expect(recorded)
        session.retain(changed.coverAssetIDs.union(history.coverAssetIDs))
        let undone = history.undo(current: changed)
        #expect(undone == original)
        session.retain(original.coverAssetIDs.union(history.coverAssetIDs))
        #expect(try session.load(changed.items[0].artworkReference)?.dark == icon)
        let redone = history.redo(current: original)
        #expect(redone == changed)
        try session.commit(changed)
        #expect(groups.group(id: changed.id) == changed)
        #expect(changed.coverAssetIDs.count == 1)
        #expect(try assets.collectGarbage() == 0)
        let next = try FolderCoverEditSession(group: changed, repository: assets)
        var cleared = changed
        cleared.items[0].websiteIcon = nil
        try next.commit(cleared)
        #expect(groups.group(id: changed.id)?.items[0].websiteIcon == nil)
        #expect(changed.coverAssetIDs.allSatisfy { !assets.contains(id: $0) })
    }
}
