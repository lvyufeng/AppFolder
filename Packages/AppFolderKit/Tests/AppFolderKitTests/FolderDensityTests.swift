import CoreText
import Foundation
import Testing
import WidgetKit
@testable import AppFolderKit

@Suite("Folder density persistence and identity")
struct FolderDensityTests {
    @Test("Legacy appearance retains its exact revision and omits the default density field")
    func legacyAppearance() throws {
        let data = Data("""
        {"appearance":{"grid":"nine","iconSize":"medium","plate":"automatic","showsTitles":true,"tintHex":"#0A84FF"},"id":"00000000-0000-0000-0000-000000000001","items":[{"children":[],"id":"00000000-0000-0000-0000-000000000002","kind":"action","name":"Maps"}],"name":"Legacy","updatedAt":0}
        """.utf8)
        let group = try JSONDecoder().decode(SavedGroup.self, from: data)
        #expect(group.resolvedAppearance.density == .standard)
        #expect(group.revision == "361c18e85327907e0201d94b82285bb8ce6968f96f69824224f06fb5d20112dc")
        #expect(!String(decoding: try JSONEncoder().encode(group), as: UTF8.self).contains("density"))
        var changed = group
        changed.appearance?.density = .dense
        #expect(changed.revision != group.revision)
        #expect(changed.items == group.items && changed.allActionNames == group.allActionNames)
        changed.appearance?.density = .standard
        #expect(changed.revision == group.revision)
    }

    @Test("Saved density survives reopening and styles preserve or replace it with the other appearance fields")
    func persistenceAndStyle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("density-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedGroupRepository(directory: directory)
        for density in FolderDensity.allCases {
            let group = SavedGroup(name: density.rawValue, items: [.action(name: "Maps", displayName: "Go")],
                                   appearance: .init(tintHex: " aabbcc ", density: density))
            #expect(store.save(group))
            let loaded = try #require(SavedGroupRepository(directory: directory).group(id: group.id))
            #expect(loaded.appearance?.density == density && loaded.appearance?.tintHex == "#AABBCC")
            let manual = FolderStyle(plate: .gradient, density: .spacious)
            #expect(group.effectiveStyle(useGroupAppearance: false, widgetStyle: manual) == manual)
            #expect(group.effectiveStyle(useGroupAppearance: true, widgetStyle: manual).density == density)
            #expect(manual.usingSystemPlate.density == .spacious)
        }
    }

    @Test("Unknown and null density values are rejected rather than silently becoming standard")
    func invalidDensity() throws {
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGroupAppearance())) as? [String: Any])
        for value: Any in ["future", "Dense", 3, NSNull()] {
            var object = original
            object["density"] = value
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroupAppearance.self, from: data) }
        }
        #expect(try JSONDecoder().decode(SavedGroupAppearance.self, from: JSONSerialization.data(withJSONObject: original)).density == .standard)
    }

    @Test("Old navigation keys are unchanged and new effective densities isolate paging state")
    func navigationIdentity() {
        let names = ["Maps", "Calendar"]
        let base = WidgetState.directLaunchExpansionKey(slotNames: names)
        for (family, columns, cells) in [(WidgetFamily.systemSmall, 3, 9), (.systemMedium, 5, 10), (.systemLarge, 4, 16), (.systemExtraLarge, 4, 12)] {
            let legacy = base + "|layout:1|nine|\(family.rawValue)|\(columns)x\(cells)"
            #expect(WidgetState.directLaunchExpansionKey(slotNames: names, grid: .nine, family: family) == legacy)
            #expect(WidgetState.directLaunchExpansionKey(slotNames: names, grid: .nine, family: family, density: .standard) == legacy)
        }
        for family in [WidgetFamily.systemMedium, .systemLarge] {
            let keys = FolderDensity.allCases.map {
                WidgetState.directLaunchExpansionKey(slotNames: names, grid: .nine, family: family, density: $0)
            }
            #expect(Set(keys).count == 3)
        }
        for family in [WidgetFamily.systemSmall, .systemExtraLarge] {
            let keys = FolderDensity.allCases.map {
                WidgetState.directLaunchExpansionKey(slotNames: names, grid: .nine, family: family, density: $0)
            }
            #expect(Set(keys).count == 1)
        }
    }

    @Test("Legacy reports read as standard and configuration IDs keep density reports separate")
    func reportCompatibility() throws {
        let group = SavedGroup(name: "Daily", items: [.action(name: "Maps")])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("density-reports-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedGroupBindingReportRepository(directory: directory)
        var reports: [SavedGroupBindingReport] = []
        for density in FolderDensity.allCases {
            let key = WidgetState.directLaunchExpansionKey(slotNames: ["Maps"], grid: .nine, family: .systemLarge, density: density)
            let report = try #require(SavedGroupBindingReport(group: group, configurationKey: key, grid: .nine,
                                                              familyRawValue: WidgetFamily.systemLarge.rawValue,
                                                              actionNames: ["Maps"], density: density))
            #expect(store.record(report))
            #expect(try JSONDecoder().decode(SavedGroupBindingReport.self, from: JSONEncoder().encode(report)) == report)
            reports.append(report)
        }
        #expect(Set(reports.map(\.id)).count == 3)
        #expect(Set(store.all.map(\.density)) == Set(FolderDensity.allCases))
        let legacyData = try JSONEncoder().encode(reports[0])
        #expect(!String(decoding: legacyData, as: UTF8.self).contains("density"))
        #expect(try JSONDecoder().decode(SavedGroupBindingReport.self, from: legacyData).id == reports[0].id)
        for value: Any in ["future", NSNull()] {
            var json = try #require(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
            json["density"] = value
            let invalid = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroupBindingReport.self, from: invalid) }
        }
    }
}

@Suite("Density and portrait grid geometry")
struct FolderDensityGeometryTests {
    private var containers: [(WidgetFamily, CGSize)] {
        var result: [(WidgetFamily, CGSize)] = [
            (.systemMedium, .init(width: 349, height: 166)), (.systemMedium, .init(width: 364, height: 170)),
            (.systemLarge, .init(width: 349, height: 360)), (.systemLarge, .init(width: 364, height: 382)),
            // TimelineProviderContext.displaySize measured on iPhone 18 Pro.
            (.systemMedium, .init(width: 349.66666666666663, height: 164.33333333333331)),
            (.systemLarge, .init(width: 349.66666666666663, height: 365)),
        ]
        if #available(macOS 27.0, *) {
            result += [(.systemExtraLargePortrait, .init(width: 349, height: 734)),
                       (.systemExtraLargePortrait, .init(width: 364, height: 758)),
                       (.systemExtraLargePortrait, .init(width: 320, height: 640)),
                       (.systemExtraLargePortrait, .init(width: 349.66666666666663, height: 565.6666666666666))]
        }
        return result
    }

    @Test("Every density uses its promised rectangle and overflow capacity")
    func familyShapes() {
        var shapes: [(WidgetFamily, FolderDensity, Int, Int)] = [
            (.systemMedium, .standard, 5, 2), (.systemMedium, .spacious, 4, 2), (.systemMedium, .dense, 7, 3),
            (.systemLarge, .standard, 4, 4), (.systemLarge, .spacious, 3, 3), (.systemLarge, .dense, 7, 7),
        ]
        if #available(macOS 27.0, *) {
            shapes += [(.systemExtraLargePortrait, .standard, 5, 8), (.systemExtraLargePortrait, .spacious, 4, 6),
                       (.systemExtraLargePortrait, .dense, 7, 11)]
        }
        for (family, density, columns, rows) in shapes {
            for grid in FolderGrid.allCases {
                let count = columns * rows
                #expect(grid.columns(for: family, density: density) == columns)
                #expect(grid.cellCount(for: family, density: density) == count)
                #expect(grid.capacity(for: family, density: density) == count - 1)
                #expect(grid.nestedCell(for: family, tileCount: count - 1, density: density) == nil)
                #expect(grid.nestedCell(for: family, tileCount: count, density: density) == count - 1)
            }
        }
    }

    @Test("Small geometry and unregistered landscape extra-large mapping ignore density")
    func unchangedFamilies() {
        for grid in FolderGrid.allCases {
            let small = grid.cellCount(for: .systemSmall)
            let columns = grid.columns(for: .systemSmall)
            for density in FolderDensity.allCases {
                #expect(grid.cellCount(for: .systemSmall, density: density) == small)
                #expect(grid.cellCount(for: .systemExtraLarge, density: density) == 12)
                #expect(grid.columns(for: .systemExtraLarge, density: density) == 4)
                for scale in [0.5, 0.75, 1] {
                    let old = FolderGridMetrics(tileCount: small, columns: columns, in: .init(width: 170, height: 138),
                                                showsTitles: true, iconScale: scale, family: .systemSmall)
                    let new = FolderGridMetrics(tileCount: small, columns: columns, in: .init(width: 170, height: 138),
                                                showsTitles: true, iconScale: scale, family: .systemSmall, density: density)
                    #expect(old == new)
                }
            }
        }
    }

    @Test("Titles fit real font metrics while square artwork and full-width cells stay within bounds")
    func fitsEveryContainer() throws {
        for (family, size) in containers {
            for density in FolderDensity.allCases {
                for header: CGFloat in [0, 32] {
                    for scale in [0.5, 0.75, 1] {
                        let named = metrics(family, density, size, header: header, scale: scale, titles: true)
                        let plain = metrics(family, density, size, header: header, scale: scale, titles: false)
                        for value in [named, plain] {
                            #expect([value.iconSide, value.cellWidth, value.cellHeight, value.spacing, value.margin,
                                     value.titleFontSize, value.labelHeight].allSatisfy { $0.isFinite && $0 >= 0 })
                            #expect(value.iconSide <= value.cellWidth)
                            #expect(value.size.width + value.margin * 2 <= size.width + 0.001)
                            #expect(value.size.height + value.margin * 2 + header <= size.height + 0.001)
                        }
                        #expect(named.cellWidth == plain.cellWidth)
                        #expect(named.iconSide >= 20)
                        #expect(named.titleFontSize >= 9)
                        let font = try #require(CTFontCreateUIFontForLanguage(.system, named.titleFontSize, nil))
                        let line = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
                        #expect(named.labelHeight >= line + named.titleSpacing)
                        #expect(plain.labelHeight == 0 && plain.titleSpacing == 0 && plain.titleFontSize == 0)
                    }
                }
            }
        }
    }

    @Test("Icon scales remain distinct without changing column identity or losing the final portrait row")
    func scalesAndRows() {
        for (family, size) in containers {
            for density in FolderDensity.allCases {
                let stops = [0.5, 0.75, 1].map { metrics(family, density, size, header: 32, scale: $0, titles: true) }
                #expect(stops[0].iconSide < stops[1].iconSide && stops[1].iconSide < stops[2].iconSide)
                let expectedRows = FolderGrid.nine.cellCount(for: family, density: density) / FolderGrid.nine.columns(for: family, density: density)
                #expect(stops.allSatisfy { $0.rows == expectedRows })
            }
        }
        if #available(macOS 27.0, *) {
            let group = SavedGroup(name: "Full portrait", items: (0..<78).map { _ in .action(name: "Maps") })
            let capacity = FolderGrid.nine.cellCount(for: .systemExtraLargePortrait, density: .dense)
            let first = SavedGroupPage(group: group, path: [], page: 0, capacity: capacity)
            let last = SavedGroupPage(group: group, path: [], page: 1, capacity: capacity)
            #expect(capacity == 77 && first.visibleItems.count == 77 && last.visibleItems.count == 1)
            #expect(first.pageCount == 2 && last.pageCount == 2)
        }
    }

    @Test("Tiny and nonfinite larger bounds never create negative frames")
    func pathologicalBounds() {
        var families = [WidgetFamily.systemMedium, .systemLarge]
        if #available(macOS 27.0, *) { families.append(.systemExtraLargePortrait) }
        for family in families {
            for density in FolderDensity.allCases {
                for size in [CGSize.zero, .init(width: 1, height: 1), .init(width: 20, height: 10), .init(width: CGFloat.infinity, height: CGFloat.infinity)] {
                    let value = metrics(family, density, size, header: 0, scale: .nan, titles: true)
                    #expect([value.iconSide, value.cellWidth, value.cellHeight, value.spacing, value.margin,
                             value.titleFontSize, value.labelHeight].allSatisfy { $0.isFinite && $0 >= 0 })
                    if size.width.isFinite {
                        #expect(value.size.width + 2 * value.margin <= size.width + 0.001)
                        #expect(value.size.height + 2 * value.margin <= size.height + 0.001)
                    }
                }
            }
        }
    }

    private func metrics(_ family: WidgetFamily, _ density: FolderDensity, _ size: CGSize,
                         header: CGFloat, scale: Double, titles: Bool) -> FolderGridMetrics {
        FolderGridMetrics(tileCount: FolderGrid.nine.cellCount(for: family, density: density),
                          columns: FolderGrid.nine.columns(for: family, density: density),
                          in: .init(width: size.width, height: max(0, size.height - header)),
                          showsTitles: titles, iconScale: scale, family: family, density: density)
    }
}
