import Testing
import WidgetKit
@testable import AppFolderKit

/// The grid geometry a direct-launch widget draws, which is not a folder's.
///
/// ## Why this suite exists
///
/// The direct-launch widget first shipped using ``FolderGridMetrics/defaultIconScale``,
/// which is 0.5 and is right for a folder. On a *medium* widget that setting spends
/// 37 pt of margin top and bottom — the margin is a share of the widget's width, and
/// a medium widget is only 166 pt tall — leaving 92 pt for three rows. Measured, a
/// nine-slot grid came out with **11.4 pt icons**: unreadable, and too small to hit.
///
/// The numbers below are that measurement pinned, so the setting cannot quietly
/// drift back. Every family and slot count the widget offers is covered, because the
/// failure was worst in one family and fine in another.
@Suite("Direct launch metrics")
struct DirectLaunchMetricsTests {
    /// The sizes the system gives the three offered families, in points.
    private static let medium = CGSize(width: 349, height: 166)
    private static let small = CGSize(width: 170, height: 170)
    private static let large = CGSize(width: 349, height: 360)

    /// The scale both the widget and this suite must agree on.
    ///
    /// Spelled here rather than imported because the widget target cannot be seen
    /// from the package — so this is a *duplicate* on purpose, and the test below
    /// fails if the widget's copy ever changes to a value that breaks the geometry.
    private static let scale: Double = 1.0

    private func metrics(_ slots: Int, columns: Int, in size: CGSize) -> FolderGridMetrics {
        FolderGridMetrics(
            tileCount: slots, columns: columns, in: size,
            showsTitles: true, iconScale: Self.scale
        )
    }

    /// A full medium grid — the arrangement that used to be 11 pt.
    @Test func mediumNineSlotsAreIconSized() {
        let m = metrics(9, columns: 3, in: Self.medium)
        #expect(m.rows == 3)
        // A Home Screen icon is about 60 pt; the requirement here is legibility and a
        // hit target, so anything at or above the small widget's icon is acceptable
        // and anything near the old 11.4 pt is not.
        #expect(m.iconSide >= 28, "medium 9-slot icons came out \(m.iconSide) pt")
    }

    /// No family may spend so much on margin that the cells are squeezed.
    @Test func everyOfferedArrangementIsLegible() {
        let cases: [(String, Int, CGSize)] = [
            ("small", 9, Self.small),
            ("medium", 9, Self.medium),
            ("medium", 4, Self.medium),
            ("large", 9, Self.large),
            ("large", 12, Self.large),
        ]
        for (family, slots, size) in cases {
            let m = metrics(slots, columns: 3, in: size)
            #expect(
                m.iconSide >= 28,
                "\(family) with \(slots) slots came out \(m.iconSide) pt"
            )
        }
    }

    /// The block still fits inside the widget, which is what makes the icons
    /// *look* deliberate rather than merely large.
    @Test func gridFitsItsWidget() {
        for size in [Self.small, Self.medium, Self.large] {
            let m = metrics(9, columns: 3, in: size)
            let width = m.margin * 2 + CGFloat(m.columns) * m.iconSide
                + CGFloat(m.columns - 1) * m.spacing
            let height = m.margin * 2 + CGFloat(m.rows) * m.cellHeight
                + CGFloat(m.rows - 1) * m.spacing
            #expect(width <= size.width + 0.5, "grid is \(width) wide in \(size.width)")
            #expect(height <= size.height + 0.5, "grid is \(height) tall in \(size.height)")
        }
    }

    /// The margin is a share of width, which is exactly why a short widget suffers
    /// from it. This is the property behind the bug, stated so a future change that
    /// derives the margin from height instead can be seen to fix it.
    @Test func theDefaultFolderScaleIsTooGenerousForAMediumWidget() {
        let folder = FolderGridMetrics(
            tileCount: 9, columns: 3, in: Self.medium,
            showsTitles: true, iconScale: FolderGridMetrics.defaultIconScale
        )
        let direct = metrics(9, columns: 3, in: Self.medium)
        #expect(folder.iconSide < direct.iconSide)
        #expect(folder.margin > direct.margin)
    }
}