import AppFolderKit
import CoreGraphics
import SwiftUI
import UIKit
import WidgetKit

enum SavedGroupAppearanceColorTarget: Equatable { case plate, title, outline }

/// Uses the same page selection as the widget, with inert action tiles.
struct SavedGroupPreview: View {
    let group: SavedGroup
    @Binding var path: [UUID]
    var onAppearanceChange: (SavedGroupAppearance?, [UUID]) -> Void
    var onFolderPreviewGridChange: (FolderPreviewGrid?, [UUID]) -> Void
    var onInteractionBoundary: () -> Void = {}
    var onAppearanceColorChange: (String, SavedGroupAppearanceColorTarget, [UUID], UUID) -> Bool = { _, _, _, _ in false }
    var canEditAppearancePresets: Bool = true
    var onPresetAppearanceApply: (SavedGroupAppearance, [UUID], UUID, String) -> Bool = { _, _, _, _ in false }
    var canvasController: SavedGroupCanvasDragController? = nil
    var canvasRevision: String? = nil
    var onCanvasDrop: (SavedGroupDropRequest) -> SavedGroupDropOutcome = { _ in .rejected(.invalidTarget) }
    var coverVariants: (FolderCover?, Int) -> CustomIconVariants? = {
        FolderCoverAssetStore.variants(for: $0, maxSide: $1)
    }
    @State private var requestedPage = 0
    @State private var pagePath: [UUID] = []
    @State private var family: WidgetFamily = .systemSmall
    @State private var showsColorPicker = false
    @State private var tintPath: [UUID]?
    @State private var colorTarget: SavedGroupAppearanceColorTarget = .plate
    @State private var colorPickerPermitID: UUID?
    @State private var appearancePresetSession: AppearancePresetSession?
    @State private var appearancePresetPermitID: UUID?
    @State private var adjustsCanvas = false
    @State private var pendingMovedItemID: UUID?
    @Namespace private var canvasNamespace
    @Environment(\.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    private var settings: SavedGroupAppearance { group.resolvedAppearance(at: path) ?? group.resolvedAppearance }
    private var ownAppearance: SavedGroupAppearance? { group.appearanceOverride(at: path) }
    private var layout: SavedGroupPageLayout {
        SavedGroupPageLayout(group: group, path: path, page: pagePath == path ? requestedPage : 0,
                             family: family, useGroupAppearance: true, widgetStyle: group.resolvedAppearance.style)
    }
    private var style: FolderStyle { layout.style }
    private var grid: FolderGrid { settings.grid }
    private var density: FolderDensity { settings.density }
    private var showsTitles: Bool { settings.showsTitles }
    private var iconScale: Double { settings.iconSize.scale }
    private var placeholderFill: AnyShapeStyle? {
        guard style.plate.usesTint else { return nil }
        return AnyShapeStyle(style.tint.isLight ? Color.black.opacity(0.18) : Color.white.opacity(0.18))
    }
    private var miniaturePlaceholderFill: AnyShapeStyle? {
        guard style.plate.usesTint else { return nil }
        return AnyShapeStyle(style.tint.isLight ? Color.black.opacity(0.32) : Color.white.opacity(0.32))
    }
    private var columns: Int { grid.columns(for: family, density: density) }
    private var capacity: Int { grid.cellCount(for: family, density: density) }
    private var artworkPixelSize: Int { WidgetArtworkResolution.maximumPixelSize(cellCount: capacity) }
    private var referenceSize: CGSize {
        switch family {
        case .systemMedium: CGSize(width: 364, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        // Reference measured on the Test iPhone 18 Pro simulator, not a universal device size.
        case .systemExtraLargePortrait: CGSize(width: 349.6666666666667, height: 565.6666666666666)
        default: CGSize(width: 170, height: 170)
        }
    }
    private var page: SavedGroupPage { layout.page }
    private var locationGroup: SavedGroup {
        // The editor can have an unfinished name while its internal tree stays
        // valid. Use a local valid name only for identity lookup, never saving it.
        var copy = group
        copy.name = "Canvas"
        return copy
    }
    private var currentFolder: GroupItem? {
        folder(at: path)
    }
    private func folder(at targetPath: [UUID]) -> GroupItem? {
        guard let id = targetPath.last else { return nil }
        return group.items(at: Array(targetPath.dropLast()))?.first { $0.id == id && $0.kind == .folder }
    }
    private var breadcrumb: String {
        var names = [group.name]
        var parent: [UUID] = []
        for id in path {
            guard let folder = group.items(at: parent)?.first(where: { $0.id == id && $0.kind == .folder }) else { break }
            names.append(folder.name)
            parent.append(id)
        }
        return names.joined(separator: " › ")
    }
    private struct PaginationContext: Equatable {
        let path: [UUID]
        let grid: FolderGrid
        let density: FolderDensity
    }

    private struct AppearancePresetSession: Identifiable {
        let id = UUID()
        let groupID: UUID
        let revision: String
        let path: [UUID]
        let appearance: SavedGroupAppearance
        let scopeName: String
    }

    var body: some View {
        canvasContents
        .frame(maxWidth: .infinity)
        .onChange(of: PaginationContext(path: path, grid: grid, density: density)) { previous, next in
            // Changing the current grid starts at its first page. Navigation to
            // a parent with a different grid must keep that parent's target page.
            if previous.path == next.path {
                canvasController?.cancel()
                requestedPage = 0
                pagePath = next.path
            }
        }
        .onChange(of: family) { _, _ in
            canvasController?.cancel()
            onInteractionBoundary()
            requestedPage = 0
            pagePath = path
        }
        .onChange(of: path) { previous, next in
            cancelColorPicker()
            appearancePresetPermitID = nil
            if pagePath != next {
                // The content list shares this path and also has an Up button.
                // Preserve the same parent-page placement from either entry.
                let previousLayout = SavedGroupPageLayout(group: group, path: previous, page: requestedPage,
                                                           family: family, useGroupAppearance: true,
                                                           widgetStyle: group.resolvedAppearance.style)
                let parent = previousLayout.parentNavigation
                requestedPage = parent?.path == next ? parent?.page ?? 0 : 0
                pagePath = next
            }
            onInteractionBoundary()
        }
        .onChange(of: requestedPage) { _, _ in onInteractionBoundary() }
        .onChange(of: group.revision) { _, _ in
            appearancePresetPermitID = nil
            if let movedID = pendingMovedItemID {
                pendingMovedItemID = nil
                revealItem(movedID)
            } else {
                let resolved = page
                path = resolved.path
                pagePath = resolved.path
                requestedPage = resolved.page
            }
            if let tintPath, group.items(at: tintPath) == nil { showsColorPicker = false }
        }
        .onChange(of: adjustsCanvas) { _, _ in
            canvasController?.cancel()
            pendingMovedItemID = nil
            onInteractionBoundary()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                canvasController?.cancel()
                appearancePresetPermitID = nil
                cancelColorPicker()
            }
        }
        .onChange(of: canEditAppearancePresets) { _, isAllowed in
            if !isAllowed {
                appearancePresetPermitID = nil
                cancelColorPicker()
            }
        }
        .onDisappear {
            canvasController?.cancel()
            appearancePresetPermitID = nil
            cancelColorPicker()
        }
        .sheet(isPresented: $showsColorPicker, onDismiss: {
            colorPickerPermitID = nil
            tintPath = nil
            colorTarget = .plate
            onInteractionBoundary()
        }) {
            let permit = colorPickerPermitID
            SavedGroupColorPicker(color: tintBinding) { finishColorPicker(permit) }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button { finishColorPicker(permit) } label: {
                        Text("完成").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("groupPreview.finishTint")
                    .padding().background(.bar)
                }
        }
        .sheet(item: $appearancePresetSession, onDismiss: {
            appearancePresetPermitID = nil
            onInteractionBoundary()
        }) { session in
            AppearancePresetsView(currentAppearance: session.appearance, scopeName: session.scopeName,
                                  canApply: canApplyPreset(in: session)) { appearance in
                applyPreset(appearance, in: session)
            }
        }
    }

    @ViewBuilder
    private var canvasContents: some View {
        if let canvasController {
            previewContents.savedGroupCanvasDragContainer(
                controller: canvasController, namespace: canvasNamespace,
                groupID: group.id, revision: canvasRevision ?? group.revision,
                enabled: adjustsCanvas && canvasRevision != nil && !showsColorPicker && appearancePresetSession == nil
            )
        } else {
            previewContents
        }
    }

    private var previewContents: some View {
        VStack(spacing: 12) {
            scopeControls
            if canvasController != nil {
                Toggle("调整图标位置", isOn: $adjustsCanvas)
                    .disabled(canvasRevision == nil)
                    .accessibilityIdentifier("groupPreview.adjustPositions")
            }
            scaledPreview
            if adjustsCanvas { canvasMoveControls }
            controls
            VStack(spacing: 4) {
                Text("外观随分组保存。在「编辑小组件」中选择分组并开启「使用分组外观」即可应用；这个开关默认关闭，关闭时使用小组件自己的外观。预览尺寸不会改变桌面尺寸。")
                Text("桌面效果可能随系统外观调整，与这里的预览略有不同。")
            }
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canvasMoveControls: some View {
        VStack(spacing: 8) {
            Text("拖到图标前调整顺序，拖到空位交换位置；停留在文件夹、翻页或返回图标上可继续移动。也可从项目菜单选择移动，再到目标位置放置。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let canvasController, canvasController.isManualSelection,
               let source = canvasController.activeSource {
                if let location = locationGroup.itemLocation(id: source.itemID),
                   let siblings = group.items(at: location.path), siblings.indices.contains(location.index) {
                    let item = siblings[location.index]
                    Text("正在移动：\(item.kind == .spacer ? String(localized: "空位") : item.displayTitle)")
                        .font(.subheadline)
                        .accessibilityIdentifier("groupPreview.movingItem")
                }
                Button {
                    submitManualDrop(.append(folderID: page.path.last))
                } label: {
                    Label("移到当前文件夹末尾", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("groupPreview.moveToEnd")
                Button(role: .cancel) { canvasController.cancel() } label: {
                    Text("取消移动").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("groupPreview.cancelMove")
            }
        }
    }

    private var scopeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if path.isEmpty {
                Text("分组默认外观").font(.headline)
            } else {
                Text("「\(page.folderName)」的内部外观").font(.headline)
                Text(verbatim: breadcrumb).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("内部外观来源", selection: usesOwnAppearance) {
                    Text("跟随上级").tag(false)
                    Text("单独设置").tag(true)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("groupPreview.appearanceSource")
                if ownAppearance == nil {
                    Text("当前跟随上级。修改下面的内部外观设置后，会为这个文件夹单独保存外观。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("未单独设置外观的下级文件夹会跟随这里。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("groupPreview.scope")
    }

    private var usesOwnAppearance: Binding<Bool> {
        let targetPath = path
        return Binding {
            group.appearanceOverride(at: targetPath) != nil
        } set: { usesOwn in
            guard let inherited = group.resolvedAppearance(at: targetPath), !targetPath.isEmpty else { return }
            onInteractionBoundary()
            onAppearanceChange(usesOwn ? inherited : nil, targetPath)
            onInteractionBoundary()
        }
    }

    /// Compute at the same reference geometry as the widget, then scale the
    /// entire canvas. Measuring the scaled size would change fixed font floors.
    private var scaledPreview: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / referenceSize.width, proxy.size.height / referenceSize.height)
            Group {
                if page.items.isEmpty && layout.parentNavigation == nil { emptyFolder }
                else { previewGrid }
            }
            .frame(width: referenceSize.width, height: referenceSize.height)
            .background {
                if let fill = style.plateFill { Rectangle().fill(fill) }
                else { Color(uiColor: .secondarySystemBackground) }
            }
            .clipShape(.rect(cornerRadius: FolderGridMetrics.widgetCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: FolderGridMetrics.widgetCornerRadius).strokeBorder(.quaternary)
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(referenceSize.width / referenceSize.height, contentMode: .fit)
        .frame(maxWidth: referenceSize.width)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptyFolder: some View {
        if adjustsCanvas, let canvasController {
            let targetID = "empty-folder:\(page.path.map(\.uuidString).joined(separator: "/")):\(page.page)"
            emptyFolderContents
                .contentShape(Rectangle())
                .savedGroupCanvasDropDestination(
                    controller: canvasController, targetID: targetID,
                    target: .append(folderID: page.path.last), onDrop: submitCanvasDrop
                )
                .overlay { canvasHighlight(targetID: targetID) }
                .contextMenu {
                    if canvasController.isManualSelection {
                        Button("移到当前文件夹末尾") { submitManualDrop(.append(folderID: page.path.last)) }
                    }
                }
                .accessibilityAction(named: Text("移到当前文件夹末尾")) {
                    submitManualDrop(.append(folderID: page.path.last))
                }
        } else {
            emptyFolderContents
        }
    }

    private var emptyFolderContents: some View {
        VStack(spacing: 4) {
            Image(systemName: "folder").font(.title2)
            Text("这里还没有内容，先添加动作、联系人、网站或文件夹。")
                .font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(style.titleStyle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                openAppearancePresets()
            } label: {
                Label("外观预设", systemImage: "paintpalette")
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .disabled(!canEditAppearancePresets || showsColorPicker || scenePhase != .active)
            .accessibilityIdentifier("groupPreview.appearancePresets")
            Picker("预览尺寸", selection: $family) {
                Text("小号").tag(WidgetFamily.systemSmall)
                Text("中号").tag(WidgetFamily.systemMedium)
                Text("大号").tag(WidgetFamily.systemLarge)
                Text("竖向超大").tag(WidgetFamily.systemExtraLargePortrait)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("groupPreview.family")
            if family == .systemSmall {
                Picker("小号网格", selection: appearanceBinding(\.grid)) {
                    Text("九宫格").tag(FolderGrid.nine)
                    Text("四宫格").tag(FolderGrid.four)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("groupPreview.grid")
            } else {
                Picker("布局密度", selection: appearanceBinding(\.density)) {
                    Text("标准").tag(FolderDensity.standard)
                    Text("大图标").tag(FolderDensity.spacious)
                    Text("密集").tag(FolderDensity.dense)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("groupPreview.density")
                LabeledContent("预览网格") {
                    Text("\(columns) 列 × \(capacity / columns) 行（\(capacity) 格）")
                }
                .font(.subheadline)
                .accessibilityIdentifier("groupPreview.gridDimensions")
            }
            Toggle("显示图标名称", isOn: appearanceBinding(\.showsTitles))
                .font(.subheadline)
                .accessibilityIdentifier("groupPreview.titles")
            Picker("图标大小", selection: appearanceBinding(\.iconSize)) {
                Text("小号").tag(SavedGroupIconSize.small)
                Text("中号").tag(SavedGroupIconSize.medium)
                Text("大号").tag(SavedGroupIconSize.large)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("groupPreview.iconSize")
            Picker("返回按钮样式", selection: appearanceBinding(\.backButtonStyle)) {
                Label("向上箭头", systemImage: FolderBackButtonStyle.chevronUp.systemImage)
                    .tag(FolderBackButtonStyle.chevronUp)
                Label("转向箭头", systemImage: FolderBackButtonStyle.turnUpLeft.systemImage)
                    .tag(FolderBackButtonStyle.turnUpLeft)
                Label("文件夹", systemImage: FolderBackButtonStyle.folder.systemImage)
                    .tag(FolderBackButtonStyle.folder)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("groupPreview.backButtonStyle")
            Picker("底板", selection: appearanceBinding(\.plate)) {
                Text("自动").tag(FolderPlate.automatic)
                Text("纯色").tag(FolderPlate.solid)
                Text("渐变").tag(FolderPlate.gradient)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("groupPreview.plate")
            if settings.plate.usesTint {
                Button {
                    openColorPicker(.plate)
                } label: {
                    HStack {
                        Text("底板颜色")
                        Spacer()
                        Circle().fill(style.tint.color)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1) }
                            .frame(width: 28, height: 28)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("底板颜色")
                .accessibilityValue(Text(verbatim: settings.tintHex))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("groupPreview.tint")
            }
            fineAppearanceControls
            if let folder = currentFolder {
                Divider()
                HStack {
                    Text("内容缩略图")
                    Spacer()
                    FolderContentsArtwork(folder: folder, leafVariants: { coverVariants($0, 32) })
                        .frame(width: 48, height: 48)
                }
                Picker("缩略图网格", selection: folderPreviewGridBinding) {
                    Text("2 × 2（4 项）").tag(FolderPreviewGrid.four)
                    Text("3 × 3（9 项）").tag(FolderPreviewGrid.nine)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("groupPreview.folderPreviewGrid")
                Text("只影响这个文件夹在上一级的内容缩略图，不跟随上级外观。自定义封面优先显示。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controlMetrics: FolderGridMetrics {
        FolderGridMetrics(tileCount: capacity, columns: columns, in: referenceSize,
                          showsTitles: showsTitles, iconScale: iconScale, family: family, density: density,
                          spacing: settings.spacing, margin: settings.margin)
    }

    private var fineAppearanceControls: some View {
        DisclosureGroup("精细外观") {
            VStack(spacing: 12) {
                Toggle("自定图标间距", isOn: optionalSpacingEnabled(\.spacing, suggested: controlMetrics.spacing, limit: 24))
                    .accessibilityIdentifier("groupPreview.customSpacing")
                if settings.spacing != nil {
                    Stepper(value: optionalSpacingValue(\.spacing), in: 0...24) {
                        Text("图标间距：\(settings.spacing ?? 0) 点")
                    }
                    .accessibilityIdentifier("groupPreview.spacing")
                }
                Toggle("自定四周边距", isOn: optionalSpacingEnabled(\.margin, suggested: controlMetrics.margin, limit: 40))
                    .accessibilityIdentifier("groupPreview.customMargin")
                if settings.margin != nil {
                    Stepper(value: optionalSpacingValue(\.margin), in: 0...40) {
                        Text("四周边距：\(settings.margin ?? 0) 点")
                    }
                    .accessibilityIdentifier("groupPreview.margin")
                }
                Text("关闭后恢复自动排布。空间不足时会收紧间距和边距；图标大小仍可单独调整。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle("自定文字颜色", isOn: optionalColorEnabled(\.titleColorHex, initialColor: style.labelColor))
                    .accessibilityIdentifier("groupPreview.customTitleColor")
                if let color = settings.titleColorHex {
                    appearanceColorButton("文字颜色", target: .title, hex: color,
                                          identifier: "groupPreview.titleColor")
                }
                Toggle("文字描边", isOn: optionalColorEnabled(\.titleOutlineHex, initialColor: .black))
                    .accessibilityIdentifier("groupPreview.titleOutline")
                if let color = settings.titleOutlineHex {
                    appearanceColorButton("描边颜色", target: .outline, hex: color,
                                          identifier: "groupPreview.titleOutlineColor")
                    Picker("描边粗细", selection: appearanceBinding(\.titleOutlineWidth)) {
                        Text("细").tag(SavedGroupTitleOutlineWidth.thin)
                        Text("中").tag(SavedGroupTitleOutlineWidth.medium)
                        Text("粗").tag(SavedGroupTitleOutlineWidth.thick)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("groupPreview.titleOutlineWidth")
                }
                Text("文字选项用于图标名称和文件夹内嵌名称，不改变图标或导航箭头。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
        .accessibilityIdentifier("groupPreview.fineAppearance")
    }

    private func optionalSpacingEnabled(_ keyPath: WritableKeyPath<SavedGroupAppearance, Int?>,
                                        suggested: CGFloat, limit: Int) -> Binding<Bool> {
        let value = appearanceBinding(keyPath)
        let initial = Int(min(CGFloat(limit), max(0, suggested.isFinite ? suggested.rounded() : 0)))
        return Binding(get: { value.wrappedValue != nil }, set: { enabled in
            onInteractionBoundary()
            value.wrappedValue = enabled ? (value.wrappedValue ?? initial) : nil
            onInteractionBoundary()
        })
    }

    private func optionalSpacingValue(_ keyPath: WritableKeyPath<SavedGroupAppearance, Int?>) -> Binding<Int> {
        let value = appearanceBinding(keyPath)
        return Binding(get: { value.wrappedValue ?? 0 }, set: { next in
            guard value.wrappedValue != nil else { return }
            value.wrappedValue = next
        })
    }

    private func optionalColorEnabled(_ keyPath: WritableKeyPath<SavedGroupAppearance, String?>,
                                      initialColor: Color) -> Binding<Bool> {
        let value = appearanceBinding(keyPath)
        let initial = hexColor(initialColor) ?? "#000000"
        return Binding(get: { value.wrappedValue != nil }, set: { enabled in
            onInteractionBoundary()
            value.wrappedValue = enabled ? (value.wrappedValue ?? initial) : nil
            onInteractionBoundary()
        })
    }

    private func appearanceColorButton(_ label: LocalizedStringKey, target: SavedGroupAppearanceColorTarget,
                                       hex: String, identifier: String) -> some View {
        Button { openColorPicker(target) } label: {
            HStack {
                Text(label)
                Spacer()
                Circle().fill(FolderTint(hex: hex)?.color ?? .clear)
                    .overlay { Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1) }
                    .frame(width: 28, height: 28)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: hex))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    private func openColorPicker(_ target: SavedGroupAppearanceColorTarget) {
        guard scenePhase == .active, canEditAppearancePresets,
              !showsColorPicker, appearancePresetSession == nil else { return }
        canvasController?.cancel()
        onInteractionBoundary()
        colorTarget = target
        tintPath = path
        colorPickerPermitID = UUID()
        showsColorPicker = true
    }

    private func cancelColorPicker() {
        colorPickerPermitID = nil
        showsColorPicker = false
    }

    private func finishColorPicker(_ permit: UUID?) {
        guard let permit, colorPickerPermitID == permit else { return }
        cancelColorPicker()
    }

    private func openAppearancePresets() {
        guard canEditAppearancePresets, scenePhase == .active,
              !showsColorPicker, appearancePresetSession == nil,
              let appearance = group.resolvedAppearance(at: path) else { return }
        canvasController?.cancel()
        onInteractionBoundary()
        let session = AppearancePresetSession(groupID: group.id, revision: group.revision, path: path,
                                              appearance: appearance,
                                              scopeName: path.isEmpty ? String(localized: "分组默认外观") : page.folderName)
        appearancePresetPermitID = session.id
        appearancePresetSession = session
    }

    private func canApplyPreset(in session: AppearancePresetSession) -> Bool {
        canEditAppearancePresets && scenePhase == .active && appearancePresetPermitID == session.id
            && appearancePresetSession?.id == session.id && group.id == session.groupID
            && group.revision == session.revision && path == session.path
            && group.resolvedAppearance(at: session.path) != nil
    }

    private func applyPreset(_ appearance: SavedGroupAppearance, in session: AppearancePresetSession) -> Bool {
        guard appearance.isValid, canApplyPreset(in: session) else { return false }
        appearancePresetPermitID = nil
        canvasController?.cancel()
        onInteractionBoundary()
        // Applying to an inheriting child deliberately creates its own value,
        // even when the inherited appearance happens to match this preset.
        let applied = onPresetAppearanceApply(appearance, session.path, session.groupID, session.revision)
        onInteractionBoundary()
        guard applied else { return false }
        appearancePresetSession = nil
        return true
    }

    private var folderPreviewGridBinding: Binding<FolderPreviewGrid> {
        let targetPath = path
        return Binding {
            folder(at: targetPath)?.folderPreviewGrid ?? .four
        } set: { value in
            guard !targetPath.isEmpty else { return }
            onInteractionBoundary()
            onFolderPreviewGridChange(value == .four ? nil : value, targetPath)
        }
    }

    /// Opening the preview or selecting its current value leaves a legacy nil
    /// appearance untouched. Only an actual setting change updates the draft.
    private func appearanceBinding<Value: Equatable>(_ keyPath: WritableKeyPath<SavedGroupAppearance, Value>,
                                                    at capturedPath: [UUID]? = nil) -> Binding<Value> {
        let targetPath = capturedPath ?? path
        return Binding {
            (group.resolvedAppearance(at: targetPath) ?? settings)[keyPath: keyPath]
        } set: { value in
            guard var next = group.resolvedAppearance(at: targetPath) else { return }
            guard next[keyPath: keyPath] != value else { return }
            next[keyPath: keyPath] = value
            onAppearanceChange(next, targetPath)
        }
    }

    private var tintBinding: Binding<Color> {
        let targetPath = tintPath ?? path
        let target = colorTarget
        let permit = colorPickerPermitID
        let groupID = group.id
        return Binding {
            let appearance = group.resolvedAppearance(at: targetPath) ?? settings
            switch target {
            case .plate: return appearance.style.tint.color
            case .title: return appearance.style.labelColor
            case .outline: return appearance.style.titleOutlineTint?.color ?? .black
            }
        } set: { color in
            guard let permit, colorPickerPermitID == permit,
                  showsColorPicker, scenePhase == .active, tintPath == targetPath,
                  colorTarget == target, let hex = hexColor(color) else { return }
            // The owner changes only this color in its live draft. The old
            // binding cannot restore a disabled color or replace newer fields.
            if !onAppearanceColorChange(hex, target, targetPath, groupID) {
                cancelColorPicker()
            }
        }
    }

    private func hexColor(_ color: Color) -> String? {
        let resolved = color.resolve(in: environment)
        let red = Double(resolved.red), green = Double(resolved.green), blue = Double(resolved.blue)
        guard red.isFinite, green.isFinite, blue.isFinite else { return nil }
        return FolderTint(red: min(max(red, 0), 1), green: min(max(green, 0), 1),
                          blue: min(max(blue, 0), 1)).hex
    }

    private func navigate(to targetPath: [UUID], page targetPage: Int) {
        pagePath = targetPath
        requestedPage = targetPage
        path = targetPath
    }

    private func navigateDuringDrag(to targetPath: [UUID], page targetPage: Int) {
        guard let source = canvasController?.activeSource,
              !targetPath.contains(source.itemID), group.items(at: targetPath) != nil else { return }
        navigate(to: targetPath, page: targetPage)
    }

    private func revealItem(_ itemID: UUID) {
        guard let location = locationGroup.itemLocation(id: itemID) else {
            let resolved = page
            navigate(to: resolved.path, page: resolved.page)
            return
        }
        let first = SavedGroupPageLayout(group: group, path: location.path, page: 0,
                                        family: family, useGroupAppearance: true,
                                        widgetStyle: group.resolvedAppearance.style)
        // Parent/previous/next tiles consume a variable number of cells. Find
        // the actual page by identity instead of dividing an index by capacity.
        for pageIndex in 0..<first.page.pageCount {
            let candidate = SavedGroupPageLayout(group: group, path: location.path, page: pageIndex,
                                                 family: family, useGroupAppearance: true,
                                                 widgetStyle: group.resolvedAppearance.style)
            if candidate.page.visibleItems.contains(where: { $0.id == itemID }) {
                navigate(to: location.path, page: pageIndex)
                return
            }
        }
        navigate(to: location.path, page: 0)
    }

    @discardableResult
    private func submitCanvasDrop(_ request: SavedGroupDropRequest) -> Bool {
        onInteractionBoundary()
        switch onCanvasDrop(request) {
        case .changed:
            pendingMovedItemID = request.itemID
            return true
        case .unchanged:
            return true
        case .rejected:
            return false
        }
    }

    private func submitManualDrop(_ target: SavedGroupDropTarget) {
        guard let request = canvasController?.requestManual(target: target) else { return }
        submitCanvasDrop(request)
    }

    private var previewGrid: some View {
        let currentLayout = layout
        return GeometryReader { proxy in
            let metrics = FolderGridMetrics(tileCount: capacity, columns: columns,
                                            in: proxy.size, showsTitles: showsTitles,
                                            iconScale: iconScale, family: family, density: density,
                                            spacing: settings.spacing, margin: settings.margin)
            Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                ForEach(0..<metrics.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<metrics.columns, id: \.self) { column in
                            let index = row * metrics.columns + column
                            if currentLayout.cells.indices.contains(index) {
                                let firstEmpty = currentLayout.cells.firstIndex(of: .empty) ?? index
                                gridCell(currentLayout.cells[index], emptyOffset: max(0, index - firstEmpty),
                                         layout: currentLayout, metrics: metrics)
                                    .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                            } else {
                                Color.clear.frame(width: metrics.cellWidth, height: metrics.cellHeight)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .transaction { $0.animation = nil }
            .padding(metrics.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: family == .systemSmall ? .top : .center)
        }
    }

    @ViewBuilder
    private func gridCell(_ value: SavedGroupGridCell, emptyOffset: Int, layout: SavedGroupPageLayout,
                          metrics: FolderGridMetrics) -> some View {
        switch value {
        case .item(let item):
            editableCell(item, metrics: metrics)
        case .parent:
            if let parent = layout.parentNavigation {
                navigationTile(symbol: style.backButtonStyle.systemImage, label: "上一级文件夹",
                               path: parent.path, targetPage: parent.page, layout: layout, metrics: metrics)
            }
        case .previous:
            navigationTile(symbol: "chevron.left", label: "上一页", path: layout.page.path,
                           targetPage: layout.page.page - 1, layout: layout, metrics: metrics)
        case .next:
            navigationTile(symbol: "chevron.right", label: "下一页", path: layout.page.path,
                           targetPage: layout.page.page + 1, layout: layout, metrics: metrics)
        case .empty:
            if adjustsCanvas, let canvasController {
                let target = SavedGroupDropTarget.vacant(folderID: layout.page.path.last,
                                                         capacity: layout.page.capacity, emptyOffset: emptyOffset)
                let targetID = "vacant:\(layout.page.path.last?.uuidString ?? "root"):\(layout.page.page):\(emptyOffset)"
                canvasVacancyTarget(metrics: metrics, target: target)
                    .contentShape(Rectangle())
                    .savedGroupCanvasDropDestination(controller: canvasController, targetID: targetID,
                                                     target: target, onDrop: submitCanvasDrop)
                    .overlay { canvasHighlight(targetID: targetID) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("可放置位置")
                    .accessibilityAction(named: Text("放入空位")) { submitManualDrop(target) }
                    .accessibilityIdentifier("groupPreview.vacant.\(emptyOffset)")
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func navigationTile(symbol: String, label: LocalizedStringKey, path targetPath: [UUID], targetPage: Int,
                                layout: SavedGroupPageLayout, metrics: FolderGridMetrics) -> some View {
        if adjustsCanvas, let canvasController {
            let targetID = "navigation:\(layout.page.path.map(\.uuidString).joined(separator: "/")):\(layout.page.page):\(targetPath.map(\.uuidString).joined(separator: "/")):\(targetPage)"
            navigationTileContents(symbol: symbol, label: label, path: targetPath, targetPage: targetPage,
                                   layout: layout, metrics: metrics)
                .savedGroupCanvasDropDestination(controller: canvasController, targetID: targetID, target: nil,
                                                 onHover: { navigateDuringDrag(to: targetPath, page: targetPage) },
                                                 onDrop: { _ in false })
                .overlay { canvasHighlight(targetID: targetID) }
        } else {
            navigationTileContents(symbol: symbol, label: label, path: targetPath, targetPage: targetPage,
                                   layout: layout, metrics: metrics)
        }
    }

    private func navigationTileContents(symbol: String, label: LocalizedStringKey, path targetPath: [UUID], targetPage: Int,
                                        layout: SavedGroupPageLayout, metrics: FolderGridMetrics) -> some View {
        Button { navigate(to: targetPath, page: targetPage) } label: {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                        .fill(.fill.tertiary)
                    Image(systemName: symbol)
                        .font(.system(size: metrics.iconSide * 0.34, weight: .semibold))
                        .foregroundStyle(style.titleStyle)
                }
                .frame(width: metrics.iconSide, height: metrics.iconSide)
                if showsTitles { Color.clear.frame(height: metrics.labelHeight) }
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

    @ViewBuilder
    private func editableCell(_ item: GroupItem, metrics: FolderGridMetrics) -> some View {
        if adjustsCanvas, let canvasController {
            let target: SavedGroupDropTarget = item.kind == .spacer ? .spacer(itemID: item.id) : .before(itemID: item.id)
            let targetID = "item:\(page.path.map(\.uuidString).joined(separator: "/")):\(page.page):\(item.id.uuidString)"
            editableDropCell(item, target: target, targetID: targetID,
                             controller: canvasController, metrics: metrics)
                .overlay { canvasHighlight(targetID: targetID, itemID: item.id) }
                .accessibilityActions { canvasItemActions(item, target: target) }
        } else {
            cell(item, metrics: metrics)
        }
    }

    private func editableDropCell(_ item: GroupItem, target: SavedGroupDropTarget, targetID: String,
                                  controller: SavedGroupCanvasDragController,
                                  metrics: FolderGridMetrics) -> some View {
        editableDragCell(item, target: target, controller: controller, metrics: metrics)
            .savedGroupCanvasDropDestination(controller: controller, targetID: targetID,
                                             target: target, onHover: canvasHoverAction(for: item),
                                             onDrop: submitCanvasDrop)
    }

    private func editableDragCell(_ item: GroupItem, target: SavedGroupDropTarget,
                                  controller: SavedGroupCanvasDragController,
                                  metrics: FolderGridMetrics) -> some View {
        editableCellContents(item, target: target, metrics: metrics)
            .contentShape(Rectangle())
            .savedGroupCanvasDragSource(controller: controller, namespace: canvasNamespace, itemID: item.id)
    }

    private func canvasHoverAction(for item: GroupItem) -> (@MainActor () -> Void)? {
        guard item.kind == .folder else { return nil }
        let targetPath = page.path + [item.id]
        return { navigateDuringDrag(to: targetPath, page: 0) }
    }

    @ViewBuilder
    private func editableCellContents(_ item: GroupItem, target: SavedGroupDropTarget,
                                      metrics: FolderGridMetrics) -> some View {
        if item.kind == .folder {
            cell(item, metrics: metrics)
                .contextMenu { canvasItemActions(item, target: target) }
        } else {
            // A tap opens editing commands; it never launches an action, site,
            // or contact. The same commands are available as VoiceOver actions.
            Menu { canvasItemActions(item, target: target) } label: {
                if item.kind == .spacer {
                    canvasVacancy(metrics: metrics, isStoredSpacer: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("空位")
                        .accessibilityIdentifier("groupPreview.spacer.\(item.id.uuidString)")
                } else {
                    cell(item, metrics: metrics)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func canvasItemActions(_ item: GroupItem, target: SavedGroupDropTarget) -> some View {
        if let canvasController {
            Button("选择此项目移动", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                onInteractionBoundary()
                _ = canvasController.selectManual(itemID: item.id)
            }
            if canvasController.isManualSelection, canvasController.activeSource?.itemID != item.id {
                Button(item.kind == .spacer ? LocalizedStringKey("放入空位") : LocalizedStringKey("移到此项前")) {
                    submitManualDrop(target)
                }
            }
        }
    }

    private func canvasVacancy(metrics: FolderGridMetrics, isStoredSpacer: Bool) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .strokeBorder(style.titleStyle.opacity(isStoredSpacer ? 0.7 : 0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .overlay {
                    Image(systemName: isStoredSpacer ? "square.dashed" : "plus")
                        .font(.system(size: metrics.iconSide * 0.28, weight: .medium))
                        .foregroundStyle(style.titleStyle)
                }
                .frame(width: metrics.iconSide, height: metrics.iconSide)
            if showsTitles { Color.clear.frame(height: metrics.labelHeight) }
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
    }

    @ViewBuilder
    private func canvasVacancyTarget(metrics: FolderGridMetrics, target: SavedGroupDropTarget) -> some View {
        if canvasController?.isManualSelection == true {
            Menu {
                Button("放入空位") { submitManualDrop(target) }
            } label: {
                canvasVacancy(metrics: metrics, isStoredSpacer: false)
            }
            .buttonStyle(.plain)
        } else {
            canvasVacancy(metrics: metrics, isStoredSpacer: false)
        }
    }

    @ViewBuilder
    private func canvasHighlight(targetID: String, itemID: UUID? = nil) -> some View {
        if let canvasController,
           canvasController.hoverTargetID == targetID || (itemID != nil && canvasController.activeSource?.itemID == itemID) {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func cell(_ item: GroupItem, metrics: FolderGridMetrics) -> some View {
        // Only this node's full artwork contributes a date accessibility value;
        // a folder's miniature children must not become its own date label.
        let variants = item.kind == .action
            ? CustomIconStore.variants(name: item.name).flatMap { $0.containsDate ? $0 : nil }
            : coverVariants(item.artworkReference, artworkPixelSize)
        switch item.kind {
        case .spacer:
            Color.clear.frame(width: metrics.cellWidth, height: metrics.cellHeight)
                .accessibilityHidden(true)
        case .folder:
            Button {
                navigate(to: page.path + [item.id], page: 0)
            } label: { face(item, metrics: metrics, variants: variants).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(item.displayTitle)
                .dateIconAccessibilityValue(variants)
                .accessibilityHint("打开文件夹")
                .accessibilityIdentifier("groupPreview.folder.\(item.id.uuidString)")
        case .action:
            face(item, metrics: metrics, variants: variants)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.displayTitle)
                .dateIconAccessibilityValue(variants)
                .accessibilityIdentifier("groupPreview.action.\(item.id.uuidString)")
        case .website:
            face(item, metrics: metrics, variants: variants)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.displayTitle)
                .dateIconAccessibilityValue(variants)
                .accessibilityIdentifier("groupPreview.website.\(item.id.uuidString)")
        case .contact:
            face(item, metrics: metrics, variants: variants)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.displayTitle)
                .dateIconAccessibilityValue(variants)
                .accessibilityIdentifier("groupPreview.contact.\(item.id.uuidString)")
        }
    }

    private func face(_ item: GroupItem, metrics: FolderGridMetrics, variants: CustomIconVariants?) -> some View {
        VStack(spacing: metrics.titleSpacing) {
            if item.kind == .folder { folderArtwork(item, metrics: metrics, variants: variants) }
            else if item.kind == .website {
                WebsiteArtwork(variants: variants,
                               cornerRadius: metrics.cornerRadius, maxPixelSize: artworkPixelSize)
                    .frame(width: metrics.iconSide, height: metrics.iconSide)
            }
            else if item.kind == .contact, let target = item.contactTarget {
                ContactArtwork(target: target, variants: variants,
                               cornerRadius: metrics.cornerRadius, maxPixelSize: artworkPixelSize)
                    .frame(width: metrics.iconSide, height: metrics.iconSide)
            }
            else {
                SavedGroupPreviewActionArtwork(name: item.name, cornerRadius: metrics.cornerRadius,
                                               maxPixelSize: artworkPixelSize,
                                               placeholderForeground: style.plate.usesTint ? style.titleStyle : nil,
                                               placeholderFill: placeholderFill)
                    .frame(width: metrics.iconSide, height: metrics.iconSide)
            }
            if showsTitles {
                FolderTitleText(text: item.displayTitle, fontSize: metrics.titleFontSize,
                                width: metrics.cellWidth, style: style,
                                availableHeight: max(0, metrics.labelHeight - metrics.titleSpacing))
            }
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
    }

    private func folderArtwork(_ folder: GroupItem, metrics: FolderGridMetrics, variants: CustomIconVariants?) -> some View {
        SavedFolderArtwork(folder: folder, cornerRadius: metrics.cornerRadius,
                           showsEmbeddedTitle: !showsTitles, titleStyle: style.titleStyle,
                           textAppearance: style,
                           miniaturePlaceholderFill: miniaturePlaceholderFill,
                           variants: variants,
                           maxPixelSize: artworkPixelSize,
                           leafVariants: { coverVariants($0, 32) })
            .frame(width: metrics.iconSide, height: metrics.iconSide)
    }

}

/// Folder covers are local to their group; absence preserves the contents preview.
struct SavedFolderArtwork: View {
    let folder: GroupItem
    var cornerRadius: CGFloat = 8
    var showsEmbeddedTitle = false
    var titleStyle: AnyShapeStyle = AnyShapeStyle(.primary)
    var textAppearance: FolderStyle? = nil
    var miniaturePlaceholderFill: AnyShapeStyle? = nil
    let variants: CustomIconVariants?
    var maxPixelSize: Int = 256
    var leafVariants: (FolderCover?) -> CustomIconVariants? = {
        FolderCoverAssetStore.variants(for: $0, maxSide: 32)
    }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let icon = variants?.resolved(isDark: colorScheme == .dark) {
                CustomIconArtwork(icon: icon, cornerRadius: cornerRadius, maxPixelSize: maxPixelSize)
                    .overlay(alignment: .bottomTrailing) {
                        GeometryReader { proxy in
                            let side = min(proxy.size.width, proxy.size.height)
                            Image(systemName: "folder.fill")
                                .font(.system(size: max(7, side * 0.16), weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: max(13, side * 0.3), height: max(13, side * 0.3))
                                .background(.black.opacity(0.7), in: Circle())
                                .padding(side * 0.03)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        }
                    }
            } else {
                FolderContentsArtwork(folder: folder, cornerRadius: cornerRadius,
                                      showsEmbeddedTitle: showsEmbeddedTitle, titleStyle: titleStyle,
                                      textAppearance: textAppearance,
                                      miniaturePlaceholderFill: miniaturePlaceholderFill,
                                      leafVariants: leafVariants)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The existing mini grid is also the editor's explicit automatic-cover preview.
/// It ignores the folder's cover so switching to Contents never shows a stale cover.
struct FolderContentsArtwork: View {
    let folder: GroupItem
    var cornerRadius: CGFloat = 8
    var showsEmbeddedTitle = false
    var titleStyle: AnyShapeStyle = AnyShapeStyle(.primary)
    var textAppearance: FolderStyle? = nil
    var miniaturePlaceholderFill: AnyShapeStyle? = nil
    var leafVariants: (FolderCover?) -> CustomIconVariants? = {
        FolderCoverAssetStore.variants(for: $0, maxSide: 32)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let leaves = folder.previewLeafItems
            let columns = (folder.folderPreviewGrid ?? .four).columns
            let miniatureSide = side * (columns == 2 ? 0.24 : 0.16)
            let spacing = side * (columns == 2 ? 0.05 : 0.025)
            let imageCornerRadius = side * 0.05
            VStack(spacing: 1) {
                Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                    ForEach(0..<columns, id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                Group {
                                    if leaves.indices.contains(index), leaves[index].kind == .website {
                                        WebsiteArtwork(variants: leafVariants(leaves[index].websiteIcon),
                                                       cornerRadius: imageCornerRadius, maxPixelSize: 32)
                                    } else if leaves.indices.contains(index), leaves[index].kind == .contact,
                                              let target = leaves[index].contactTarget {
                                        ContactArtwork(target: target, variants: leafVariants(leaves[index].contactIcon),
                                                       cornerRadius: imageCornerRadius, maxPixelSize: 32)
                                    } else if leaves.indices.contains(index) {
                                        SavedGroupPreviewActionArtwork(name: leaves[index].name, cornerRadius: imageCornerRadius,
                                                                       maxPixelSize: 32, isMiniature: true,
                                                                       placeholderFill: miniaturePlaceholderFill)
                                    } else {
                                        SavedGroupPreviewMiniPlaceholder(cornerRadius: side * 0.04,
                                                                         fill: miniaturePlaceholderFill)
                                    }
                                }
                                .frame(width: miniatureSide, height: miniatureSide)
                            }
                        }
                    }
                }
                if showsEmbeddedTitle {
                    if let textAppearance {
                        FolderTitleText(text: folder.name, fontSize: max(6, side * 0.17),
                                        width: side * 0.9, style: textAppearance,
                                        minimumScaleFactor: 0.6, weight: .medium)
                    } else {
                        Text(folder.name).font(.system(size: max(6, side * 0.17), weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(titleStyle).frame(width: side * 0.9)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(.fill.tertiary, in: .rect(cornerRadius: cornerRadius))
        }
        .accessibilityHidden(true)
    }
}

/// One native picker presentation is one color-editing session. Its delegate
/// updates the existing color binding without ending the editor's coalescing.
private struct SavedGroupColorPicker: UIViewControllerRepresentable {
    @Binding var color: Color
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(color: $color, onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(color)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.color = $color
        context.coordinator.onFinish = onFinish
        // Do not write the rounded stored color back during a drag.
    }

    static func dismantleUIViewController(_ picker: UIColorPickerViewController, coordinator: Coordinator) {
        picker.delegate = nil
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var color: Binding<Color>
        var onFinish: () -> Void

        init(color: Binding<Color>, onFinish: @escaping () -> Void) {
            self.color = color
            self.onFinish = onFinish
        }

        func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                       didSelect color: UIColor, continuously: Bool) {
            self.color.wrappedValue = Color(uiColor: color)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            onFinish()
        }
    }
}

/// The view retains only display-sized artwork and never starts a network lookup.
/// Miniatures use 32 pixels; full tiles follow the same capacity budget as widgets.
private struct SavedGroupPreviewActionArtwork: View {
    let name: String
    let cornerRadius: CGFloat
    let maxPixelSize: Int
    var isMiniature = false
    var placeholderForeground: AnyShapeStyle? = nil
    var placeholderFill: AnyShapeStyle? = nil
    @State private var artwork: SavedGroupPreviewArtworkLoader.Artwork?
    @Environment(\.colorScheme) private var colorScheme

    private struct Request: Equatable {
        let name: String
        let maxPixelSize: Int
    }

    var body: some View {
        Group {
            if let icon = artwork?.variants?.resolved(isDark: colorScheme == .dark) {
                CustomIconArtwork(icon: icon, cornerRadius: cornerRadius, maxPixelSize: maxPixelSize)
            } else if let image = artwork?.automatic {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: cornerRadius))
            } else {
                SavedGroupPreviewMiniPlaceholder(cornerRadius: cornerRadius,
                                                 fill: placeholderFill ?? (isMiniature ? nil : AnyShapeStyle(.quaternary)))
                    .overlay {
                        if isMiniature {
                            if let symbol = artwork?.symbolName {
                                Image(systemName: symbol).resizable().scaledToFit()
                                    .padding(2).foregroundStyle(placeholderForeground ?? AnyShapeStyle(.secondary))
                            }
                        } else {
                            GeometryReader { proxy in
                                Image(systemName: artwork?.symbolName ?? "app.dashed")
                                    .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.45))
                                    .foregroundStyle(placeholderForeground ?? AnyShapeStyle(.secondary))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
            }
        }
        .accessibilityHidden(true)
        .task(id: Request(name: name, maxPixelSize: maxPixelSize)) {
            artwork = nil
            let loaded = await SavedGroupPreviewArtworkLoader.shared.load(name, maxPixelSize: maxPixelSize)
            if !Task.isCancelled { artwork = loaded }
        }
    }
}

private struct SavedGroupPreviewMiniPlaceholder: View {
    let cornerRadius: CGFloat
    let fill: AnyShapeStyle?

    var body: some View {
        if let fill { RoundedRectangle(cornerRadius: cornerRadius).fill(fill) }
        else { RoundedRectangle(cornerRadius: cornerRadius).fill(.fill.secondary) }
    }
}

/// Serial decoding also bounds temporary full-source allocations when a dense
/// page first appears, while all disk and image work stays off the main actor.
private actor SavedGroupPreviewArtworkLoader {
    static let shared = SavedGroupPreviewArtworkLoader()
    struct Artwork: Sendable {
        let variants: CustomIconVariants?
        let automatic: CGImage?
        let symbolName: String?
    }

    private let cache = WidgetArtworkCache(directory: DirectLaunchIcons.containerDirectory())

    func load(_ name: String, maxPixelSize: Int) -> Artwork? {
        guard !Task.isCancelled else { return nil }
        let variants = CustomIconStore.variants(name: name)?.thumbnail(maxSide: maxPixelSize)
        // A dark-only custom icon still needs the automatic picture in light mode.
        // Both photographs are reduced before they enter view state.
        guard variants?.standard == nil else {
            return Artwork(variants: variants, automatic: nil, symbolName: nil)
        }
        let id = AutomaticActionIcon.appStoreID(name: name)
        let image = id.flatMap { cache.image(appStoreID: $0, maxPixelSize: maxPixelSize) }
        return Artwork(variants: variants, automatic: image, symbolName: AutomaticActionIcon.symbolName(name: name))
    }
}
