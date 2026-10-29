import AppFolderKit
import SwiftUI

/// One read-only projection serves organization, selection, and the icon studio.
struct ActionLibrarySourceData: Sendable {
    let library: ActionLibrarySnapshot
    let groups: [SavedGroup]
    let groupReadFailed: Bool
    let observedNames: [String]
    let iconNames: [String]
    let mappingNames: [String]

    static func read() -> Self {
        let groups = SavedGroupStore.snapshot
        return Self(library: ActionLibraryStore.snapshot, groups: groups.groups,
                    groupReadFailed: groups.hasReadFailures || !groups.isAvailable,
                    observedNames: DirectLaunchOverrides.observedSlots.map(\.name),
                    iconNames: Array(CustomIconStore.displayNames.values),
                    mappingNames: Array(DirectLaunchOverrides.all.keys))
    }

    func entries(records: [ActionLibraryRecord]? = nil) -> [ActionLibraryEntry] {
        ActionLibraryProjection.entries(records: records ?? library.records, savedGroups: groups,
                                        observedNames: observedNames, customIconNames: iconNames,
                                        mappingNames: mappingNames)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Storage is injectable without changing the browsing or editing behavior.
struct ActionLibraryDataSource: Sendable {
    let read: @Sendable () -> ActionLibrarySourceData
    let apply: @Sendable ([ActionLibraryMutation]) throws -> ActionLibrarySnapshot
    static let live = Self(read: { ActionLibrarySourceData.read() }, apply: { try ActionLibraryStore.apply($0) })
}

enum ActionLibraryCategory: Hashable {
    case all, untagged, tag(String)
}

enum ActionLibraryFilter {
    static func entries(_ entries: [ActionLibraryEntry], query: String,
                        category: ActionLibraryCategory, archived: Bool) -> [ActionLibraryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            guard entry.isArchived == archived else { return false }
            switch category {
            case .all: break
            case .untagged: guard entry.tags.isEmpty else { return false }
            case .tag(let tag):
                guard entry.tags.contains(where: {
                    SavedGroupBinding.normalizedName($0) == SavedGroupBinding.normalizedName(tag)
                }) else { return false }
            }
            return query.isEmpty || entry.name.localizedStandardContains(query)
                || entry.tags.contains { $0.localizedStandardContains(query) }
        }
    }
}

struct ActionLibraryBrowserSections: View {
    let entries: [ActionLibraryEntry]
    @Binding var query: String
    @Binding var category: ActionLibraryCategory
    @Binding var archived: Bool
    let selectedIDs: Set<String>
    let onToggle: (ActionLibraryEntry) -> Void
    let onSelectVisible: ([ActionLibraryEntry]) -> Void
    var onEdit: ((ActionLibraryEntry) -> Void)? = nil
    var onArchive: ((ActionLibraryEntry) -> Void)? = nil
    var canInteract = true
    var isReadComplete = true

    private var visible: [ActionLibraryEntry] {
        ActionLibraryFilter.entries(entries, query: query, category: category, archived: archived)
    }
    private var tags: [String] {
        var values: [String: String] = [:]
        for tag in entries.flatMap(\.tags) {
            let key = SavedGroupBinding.normalizedName(tag)
            if values[key] == nil { values[key] = tag }
        }
        if case .tag(let tag) = category { values[SavedGroupBinding.normalizedName(tag)] = tag }
        return values.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        let matching = visible
        Section {
            TextField("搜索名称或标签", text: $query)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            Picker("归档状态", selection: $archived) {
                Text("未归档").tag(false)
                Text("已归档").tag(true)
            }
            .pickerStyle(.segmented)
            Picker("分类", selection: $category) {
                Text("全部分类").tag(ActionLibraryCategory.all)
                Text("未分类").tag(ActionLibraryCategory.untagged)
                ForEach(tags, id: \.self) { Text($0).tag(ActionLibraryCategory.tag($0)) }
            }
            Button("选择当前结果") { onSelectVisible(matching.filter(\.canAdd)) }
                .disabled(!canInteract || !matching.contains { $0.canAdd && !selectedIDs.contains($0.id) })
        }
        Section {
            if matching.isEmpty {
                emptyState
            } else {
                ForEach(matching) { entry in
                    ActionLibraryRow(entry: entry, selected: selectedIDs.contains(entry.id),
                                     onToggle: { onToggle(entry) },
                                     onEdit: onEdit.map { action in { action(entry) } },
                                     onArchive: onArchive.map { action in { action(entry) } },
                                     canInteract: canInteract)
                }
            }
        } footer: {
            Text("这里只整理名称与标签，不表示 App 已安装或系统动作已配置。")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !isReadComplete {
            Text("暂时无法显示完整资料，请重新读取。")
                .foregroundStyle(.secondary)
        } else if entries.isEmpty {
            Text("还没有动作记录。可先配置小组件动作，或手动记录完整动作名称。")
                .foregroundStyle(.secondary)
            NavigationLink { SetupGuideView(showsGroupsLink: false) } label: {
                Label("添加小组件", systemImage: "plus.app")
            }
        } else {
            Text(LocalizedStringKey(archived ? "没有符合条件的归档记录。" : "没有符合条件的动作记录。"))
                .foregroundStyle(.secondary)
            Button("清除筛选") { query = ""; category = .all }
            if !archived && entries.contains(where: \.isArchived) {
                Button("查看已归档") { archived = true; query = ""; category = .all }
            }
        }
    }
}

private struct ActionLibraryRow: View {
    let entry: ActionLibraryEntry
    let selected: Bool
    let onToggle: () -> Void
    let onEdit: (() -> Void)?
    let onArchive: (() -> Void)?
    let canInteract: Bool

    private var sourceTitle: LocalizedStringKey {
        if entry.sources.contains(.observedWidget) { return "小组件曾记录" }
        if entry.sources.contains(.savedGroup) { return "已保存分组引用" }
        if entry.sources.contains(.customIcon) || entry.sources.contains(.manualMapping) { return "仅图标或商店匹配记录" }
        return "本地资料记录"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    GroupItemArtwork(item: .action(name: entry.name)).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).foregroundStyle(.primary)
                        if !entry.tags.isEmpty { Text(entry.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        Text(sourceTitle).font(.caption).foregroundStyle(.secondary)
                        if !entry.canAdd {
                            Text("名称过长或格式无效，无法添加或整理。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canInteract || !entry.canAdd)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if let onEdit, let onArchive {
                Menu {
                    Button("编辑资料", systemImage: "tag", action: onEdit)
                    Button(LocalizedStringKey(entry.isArchived ? "取消归档" : "归档"), systemImage: "archivebox", action: onArchive)
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 40, height: 40)
                }
                .disabled(!canInteract || !entry.canAdd)
                .accessibilityLabel(Text("整理\(entry.name)"))
            }
        }
    }
}

struct ActionLibraryReadNotice: View {
    let libraryFailed: Bool
    let groupsFailed: Bool
    let retry: () -> Void

    var body: some View {
        if libraryFailed || groupsFailed {
            Section {
                if libraryFailed { Text("动作资料库暂时无法读取，整理功能不可用。请重新读取后再试。") }
                if groupsFailed { Text("部分分组暂时无法读取，候选动作可能不完整。") }
                Button("重新读取", action: retry)
            }
        }
    }
}
