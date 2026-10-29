import Foundation
import WidgetKit

/// One validated page and its inherited style, shared by the preview and widget.
/// Navigation identity must still be computed from the root widget configuration;
/// changing a folder's style must not change the key used to read its path.
public struct SavedGroupPageLayout: Sendable, Equatable {
    public let page: SavedGroupPage
    public let style: FolderStyle
    public let parentNavigation: SavedGroupNavigation.Snapshot?
    public let cells: [SavedGroupGridCell]

    public init(group: SavedGroup, path: [UUID] = [], page requestedPage: Int = 0,
                family: WidgetFamily, useGroupAppearance: Bool, widgetStyle: FolderStyle) {
        let appearance = group.resolvedAppearance(at: path)
        let validPath = appearance != nil
        let resolvedPath = validPath ? path : []
        style = useGroupAppearance ? (appearance ?? group.resolvedAppearance).style : widgetStyle
        page = SavedGroupPage(group: group, path: resolvedPath, page: validPath ? requestedPage : 0,
                              capacity: style.grid.cellCount(for: family, density: style.density), usesIconNavigation: true)
        cells = page.cells
        if let parent = page.parentPath, let child = page.path.last,
           let parentAppearance = group.resolvedAppearance(at: parent),
           let parentItems = group.items(at: parent),
           let index = parentItems.firstIndex(where: { $0.id == child && $0.kind == .folder }) {
            let parentStyle = useGroupAppearance ? parentAppearance.style : widgetStyle
            let capacity = parentStyle.grid.cellCount(for: family, density: parentStyle.density)
            let ranges = SavedGroupIconPagination.ranges(itemCount: parentItems.count, capacity: capacity, hasParent: !parent.isEmpty)
            parentNavigation = .init(path: parent, page: ranges.firstIndex(where: { $0.contains(index) }) ?? 0)
        } else {
            parentNavigation = nil
        }
    }
}
