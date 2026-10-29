import Foundation
import SwiftUI
import Testing
import WidgetKit
@testable import AppFolderKit

@Suite("Fine saved-group appearance")
struct SavedGroupFineAppearanceTests {
    @Test("Absent fine controls preserve exact appearance bytes and decode explicit optional nulls")
    func unchangedDefaultEncoding() throws {
        let legacy = Data(##"{"grid":"nine","iconSize":"medium","plate":"automatic","showsTitles":true,"tintHex":"#0A84FF"}"##.utf8)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(SavedGroupAppearance.default) == legacy)
        let decoded = try JSONDecoder().decode(SavedGroupAppearance.self, from: legacy)
        #expect(decoded.spacing == nil && decoded.margin == nil)
        #expect(decoded.titleColorHex == nil && decoded.titleOutlineHex == nil && decoded.titleOutlineWidth == .thin)
        var object = try #require(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        for key in ["spacing", "margin", "titleColorHex", "titleOutlineHex"] { object[key] = NSNull() }
        object["titleOutlineWidth"] = "thin"
        let nulls = try JSONDecoder().decode(SavedGroupAppearance.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(nulls == .default)
        #expect(try encoder.encode(nulls) == legacy)
        object["titleOutlineWidth"] = NSNull()
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SavedGroupAppearance.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test("Fine controls validate every boundary, preserve invalid drafts and normalize colors")
    func validationAndNormalization() throws {
        for spacing in [0, 24] {
            for margin in [0, 40] {
                let appearance = SavedGroupAppearance(spacing: spacing, margin: margin,
                                                       titleColorHex: " aabbcc ", titleOutlineHex: "#123abc", titleOutlineWidth: .thick)
                #expect(appearance.isValid && appearance.titleColorHex == "#AABBCC" && appearance.titleOutlineHex == "#123ABC")
                let style = try #require(appearance.validatedStyle)
                #expect(style.spacing == spacing && style.margin == margin)
                #expect(style.titleTint?.hex == "#AABBCC" && style.titleOutlineTint?.hex == "#123ABC" && style.titleOutlineWidth == .thick)
                #expect(try JSONDecoder().decode(SavedGroupAppearance.self, from: JSONEncoder().encode(appearance)) == appearance)
            }
        }
        var invalid: [SavedGroupAppearance] = []
        for value in [Int.min, -1, 25, Int.max] { invalid.append(.init(spacing: value)) }
        for value in [Int.min, -1, 41, Int.max] { invalid.append(.init(margin: value)) }
        for color in ["", "#ABC", "not a color", "#123456\n", "１２３４５６"] {
            let title = SavedGroupAppearance(titleColorHex: color)
            let outline = SavedGroupAppearance(titleOutlineHex: color)
            #expect(title.titleColorHex == color && outline.titleOutlineHex == color)
            invalid += [title, outline]
        }
        for appearance in invalid {
            #expect(!appearance.isValid && appearance.validatedStyle == nil)
            #expect(appearance.style == SavedGroupAppearance.default.style)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(SavedGroupAppearance.self, from: JSONEncoder().encode(appearance))
            }
        }
        #expect(SavedGroupTitleOutlineWidth.allCases.map(\.points) == [0.5, 1, 1.5])
    }

    @Test("Wrong field types and unknown outline widths never become defaults")
    func decodingRejectsWrongTypes() throws {
        let data = try JSONEncoder().encode(SavedGroupAppearance.default)
        let base = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let malformed: [(String, Any)] = [("spacing", 0.5), ("spacing", "1"), ("margin", true),
                                         ("margin", 40.5), ("titleColorHex", 123), ("titleOutlineHex", false),
                                         ("titleOutlineWidth", "wide"), ("titleOutlineWidth", 1)]
        for (key, value) in malformed {
            var object = base; object[key] = value
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(SavedGroupAppearance.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
    }

    @Test("Fine appearance survives copying, preset persistence and undo without affecting node identities")
    func valueCopiesAndHistory() throws {
        let appearance = SavedGroupAppearance(grid: .four, showsTitles: false, iconSize: .large,
                                               plate: .gradient, tintHex: "#ABCDEF", density: .dense,
                                               backButtonStyle: .folder, spacing: 0, margin: 40,
                                               titleColorHex: "#123456", titleOutlineHex: "#FEDCBA", titleOutlineWidth: .medium)
        let child = GroupItem.folder(name: "Child", children: [.action(name: "Maps")], folderAppearance: appearance)
        let group = SavedGroup(name: "Group", items: [child], appearance: appearance)
        let reloaded = try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group))
        #expect(reloaded == group && reloaded.items[0].folderAppearance == appearance)
        var history = SavedGroupEditHistory()
        var edited = group
        let applied = edited.setAppearance(.default, at: [child.id])
        #expect(applied)
        history.record(before: group, after: edited)
        #expect(history.undo(current: edited) == group)
        #expect(history.redo(current: group) == edited)
        #expect(group.items[0].id == edited.items[0].id)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fine-preset-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let preset = AppearancePreset(name: "Fine", appearance: appearance)
        let repository = AppearancePresetRepository(directory: root)
        #expect(repository.insertMissing([preset]).didCommit)
        #expect(try repository.exportRecords() == [preset])
        var canonical = group
        canonical.appearance?.titleColorHex = "123456"
        canonical.appearance?.titleOutlineHex = " fedcba "
        #expect(canonical.revision == group.revision)
        var changed = group; changed.appearance?.spacing = nil
        #expect(changed.revision != group.revision)
    }

    @Test("Fine fields preserve capacity, inheritance, manual style and system-plate values")
    func stylePropagation() throws {
        let appearance = SavedGroupAppearance(spacing: 12, margin: 30, titleColorHex: "#FF2200",
                                               titleOutlineHex: "#102030", titleOutlineWidth: .thick)
        let style = try #require(appearance.validatedStyle)
        var expected = style; expected.plate = .automatic
        #expect(style.usingSystemPlate == expected)
        let child = GroupItem.folder(name: "Inherits", children: [.action(name: "Maps")])
        let group = SavedGroup(name: "Group", items: [child], appearance: appearance)
        #expect(group.resolvedAppearance(at: [child.id]) == appearance)
        let manual = FolderStyle(plate: .solid, showsTitles: false, grid: .four)
        #expect(group.effectiveStyle(useGroupAppearance: false, widgetStyle: manual) == manual)
        #expect(group.effectiveStyle(useGroupAppearance: true, widgetStyle: manual) == style)
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(macOS 27.0, *) { families.append(.systemExtraLargePortrait) }
        for family in families {
            for density in FolderDensity.allCases {
                #expect(style.grid.cellCount(for: family, density: density) == FolderGrid.nine.cellCount(for: family, density: density))
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues(); environment.colorScheme = scheme
            #expect(style.labelColor.resolve(in: environment) == Color(red: 1, green: 34.0 / 255, blue: 0).resolve(in: environment))
            #expect(FolderStyle().labelColor.resolve(in: environment) == Color.secondary.resolve(in: environment))
            #expect(FolderStyle(plate: .solid, tint: try #require(FolderTint(hex: "#FFFFFF"))).labelColor.resolve(in: environment)
                    == Color.black.opacity(0.72).resolve(in: environment))
        }
    }
}
