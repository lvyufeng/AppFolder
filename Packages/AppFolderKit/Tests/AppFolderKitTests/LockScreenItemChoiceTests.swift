import Foundation
import Testing
@testable import AppFolderKit

@Suite("Lock screen saved-item choices")
struct LockScreenItemChoiceTests {
    @Test("Composite IDs use a strict canonical string and retain both UUIDs through Codable")
    func identifierContract() throws {
        let groupID = UUID(uuidString: "A1B2C3D4-1234-5678-9ABC-123456789ABC")!
        let itemID = UUID(uuidString: "D4C3B2A1-4321-8765-CBA9-CBA987654321")!
        let id = LockScreenItemID(groupID: groupID, itemID: itemID)
        let raw = "a1b2c3d4-1234-5678-9abc-123456789abc/d4c3b2a1-4321-8765-cba9-cba987654321"
        #expect(id.rawValue == raw)
        #expect(LockScreenItemID(rawValue: raw) == id)
        let data = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(String.self, from: data) == raw)
        #expect(try JSONDecoder().decode(LockScreenItemID.self, from: data) == id)
        for invalid in ["", raw.uppercased(), " " + raw, raw + "\n", raw + "/", "/" + raw,
                        raw + "/extra", raw.replacingOccurrences(of: "/", with: "%2F"),
                        raw.replacingOccurrences(of: "-", with: ""), raw.replacingOccurrences(of: "/", with: "//"),
                        "{" + raw + "}", "urn:uuid:" + raw, raw.replacingOccurrences(of: "a", with: "Ａ"),
                        raw + "?group=other", raw + "#item", String(repeating: "a", count: 10_000)] {
            #expect(LockScreenItemID(rawValue: invalid) == nil)
            let invalidData = try JSONEncoder().encode(invalid)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(LockScreenItemID.self, from: invalidData) }
        }
    }

    @Test("Flattening preserves group order, mixed leaf order, aliases and all four ancestor names")
    func orderedMixedChoices() throws {
        let action = GroupItem.action(name: "Maps", displayName: "Travel")
        let website = GroupItem.website(name: "Travel", url: "https://example.com/Path")
        let fourth = GroupItem.folder(name: "Four", children: [.spacer(), website])
        let third = GroupItem.folder(name: "Three", children: [fourth])
        let second = GroupItem.folder(name: "Two", children: [third])
        let first = GroupItem.folder(name: "One", children: [action, second])
        let final = GroupItem.action(name: "Calendar")
        let group = SavedGroup(name: "Daily", items: [.spacer(), first, final])
        let other = SavedGroup(name: "Other", items: [.action(name: "First globally")])
        let choices = LockScreenItemChoice.choices(in: [other, group])
        #expect(choices.map(\.item.id) == [other.items[0].id, action.id, website.id, final.id])
        #expect(choices.map(\.title) == ["First globally", "Travel", "Travel", "Calendar"])
        #expect(choices.map(\.groupName) == ["Other", "Daily", "Daily", "Daily"])
        #expect(choices.map(\.folderPath) == [[], ["One"], ["One", "Two", "Three", "Four"], []])
        #expect(choices[1].item.name == "Maps", "an alias must not become an action binding key")
        #expect(choices[2].item == website)
        #expect(Set(choices.map(\.id)).count == 4)
        #expect(LockScreenItemChoice.choices(in: group) == Array(choices.dropFirst()))
    }

    @Test("Moving and renaming a selected node updates its display path without changing identity")
    func movementKeepsIdentity() throws {
        let action = GroupItem.action(name: "Maps", displayName: "Travel")
        let source = GroupItem.folder(name: "Source", children: [action])
        let destination = GroupItem.folder(name: "Destination", children: [])
        var group = SavedGroup(name: "Daily", items: [source, destination])
        let id = LockScreenItemID(groupID: group.id, itemID: action.id)
        let before = try #require(LockScreenItemChoice.resolve(id, in: group, expectedKind: .action))
        let moved = group.move(itemID: action.id, to: [destination.id])
        #expect(moved)
        group.name = "Renamed group"
        group.items[1].children[0].displayName = "Commute"
        let after = try #require(LockScreenItemChoice.resolve(id, in: group, expectedKind: .action))
        #expect(after.id == before.id)
        #expect(after.folderPath == ["Destination"] && after.groupName == "Renamed group")
        #expect(after.title == "Commute" && after.item.name == "Maps")
    }

    @Test("Deletion, replacement and a different group never fall back to the same name or position")
    func exactIdentityOnly() {
        let original = GroupItem.action(name: "Maps")
        let sameName = GroupItem.action(name: "Maps")
        var group = SavedGroup(name: "Daily", items: [original, sameName])
        let id = LockScreenItemID(groupID: group.id, itemID: original.id)
        let other = SavedGroup(name: "Same visible name", items: [original])
        #expect(LockScreenItemChoice.resolve(id, in: other) == nil)
        group.items.removeFirst()
        #expect(LockScreenItemChoice.resolve(id, in: [group, other]) == nil)
        group.items.insert(.action(name: "Maps"), at: 0)
        #expect(LockScreenItemChoice.resolve(id, in: group) == nil)
        let movedGroupID = LockScreenItemID(groupID: other.id, itemID: original.id)
        #expect(LockScreenItemChoice.resolve(movedGroupID, in: [group, other])?.item == original)
        #expect(LockScreenItemChoice.choices(in: [group, other]).map(\.id).contains(movedGroupID))
    }

    @Test("Non-leaf replacements never resolve and the expected kind guards action-to-website changes")
    func changedKind() throws {
        let original = GroupItem.action(name: "Maps")
        var group = SavedGroup(name: "Daily", items: [original])
        let id = LockScreenItemID(groupID: group.id, itemID: original.id)
        group.items[0] = GroupItem(id: original.id, kind: .folder, name: "Maps", children: [.action(name: "Maps")])
        #expect(group.isValid)
        #expect(LockScreenItemChoice.resolve(id, in: group) == nil)
        group.items[0] = GroupItem(id: original.id, kind: .spacer)
        #expect(LockScreenItemChoice.resolve(id, in: group) == nil)
        group.items[0] = GroupItem(id: original.id, kind: .website, name: "Maps", websiteURL: "https://example.com")
        #expect(LockScreenItemChoice.resolve(id, in: group, expectedKind: .action) == nil)
        let website = try #require(LockScreenItemChoice.resolve(id, in: group, expectedKind: .website))
        #expect(website.item.kind == .website)
        #expect(LockScreenItemChoice.resolve(id, in: group) == website,
                "without an expected kind, the UUID pair identifies the current valid leaf")
    }

    @Test("Invalid groups and duplicate group IDs cannot create ambiguous selectable items")
    func invalidAndAmbiguousGroups() {
        let leaf = GroupItem.action(name: "Maps")
        let valid = SavedGroup(name: "Valid", items: [leaf])
        var invalid = SavedGroup(name: "Invalid", items: [leaf, leaf])
        let id = LockScreenItemID(groupID: invalid.id, itemID: leaf.id)
        #expect(!invalid.isValid)
        #expect(LockScreenItemChoice.choices(in: invalid).isEmpty)
        #expect(LockScreenItemChoice.resolve(id, in: invalid) == nil)
        #expect(LockScreenItemChoice.choices(in: [invalid, valid]) == LockScreenItemChoice.choices(in: valid))
        invalid = SavedGroup(name: "Too many", items: (0...SavedGroup.maximumItems).map { _ in .spacer() })
        #expect(LockScreenItemChoice.choices(in: invalid).isEmpty)
        var conflicting = valid
        conflicting.items[0].name = "Other target"
        #expect(LockScreenItemChoice.choices(in: [valid, conflicting]).isEmpty)
        #expect(LockScreenItemChoice.resolve(.init(groupID: valid.id, itemID: leaf.id), in: [valid, conflicting]) == nil)
    }

    @Test("The maximum valid layout is fully selectable without preview-style truncation")
    func completeCapacity() {
        let group = SavedGroup(name: "Full", items: (0..<SavedGroup.maximumItems).map { _ in .action(name: "Repeated action") })
        let choices = LockScreenItemChoice.choices(in: group)
        #expect(choices.count == SavedGroup.maximumItems)
        #expect(choices.map(\.item.id) == group.items.map(\.id))
        #expect(Set(choices.map(\.id)).count == SavedGroup.maximumItems)
        #expect(choices.allSatisfy { $0.title == "Repeated action" && $0.folderPath.isEmpty })
    }
}
