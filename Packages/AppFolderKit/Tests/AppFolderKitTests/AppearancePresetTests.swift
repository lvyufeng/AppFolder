import Foundation
import Testing
@testable import AppFolderKit

@Suite("Named appearance presets")
struct AppearancePresetTests {
    @Test("Display names trim and normalize without folding accents, width or case")
    func nameIdentityAndBoundaries() throws {
        let preset = AppearancePreset(name: "  Cafe\u{301}  ", appearance: .default)
        #expect(preset.isValid && preset.name.utf8.elementsEqual("Café".utf8))
        #expect(preset.id == SavedGroupBinding.normalizedName("CAFÉ"))
        #expect(preset.name != "CAFÉ")
        #expect(AppearancePreset(name: "Ａ", appearance: .default).id != AppearancePreset(name: "A", appearance: .default).id)
        #expect(AppearancePreset(name: "resume", appearance: .default).id != AppearancePreset(name: "résumé", appearance: .default).id)
        for name in [String(repeating: "x", count: 64), String(repeating: "😀", count: 64)] {
            #expect(AppearancePreset(name: name, appearance: .default).isValid)
        }
        for invalid in ["", " \u{00A0}", "\tName", "Name\n", "a\u{0000}b", "a\u{0085}b",
                        String(repeating: "x", count: 65), "x" + String(repeating: "\u{0301}", count: 128)] {
            let record = AppearancePreset(name: invalid, appearance: .default)
            #expect(!AppearancePreset.isValidName(invalid) && !record.isValid)
            #expect(record.name.utf8.elementsEqual(invalid.utf8))
            #expect(throws: (any Error).self) { try JSONEncoder().encode(record) }
        }
    }

    @Test("All appearance fields round-trip, valid colors normalize and invalid colors never become defaults")
    func completeAppearance() throws {
        for grid in FolderGrid.allCases {
            for size in SavedGroupIconSize.allCases {
                for plate in FolderPlate.allCases {
                    for density in FolderDensity.allCases {
                        for back in FolderBackButtonStyle.allCases {
                            var appearance = SavedGroupAppearance(grid: grid, showsTitles: false, iconSize: size,
                                                                  plate: plate, tintHex: "#AC34EF", density: density,
                                                                  backButtonStyle: back)
                            appearance.tintHex = " ac34ef "
                            let record = AppearancePreset(name: "Look", appearance: appearance)
                            #expect(record.appearance.tintHex == "#AC34EF")
                            #expect(record.appearance.grid == grid && !record.appearance.showsTitles)
                            #expect(record.appearance.iconSize == size && record.appearance.plate == plate)
                            #expect(record.appearance.density == density && record.appearance.backButtonStyle == back)
                            #expect(try JSONDecoder().decode(AppearancePreset.self, from: JSONEncoder().encode(record)) == record)
                        }
                    }
                }
            }
        }
        for invalid in ["", "#12345", "not-a-color", "#ABCDEF\n"] {
            let record = AppearancePreset(name: "Invalid", appearance: .init(tintHex: invalid))
            #expect(!record.isValid && record.appearance.tintHex == invalid)
            #expect(throws: (any Error).self) { try JSONEncoder().encode(record) }
        }
        #expect(AppearancePreset(name: "Default", appearance: .default).appearance == .default)
    }

    @Test("Persisted records reject ambiguous names and fields while accepting valid color spellings")
    func strictDecoding() throws {
        let original = AppearancePreset(name: "Café", appearance: .default)
        let bytes = try JSONEncoder().encode(original)
        let base = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var invalid: [[String: Any]] = []
        for name: Any in [" Café ", "Cafe\u{0301}", "\nCafé", "", NSNull(), 123] {
            var object = base; object["name"] = name; invalid.append(object)
        }
        var missing = base; missing["appearance"] = nil; invalid.append(missing)
        var unknown = base; unknown["groupID"] = UUID().uuidString; invalid.append(unknown)
        var badAppearance = base
        var appearance = try #require(base["appearance"] as? [String: Any])
        appearance["tintHex"] = "bad"
        badAppearance["appearance"] = appearance
        invalid.append(badAppearance)
        for object in invalid {
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(AppearancePreset.self, from: data) }
        }
        appearance["tintHex"] = "0a84ff"
        var normalized = base; normalized["appearance"] = appearance
        #expect(try JSONDecoder().decode(AppearancePreset.self, from: JSONSerialization.data(withJSONObject: normalized)) == original)
    }

    @Test("Preset appearance is a value copy and changes neither source group nor global defaults")
    func detachedValue() {
        let defaultBefore = SavedGroupAppearance.default
        var group = SavedGroup(name: "Group", items: [.action(name: "Calendar")], appearance: .default)
        let original = group
        let preset = AppearancePreset(name: "Original", appearance: group.appearance ?? .default)
        group.appearance?.tintHex = "#FF0000"
        group.appearance?.showsTitles.toggle()
        #expect(preset.appearance == original.appearance)
        #expect(SavedGroupAppearance.default == defaultBefore)
    }
}
