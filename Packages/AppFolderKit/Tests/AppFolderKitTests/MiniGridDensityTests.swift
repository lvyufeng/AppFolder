import CoreGraphics
import Testing

@testable import AppFolderKit

/// The overflow cell's mini-grid: how many miniatures, and how big.
///
/// These assert the *rule* — a miniature is never smaller than
/// ``MiniGridDensity/minimumMiniSide``, and the block always fits the cell — and
/// only then the sizes that rule happens to produce. A test that pinned 32.14
/// would pass while the floor was quietly lowered; a test that pins the floor
/// catches the change that moves every size at once.
@Suite("Mini grid density")
struct MiniGridDensityTests {
    /// The cell side the design is actually drawn at, at both ends.
    ///
    /// 37.2 pt is pinned in `WidgetGridTests` for a small widget at the default
    /// icon scale, and about 79.8 pt is the same for a large one. Using the real
    /// numbers rather than round ones means a change to ``FolderGridMetrics``
    /// that moves the cell shows up here as a density change, which is exactly
    /// the coupling that matters.
    private let smallCell: CGFloat = 37.2
    private let largeCell: CGFloat = 79.8

    @Test("The block always fits inside the cell it was given")
    func blockFitsTheCell() {
        // Swept rather than sampled: the failure this guards against is a
        // density that overflows at *some* size, which a couple of examples
        // would step straight over.
        for tenths in 0...1_200 {
            let cell = CGFloat(tenths) / 10
            let density = MiniGridDensity(cellSide: cell)
            let drawn = CGFloat(density.rows) * density.miniSide
                + CGFloat(density.rows - 1) * density.spacing
            #expect(
                drawn <= cell + 0.0001,
                "cell \(cell): \(density.columns)x\(density.columns) draws \(drawn)"
            )
        }
    }

    @Test("The block leaves the cell's corner and the badge their room")
    func blockLeavesRoomForTheBadge() {
        // Not the same test as "fits": reaching the cell's edge would still fit
        // and would still put the count badge on top of the outermost miniature
        // and the block into the corner radius. The allowance is what stops that,
        // so it is asserted as a proportion rather than left to the callers.
        for cell in [smallCell, largeCell, 120, 400] {
            let density = MiniGridDensity(cellSide: cell)
            let drawn = CGFloat(density.rows) * density.miniSide
                + CGFloat(density.rows - 1) * density.spacing
            #expect(abs(drawn / cell - MiniGridDensity.fillShare) < 0.0001)
        }
    }

    @Test("A miniature is never smaller than the legibility floor")
    func miniaturesStayLegible() {
        // Only where the cell *can* hold one at the floor. A cell narrower than
        // one miniature plus the badge and corner allowances has nowhere to go,
        // and shrinking is the graceful answer — the alternative would be drawing
        // outside the cell. No widget is anywhere near this small; the smallest
        // drawn cell is about 37 pt against a threshold of about 14.
        let possible = MiniGridDensity.requiredSide(forColumns: 1)
        for hundredths in 0...12_000 {
            let cell = CGFloat(hundredths) / 100
            guard cell >= possible else { continue }
            let density = MiniGridDensity(cellSide: cell)
            #expect(
                density.miniSide >= MiniGridDensity.minimumMiniSide - 0.0001,
                "cell \(cell): miniature \(density.miniSide) is below the floor"
            )
        }
    }

    @Test("Density never goes down as the cell grows")
    func densityIsMonotonic() {
        var previous = 0
        for tenths in 0...1_200 {
            let density = MiniGridDensity(cellSide: CGFloat(tenths) / 10)
            #expect(density.columns >= previous)
            previous = density.columns
        }
    }

    @Test("The threshold is where the floor says it is, not where a number was picked")
    func thresholdsComeFromTheFloor() {
        for columns in 2...MiniGridDensity.maximumColumns {
            let required = MiniGridDensity.requiredSide(forColumns: columns)

            // At the threshold the miniatures are exactly the floor.
            #expect(abs(MiniGridDensity(cellSide: required).miniSide
                    - MiniGridDensity.minimumMiniSide) < 0.0001)

            // And just below it the density has not yet climbed there. This is
            // the half that a "does it eventually reach 3" test would miss: a
            // ladder that switched early would still pass that.
            let justBelow = MiniGridDensity(cellSide: required - 0.01)
            #expect(justBelow.columns < columns)
        }
    }

    @Test("The smallest cell the design draws keeps the 2x2 it always had")
    func smallWidgetStaysTwoByTwo() {
        let density = MiniGridDensity(cellSide: smallCell)
        #expect(density.columns == 2)
        // The old hard-coded shares, restated: a 0.28 miniature in a 37.2 pt
        // cell is 10.4 pt. The change must not move this — small is where the
        // cell is most likely to become illegible.
        #expect(abs(density.miniSide - 10.416) < 0.01)
    }

    @Test("A large cell gets the denser grid, not the same four icons spaced out")
    func largeWidgetGetsMoreMiniatures() {
        let density = MiniGridDensity(cellSide: largeCell)
        #expect(density.columns == 3)
        #expect(density.capacity == 9)
        // Larger than the small cell's miniature *and* more of them — the point
        // of the ladder. If only the first held, this would be a scaling bug.
        #expect(density.miniSide > MiniGridDensity(cellSide: smallCell).miniSide)
    }

    @Test("Capacity never exceeds what the view has previews for")
    func capacityMatchesTheGatherableMaximum() {
        for tenths in 0...1_200 {
            let density = MiniGridDensity(cellSide: CGFloat(tenths) / 10)
            #expect(density.capacity <= MiniGridDensity.maximumCapacity)
        }
        // The two have to agree at the top, or a view would size its list from
        // one and draw from the other and silently drop miniatures.
        let largest = MiniGridDensity(cellSide: 10_000)
        #expect(largest.capacity == MiniGridDensity.maximumCapacity)
    }

    @Test("A cell with no room draws one miniature rather than crashing or dividing by zero")
    func degenerateSizesAreSurvivable() {
        for cell in [CGFloat(0), 1, -5] {
            let density = MiniGridDensity(cellSide: cell)
            #expect(density.columns >= 1)
            #expect(density.miniSide >= 0)
            #expect(density.spacing.isFinite)
        }
    }
}