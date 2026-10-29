import CoreText
import Testing
import WidgetKit
@testable import AppFolderKit

@Suite("Fine grid geometry")
struct FolderFineGridMetricsTests {
    @Test("Default small geometry retains every previously captured field exactly")
    func legacyGoldenGeometry() {
        // Captured by compiling the untouched pre-change FolderGridMetrics.
        let four = FolderGridMetrics(tileCount: 4, columns: 2, in: .init(width: 170, height: 170),
                                     showsTitles: true, iconScale: 0.75, family: .systemSmall)
        #expect(values(four) == [51.78689583333333, 51.78689583333333, 69.98229166666667,
                                 6.085416666666667, 11.975, 18.195395833333336, 14.192408750000002,
                                 2.729309375, 109.65920833333334, 146.05, 11.393117083333333])
        let nine = FolderGridMetrics(tileCount: 9, columns: 3, in: .init(width: 170, height: 138),
                                     showsTitles: true, iconScale: 0.75, family: .systemSmall)
        #expect(values(nine) == [28.000000379297468, 28.000000379297468, 37.83783835040199,
                                 5.15970522960027, 7.083537244796752, 9.837837971104518, 7.673513617461524,
                                 1.4756756956656776, 94.31941159709295, 123.8329255104065, 6.160000083445443])
        let large = FolderGridMetrics(tileCount: 49, columns: 7, in: .init(width: 364, height: 350),
                                      iconScale: 0.75, family: .systemLarge, density: .dense)
        #expect(values(large) == [45.917857142857144, 47.917857142857144, 45.917857142857144,
                                  3.2624999999999997, 4.5, 0, 0, 0, 355, 341, 10.101928571428571])
    }

    @Test("Explicit gap and margin fix cells while each icon-size setting remains distinct")
    func independentControls() {
        for titles in [false, true] {
            let sizes = [0.5, 0.75, 1.0].map { scale in
                FolderGridMetrics(tileCount: 9, columns: 3, in: .init(width: 170, height: 170),
                                  showsTitles: titles, iconScale: scale, family: .systemSmall, spacing: 6, margin: 10)
            }
            #expect(sizes.allSatisfy { $0.spacing == 6 && $0.margin == 10 && $0.cellWidth == 46 && $0.cellHeight == 46 })
            #expect(sizes[0].titleFontSize == sizes[1].titleFontSize && sizes[1].titleFontSize == sizes[2].titleFontSize)
            #expect(sizes[0].iconSide < sizes[1].iconSide && sizes[1].iconSide < sizes[2].iconSide)
            #expect(abs(sizes[0].iconSide / sizes[2].iconSide - 0.75) < 1e-12)
            #expect(abs(sizes[1].iconSide / sizes[2].iconSide - 0.875) < 1e-12)
        }
        for scale in [0.5, 0.75, 1.0] {
            let zero = FolderGridMetrics(tileCount: 9, columns: 3, in: .init(width: 170, height: 170),
                                         iconScale: scale, spacing: 0, margin: 0)
            #expect(zero.spacing == 0 && zero.margin == 0 && zero.size == CGSize(width: 170, height: 170))
            let gapOnly = FolderGridMetrics(tileCount: 9, columns: 3, in: .init(width: 170, height: 170), iconScale: scale, spacing: 0)
            #expect(gapOnly.spacing == 0)
            let marginOnly = FolderGridMetrics(tileCount: 9, columns: 3, in: .init(width: 170, height: 170), iconScale: scale, margin: 20)
            #expect(marginOnly.margin == 20)
        }
    }

    @Test("Every supported family and density fits all boundary choices with a real font budget")
    func allFamiliesAndDensities() throws {
        var families: [(WidgetFamily, CGSize)] = [(.systemSmall, .init(width: 170, height: 138)),
                                                 (.systemMedium, .init(width: 364, height: 138)),
                                                 (.systemLarge, .init(width: 364, height: 350)),
                                                 (.systemExtraLarge, .init(width: 364, height: 170))]
        if #available(macOS 27.0, *) { families.append((.systemExtraLargePortrait, .init(width: 349.6667, height: 533.6667))) }
        for (family, size) in families {
            for density in FolderDensity.allCases {
                for grid in FolderGrid.allCases {
                    let count = grid.cellCount(for: family, density: density)
                    let columns = grid.columns(for: family, density: density)
                    for spacing: Int? in [nil, 0, 12, 24] {
                        for margin: Int? in [nil, 0, 20, 40] where spacing != nil || margin != nil {
                            for scale in [0.5, 0.75, 1.0] {
                                for titles in [false, true] {
                                    let m = FolderGridMetrics(tileCount: count, columns: columns, in: size,
                                                              showsTitles: titles, iconScale: scale, family: family,
                                                              density: density, spacing: spacing, margin: margin)
                                    checkFits(m, size)
                                    #expect(m.columns == columns && m.rows == count / columns)
                                    #expect(m.iconSide > 0)
                                    if titles, m.titleFontSize > 0 {
                                        let font = try #require(CTFontCreateUIFontForLanguage(.system, m.titleFontSize, nil))
                                        let line = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
                                        #expect(line + m.titleSpacing <= m.labelHeight + 1e-9)
                                    } else {
                                        #expect(m.titleFontSize == 0 && m.labelHeight == 0 && m.titleSpacing == 0)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Oversized requests preserve margin first and leave space for all 77 cells")
    func clampPolicy() {
        let crowded = FolderGridMetrics(tileCount: 77, columns: 7, in: .init(width: 100, height: 100),
                                         showsTitles: true, iconScale: 1, spacing: 24, margin: 40)
        #expect(crowded.margin == 40 && abs(crowded.spacing - 0.9) < 1e-12)
        #expect(crowded.rows == 11 && crowded.columns == 7 && crowded.cellHeight == 1)
        #expect(crowded.iconSide == 1 && crowded.labelHeight == 0)
        checkFits(crowded, .init(width: 100, height: 100))
        let tiny = FolderGridMetrics(tileCount: 9, columns: 3, in: .init(width: 1, height: 1),
                                      showsTitles: true, spacing: 24, margin: 40)
        #expect(tiny.margin == 0 && tiny.spacing == 0 && tiny.iconSide > 0)
        checkFits(tiny, .init(width: 1, height: 1))
        for request in [Int.min, -1, 25, 41, Int.max] {
            let m = FolderGridMetrics(tileCount: 9, columns: 3, in: .init(width: 170, height: 170), spacing: request, margin: request)
            checkFits(m, .init(width: 170, height: 170))
        }
    }

    @Test("Tiny, nonfinite and extreme counts stay finite without overflowing either bounded axis")
    func pathologicalInputs() {
        let bounds: [CGSize] = [.zero, .init(width: 1, height: 1), .init(width: 20, height: 10),
                                .init(width: 170, height: 1), .init(width: 1e-200, height: 1e-200),
                                .init(width: -1, height: -1), .init(width: CGFloat.nan, height: CGFloat.nan),
                                .init(width: CGFloat.infinity, height: CGFloat.infinity), .init(width: 170, height: CGFloat.infinity),
                                .init(width: 170, height: -CGFloat.infinity), .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)]
        for size in bounds {
            for shape in [(9, 3), (77, 7), (1, 1), (0, 0), (Int.max, 1), (1, Int.max)] {
                for request: Int? in [nil, 0, 24] {
                    let m = FolderGridMetrics(tileCount: shape.0, columns: shape.1, in: size,
                                              showsTitles: true, iconScale: .nan, spacing: request, margin: request)
                    checkFits(m, size)
                }
            }
        }
        let unlimited = FolderGridMetrics(tileCount: 77, columns: 7, in: .init(width: 350, height: CGFloat.infinity), spacing: 5, margin: 10)
        #expect(unlimited.size.height > 350 && unlimited.size.height.isFinite)
        #expect(unlimited.cellWidth == unlimited.cellHeight)
    }

    private func values(_ m: FolderGridMetrics) -> [CGFloat] {
        [m.iconSide, m.cellWidth, m.cellHeight, m.spacing, m.margin, m.labelHeight,
         m.titleFontSize, m.titleSpacing, m.size.width, m.size.height, m.cornerRadius]
    }

    private func checkFits(_ m: FolderGridMetrics, _ size: CGSize) {
        #expect(values(m).allSatisfy { $0.isFinite && $0 >= 0 })
        #expect(m.iconSide <= m.cellWidth + 1e-9)
        #expect(m.iconSide + m.labelHeight <= m.cellHeight + max(1, m.cellHeight) * 1e-12)
        if size.width.isFinite {
            #expect(m.size.width + 2 * m.margin <= max(0, size.width) + max(1, abs(size.width)) * 1e-12)
        }
        if size.height.isFinite {
            #expect(m.size.height + 2 * m.margin <= max(0, size.height) + max(1, abs(size.height)) * 1e-12)
        }
    }
}
