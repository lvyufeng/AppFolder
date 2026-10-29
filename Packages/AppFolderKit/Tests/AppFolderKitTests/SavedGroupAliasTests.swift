import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group action aliases")
struct SavedGroupAliasTests {
    @Test("Old group JSON without alias fields keeps real action titles")
    func legacyGroupDecoding() throws {
        let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","updatedAt":0,
         "items":[{"id":"00000000-0000-0000-0000-000000000002","kind":"folder","name":"Tools",
           "children":[{"id":"00000000-0000-0000-0000-000000000003","kind":"action","name":"Maps","children":[]}]}]}
        """.utf8)
        let group = try JSONDecoder().decode(SavedGroup.self, from: data)
        let action = try #require(group.items.first?.children.first)
        #expect(group.isValid)
        #expect(action.displayName == nil)
        #expect(action.displayTitle == "Maps")
        #expect(group.allActionNames == ["Maps"])
    }

    @Test("Display aliases never replace action binding or miniature artwork keys")
    func identityStaysWithRealName() {
        let folder = GroupItem.folder(name: "Tools", children: [
            .action(name: "Maps", displayName: "Calendar"),
            .action(name: "Calendar", displayName: "Calendar"),
            .action(name: "Maps", displayName: "Work route"),
        ])
        let group = SavedGroup(name: "Alias", items: [folder])
        #expect(group.isValid)
        #expect(group.allActionNames == ["Maps", "Calendar"])
        #expect(folder.previewActionNames == ["Maps", "Calendar", "Maps"])
        #expect(folder.children.map(\.displayTitle) == ["Calendar", "Calendar", "Work route"])
        #expect(folder.children[0].previewActionNames == ["Maps"])
        let unique = SavedGroupBinding(actionNames: ["Calendar", "Maps"])
        #expect(unique.resolve(folder.children[0].name) == .matched(index: 1))
        #expect(unique.resolve(folder.children[1].name) == .matched(index: 0))
        #expect(unique.resolve(folder.children[2].name) == .matched(index: 1))
        let conflict = SavedGroupBinding(actionNames: ["Maps", " maps ", "Calendar"])
        #expect(conflict.resolve(folder.children[0].name) == .ambiguous)
        #expect(conflict.resolve(folder.children[1].name) == .matched(index: 2))
        #expect(conflict.resolve(folder.children[2].name) == .ambiguous)
    }

    @Test("Alias edits affect revisions, and removing an alias restores the original title")
    func revisionAndRemoval() throws {
        var group = SavedGroup(name: "Group", items: [.action(name: "Maps")])
        let original = group.revision
        group.items[0].displayName = "Home route"
        #expect(group.revision != original)
        #expect(group.items[0].displayTitle == "Home route")
        let aliased = group.revision
        group.items[0].displayName = "  Home route  "
        #expect(group.revision == aliased)
        let decoded = try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group))
        #expect(decoded.items[0].displayName == "Home route")
        group.items[0].displayName = nil
        #expect(group.items[0].displayTitle == "Maps")
        #expect(group.revision == original)
    }

    @Test("Aliases are trimmed and use the same character and byte boundaries as names")
    func validAliasBoundaries() {
        #expect(GroupItem.action(name: "Maps", displayName: "  Home route  ").displayName == "Home route")
        let eightyCharacters = String(repeating: "a", count: 80)
        let bytes512 = "é" + String(repeating: "\u{301}", count: 255)
        #expect(bytes512.utf8.count == 512)
        #expect(SavedGroup(name: "Allowed", items: [.action(name: "Maps", displayName: eightyCharacters)]).isValid)
        #expect(SavedGroup(name: "Allowed", items: [.action(name: "Maps", displayName: bytes512)]).isValid)
    }

    @Test("Invalid aliases fail validation and decoding", arguments: [
        "", "   ", "Line\nbreak", "Tab\tinside", "Null\0inside",
        String(repeating: "a", count: 81), "é" + String(repeating: "\u{301}", count: 256),
    ])
    func invalidAliases(alias: String) throws {
        var action = GroupItem.action(name: "Maps")
        action.displayName = alias
        let group = SavedGroup(name: "Invalid alias", items: [action])
        #expect(!group.isValid)
        let data = try JSONEncoder().encode(group)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroup.self, from: data) }
    }

    @Test("Folder and spacer aliases are rejected instead of silently discarded")
    func aliasesAreActionOnly() throws {
        for kind in [GroupItem.Kind.folder, .spacer] {
            let item = GroupItem(kind: kind, name: kind == .folder ? "Tools" : "", displayName: "Hidden alias")
            let group = SavedGroup(name: "Invalid kind", items: [item])
            #expect(item.displayTitle == item.name)
            #expect(!group.isValid)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group))
            }
        }
    }

    @Test("Alias saves survive reopening, and invalid edits preserve the prior record")
    func aliasStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Alias-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SavedGroupRepository(directory: directory)
        var group = SavedGroup(name: "Group", items: [.action(name: "Maps", displayName: "Home route")])
        #expect(repository.save(group))
        let reopened = SavedGroupRepository(directory: directory)
        #expect(reopened.group(id: group.id)?.items[0].displayTitle == "Home route")
        let original = group
        group.items[0].displayName = ""
        #expect(!repository.save(group))
        #expect(reopened.group(id: group.id) == original)
        group.items[0].displayName = nil
        #expect(repository.save(group))
        #expect(reopened.group(id: group.id)?.items[0].displayTitle == "Maps")
    }
}
