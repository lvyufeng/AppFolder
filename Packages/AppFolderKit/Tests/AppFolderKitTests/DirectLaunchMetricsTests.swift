import CoreText
import Testing
import WidgetKit
@testable import AppFolderKit

/// Geometry shared by the live widget and its saved-group preview.
@Suite("Direct launch metrics")
struct DirectLaunchMetricsTests {
    private static let largerWidgets: [(family: WidgetFamily, size: CGSize)] = [
        (.systemMedium, CGSize(width: 349, height: 166)),
        (.systemMedium, CGSize(width: 364, height: 170)),
        (.systemLarge, CGSize(width: 349, height: 360)),
        (.systemLarge, CGSize(width: 364, height: 382)),
    ]
    private static let scales: [Double] = [0.5, 0.75, 1]

    private func metrics(
        family: WidgetFamily, size: CGSize, header: CGFloat = 0,
        titles: Bool = true, scale: Double = 0.5
    ) -> FolderGridMetrics {
        FolderGridMetrics(
            tileCount: FolderGrid.nine.cellCount(for: family),
            columns: FolderGrid.nine.columns(for: family),
            in: CGSize(width: size.width, height: size.height - header),
            showsTitles: titles, iconScale: scale, family: family
        )
    }

    @Test func theWideShapesComeFromTheGridRule() {
        for grid in FolderGrid.allCases {
            #expect(grid.columns(for: .systemMedium) == 5)
            #expect(grid.cellCount(for: .systemMedium) == 10)
            #expect(grid.capacity(for: .systemMedium) == 9)
            #expect(grid.columns(for: .systemLarge) == 4)
            #expect(grid.cellCount(for: .systemLarge) == 16)
            #expect(grid.capacity(for: .systemLarge) == 15)
        }
    }

    @Test func largerGridsFitIncludingNamesMarginsAndSavedGroupHeader() {
        for widget in Self.largerWidgets {
            for header: CGFloat in [0, 32] {
                for titles in [false, true] {
                    for scale in Self.scales {
                        let m = metrics(family: widget.family, size: widget.size,
                                        header: header, titles: titles, scale: scale)
                        let values = [m.iconSide, m.cellWidth, m.cellHeight, m.spacing,
                                      m.margin, m.labelHeight, m.titleFontSize, m.titleSpacing]
                        #expect(values.allSatisfy { $0.isFinite && $0 >= 0 })
                        #expect(m.iconSide <= m.cellWidth)
                        #expect(m.size.width + 2 * m.margin <= widget.size.width + 0.001)
                        #expect(m.size.height + 2 * m.margin + header <= widget.size.height + 0.001)
                        #expect(m.rows == (widget.family == .systemMedium ? 2 : 4))
                        #expect(m.columns == (widget.family == .systemMedium ? 5 : 4))
                    }
                }
            }
        }
    }

    @Test func columnsUseTheWidthEvenWhenNamesLimitTheIconHeight() {
        for widget in Self.largerWidgets {
            for header: CGFloat in [0, 32] {
                for scale in Self.scales {
                    let named = metrics(family: widget.family, size: widget.size,
                                        header: header, scale: scale)
                    let unnamed = metrics(family: widget.family, size: widget.size,
                                          header: header, titles: false, scale: scale)
                    // Labels must not shrink the horizontal layout or its tap cells.
                    #expect(named.cellWidth == unnamed.cellWidth)
                    #expect(abs(named.size.width + 2 * named.margin - widget.size.width) < 0.001)
                    // Measure actual artwork edges, not just expanded cell frames.
                    let artworkSpan = named.size.width - (named.cellWidth - named.iconSide)
                    #expect(artworkSpan >= widget.size.width * 0.85)
                }
            }
        }
    }

    @Test func titleReservationFitsTheActualSystemFont() throws {
        for widget in Self.largerWidgets {
            for header: CGFloat in [0, 32] {
                for scale in Self.scales {
                    let m = metrics(family: widget.family, size: widget.size,
                                    header: header, scale: scale)
                    #expect(m.titleFontSize >= 12)
                    #expect(m.titleSpacing >= 2)
                    let font = try #require(CTFontCreateUIFontForLanguage(.system, m.titleFontSize, nil))
                    let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
                    #expect(m.labelHeight >= lineHeight + m.titleSpacing)
                }
            }
        }
    }

    @Test func hiddenTitlesReserveNoSpace() {
        for widget in Self.largerWidgets {
            let m = metrics(family: widget.family, size: widget.size, titles: false)
            #expect(m.labelHeight == 0)
            #expect(m.titleFontSize == 0)
            #expect(m.titleSpacing == 0)
            #expect(m.cellHeight == m.iconSide)
        }
    }

    @Test func allThreeIconSizesAreDistinctAndLegibleWithNavigation() {
        for widget in Self.largerWidgets {
            for header: CGFloat in [0, 32] {
                for titles in [false, true] {
                    let stops = Self.scales.map {
                        metrics(family: widget.family, size: widget.size,
                                header: header, titles: titles, scale: $0)
                    }
                    #expect(stops[0].iconSide < stops[1].iconSide)
                    #expect(stops[1].iconSide < stops[2].iconSide)
                    #expect(stops[0].margin >= stops[1].margin)
                    #expect(stops[1].margin >= stops[2].margin)
                    #expect(stops[0].spacing >= stops[1].spacing)
                    #expect(stops[1].spacing >= stops[2].spacing)
                    let minimumIcon: CGFloat = widget.family == .systemMedium ? 36 : 51
                    #expect(stops.allSatisfy { $0.iconSide >= minimumIcon })
                }
            }
        }
    }

    @Test func largerMarginsAndGapsRemainBoundedInPoints() {
        for widget in Self.largerWidgets {
            for header: CGFloat in [0, 32] {
                for scale in Self.scales {
                    let m = metrics(family: widget.family, size: widget.size,
                                    header: header, scale: scale)
                    #expect((6...12).contains(m.margin))
                    #expect((4...10).contains(m.spacing))
                }
            }
        }
    }

    @Test func explicitSmallFamilyPreservesLegacyGeometry() {
        for columns in [2, 3] {
            for header: CGFloat in [0, 32] {
                for titles in [false, true] {
                    for scale in Self.scales {
                        let size = CGSize(width: 170, height: 170 - header)
                        let legacy = FolderGridMetrics(tileCount: columns * columns, columns: columns,
                                                       in: size, showsTitles: titles, iconScale: scale)
                        let explicit = FolderGridMetrics(tileCount: columns * columns, columns: columns,
                                                         in: size, showsTitles: titles, iconScale: scale,
                                                         family: .systemSmall)
                        #expect(legacy == explicit)
                        #expect(explicit.cellWidth == explicit.iconSide)
                    }
                }
            }
        }
    }

    @Test func tinyLargerContainersNeverProduceNegativeOrOverflowingGeometry() {
        for size in [CGSize.zero, CGSize(width: 1, height: 1), CGSize(width: 20, height: 10)] {
            for family in [WidgetFamily.systemMedium, .systemLarge] {
                let m = metrics(family: family, size: size)
                let values = [m.iconSide, m.cellWidth, m.cellHeight, m.spacing,
                              m.margin, m.labelHeight, m.titleFontSize, m.titleSpacing]
                #expect(values.allSatisfy { $0.isFinite && $0 >= 0 })
                #expect(m.size.width + 2 * m.margin <= size.width + 0.001)
                #expect(m.size.height + 2 * m.margin <= size.height + 0.001)
            }
        }
    }
}
