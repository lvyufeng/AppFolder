import WidgetKit

/// Which configured actions need artwork in the current widget entry.
/// Keep names and shortcuts for every action, but avoid retaining photos from
/// offscreen pages in a memory-limited widget extension.
public enum DirectLaunchArtworkSelection {
    /// Actions drawn as individual tiles, excluding the collapsed overflow
    /// door's miniatures. Artwork in `visibleArtworkIndices` but outside this
    /// set only needs thumbnail resolution in the current entry.
    public static func fullSizeArtworkIndices(
        slotCount: Int,
        family: WidgetFamily,
        grid: FolderGrid,
        isExpanded: Bool,
        page: Int,
        density: FolderDensity = .standard
    ) -> Set<Int> {
        if isExpanded {
            return visibleArtworkIndices(
                slotCount: slotCount, family: family, grid: grid,
                isExpanded: true, page: page, density: density
            )
        }

        return Set(0..<min(max(0, slotCount), grid.capacity(for: family, density: density)))
    }

    public static func visibleArtworkIndices(
        slotCount: Int,
        family: WidgetFamily,
        grid: FolderGrid,
        isExpanded: Bool,
        page: Int,
        density: FolderDensity = .standard
    ) -> Set<Int> {
        let count = max(0, slotCount)
        let capacity = grid.capacity(for: family, density: density)
        guard count > capacity else { return Set(0..<count) }

        if isExpanded {
            let layout = FolderExpansionLayout(family: family,
                                               columns: grid.columns(for: family, density: density),
                                               cellCount: grid.cellCount(for: family, density: density),
                                               appCount: count - capacity, reservesBackCell: true)
            return Set(layout.appIndices(onPage: page).map { capacity + $0 })
        }

        // The collapsed door previews only the first few overflow actions.
        return Set(0..<min(count, capacity + MiniGridDensity.maximumCapacity))
    }
}
