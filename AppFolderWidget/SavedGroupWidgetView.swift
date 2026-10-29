import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

/// Saved layout nodes select a presentation, never manufacture a system action.
struct SavedGroupWidgetView: View {
    let entry: DirectLaunchEntry
    let family: WidgetFamily
    @Environment(\.colorScheme) private var colorScheme

    private var binding: SavedGroupBinding { SavedGroupBinding(actionNames: entry.slots.map(\.name)) }

    var body: some View {
        Group {
            if let layout = entry.savedGroupLayout {
                contents(layout)
            } else if let id = entry.selectedGroupID {
                Link(destination: SavedGroupHelpRoute(groupID: id).url) {
                    unavailableGroup
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开此项目的配置帮助")
            } else {
                unavailableGroup
            }
        }
        .background {
            if let fill = entry.style.plateFill { Rectangle().fill(fill) }
        }
        .appFolderWidgetContainerBackground()
    }

    private var unavailableGroup: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.badge.questionmark").font(.title2)
            Text("分组不可用").font(.caption.weight(.semibold))
            Text("长按小组件，重新选择分组布局。")
                .font(.caption2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private func contents(_ layout: SavedGroupPageLayout) -> some View {
        let capacity = layout.page.capacity
        let page = layout.page
        return ZStack {
            Button(intent: InertTapIntent(cell: 0)) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityHidden(true)

            if page.items.isEmpty && layout.parentNavigation == nil {
                VStack(spacing: 4) {
                    Image(systemName: "folder").font(.title2)
                    Text("空文件夹").font(.caption)
                    Text("在 AppFolder 中添加内容。")
                        .font(.caption2).multilineTextAlignment(.center)
                }
                .foregroundStyle(entry.style.titleStyle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
            } else {
                GeometryReader { proxy in
                    let metrics = FolderGridMetrics(
                        tileCount: capacity, columns: entry.style.grid.columns(for: family, density: entry.style.density),
                        in: proxy.size, showsTitles: entry.style.showsTitles,
                        iconScale: entry.style.iconScale, family: family, density: entry.style.density,
                        spacing: entry.style.spacing, margin: entry.style.margin
                    )
                    Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                        ForEach(0..<metrics.rows, id: \.self) { row in
                            GridRow {
                                ForEach(0..<metrics.columns, id: \.self) { column in
                                    let index = row * metrics.columns + column
                                    if layout.cells.indices.contains(index) {
                                        gridCell(layout.cells[index], layout: layout, metrics: metrics)
                                            .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                                    } else {
                                        Color.clear.frame(width: metrics.cellWidth, height: metrics.cellHeight)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(metrics.margin)
                    .frame(width: proxy.size.width, height: proxy.size.height,
                           alignment: family == .systemSmall ? .top : .center)
                }
            }
        }
    }

    @ViewBuilder
    private func gridCell(_ value: SavedGroupGridCell, layout: SavedGroupPageLayout,
                          metrics: FolderGridMetrics) -> some View {
        switch value {
        case .item(let item):
            cell(item, page: layout.page, metrics: metrics)
        case .parent:
            if let parent = layout.parentNavigation {
                navigationTile(symbol: layout.style.backButtonStyle.systemImage, label: "返回上级",
                               path: parent.path, targetPage: parent.page, layout: layout, metrics: metrics)
            }
        case .previous:
            navigationTile(symbol: "chevron.left", label: "上一页", path: layout.page.path,
                           targetPage: layout.page.page - 1, layout: layout, metrics: metrics)
        case .next:
            navigationTile(symbol: "chevron.right", label: "下一页", path: layout.page.path,
                           targetPage: layout.page.page + 1, layout: layout, metrics: metrics)
        case .empty:
            Color.clear.accessibilityHidden(true)
        }
    }

    private func navigationTile(symbol: String, label: LocalizedStringKey, path: [UUID], targetPage: Int,
                                layout: SavedGroupPageLayout, metrics: FolderGridMetrics) -> some View {
        Button(intent: navigationIntent(path: path, page: targetPage)) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                        .fill(.fill.tertiary)
                    Image(systemName: symbol)
                        .font(.system(size: metrics.iconSide * 0.34, weight: .semibold))
                        .foregroundStyle(entry.style.titleStyle)
                }
                .frame(width: metrics.iconSide, height: metrics.iconSide)
                // Navigation has no visible label, while icon baselines still
                // align with user content when its names are enabled.
                if entry.style.showsTitles { Color.clear.frame(height: metrics.labelHeight) }
            }
            .frame(width: metrics.cellWidth, height: metrics.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("第 \(layout.page.page + 1) 页，共 \(layout.page.pageCount) 页"))
        .accessibilityAddTraits(.isButton)
    }

    private func navigationIntent(path: [UUID], page: Int) -> NavigateSavedGroupIntent {
        NavigateSavedGroupIntent(
            key: entry.expansionKey,
            expectedPath: SavedGroupNavigation.encodePath(entry.groupNavigation.path),
            expectedPage: entry.groupNavigation.page,
            targetPath: SavedGroupNavigation.encodePath(path), targetPage: page
        )
    }

    @ViewBuilder
    private func cell(_ item: GroupItem, page: SavedGroupPage, metrics: FolderGridMetrics) -> some View {
        switch item.kind {
        case .spacer:
            Color.clear.accessibilityHidden(true)
        case .contact:
            if let groupID = entry.savedGroup?.id, let target = item.contactTarget {
                Link(destination: ContactLaunchRoute(groupID: groupID, itemID: item.id).url) {
                    VStack(spacing: metrics.titleSpacing) {
                        ContactArtwork(target: target, variants: entry.tileArtwork[item.id],
                                       cornerRadius: metrics.cornerRadius, usesWidgetRendering: true,
                                       maxPixelSize: entry.artworkPixelSize)
                            .frame(width: metrics.iconSide, height: metrics.iconSide)
                        if entry.style.showsTitles { title(item.displayTitle, metrics: metrics) }
                    }
                    .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .privacySensitive()
                .accessibilityLabel(Text(verbatim: item.displayTitle + " · " + target.operation.widgetLocalizedName))
                .accessibilityHint("通过 AppFolder 联系此人")
                .dateIconAccessibilityValue(entry.tileArtwork[item.id])
            } else {
                unresolved(item, message: "联系人暂不可用", metrics: metrics)
            }
        case .website:
            if let address = item.websiteURL, WebsiteURL.validated(address) != nil {
                if item.effectiveWebsiteBrowser == .systemDefault {
                    Button(intent: OpenWebsiteIntent(url: address)) { websiteFace(item, metrics: metrics) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(item.displayTitle))
                        .accessibilityHint("打开网站链接")
                        .dateIconAccessibilityValue(entry.tileArtwork[item.id])
                } else if let groupID = entry.savedGroup?.id {
                    Link(destination: WebsiteLaunchRoute(groupID: groupID, itemID: item.id).url) {
                        websiteFace(item, metrics: metrics)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(item.displayTitle))
                    .accessibilityHint("通过 AppFolder 按所选方式打开网站")
                    .dateIconAccessibilityValue(entry.tileArtwork[item.id])
                } else {
                    unresolved(item, message: "链接不可用", metrics: metrics)
                }
            } else {
                unresolved(item, message: "链接不可用", metrics: metrics)
            }
        case .folder:
            Button(intent: navigationIntent(path: page.path + [item.id], page: 0)) {
                VStack(spacing: metrics.titleSpacing) {
                    folderArtwork(item, metrics: metrics)
                    if entry.style.showsTitles { title(item.name, metrics: metrics) }
                }
                .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(item.name))
            .accessibilityHint("打开文件夹")
            .dateIconAccessibilityValue(entry.tileArtwork[item.id])
        case .action:
            switch binding.resolve(item.name) {
            case .matched(let index) where entry.slots.indices.contains(index) && entry.shortcuts.indices.contains(index):
                Button(intent: RunSystemShortcutIntent(shortcut: entry.shortcuts[index])) {
                    VStack(spacing: metrics.titleSpacing) {
                        DirectLaunchArtwork(slot: entry.slots[index], cornerRadius: metrics.cornerRadius,
                                            maxPixelSize: entry.artworkPixelSize)
                            .frame(width: metrics.iconSide, height: metrics.iconSide)
                        if entry.style.showsTitles { title(item.displayTitle, metrics: metrics) }
                    }
                    .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(item.displayTitle))
                .accessibilityHint("运行此动作")
                .dateIconAccessibilityValue(entry.slots[index].customIcons)
            case .ambiguous:
                unresolved(item, message: "同名冲突", metrics: metrics)
            default:
                unresolved(item, message: "未配置", metrics: metrics)
            }
        }
    }

    private func websiteFace(_ item: GroupItem, metrics: FolderGridMetrics) -> some View {
        VStack(spacing: metrics.titleSpacing) {
            WebsiteArtwork(variants: entry.tileArtwork[item.id], cornerRadius: metrics.cornerRadius,
                           usesWidgetRendering: true, maxPixelSize: entry.artworkPixelSize)
                .frame(width: metrics.iconSide, height: metrics.iconSide)
            if entry.style.showsTitles { title(item.displayTitle, metrics: metrics) }
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        .contentShape(Rectangle())
    }

    private func unresolved(_ item: GroupItem, message: LocalizedStringKey, metrics: FolderGridMetrics) -> some View {
        Link(destination: helpURL(for: item)) {
            VStack(spacing: metrics.titleSpacing) {
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: metrics.iconSide * 0.25))
                    Text(message).font(.system(size: max(6, metrics.iconSide * 0.16)))
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(width: metrics.iconSide, height: metrics.iconSide)
                .background(.fill.tertiary, in: .rect(cornerRadius: metrics.cornerRadius))
                if entry.style.showsTitles { title(item.displayTitle, metrics: metrics) }
            }
            .foregroundStyle(entry.style.titleStyle)
            .frame(width: metrics.cellWidth, height: metrics.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.displayTitle))
        .accessibilityValue(Text(message))
        .accessibilityHint("打开此项目的配置帮助")
    }

    private func helpURL(for item: GroupItem) -> URL {
        // The report identity includes this layout revision and configuration,
        // so another widget's successful match cannot be shown as this one's.
        let rootStyle = entry.rootStyle ?? entry.style
        let report = entry.savedGroup.flatMap {
            SavedGroupBindingReport(group: $0, configurationKey: entry.expansionKey,
                                    grid: rootStyle.grid, familyRawValue: family.rawValue,
                                    actionNames: entry.slots.map(\.name), checkedAt: entry.date, density: rootStyle.density)
        }
        return SavedGroupHelpRoute(groupID: entry.savedGroup?.id ?? entry.selectedGroupID ?? item.id,
                                   itemID: item.id, reportID: report?.id).url
    }

    private func title(_ name: String, metrics: FolderGridMetrics) -> some View {
        FolderTitleText(text: name, fontSize: metrics.titleFontSize, width: metrics.cellWidth,
                        style: entry.style, usesWidgetRendering: true,
                        availableHeight: metrics.labelHeight - metrics.titleSpacing)
    }

    @ViewBuilder
    private func folderArtwork(_ folder: GroupItem, metrics: FolderGridMetrics) -> some View {
        if let cover = entry.tileArtwork[folder.id]?.resolved(isDark: colorScheme == .dark) {
            let side = metrics.iconSide
            CustomIconArtwork(icon: cover, cornerRadius: metrics.cornerRadius,
                              usesWidgetRendering: true, maxPixelSize: entry.artworkPixelSize)
                .frame(width: side, height: side)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: max(7, side * 0.16), weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: max(13, side * 0.3), height: max(13, side * 0.3))
                        .background(.black.opacity(0.7), in: .circle)
                        .padding(side * 0.03)
                }
                .accessibilityHidden(true)
        } else {
            folderContentArtwork(folder, metrics: metrics)
        }
    }

    private func folderContentArtwork(_ folder: GroupItem, metrics: FolderGridMetrics) -> some View {
        let leaves = folder.previewLeafItems
        let columns = (folder.folderPreviewGrid ?? .four).columns
        let side = metrics.iconSide
        // Keep the established 2x2 geometry; a chosen 3x3 uses the same block
        // footprint so its embedded name and rounded corners remain clear.
        let miniatureSide = columns == 2 ? side * 0.24 : side * 0.16
        let spacing = columns == 2 ? side * 0.05 : side * 0.025
        return VStack(spacing: 1) {
            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                ForEach(0..<columns, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            Group {
                                if leaves.indices.contains(index), let target = leaves[index].contactTarget {
                                    ContactArtwork(target: target, variants: entry.tileArtwork[leaves[index].id],
                                                   cornerRadius: side * 0.05, usesWidgetRendering: true, maxPixelSize: 32)
                                } else if leaves.indices.contains(index), leaves[index].kind == .website {
                                    WebsiteArtwork(variants: entry.tileArtwork[leaves[index].id],
                                                   cornerRadius: side * 0.05, usesWidgetRendering: true,
                                                   maxPixelSize: 32)
                                } else if leaves.indices.contains(index),
                                          case .matched(let slotIndex) = binding.resolve(leaves[index].name),
                                          entry.slots.indices.contains(slotIndex) {
                                    DirectLaunchArtwork(slot: entry.slots[slotIndex], cornerRadius: side * 0.05,
                                                        maxPixelSize: 32)
                                } else {
                                    RoundedRectangle(cornerRadius: side * 0.04).fill(.fill.secondary)
                                }
                            }
                            .frame(width: miniatureSide, height: miniatureSide)
                        }
                    }
                }
            }
            if !entry.style.showsTitles {
                FolderTitleText(text: folder.name, fontSize: max(6, side * 0.17), width: side * 0.9,
                                style: entry.style, minimumScaleFactor: 0.6, weight: .medium,
                                usesWidgetRendering: true)
            }
        }
        .frame(width: side, height: side)
        .background(.fill.tertiary, in: .rect(cornerRadius: metrics.cornerRadius))
        .accessibilityHidden(true)
    }

}
