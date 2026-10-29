import AppFolderKit
import SwiftUI

/// A preset is a saved value, not a live link to a group's appearance.
struct AppearancePresetsView: View {
    let currentAppearance: SavedGroupAppearance
    let scopeName: String
    let canApply: Bool
    let onApply: (SavedGroupAppearance) -> Bool

    @State private var snapshot: AppearancePresetSnapshot?
    @State private var searchText = ""
    @State private var newName = ""
    @State private var renameTarget: AppearancePreset?
    @State private var renameName = ""
    @State private var recentlyRemoved: AppearancePreset?
    @State private var confirmation: Confirmation?
    @State private var errorMessage: LocalizedStringKey?
    @State private var feedback: LocalizedStringKey?
    @State private var requiresReload = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private enum Confirmation {
        case update(AppearancePreset)
        case remove(AppearancePreset)
    }

    private var canWrite: Bool {
        snapshot?.status == .available && !requiresReload && scenePhase == .active
    }

    var body: some View {
        NavigationStack {
            Form {
                currentAppearanceSection
                statusSection
                saveSection
                if let renameTarget { renameSection(renameTarget) }
                if let recentlyRemoved { removalSection(recentlyRemoved) }
                recordsSection
            }
            .navigationTitle("外观预设")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索预设名称")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("appearancePresets.done")
                }
            }
            .confirmationDialog("管理预设", isPresented: confirmationPresented,
                                titleVisibility: .visible, presenting: confirmation) { action in
                switch action {
                case .update(let preset):
                    Button("更新为当前外观") { update(preset) }
                case .remove(let preset):
                    Button("移除预设", role: .destructive) { remove(preset) }
                }
                Button("取消", role: .cancel) { }
            } message: { action in
                switch action {
                case .update(let preset):
                    Text("将预设「\(preset.name)」更新为本页显示的当前外观？已经应用过的分组不会改变。")
                case .remove(let preset):
                    Text("移除预设「\(preset.name)」？已经应用过的分组不会改变；关闭本页前可撤销最近一次移除。")
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var currentAppearanceSection: some View {
        Section {
            Text("应用位置：\(scopeName)").font(.subheadline.weight(.semibold))
            AppearancePresetSummary(appearance: currentAppearance)
            if !canApply {
                Text("编辑位置或草稿已改变。请关闭并重新打开外观预设，再应用到当前层。")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("appearancePresets.targetExpired")
            }
        } header: {
            Text("当前外观")
        } footer: {
            Text("当前外观取自打开本页时的设置。应用预设只改变这一层的外观，可在编辑器中撤销；保存、更新或移除预设不会改变分组，也不会开启「使用分组外观」。")
        }
    }

    private var statusSection: some View {
        Section {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
                    .accessibilityIdentifier("appearancePresets.error")
            }
            if let feedback {
                Label { Text(feedback) } icon: { Image(systemName: "checkmark.circle") }
                    .accessibilityIdentifier("appearancePresets.feedback")
            }
            if let snapshot {
                switch snapshot.status {
                case .available: EmptyView()
                case .unavailable:
                    Text("外观预设存储暂时不可用。输入已保留，请重新读取后再试。")
                case .busy:
                    Text("外观预设正在被其他操作使用。输入已保留，请稍后重新读取。")
                case .unreadable:
                    Text("无法读取外观预设，现有数据不会被覆盖。输入已保留，请重新读取后再试。")
                }
            } else {
                ProgressView()
            }
            Button("重新读取") { reload(acceptRenamingSnapshot: true) }
                .accessibilityIdentifier("appearancePresets.reload")
        }
    }

    private var saveSection: some View {
        Section {
            TextField("预设名称", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("appearancePresets.newName")
            Button("保存当前外观为预设") { saveCurrent() }
                .disabled(!canWrite || newName.isEmpty)
                .accessibilityIdentifier("appearancePresets.save")
        } footer: {
            Text("名称首尾空格会忽略，最多 64 个字符。最多保存 64 个预设。")
        }
    }

    private func renameSection(_ preset: AppearancePreset) -> some View {
        Section {
            Text(verbatim: preset.name).font(.subheadline.weight(.semibold))
            AppearancePresetSummary(appearance: preset.appearance)
            TextField("新名称", text: $renameName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("appearancePresets.renameName")
            Button("保存名称") { rename(preset) }
                .disabled(!canWrite || renameName.isEmpty)
                .accessibilityIdentifier("appearancePresets.renameSave")
            Button("取消改名", role: .cancel) {
                renameTarget = nil
                renameName = ""
            }
        } header: {
            Text("重命名预设")
        }
    }

    private func removalSection(_ preset: AppearancePreset) -> some View {
        Section {
            Button("撤销移除「\(preset.name)」") { undoRemoval(preset) }
                .disabled(!canWrite)
                .accessibilityIdentifier("appearancePresets.undoRemoval")
        } footer: {
            Text("仅恢复最近移除的预设；同名预设已存在时不会覆盖。")
        }
    }

    @ViewBuilder
    private var recordsSection: some View {
        if let snapshot, snapshot.status == .available {
            if snapshot.records.isEmpty {
                Section {
                    ContentUnavailableView("还没有外观预设", systemImage: "paintpalette",
                                           description: Text("为当前外观命名并保存，就能在其他分组或文件夹中复用。"))
                }
            } else {
                let matches = matchingPresets(in: snapshot.records)
                if matches.isEmpty {
                    Section {
                        ContentUnavailableView("没有匹配的预设", systemImage: "magnifyingglass")
                    }
                } else {
                    ForEach(matches) { preset in presetSection(preset) }
                }
            }
        }
    }

    private func matchingPresets(in records: [AppearancePreset]) -> [AppearancePreset] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? records : records.filter { $0.name.localizedStandardContains(query) }
    }

    private func presetSection(_ preset: AppearancePreset) -> some View {
        Section {
            AppearancePresetSummary(appearance: preset.appearance)
            HStack {
                Button("应用到当前层") { apply(preset) }
                    .buttonStyle(.borderless)
                    .disabled(!canApply || !canWrite)
                    .accessibilityIdentifier("appearancePresets.apply.\(preset.id)")
                Spacer()
                Menu("管理预设") {
                    Button("重命名预设") {
                        renameTarget = preset
                        renameName = preset.name
                        errorMessage = nil
                        feedback = nil
                    }
                    Button("更新为当前外观") { confirmation = .update(preset) }
                    Button("移除预设", role: .destructive) { confirmation = .remove(preset) }
                }
                .buttonStyle(.borderless)
                .disabled(!canWrite)
                .accessibilityIdentifier("appearancePresets.manage.\(preset.id)")
            }
        } header: {
            Text(verbatim: preset.name).textCase(nil)
        }
    }

    private func reload(acceptRenamingSnapshot: Bool = false) {
        let latest = AppearancePresetStore.snapshot
        snapshot = latest
        if latest.status == .available {
            requiresReload = false
            errorMessage = nil
            // A user-requested refresh keeps their typed name, while showing
            // the newly read appearance before they explicitly retry a rename.
            if acceptRenamingSnapshot, let target = renameTarget,
               let refreshed = latest.records.first(where: { $0.id == target.id }) {
                renameTarget = refreshed
            }
        }
    }

    private func saveCurrent() {
        guard canWrite else { return }
        let preset = AppearancePreset(name: newName, appearance: currentAppearance)
        guard validate(preset) else { return }
        guard write([.init(name: preset.name, expected: nil, replacement: preset)]) == nil else { return }
        newName = ""
        feedback = "已保存预设「\(preset.name)」。"
    }

    private func rename(_ preset: AppearancePreset) {
        guard canWrite else { return }
        let renamed = AppearancePreset(name: renameName, appearance: preset.appearance)
        guard validate(renamed) else { return }
        let mutations: [AppearancePresetMutation]
        if renamed.id == preset.id {
            mutations = [.init(name: preset.name, expected: preset, replacement: renamed)]
        } else {
            mutations = [.init(name: preset.name, expected: preset, replacement: nil),
                         .init(name: renamed.name, expected: nil, replacement: renamed)]
        }
        guard write(mutations) == nil else { return }
        renameTarget = nil
        renameName = ""
        feedback = "已重命名为「\(renamed.name)」。"
    }

    private func update(_ preset: AppearancePreset) {
        guard canWrite else { return }
        let updated = AppearancePreset(name: preset.name, appearance: currentAppearance)
        guard write([.init(name: preset.name, expected: preset, replacement: updated)]) == nil else { return }
        if renameTarget?.id == preset.id { renameTarget = updated }
        feedback = "已更新预设「\(preset.name)」。"
    }

    private func remove(_ preset: AppearancePreset) {
        guard canWrite else { return }
        let failure = write([.init(name: preset.name, expected: preset, replacement: nil)])
        // An unconfirmed atomic write may have completed. Keep the old value
        // available for a conditional restore even when success is unknown.
        if failure == nil || failure == .writeFailed { recentlyRemoved = preset }
        guard failure == nil else { return }
        if renameTarget?.id == preset.id { renameTarget = nil }
        feedback = "已移除预设「\(preset.name)」。"
    }

    private func undoRemoval(_ preset: AppearancePreset) {
        guard canWrite else { return }
        guard write([.init(name: preset.name, expected: nil, replacement: preset)]) == nil else { return }
        recentlyRemoved = nil
        feedback = "已恢复预设「\(preset.name)」。"
    }

    private func apply(_ preset: AppearancePreset) {
        feedback = nil
        let latest = AppearancePresetStore.snapshot
        snapshot = latest
        guard latest.status == .available else { return }
        guard latest.records.first(where: { $0.id == preset.id }) == preset else {
            errorMessage = "预设已更改或移除。请确认重新读取后的外观，再应用。"
            return
        }
        guard canApply, scenePhase == .active, onApply(preset.appearance) else {
            errorMessage = "编辑位置或草稿已改变。请关闭并重新打开外观预设，再应用到当前层。"
            return
        }
    }

    private func validate(_ preset: AppearancePreset) -> Bool {
        guard preset.isValid else {
            errorMessage = "请输入有效的预设名称；过长或包含换行的名称无法保存。"
            feedback = nil
            return false
        }
        return true
    }

    /// A failed write never discards text fields or retries against a new
    /// expected value. The user must reread and explicitly submit again.
    private func write(_ mutations: [AppearancePresetMutation]) -> AppearancePresetError? {
        feedback = nil
        do {
            snapshot = try AppearancePresetStore.apply(mutations)
            errorMessage = nil
            requiresReload = false
            return nil
        } catch {
            let failure = error as? AppearancePresetError ?? .writeFailed
            switch failure {
            case .unavailable:
                errorMessage = "外观预设存储暂时不可用。输入已保留，请重新读取后再试。"
            case .busy:
                errorMessage = "外观预设正在被其他操作使用。输入已保留，请稍后重新读取。"
            case .unreadable:
                errorMessage = "无法读取外观预设，现有数据不会被覆盖。输入已保留，请重新读取后再试。"
            case .conflict:
                errorMessage = "名称已被使用，或预设已在别处更改。输入已保留，请重新读取并确认后再试。"
            case .capacityExceeded:
                errorMessage = "已达到 64 个外观预设的上限。请移除不再需要的预设后重试。"
            case .invalidChanges:
                errorMessage = "无法保存此预设。请检查名称和当前外观后重试。"
            case .writeFailed:
                errorMessage = "未能确认预设已保存。输入已保留，请重新读取检查结果，再决定是否重试。"
            }
            switch failure {
            case .invalidChanges, .capacityExceeded: break
            default: requiresReload = true
            }
            return failure
        }
    }
}

/// The labels match the existing appearance controls and include every field
/// that applying a preset replaces. No widget configuration is represented.
private struct AppearancePresetSummary: View {
    let appearance: SavedGroupAppearance

    var body: some View {
        VStack(spacing: 3) {
            LabeledContent("小号网格") { Text(gridName) }
            LabeledContent("布局密度") { Text(densityName) }
            LabeledContent("显示图标名称") {
                Text(appearance.showsTitles ? LocalizedStringKey("显示") : LocalizedStringKey("隐藏"))
            }
            LabeledContent("图标大小") { Text(iconSizeName) }
            LabeledContent("底板") { Text(LocalizedStringKey(appearance.plate.localizedName)) }
            if appearance.plate.usesTint {
                LabeledContent("底板颜色") {
                    HStack(spacing: 5) {
                        Circle().fill(appearance.style.tint.color)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1) }
                            .frame(width: 12, height: 12).accessibilityHidden(true)
                        Text(verbatim: appearance.tintHex)
                    }
                }
            }
            LabeledContent("返回按钮样式") { Label(backButtonName, systemImage: appearance.backButtonStyle.systemImage) }
            LabeledContent("图标间距") {
                if let spacing = appearance.spacing { Text("\(spacing) 点") }
                else { Text("自动") }
            }
            LabeledContent("四周边距") {
                if let margin = appearance.margin { Text("\(margin) 点") }
                else { Text("自动") }
            }
            LabeledContent("文字颜色") {
                if let color = appearance.titleColorHex { Text(verbatim: color) }
                else { Text("自动") }
            }
            LabeledContent("文字描边") {
                if let color = appearance.titleOutlineHex { Text(verbatim: color) }
                else { Text("关闭") }
            }
            if appearance.titleOutlineHex != nil {
                LabeledContent("描边粗细") {
                    switch appearance.titleOutlineWidth {
                    case .thin: Text("细")
                    case .medium: Text("中")
                    case .thick: Text("粗")
                    }
                }
            }
            LabeledContent("文字预览") {
                FolderTitleText(text: String(localized: "名称示例"), fontSize: 16,
                                width: 140, style: appearance.style)
            }
        }
        .font(.caption)
    }

    private var gridName: LocalizedStringKey { appearance.grid == .four ? "四宫格" : "九宫格" }
    private var densityName: LocalizedStringKey {
        switch appearance.density {
        case .standard: "标准"
        case .spacious: "大图标"
        case .dense: "密集"
        }
    }
    private var iconSizeName: LocalizedStringKey {
        switch appearance.iconSize {
        case .small: "小号"
        case .medium: "中号"
        case .large: "大号"
        }
    }
    private var backButtonName: LocalizedStringKey {
        switch appearance.backButtonStyle {
        case .chevronUp: "向上箭头"
        case .turnUpLeft: "转向箭头"
        case .folder: "文件夹"
        }
    }
}
