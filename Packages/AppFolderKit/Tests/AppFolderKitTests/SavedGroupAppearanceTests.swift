import Foundation
import Testing
import WidgetKit
@testable import AppFolderKit

@Suite("Saved group appearance")
struct SavedGroupAppearanceTests {
    @Test("Legacy JSON omits appearance and retains its pre-appearance revision")
    func legacyRevision() throws {
        let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","items":[{"children":[],"id":"00000000-0000-0000-0000-000000000002","kind":"action","name":"Maps"}],"name":"Legacy","updatedAt":0}
        """.utf8)
        let group = try JSONDecoder().decode(SavedGroup.self, from: data)
        #expect(group.appearance == nil)
        #expect(group.resolvedAppearance == .default)
        // Golden SHA-256 of the old sorted-key revision JSON, with updatedAt 0.
        #expect(group.revision == "d8e7b48c831bab4e3aa94f7b00cb4361afff8957654670dec355a5b5b3ce6c76")
        let encoded = try JSONEncoder().encode(group)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["appearance"] == nil)
    }

    @Test("The group switch selects all saved fields or preserves the entire manual style")
    func effectiveStyle() throws {
        let manual = FolderStyle(plate: .solid, tint: try #require(FolderTint(hex: "#123456")),
                                 showsTitles: false, iconScale: 0.5, grid: .four)
        var group = SavedGroup(name: "Group")
        #expect(group.effectiveStyle(useGroupAppearance: false, widgetStyle: manual) == manual)
        let defaults = group.effectiveStyle(useGroupAppearance: true, widgetStyle: manual)
        #expect(defaults.grid == .nine)
        #expect(defaults.showsTitles)
        #expect(defaults.iconScale == 0.75)
        #expect(defaults.plate == .automatic)
        #expect(defaults.tint.hex == "#0A84FF")
        group.appearance = .init(grid: .four, showsTitles: false, iconSize: .large,
                                 plate: .gradient, tintHex: "#AA00FF")
        #expect(group.effectiveStyle(useGroupAppearance: true, widgetStyle: manual) == group.appearance?.style)
        #expect(group.effectiveStyle(useGroupAppearance: false, widgetStyle: manual) == manual)
    }

    @Test("Valid tint spelling is canonical on initialization, decoding and saving")
    func tintNormalization() throws {
        var appearance = SavedGroupAppearance(tintHex: " a0b1c2 ")
        #expect(appearance.tintHex == "#A0B1C2")
        appearance.tintHex = " #a0b1c2 "
        #expect(appearance.isValid)
        let decoded = try JSONDecoder().decode(SavedGroupAppearance.self, from: JSONEncoder().encode(appearance))
        #expect(decoded.tintHex == "#A0B1C2")
        #expect(decoded.validatedStyle?.tint.hex == "#A0B1C2")
    }

    @Test("Malformed colors remain invalid even though draft rendering is safe", arguments: [
        "", " ", "#123", "#1234567", "+12345", "-12345", "#GG0000", "12 456", "１２３４５６", "#123456\n",
    ])
    func invalidTint(hex: String) throws {
        let appearance = SavedGroupAppearance(tintHex: hex)
        #expect(FolderTint(hex: hex) == nil)
        #expect(!appearance.isValid)
        #expect(appearance.tintHex == hex)
        #expect(appearance.validatedStyle == nil)
        #expect(appearance.style == SavedGroupAppearance.default.style)
        let group = SavedGroup(name: "Invalid", appearance: appearance)
        #expect(!group.isValid)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group))
        }
    }

    @Test("Unknown enum values and incomplete appearance records fail decoding")
    func invalidSchema() throws {
        let data = try JSONEncoder().encode(SavedGroup(name: "Group", appearance: .default))
        let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["grid", "iconSize", "plate"] {
            var object = original
            var appearance = try #require(object["appearance"] as? [String: Any])
            appearance[key] = "future-choice"
            object["appearance"] = appearance
            let malformed = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroup.self, from: malformed) }
        }
        for key in ["grid", "showsTitles", "iconSize", "plate", "tintHex"] {
            var object = original
            var appearance = try #require(object["appearance"] as? [String: Any])
            appearance.removeValue(forKey: key)
            object["appearance"] = appearance
            let incomplete = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroup.self, from: incomplete) }
        }
    }

    @Test("Appearance survives reopening and copying; invalid saves preserve both groups")
    func persistenceAndCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Appearance-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SavedGroupRepository(directory: directory)
        var original = SavedGroup(name: "Original", items: [.action(name: "Maps", displayName: "Home")],
                                  appearance: .init(grid: .four, showsTitles: false, iconSize: .large,
                                                    plate: .gradient, tintHex: "#ABCDEF"))
        original.appearance?.tintHex = " abcdef "
        #expect(repository.save(original))
        let reopened = SavedGroupRepository(directory: directory)
        let stored = try #require(reopened.group(id: original.id))
        #expect(stored.appearance?.tintHex == "#ABCDEF")
        #expect(stored.items == original.items)
        var copy = SavedGroup(name: "Copy", items: stored.items, appearance: stored.appearance)
        #expect(repository.save(copy))
        #expect(reopened.group(id: copy.id)?.appearance == stored.appearance)
        copy.appearance?.tintHex = "+12345"
        #expect(!repository.save(copy))
        #expect(reopened.group(id: copy.id)?.appearance == stored.appearance)
        #expect(reopened.group(id: original.id) == stored)
    }

    @Test("Appearance changes revisions and capacity without changing action identities")
    func revisionAndCapacity() {
        let items: [GroupItem] = [.action(name: "Maps", displayName: "Home"), .spacer()]
        let group = SavedGroup(name: "Group", items: items)
        let variants: [SavedGroupAppearance] = [
            .init(grid: .four), .init(showsTitles: false), .init(iconSize: .small),
            .init(iconSize: .large), .init(plate: .solid), .init(plate: .gradient), .init(tintHex: "#112233"),
        ]
        var withDefault = group
        withDefault.appearance = .default
        for appearance in variants {
            var changed = group
            changed.appearance = appearance
            #expect(changed.revision != group.revision)
            #expect(changed.revision != withDefault.revision)
            #expect(changed.items == group.items)
            #expect(changed.allActionNames == ["Maps"])
            #expect(changed.items[0].previewActionNames == ["Maps"])
        }
        var canonical = group
        canonical.appearance = .init(tintHex: "#AABBCC")
        var equivalent = canonical
        equivalent.appearance?.tintHex = " aabbcc "
        #expect(canonical.revision == equivalent.revision)
        equivalent.appearance = nil
        #expect(equivalent.revision == group.revision)
        for grid in FolderGrid.allCases {
            let style = SavedGroupAppearance(grid: grid).style
            #expect(style.grid.cellCount(for: .systemSmall) == (grid == .four ? 4 : 9))
            #expect(style.grid.cellCount(for: .systemMedium) == 10)
            #expect(style.grid.cellCount(for: .systemLarge) == 16)
            #expect(style.grid.capacity(for: .systemSmall) == (grid == .four ? 3 : 8))
            #expect(style.grid.capacity(for: .systemMedium) == 9)
            #expect(style.grid.capacity(for: .systemLarge) == 15)
        }
        #expect(SavedGroupIconSize.allCases.map(\.scale) == [0.5, 0.75, 1])
    }
}
