import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group contacts")
struct SavedGroupContactTests {
    private func target(_ operation: ContactTarget.Operation = .phone) throws -> ContactTarget {
        try #require(ContactTarget(operation: operation, number: "+12025550100"))
    }

    @Test("Contact titles and repeated endpoints stay independent of action binding and icon names")
    func identityAndPreview() throws {
        let phone = GroupItem.contact(name: "Camera", target: try target())
        let message = GroupItem.contact(name: "Camera", target: try target(.message))
        let action = GroupItem.action(name: "Real action", displayName: "Camera")
        let website = GroupItem.website(name: "Camera", url: "https://example.com/")
        var folder = GroupItem.folder(name: "People", children: [
            phone, .spacer(), .folder(name: "Nested", children: [action, message, website]),
            .action(name: "Second"), .action(name: "Third"), .action(name: "Fourth"), .action(name: "Fifth")
        ])
        let group = SavedGroup(name: "Mixed", items: [folder])
        #expect(group.isValid && group.contactItemCount == 2)
        #expect(group.allActionNames == ["Real action", "Second", "Third", "Fourth", "Fifth"])
        #expect(folder.previewLeafItems == [phone, action, message, website])
        folder.folderPreviewGrid = .nine
        #expect(folder.previewLeafItems.count == 8)
        #expect(folder.previewActionNames == ["Real action", "Second", "Third", "Fourth"])
        #expect(phone.displayTitle == "Camera" && phone.previewActionNames.isEmpty)
        let contactsOnly = SavedGroup(name: "People", items: [phone, message])
        let report = try #require(SavedGroupBindingReport(group: contactsOnly, configurationKey: "contacts", grid: .nine,
                                                        familyRawValue: 0, actionNames: []))
        #expect(contactsOnly.isValid && contactsOnly.allActionNames.isEmpty)
        #expect(report.requiredNames.isEmpty && report.missingNames.isEmpty && report.ambiguousNames.isEmpty)
        var deepest = phone
        for level in (1...4).reversed() { deepest = .folder(name: "Level \(level)", children: [deepest]) }
        #expect(SavedGroup(name: "Deep", items: [deepest]).isValid)
        #expect(deepest.previewLeafItems == [phone])
    }

    @Test("Contact fields cannot migrate to other kinds or conceal children and unrelated fields")
    func schema() throws {
        let valid = GroupItem.contact(name: "Person", target: try target())
        let asset = try #require(FolderCoverAssetID(rawValue: String(repeating: "a", count: 64)))
        let icon = FolderCover(dark: asset)
        var invalid: [GroupItem] = []
        var item = valid; item.contactTarget = nil; invalid.append(item)
        item = valid; item.children = [.action(name: "Hidden")]; invalid.append(item)
        item = valid; item.displayName = "Alias"; invalid.append(item)
        item = valid; item.contactIcon = .init(); invalid.append(item)
        item = valid; item.websiteURL = "https://example.com/"; invalid.append(item)
        item = valid; item.websiteIcon = icon; invalid.append(item)
        item = valid; item.folderCover = icon; invalid.append(item)
        item = valid; item.folderAppearance = .default; invalid.append(item)
        item = valid; item.folderPreviewGrid = .nine; invalid.append(item)
        for kind in [GroupItem.Kind.action, .website, .folder, .spacer] {
            invalid.append(.init(kind: kind, name: kind == .spacer ? "" : "Title", contactTarget: try target()))
            invalid.append(.init(kind: kind, name: kind == .spacer ? "" : "Title", contactIcon: icon))
        }
        for node in invalid {
            let group = SavedGroup(name: "Invalid", items: [node])
            #expect(!group.isValid)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group)) }
        }
        for kind in ["action", "website", "folder", "spacer"] {
            for key in ["contactTarget", "contactIcon"] {
                let object: [String: Any] = ["id": UUID().uuidString, "kind": kind, "name": "Title", "children": [], key: NSNull()]
                #expect(throws: (any Error).self) {
                    try JSONDecoder().decode(GroupItem.self, from: JSONSerialization.data(withJSONObject: object))
                }
            }
        }
    }

    @Test("Move, edit, undo and lock-screen resolution retain the same contact identity and current endpoint")
    func treeEdits() throws {
        let asset = try #require(FolderCoverAssetID(rawValue: String(repeating: "a", count: 64)))
        let person = GroupItem.contact(name: "Person", target: try target(), icon: .init(dark: asset))
        let source = GroupItem.folder(name: "Source", children: [person])
        let destination = GroupItem.folder(name: "Destination")
        let original = SavedGroup(name: "People", items: [source, destination])
        let id = LockScreenItemID(groupID: original.id, itemID: person.id)
        let choice = try #require(LockScreenItemChoice.resolve(id, in: original, expectedKind: .contact))
        #expect(choice.title == person.name && choice.folderPath == ["Source"])
        var edited = original
        let moved = edited.move(itemID: person.id, to: [destination.id])
        #expect(moved)
        var children = try #require(edited.items(at: [destination.id]))
        children[0].name = "Renamed"
        children[0].contactTarget = try target(.faceTimeVideo)
        let replaced = edited.replaceItems(children, at: [destination.id])
        #expect(replaced && edited.revision != original.revision)
        let resolved = try #require(LockScreenItemChoice.resolve(id, in: edited, expectedKind: .contact))
        #expect(resolved.folderPath == ["Destination"] && resolved.item.contactTarget?.operation == .faceTimeVideo)
        #expect(resolved.item.id == person.id && resolved.item.contactIcon == person.contactIcon)
        var history = SavedGroupEditHistory()
        history.record(before: original, after: edited)
        #expect(history.coverAssetIDs == [asset])
        let undone = history.undo(current: edited)
        #expect(undone == original)
        let redone = history.redo(current: original)
        #expect(redone == edited)
        var changedKind = edited
        changedKind.items[1].children[0] = .init(id: person.id, kind: .action, name: person.name)
        #expect(LockScreenItemChoice.resolve(id, in: changedKind, expectedKind: .contact) == nil)
        var deleted = edited; deleted.items[1].children = []
        #expect(LockScreenItemChoice.resolve(id, in: deleted) == nil)
        var otherGroup = edited; otherGroup.id = UUID()
        #expect(LockScreenItemChoice.resolve(id, in: otherGroup) == nil)
    }

    @Test("Contact artwork is retained by editor history and saved atomically; missing assets can be cleared")
    func persistenceAndAssets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Contact-core-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("SavedGroups")
        let repository = SavedGroupRepository(directory: directory)
        let assets = FolderCoverAssetRepository(directory: root.appendingPathComponent("FolderCoverAssets"), groupDirectory: directory)
        let original = SavedGroup(name: "People", items: [.contact(name: "Person", target: try target())])
        #expect(repository.save(original))
        let session = try FolderCoverEditSession(group: original, repository: assets)
        let icon = try #require(CustomIcon.symbol("phone.fill"))
        var changed = original
        changed.items[0].contactIcon = try session.stage(variants: .init(dark: icon))
        #expect(changed.items[0].artworkReference == changed.items[0].contactIcon)
        var history = SavedGroupEditHistory()
        history.record(before: original, after: changed)
        session.retain(changed.coverAssetIDs.union(history.coverAssetIDs))
        let undone = history.undo(current: changed)
        #expect(undone == original)
        session.retain(original.coverAssetIDs.union(history.coverAssetIDs))
        #expect(try session.load(changed.items[0].contactIcon)?.dark == icon)
        let redone = history.redo(current: original)
        #expect(redone == changed)
        try session.commit(changed)
        #expect(SavedGroupRepository(directory: directory).group(id: original.id) == changed)
        #expect(try assets.collectGarbage() == 0)
        let assetID = try #require(changed.coverAssetIDs.first)
        #expect(assets.remove(id: assetID))
        #expect(!repository.save(changed))
        var cleared = changed; cleared.items[0].contactIcon = nil
        #expect(repository.save(cleared))
        #expect(repository.group(id: original.id) == cleared)
    }

    @Test("Changing only the endpoint or operation invalidates a previous revision and current choices use the new value")
    func targetRevision() throws {
        let initial = SavedGroup(name: "People", items: [.contact(name: "Person", target: try target())])
        let id = LockScreenItemID(groupID: initial.id, itemID: initial.items[0].id)
        var group = initial
        group.items[0].contactTarget = try target(.message)
        #expect(group.revision != initial.revision)
        let messageRevision = group.revision
        let replacement = try #require(ContactTarget(operation: .message, number: "+12025550101"))
        group.items[0].contactTarget = replacement
        #expect(group.revision != messageRevision)
        let current = try #require(LockScreenItemChoice.resolve(id, in: group, expectedKind: .contact))
        #expect(current.item.contactTarget?.number == "+12025550101")
        #expect(current.item.name == initial.items[0].name && current.item.id == initial.items[0].id)
        #expect(try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group)) == group)
    }
}
