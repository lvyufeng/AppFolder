import AppFolderKit
import SwiftUI
import UIKit
import WidgetKit

private extension SavedGroup {
    var websiteCount: Int {
        func count(_ items: [GroupItem]) -> Int {
            items.reduce(0) { $0 + ($1.kind == .website ? 1 : ($1.kind == .folder ? count($1.children) : 0)) }
        }
        return count(items)
    }
}

/// Saved layouts contain local launch targets and folders; iOS owns system actions.
struct SavedGroupsView: View {
    @State private var groups: [SavedGroup] = []
    @State private var readSnapshot: SavedGroupReadSnapshot?
    @State private var removed: [SavedGroup] = []
    // This lease survives navigation into an editor and protects delete undo.
    @State private var removedCoverLease: FolderCoverAssetLease?
    @State private var isCreating = false
    @State private var failed = false
    @State private var hasKnownActions = false
    @State private var lastSavedGroupID: UUID?
    @State private var reports: [UUID: [SavedGroupBindingReport]] = [:]
    @State private var sharePreparation: SharePreparation?
    @State private var preparedShare: PreparedGroupShare?
    @State private var shareFailure: String?
    @State private var inboxCleanupFailureCount = 0

    private struct SharePreparation: Identifiable, Sendable {
        let id = UUID()
        let groupID: UUID
        let name: String
    }
    @Environment(\.scenePhase) private var scenePhase

    private var lastSavedGroup: SavedGroup? { groups.first { $0.id == lastSavedGroupID } }

    var body: some View {
        List {
            Section {
                Text("在这里整理动作、联系人和网站，再到小组件中选择分组。只有 App 动作需要额外配置系统动作。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !hasKnownActions {
                    NavigationLink {
                        SetupGuideView(showsGroupsLink: false)
                    } label: {
                        Label("添加小组件", systemImage: "plus.app")
                    }
                    .accessibilityIdentifier("groups.setup")
                }
                Button { isCreating = true } label: {
                    Label("新建分组", systemImage: "folder.badge.plus")
                }
                .disabled(!SavedGroupStore.isAvailable)
                .accessibilityIdentifier("groups.create")
                ShareInboxShortcut()
            }

            if let saved = lastSavedGroup {
                Section {
                    Text("已保存「\(saved.name)」")
                    if inboxCleanupFailureCount > 0 {
                        Text("分组已保存，但有 \(inboxCleanupFailureCount) 条待添加记录暂未移除。再次选择同一分组不会重复加入。")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("groups.inboxCleanupWarning")
                    }
                    NavigationLink {
                        SavedGroupConfigurationDetails(group: saved)
                    } label: {
                        Label("继续配置小组件", systemImage: "arrow.right.circle")
                    }
                    .accessibilityIdentifier("groups.continueSetup")
                }
            }

            if !SavedGroupStore.isAvailable {
                Section {
                    Text("共享空间不可用")
                    Text("分组暂时无法保存到小组件，请检查 App 的安装后再试。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if let readSnapshot, readSnapshot.hasReadFailures {
                Section {
                    if readSnapshot.directoryFailure {
                        Text("暂时无法读取分组列表，请重试。")
                        if !groups.isEmpty {
                            Text("下方显示上次读取的分组，可能不是最新内容。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("有 \(readSnapshot.unreadableCount) 个分组暂时无法读取。可读取的分组仍会显示。")
                    }
                    Button("重新读取", systemImage: "arrow.clockwise", action: reload)
                        .accessibilityIdentifier("groups.retryRead")
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("从备份恢复", systemImage: "externaldrive")
                    }
                    .accessibilityIdentifier("groups.restoreBackup")
                } header: {
                    Text("分组读取不完整")
                        .accessibilityIdentifier("groups.readFailure")
                } footer: {
                    Text("读取失败没有删除或改写任何分组文件。")
                }
            }

            if let readSnapshot, readSnapshot.isAvailable, groups.isEmpty, !readSnapshot.hasReadFailures {
                ContentUnavailableView("还没有分组", systemImage: "square.grid.2x2",
                                       description: Text("把常用动作、联系人和网站排好顺序，也可以放进文件夹。"))
            } else if !groups.isEmpty {
                Section {
                    ForEach(groups) { group in
                        groupRow(group)
                    }
                } header: {
                    Text("我的分组")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("分享分组").fontWeight(.medium)
                        Text("分享文件包含这个分组、联系人姓名和号码、完整网站链接及图标照片。App 动作需在接收设备重新配置。")
                        Text("也包含这个分组所用动作的标签与归档资料。")
                    }
                    .accessibilityIdentifier("groupShare.summary")
                }
            }

            if let last = removed.last {
                Section {
                    Button {
                        guard SavedGroupStore.save(last) else { failed = true; return }
                        removed.removeLast()
                        retainRemovedCovers()
                        reloadWidgets()
                        reload()
                    } label: { Label("撤销删除", systemImage: "arrow.uturn.backward") }
                } footer: {
                    Text(last.name)
                }
            }
        }
        .navigationTitle("我的分组")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isCreating) {
            SavedGroupEditor(group: SavedGroup(name: String(localized: "新分组")),
                             onInboxCleanupFailure: { inboxCleanupFailureCount = $0 }, onSave: didSave)
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .refreshable { reload() }
        .task(id: sharePreparation?.id) {
            if let sharePreparation { await prepareShare(sharePreparation) }
        }
        .background {
            GroupSharePresenter(file: preparedShare, onCompletion: finishSharing)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .alert("无法分享分组", isPresented: Binding(get: { shareFailure != nil }, set: { if !$0 { shareFailure = nil } })) {
            Button("好", role: .cancel) {}
        } message: { if let shareFailure { Text(shareFailure) } }
        .alert("未能完成", isPresented: $failed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("分组没有更新成功，请稍后再试。")
        }
    }

    private func groupRow(_ group: SavedGroup) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                SavedGroupEditor(group: group, onInboxCleanupFailure: { inboxCleanupFailureCount = $0 }, onSave: didSave)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").foregroundStyle(.tint)
                        .font(.title2).frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name).font(.headline)
                        Text(verbatim: contentSummary(group))
                        .font(.caption).foregroundStyle(.secondary)
                        GroupBindingSummary(group: group, reports: reports[group.id] ?? [], showsDate: false)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("groups.item.\(group.id.uuidString)")

            Menu { groupActions(group) } label: {
                Group {
                    if sharePreparation?.groupID == group.id { ProgressView() }
                    else { Image(systemName: "ellipsis.circle") }
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("整理\(group.name)"))
            .accessibilityValue(Text(sharePreparation?.groupID == group.id ? String(localized: "正在准备分享…") : ""))
            .accessibilityIdentifier("groups.menu.\(group.id.uuidString)")
        }
        .padding(.vertical, 4)
        .swipeActions { Button("删除", role: .destructive) { remove(group) } }
        .contextMenu { groupActions(group) }
    }

    private func contentSummary(_ group: SavedGroup) -> String {
        var parts: [String] = []
        if !group.allActionNames.isEmpty { parts.append(String(localized: "\(group.allActionNames.count) 个动作")) }
        if group.websiteCount > 0 { parts.append(String(localized: "\(group.websiteCount) 个网站")) }
        if group.contactItemCount > 0 { parts.append(String(localized: "\(group.contactItemCount) 个联系人图块")) }
        return parts.isEmpty ? String(localized: "\(group.allActionNames.count) 个动作") : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func groupActions(_ group: SavedGroup) -> some View {
        Button("分享分组", systemImage: "square.and.arrow.up") {
            guard sharePreparation == nil, preparedShare == nil else { return }
            sharePreparation = SharePreparation(groupID: group.id, name: group.name)
        }
        .disabled(sharePreparation != nil || preparedShare != nil)
        .accessibilityIdentifier("groups.share.\(group.id.uuidString)")
        Button("复制分组", systemImage: "doc.on.doc") { duplicate(group) }
        Button("删除", systemImage: "trash", role: .destructive) { remove(group) }
    }

    private func prepareShare(_ request: SharePreparation) async {
        defer { if sharePreparation?.id == request.id { sharePreparation = nil } }
        do {
            let file = try await Task.detached(priority: .userInitiated) {
                let data = try LibraryBackup.exportData(groupID: request.groupID)
                return try PreparedGroupShare(data: data, name: request.name)
            }.value
            // The temporary file's final owner cleans it even if this list left
            // the screen while the bounded export was still being prepared.
            guard !Task.isCancelled else { return }
            preparedShare = file
        } catch {
            guard !Task.isCancelled else { return }
            if let backupError = error as? LibraryBackupError, backupError == .fileTooLarge {
                shareFailure = String(localized: "这个分组的分享文件太大，请减少照片后重试。")
            } else {
                shareFailure = String(localized: "无法准备分享文件。请确认分组仍存在且图标可读取，并检查可用空间后重试。")
            }
        }
    }

    private func finishSharing(failed: Bool) {
        // The native presenter calls back only after completion/cancellation
        // and dismissal, so UIActivityItemSource has finished using this file.
        preparedShare?.removeTemporaryFile()
        preparedShare = nil
        if failed {
            shareFailure = String(localized: "分享没有完成，请重新选择保存位置或分享方式。")
        }
    }

    private func reload() {
        let snapshot = SavedGroupStore.snapshot
        // Keep the last visible items during a directory-wide read failure.
        // The accompanying message explicitly marks that list as possibly stale.
        if !snapshot.directoryFailure { groups = snapshot.groups }
        readSnapshot = snapshot
        reports = Dictionary(grouping: SavedGroupBindingReportStore.all, by: \.groupID)
        hasKnownActions = !GroupActionCandidates.read().isEmpty
    }

    private func didSave(_ group: SavedGroup) {
        reload()
        lastSavedGroupID = group.id
    }
    private func reloadWidgets() { AppFolderWidgetRefresh.libraryChanged() }

    private func duplicate(_ group: SavedGroup) {
        let name = String(group.name.prefix(60)) + " " + String(localized: "副本")
        let copy = SavedGroup(name: name, items: group.items, appearance: group.appearance)
        guard SavedGroupStore.save(copy) else { failed = true; return }
        reloadWidgets()
        reload()
    }

    private func remove(_ group: SavedGroup) {
        let retained = removed.reduce(into: group.coverAssetIDs) { $0.formUnion($1.coverAssetIDs) }
        do {
            if let removedCoverLease { removedCoverLease.update(retaining: retained) }
            else { removedCoverLease = try FolderCoverAssetStore.lease(retaining: retained) }
        } catch { failed = true; return }
        guard SavedGroupStore.remove(id: group.id) else {
            retainRemovedCovers()
            failed = true
            return
        }
        removed.append(group)
        reloadWidgets()
        reload()
    }

    private func retainRemovedCovers() {
        let retained = removed.reduce(into: Set<FolderCoverAssetID>()) { $0.formUnion($1.coverAssetIDs) }
        if retained.isEmpty {
            removedCoverLease?.close()
            removedCoverLease = nil
        } else {
            removedCoverLease?.update(retaining: retained)
        }
    }
}

struct SavedGroupEditor: View {
    @State private var draft: SavedGroup
    @State private var groupName: String
    @State private var path: [UUID] = []
    @State private var folderName = ""
    @State private var actionRequest: ActionRequest?
    @State private var committedActionRequestID: UUID?
    @State private var showsAppearance = false
    @State private var appearanceScrollRequest = UUID()
    @State private var moveRequest: MoveRequest?
    @State private var nameRequest: GroupItemNameRequest?
    @State private var coverRequest: CoverRequest?
    @State private var websiteRequest: WebsiteRequest?
    @State private var committedWebsiteRequestID: UUID?
    @State private var contactRequest: ContactRequest?
    @State private var committedContactRequestID: UUID?
    @State private var showsInboxPicker = false
    @State private var inboxTargetPath: [UUID] = []
    @State private var claimedInboxIDs = Set<UUID>()
    @State private var seededInbox = false
    @State private var coverSession: FolderCoverEditSession?
    @State private var error: String?
    @State private var showsExitConfirmation = false
    @State private var pendingExitAction: ExitAction?
    @State private var exitRequested = false
    @State private var history = SavedGroupEditHistory()
    @State private var canvasController = SavedGroupCanvasDragController()
    @FocusState private var focusedField: EditorField?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let original: SavedGroup
    private let initialInboxEntries: [ShareInboxEntry]
    private let onInboxCleanupFailure: (Int) -> Void
    let onSave: (SavedGroup) -> Void

    private struct ActionRequest: Identifiable {
        let id = UUID()
        let path: [UUID]
    }

    private struct MoveRequest: Identifiable {
        let id: UUID
    }
    private struct CoverRequest: Identifiable {
        let item: GroupItem
        let path: [UUID]
        let variants: CustomIconVariants?
        var id: UUID { item.id }
    }
    private struct WebsiteRequest: Identifiable {
        let id = UUID()
        let item: GroupItem?
        let path: [UUID]
        let canReplaceIcon: Bool
    }
    private struct ContactRequest: Identifiable {
        let id = UUID()
        let item: GroupItem?
        let path: [UUID]
    }
    private enum CoverEditError: Error { case unavailable, staleFolder }
    private enum ExitAction: Equatable { case save, discard }
    private enum EditorField: Hashable { case groupName, folderName }

    init(group: SavedGroup, initialInboxEntries: [ShareInboxEntry] = [],
         onInboxCleanupFailure: @escaping (Int) -> Void = { _ in },
         onSave: @escaping (SavedGroup) -> Void) {
        _draft = State(initialValue: group)
        _groupName = State(initialValue: group.name)
        original = group
        self.initialInboxEntries = initialInboxEntries
        self.onInboxCleanupFailure = onInboxCleanupFailure
        self.onSave = onSave
    }

    private var draftForSaving: SavedGroup {
        var value = draft
        value.name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }
    private var historySnapshot: SavedGroup {
        var value = draft
        value.name = groupName
        return value
    }
    private var groupNameBinding: Binding<String> {
        Binding { groupName } set: { name in
            let before = historySnapshot
            groupName = String(name.prefix(SavedGroup.maximumNameLength))
            history.record(before: before, after: historySnapshot, coalescingKey: "groupName")
            retainCoverAssets()
        }
    }
    private func updateAppearance(_ appearance: SavedGroupAppearance?, at targetPath: [UUID]) {
        guard let previous = draft.resolvedAppearance(at: targetPath) else { appearanceUpdateFailed(); return }
        let before = historySnapshot
        // Only a change to exactly one color joins its own picker gesture.
        // Layout edits, enabling a picker, and applying a preset set boundaries.
        var colorKey: String?
        if let appearance {
            var candidate = previous
            candidate.tintHex = appearance.tintHex
            if candidate == appearance, previous.tintHex != appearance.tintHex {
                colorKey = "tint"
            } else {
                candidate = previous
                candidate.titleColorHex = appearance.titleColorHex
                if candidate == appearance, previous.titleColorHex != appearance.titleColorHex {
                    colorKey = "titleColor"
                } else {
                    candidate = previous
                    candidate.titleOutlineHex = appearance.titleOutlineHex
                    if candidate == appearance, previous.titleOutlineHex != appearance.titleOutlineHex {
                        colorKey = "titleOutline"
                    }
                }
            }
        }
        if colorKey == nil { history.endCoalescing() }
        guard draft.setAppearance(appearance, at: targetPath) else { appearanceUpdateFailed(); return }
        let scope = targetPath.last?.uuidString ?? "root"
        history.record(before: before, after: historySnapshot,
                       coalescingKey: colorKey.map { "appearance.\($0).\(scope)" })
        retainCoverAssets()
    }

    private func applyAppearancePreset(_ appearance: SavedGroupAppearance, at targetPath: [UUID],
                                       groupID: UUID, expectedRevision: String) -> Bool {
        // Recheck the editor's live state, not only the sheet's captured View.
        // A delayed application must never edit a different folder or draft.
        guard canEditCanvas, draft.id == groupID, draftForSaving.revision == expectedRevision,
              path == targetPath, appearance.isValid,
              draft.resolvedAppearance(at: targetPath) != nil else { return false }
        history.endCoalescing()
        updateAppearance(appearance, at: targetPath)
        history.endCoalescing()
        return draft.appearanceOverride(at: targetPath) == appearance
    }

    private func updateAppearanceColor(_ hex: String, target: SavedGroupAppearanceColorTarget,
                                       at targetPath: [UUID], groupID: UUID) -> Bool {
        guard canEditCanvas, draft.id == groupID, path == targetPath,
              let tint = FolderTint(hex: hex),
              var appearance = draft.resolvedAppearance(at: targetPath) else { return false }
        switch target {
        case .plate:
            guard appearance.plate.usesTint else { return false }
            if appearance.tintHex == tint.hex { return true }
            appearance.tintHex = tint.hex
        case .title:
            guard appearance.titleColorHex != nil else { return false }
            if appearance.titleColorHex == tint.hex { return true }
            appearance.titleColorHex = tint.hex
        case .outline:
            guard appearance.titleOutlineHex != nil else { return false }
            if appearance.titleOutlineHex == tint.hex { return true }
            appearance.titleOutlineHex = tint.hex
        }
        updateAppearance(appearance, at: targetPath)
        return draft.appearanceOverride(at: targetPath) == appearance
    }

    private func updateFolderPreviewGrid(_ grid: FolderPreviewGrid?, at targetPath: [UUID]) {
        guard let id = targetPath.last,
              var siblings = draft.items(at: Array(targetPath.dropLast())),
              let index = siblings.firstIndex(where: { $0.id == id && $0.kind == .folder }) else {
            appearanceUpdateFailed()
            return
        }
        history.endCoalescing()
        let before = historySnapshot
        siblings[index].folderPreviewGrid = grid
        guard draft.replaceItems(siblings, at: Array(targetPath.dropLast())) else { appearanceUpdateFailed(); return }
        history.record(before: before, after: historySnapshot)
        retainCoverAssets()
    }

    private func appearanceUpdateFailed() {
        error = String(localized: "无法更新这个位置的外观，当前设置未改变。请重新打开文件夹后再试。")
    }

    private func editFolderAppearance(_ item: GroupItem) {
        let targetPath = path + [item.id]
        guard draft.items(at: targetPath) != nil else { appearanceUpdateFailed(); return }
        history.endCoalescing()
        focusedField = nil
        path = targetPath
        showsAppearance = true
        appearanceScrollRequest = UUID()
    }
    private var hasUnsavedChanges: Bool {
        groupName != original.name || draft.items != original.items || draft.appearance != original.appearance
    }
    private var canSave: Bool { !exitRequested && draftForSaving.isValid && SavedGroupStore.isAvailable && coverSession != nil }
    private var canEditCanvas: Bool {
        !exitRequested && scenePhase == .active && coverSession != nil
            && !showsExitConfirmation && pendingExitAction == nil
            && actionRequest == nil && moveRequest == nil && nameRequest == nil
            && coverRequest == nil && websiteRequest == nil && contactRequest == nil
            && !showsInboxPicker
    }
    private var confirmedExitAction: ExitAction? { showsExitConfirmation ? nil : pendingExitAction }
    private var items: [GroupItem] { draft.items(at: path) ?? [] }
    private var currentFolder: String {
        SavedGroupPage(group: draftForSaving, path: path, page: 0, capacity: 9).folderName
    }
    private var trimmedFolderName: String { folderName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollViewReader { scroll in
        List {
            Section {
                TextField("分组名称", text: groupNameBinding)
                    .accessibilityIdentifier("groupEditor.name")
                    .focused($focusedField, equals: .groupName)
                    .onSubmit { history.endCoalescing() }
            } footer: {
                Text("保存后，在小组件的「分组布局」中选择它。联系人和网站无需额外动作；App 动作需配置对应名称。分组外观可按需开启。")
            }

            Section("外观与预览") {
                DisclosureGroup(isExpanded: $showsAppearance) {
                    SavedGroupPreview(group: draftForSaving, path: $path,
                                      onAppearanceChange: { updateAppearance($0, at: $1) },
                                      onFolderPreviewGridChange: { updateFolderPreviewGrid($0, at: $1) },
                                      onInteractionBoundary: { history.endCoalescing() },
                                      onAppearanceColorChange: {
                                          updateAppearanceColor($0, target: $1, at: $2, groupID: $3)
                                      },
                                      canEditAppearancePresets: canEditCanvas,
                                      onPresetAppearanceApply: {
                                          applyAppearancePreset($0, at: $1, groupID: $2, expectedRevision: $3)
                                      },
                                      canvasController: canvasController,
                                      canvasRevision: canEditCanvas ? draft.revision : nil,
                                      onCanvasDrop: applyCanvasDrop,
                                      coverVariants: { coverSession?.variants(for: $0, maxSide: $1) })
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } label: {
                    Text("预览与调整布局")
                        .accessibilityIdentifier("groupEditor.appearance")
                }
            }
            .id("groupEditor.appearanceSection")

            SavedGroupConfigurationSection(group: draftForSaving)

            if items.count > 8 {
                Section {
                    Button {
                        withAnimation { scroll.scrollTo("groupEditor.addContentSection", anchor: .top) }
                    } label: {
                        Label("添加内容", systemImage: "plus")
                    }
                    .accessibilityIdentifier("groupEditor.jumpToAddContent")
                }
            }

            Section {
                if !path.isEmpty {
                    Button {
                        path.removeLast()
                    } label: { Label("上一级文件夹", systemImage: "arrow.turn.up.left") }
                    .accessibilityIdentifier("groupEditor.parent")
                }
                if items.isEmpty {
                    Text("这里还没有内容，先添加动作、联系人、网站或文件夹。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    editorRow(item, index: index)
                }
                .onMove(perform: reorder)
                .onDelete(perform: delete)
            } header: {
                Text(currentFolder)
            } footer: {
                Text("用每行的菜单移动或重命名；空位也占一个格子。文件夹可继续嵌套。")
            }

            Section("添加内容") {
                Button {
                    history.endCoalescing()
                    actionRequest = ActionRequest(path: path)
                } label: {
                    Label("添加动作", systemImage: "plus.app")
                }
                .accessibilityIdentifier("groupEditor.addAction")
                Button {
                    editWebsite(nil)
                } label: { Label("添加网站", systemImage: "globe") }
                    .accessibilityIdentifier("groupEditor.addWebsite")
                Button {
                    history.endCoalescing()
                    contactRequest = ContactRequest(item: nil, path: path)
                } label: { Label("添加联系人", systemImage: "person.crop.circle.badge.plus") }
                    .accessibilityIdentifier("groupEditor.addContact")
                Button {
                    history.endCoalescing()
                    inboxTargetPath = path
                    showsInboxPicker = true
                } label: { Label("从待添加网页加入", systemImage: "tray.and.arrow.down") }
                    .accessibilityIdentifier("groupEditor.addFromInbox")
                HStack {
                    TextField("文件夹名称", text: $folderName)
                        .accessibilityIdentifier("groupEditor.folderName")
                        .focused($focusedField, equals: .folderName)
                        .onChange(of: folderName) { _, name in
                            if name.count > 80 { folderName = String(name.prefix(80)) }
                        }
                    Button("添加文件夹") {
                        if append(.folder(name: trimmedFolderName)) { folderName = "" }
                    }
                    .disabled(trimmedFolderName.isEmpty || path.count >= SavedGroup.maximumDepth)
                    .accessibilityIdentifier("groupEditor.addFolder")
                }
                Button { _ = append(.spacer()) } label: {
                    Label("添加空位", systemImage: "square.dashed")
                }
                .accessibilityIdentifier("groupEditor.addSpacer")
            }
            .id("groupEditor.addContentSection")

            Section {
                if draft.allActionNames.isEmpty && (draft.websiteCount > 0 || draft.contactItemCount > 0) {
                    Text("联系人和网站无需配置系统动作。在小组件中选择这个分组即可。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("动作名称必须与小组件中选择的名称相同。没有对应动作，或多个动作同名时，格子会提示重新配置，不会猜测打开目标。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("编辑分组")
        .navigationBarTitleDisplayMode(.inline)
        // Hiding the native back button also removes the native interactive-pop
        // gesture. Every exit goes through the same explicit draft decision.
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(hasUnsavedChanges && !exitRequested)
        .onAppear {
            prepareCoverSession()
            seedInboxIfNeeded()
        }
        .onChange(of: confirmedExitAction) { _, action in
            guard let action else { return }
            // Let SwiftUI remove the confirmation presentation before asking
            // the navigation destination to leave on the next main-loop turn.
            DispatchQueue.main.async {
                guard !showsExitConfirmation, pendingExitAction == action else { return }
                pendingExitAction = nil
                switch action {
                case .save: save()
                case .discard: discardAndExit()
                }
            }
        }
        .onChange(of: focusedField) { _, _ in history.endCoalescing() }
        .onChange(of: path) { _, _ in history.endCoalescing() }
        .onChange(of: showsAppearance) { _, expanded in
            history.endCoalescing()
            if !expanded { canvasController.cancel() }
        }
        .onChange(of: canEditCanvas) { _, enabled in
            if !enabled { canvasController.cancel() }
        }
        .onChange(of: appearanceScrollRequest) { _, _ in
            withAnimation { scroll.scrollTo("groupEditor.appearanceSection", anchor: .top) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                history.endCoalescing()
                canvasController.cancel()
            }
        }
        .onDisappear {
            history.endCoalescing()
            canvasController.cancel()
            // Sheets and child views also disappear. Only a deliberate editor
            // exit may release the assets needed by this draft and its history.
            if exitRequested { coverSession?.discard() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("返回", systemImage: "chevron.backward") { requestExit() }
                    .accessibilityIdentifier("groupEditor.back")
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!history.canUndo)
                .accessibilityLabel("撤销")
                .accessibilityIdentifier("groupEditor.undo")

                Button { save() } label: {
                    Text("保存分组").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!canSave)
                .accessibilityIdentifier("groupEditor.save")

                Button(action: redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!history.canRedo)
                .accessibilityLabel("重做")
                .accessibilityIdentifier("groupEditor.redo")
            }
            .padding().background(.bar)
        }
        .sheet(item: $actionRequest) { request in
            ActionLibraryPicker { names in applyActions(names, to: request) }
        }
        .sheet(item: $moveRequest) { request in
            GroupMovePicker(group: draft, itemID: request.id, currentPath: path) { destination in
                move(itemID: request.id, to: destination)
            }
        }
        .sheet(item: $nameRequest) { request in
            GroupItemNameEditor(request: request) { value in
                rename(request, value: value)
            }
        }
        .sheet(item: $coverRequest) { request in
            NavigationStack {
                if request.item.kind == .website {
                    CustomIconEditorView(website: request.item, initialVariants: request.variants) { variants in
                        try applyCover(variants, to: request)
                    }
                } else if request.item.kind == .contact {
                    CustomIconEditorView(contact: request.item, initialVariants: request.variants) { variants in
                        try applyCover(variants, to: request)
                    }
                } else {
                    CustomIconEditorView(folder: request.item, initialVariants: request.variants,
                                         leafVariants: { coverSession?.variants(for: $0, maxSide: 32) }) { variants in
                        try applyCover(variants, to: request)
                    }
                }
            }
        }
        .sheet(item: $websiteRequest) { request in
            WebsiteEditorView(item: request.item, canReplaceIcon: request.canReplaceIcon) { name, address, browser, icon in
                applyWebsite(name: name, address: address, browser: browser, standardIcon: icon, to: request)
            }
        }
        .sheet(item: $contactRequest) { request in
            ContactEditorView(item: request.item) { name, target in
                applyContact(name: name, target: target, to: request)
            }
        }
        .sheet(isPresented: $showsInboxPicker) {
            NavigationStack {
                ShareInboxView { entries in
                    try applyInboxEntries(entries, at: inboxTargetPath)
                }
            }
        }
        .confirmationDialog("保存对分组的修改？", isPresented: $showsExitConfirmation, titleVisibility: .visible) {
            Button("保存分组") { confirmExit(.save) }.disabled(!canSave)
            Button("放弃修改", role: .destructive) { confirmExit(.discard) }
            Button("继续编辑", role: .cancel) { pendingExitAction = nil }
        } message: {
            Text("尚未保存的修改会在离开后丢失。")
        }
        .alert("未能完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) {}
        } message: { if let error { Text(error) } }
        }
    }

    private func editorRow(_ item: GroupItem, index: Int) -> some View {
        HStack(spacing: 12) {
            if item.kind == .folder {
                Button { path.append(item.id) } label: {
                    HStack(spacing: 12) {
                        SavedFolderArtwork(folder: item, variants: coverSession?.variants(for: item.folderCover, maxSide: 32),
                                           leafVariants: { coverSession?.variants(for: $0, maxSide: 32) })
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(.primary)
                            Text("\(item.children.count) 项内容").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("groupEditor.open.\(item.id.uuidString)")
            } else {
                if item.kind == .website {
                    WebsiteArtwork(variants: coverSession?.variants(for: item.websiteIcon, maxSide: 32),
                                   cornerRadius: 8, maxPixelSize: 32).frame(width: 32, height: 32)
                } else if item.kind == .contact, let target = item.contactTarget {
                    ContactArtwork(target: target, variants: coverSession?.variants(for: item.contactIcon, maxSide: 32),
                                   cornerRadius: 8, maxPixelSize: 32).frame(width: 32, height: 32)
                } else {
                    GroupItemArtwork(item: item).frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind == .spacer ? String(localized: "空位") : item.displayTitle)
                    if item.kind == .action, item.displayName != nil {
                        Text("绑定动作：\(item.name)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if item.kind == .website, let address = item.websiteURL {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if item.kind == .contact, let target = item.contactTarget {
                        Text(verbatim: target.operation.appLocalizedName + " · " + target.number)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer()
            }
            Menu {
                Button("上移", systemImage: "arrow.up") { moveWithin(index, by: -1) }.disabled(index == 0)
                Button("下移", systemImage: "arrow.down") { moveWithin(index, by: 1) }.disabled(index == items.count - 1)
                Button("移到文件夹", systemImage: "folder") {
                    history.endCoalescing()
                    moveRequest = MoveRequest(id: item.id)
                }
                if item.kind == .action {
                    Button("修改显示名称", systemImage: "textformat") {
                        history.endCoalescing()
                        nameRequest = GroupItemNameRequest(item: item, field: .displayName)
                    }
                    .accessibilityIdentifier("groupEditor.renameDisplayName.\(item.id.uuidString)")
                    Button("更换绑定动作", systemImage: "link") {
                        history.endCoalescing()
                        nameRequest = GroupItemNameRequest(item: item, field: .bindingName)
                    }
                    .accessibilityIdentifier("groupEditor.changeBinding.\(item.id.uuidString)")
                } else if item.kind == .website {
                    Button("编辑网站", systemImage: "pencil") {
                        editWebsite(item)
                    }
                    .accessibilityIdentifier("groupEditor.editWebsite.\(item.id.uuidString)")
                    Button("网站图标", systemImage: "photo.on.rectangle") { editCover(item) }
                        .disabled(coverSession == nil)
                        .accessibilityIdentifier("groupEditor.websiteIcon.\(item.id.uuidString)")
                    if item.websiteIcon != nil {
                        Button("恢复默认网站图标", systemImage: "globe") { restoreWebsiteIcon(item) }
                            .disabled(coverSession == nil)
                            .accessibilityIdentifier("groupEditor.restoreWebsiteIcon.\(item.id.uuidString)")
                    }
                    Button("修改名称", systemImage: "textformat") {
                        history.endCoalescing()
                        nameRequest = GroupItemNameRequest(item: item, field: .websiteName)
                    }
                    .accessibilityIdentifier("groupEditor.renameWebsite.\(item.id.uuidString)")
                } else if item.kind == .contact {
                    Button("编辑联系人", systemImage: "pencil") {
                        history.endCoalescing()
                        contactRequest = ContactRequest(item: item, path: path)
                    }
                    .accessibilityIdentifier("groupEditor.editContact.\(item.id.uuidString)")
                    Button("联系人图标", systemImage: "photo.on.rectangle") { editCover(item) }
                        .disabled(coverSession == nil)
                        .accessibilityIdentifier("groupEditor.contactIcon.\(item.id.uuidString)")
                    if item.contactIcon != nil {
                        Button("恢复默认联系人图标", systemImage: item.contactTarget?.operation.systemImage ?? "person.crop.circle") {
                            restoreContactIcon(item)
                        }
                        .disabled(coverSession == nil)
                        .accessibilityIdentifier("groupEditor.restoreContactIcon.\(item.id.uuidString)")
                    }
                } else if item.kind == .folder {
                    Button("编辑内部外观", systemImage: "slider.horizontal.3") { editFolderAppearance(item) }
                        .accessibilityIdentifier("groupEditor.folderAppearance.\(item.id.uuidString)")
                    if item.folderAppearance != nil {
                        Button("跟随上级外观", systemImage: "arrow.turn.up.left") {
                            history.endCoalescing()
                            updateAppearance(nil, at: path + [item.id])
                        }
                        .accessibilityIdentifier("groupEditor.inheritAppearance.\(item.id.uuidString)")
                    }
                    Button("编辑封面", systemImage: "photo.on.rectangle") { editCover(item) }
                        .disabled(coverSession == nil)
                        .accessibilityIdentifier("groupEditor.cover.\(item.id.uuidString)")
                    if item.folderCover != nil {
                        Button("恢复内容缩略图", systemImage: "square.grid.2x2") { restoreFolderContents(item) }
                            .disabled(coverSession == nil)
                            .accessibilityIdentifier("groupEditor.restoreCover.\(item.id.uuidString)")
                    }
                    Button("修改名称", systemImage: "pencil") {
                        history.endCoalescing()
                        nameRequest = GroupItemNameRequest(item: item, field: .folderName)
                    }
                    .accessibilityIdentifier("groupEditor.renameFolder.\(item.id.uuidString)")
                }
                Button("删除", systemImage: "trash", role: .destructive) { delete(IndexSet(integer: index)) }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .accessibilityLabel(Text("整理\(item.kind == .spacer ? String(localized: "空位") : item.displayTitle)"))
            .accessibilityIdentifier("groupEditor.menu.\(item.id.uuidString)")
        }
        .padding(.vertical, 2)
    }

    private func applyActions(_ names: [String], to request: ActionRequest) -> Bool {
        if committedActionRequestID == request.id { return true }
        guard !exitRequested, actionRequest?.id == request.id, !names.isEmpty,
              names.allSatisfy(ActionLibraryRecord.isValidName),
              let siblings = draft.items(at: request.path) else { return false }
        history.endCoalescing()
        let before = historySnapshot
        guard draft.replaceItems(siblings + names.map { .action(name: $0) }, at: request.path) else { return false }
        history.record(before: before, after: historySnapshot)
        retainCoverAssets()
        committedActionRequestID = request.id
        return true
    }

    @discardableResult
    private func append(_ item: GroupItem, reportsFailure: Bool = true) -> Bool {
        var next = items
        next.append(item)
        return replace(next, reportsFailure: reportsFailure)
    }

    @discardableResult
    private func replace(_ next: [GroupItem], reportsFailure: Bool = true) -> Bool {
        history.endCoalescing()
        let before = historySnapshot
        guard draft.replaceItems(next, at: path) else {
            if reportsFailure {
                error = String(localized: "请填写有效名称。分组最多 200 项内容，文件夹最多嵌套四层。")
            }
            return false
        }
        history.record(before: before, after: historySnapshot)
        retainCoverAssets()
        return true
    }

    private func move(itemID: UUID, to destination: [UUID]) -> Bool {
        history.endCoalescing()
        let before = historySnapshot
        guard draft.move(itemID: itemID, to: destination) else { return false }
        history.record(before: before, after: historySnapshot)
        retainCoverAssets()
        return true
    }

    /// The canvas consumes its one-shot session before calling this. Mutate the
    /// valid internal draft, while history retains the user's unfinished name.
    private func applyCanvasDrop(_ request: SavedGroupDropRequest) -> SavedGroupDropOutcome {
        guard canEditCanvas else { return .rejected(.invalidTarget) }
        history.endCoalescing()
        let before = historySnapshot
        let outcome = draft.applyDrop(request)
        switch outcome {
        case .changed:
            history.record(before: before, after: historySnapshot)
            retainCoverAssets()
            error = nil
            return .changed
        case .unchanged:
            return .unchanged
        case .rejected:
            error = String(localized: "未能移动项目，分组内容没有改变。请重新选择位置；分组最多 200 项，文件夹最多四层。")
            return outcome
        }
    }

    private func reorder(from offsets: IndexSet, to destination: Int) {
        var next = items
        next.move(fromOffsets: offsets, toOffset: destination)
        replace(next)
    }

    private func moveWithin(_ index: Int, by offset: Int) {
        var next = items
        let target = index + offset
        guard next.indices.contains(index), next.indices.contains(target) else { return }
        next.swapAt(index, target)
        replace(next)
    }

    private func delete(_ offsets: IndexSet) {
        var next = items
        next.remove(atOffsets: offsets)
        replace(next)
    }

    private func rename(_ request: GroupItemNameRequest, value: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == request.id }) else { return false }
        var next = items
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch request.field {
        case .displayName: next[index].displayName = trimmed.isEmpty ? nil : trimmed
        case .bindingName, .folderName, .websiteName: next[index].name = trimmed
        }
        return replace(next, reportsFailure: false)
    }

    private func editWebsite(_ item: GroupItem?) {
        history.endCoalescing()
        var canReplaceIcon = true
        if let item, item.websiteIcon != nil {
            do {
                guard let coverSession else { throw CoverEditError.unavailable }
                // Exact reads distinguish an absent dark image from one that
                // exists but is unavailable. Text edits remain possible either way.
                _ = try coverSession.load(item.websiteIcon)
            } catch { canReplaceIcon = false }
        }
        websiteRequest = WebsiteRequest(item: item, path: path, canReplaceIcon: canReplaceIcon)
    }

    private func applyWebsite(name: String, address: String, browser: WebsiteBrowser, standardIcon: CustomIcon?,
                              to request: WebsiteRequest) -> Bool {
        // Accept each presentation once even if a stale sheet callback arrives
        // during dismissal. Failed edits remain retryable with the same request.
        if committedWebsiteRequestID == request.id { return true }
        guard websiteRequest?.id == request.id else { return false }
        guard WebsiteURL.validated(address) != nil,
              var next = draft.items(at: request.path) else { return false }
        let websiteIndex: Int
        if let item = request.item {
            guard let index = next.firstIndex(where: { $0.id == item.id && $0.kind == .website }) else { return false }
            websiteIndex = index
            next[index].name = name
            next[index].websiteURL = address
            next[index].websiteBrowser = browser == .systemDefault ? nil : browser
        } else {
            websiteIndex = next.count
            next.append(.website(name: name, url: address, browser: browser == .systemDefault ? nil : browser))
        }
        // Validate the complete tree before staging any optional artwork.
        var candidate = draft
        guard candidate.replaceItems(next, at: request.path) else { return false }
        defer { retainCoverAssets() }
        if let standardIcon {
            guard request.canReplaceIcon, standardIcon.isValid, let coverSession else { return false }
            do {
                // Read again at application time. A failed read must not treat
                // an unknown dark variant as nil and silently erase it.
                let previous = try coverSession.load(next[websiteIndex].websiteIcon)
                next[websiteIndex].websiteIcon = try coverSession.stage(variants: CustomIconVariants(
                    standard: standardIcon, dark: previous?.dark
                ))
                guard candidate.replaceItems(next, at: request.path) else { return false }
            } catch { return false }
        }
        history.endCoalescing()
        let before = historySnapshot
        draft.items = candidate.items
        history.record(before: before, after: historySnapshot)
        committedWebsiteRequestID = request.id
        return true
    }

    private func applyContact(name: String, target: ContactTarget, to request: ContactRequest) -> Bool {
        if committedContactRequestID == request.id { return true }
        guard contactRequest?.id == request.id,
              var next = draft.items(at: request.path) else { return false }
        if let item = request.item {
            guard let index = next.firstIndex(where: { $0.id == item.id && $0.kind == .contact }) else { return false }
            next[index].name = name
            next[index].contactTarget = target
            // Keep the existing node ID and independent artwork references.
        } else {
            next.append(.contact(name: name, target: target))
        }
        history.endCoalescing()
        let before = historySnapshot
        guard draft.replaceItems(next, at: request.path) else { return false }
        history.record(before: before, after: historySnapshot)
        retainCoverAssets()
        committedContactRequestID = request.id
        return true
    }

    private func prepareCoverSession() {
        guard coverSession == nil else { return }
        do {
            coverSession = try FolderCoverEditSession(group: original)
            retainCoverAssets()
        } catch {
            self.error = String(localized: "分组图像暂时不可用，请稍后再试。")
        }
    }

    private func seedInboxIfNeeded() {
        guard !seededInbox else { return }
        seededInbox = true
        guard !initialInboxEntries.isEmpty else { return }
        do { try applyInboxEntries(initialInboxEntries, at: []) }
        catch { self.error = ShareInboxUI.message(for: error) }
    }

    private func applyInboxEntries(_ entries: [ShareInboxEntry], at targetPath: [UUID]) throws {
        let fresh = try ShareInboxUI.freshEntries(entries)
        // Name input can be temporarily empty. Validate the item-tree operation
        // using the original valid name, without replacing the user's raw text.
        var candidate = draft
        candidate.name = original.name
        let result = try ShareInboxImport.apply(entries: fresh, to: candidate, path: targetPath,
                                               fallbackName: String(localized: "网站"))
        history.endCoalescing()
        let before = historySnapshot
        draft.items = result.nextGroup.items
        claimedInboxIDs.formUnion(result.selectedIDs)
        history.record(before: before, after: historySnapshot)
        retainCoverAssets()
    }

    private func retainCoverAssets() {
        // All draft/history edits finish here, including edits whose value can
        // return to an earlier revision. Revoke a drag before retaining assets.
        canvasController.cancel()
        coverSession?.retain(draft.coverAssetIDs.union(history.coverAssetIDs))
    }

    private func editCover(_ item: GroupItem) {
        history.endCoalescing()
        guard let coverSession else { return }
        do {
            let variants = try coverSession.load(item.artworkReference)
            coverRequest = CoverRequest(item: item, path: path, variants: variants)
        } catch {
            self.error = String(localized: "分组图像暂时无法读取，已有图像未改变。请稍后再试，或从菜单恢复默认图像。")
        }
    }

    private func applyCover(_ variants: CustomIconVariants?, to request: CoverRequest) throws {
        guard let coverSession else { throw CoverEditError.unavailable }
        guard var next = draft.items(at: request.path),
              let index = next.firstIndex(where: { $0.id == request.id && ($0.kind == .folder || $0.kind == .website || $0.kind == .contact) }) else {
            throw CoverEditError.staleFolder
        }
        history.endCoalescing()
        let before = historySnapshot
        // Staging changes no saved group. A rejected draft leaves the sheet open.
        defer { retainCoverAssets() }
        let reference = try coverSession.stage(variants: variants)
        if next[index].kind == .website { next[index].websiteIcon = reference }
        else if next[index].kind == .contact { next[index].contactIcon = reference }
        else { next[index].folderCover = reference }
        guard draft.replaceItems(next, at: request.path) else { throw CoverEditError.staleFolder }
        history.record(before: before, after: historySnapshot)
    }

    private func restoreFolderContents(_ item: GroupItem) {
        do {
            // Do not load artwork: clearing a broken reference must still work.
            try applyCover(nil, to: CoverRequest(item: item, path: path, variants: nil))
        } catch {
            self.error = String(localized: "未能恢复内容缩略图，当前设置未改变。请稍后再试。")
        }
    }

    private func restoreWebsiteIcon(_ item: GroupItem) {
        do {
            try applyCover(nil, to: CoverRequest(item: item, path: path, variants: nil))
        } catch {
            self.error = String(localized: "未能恢复默认网站图标，当前设置未改变。请稍后再试。")
        }
    }

    private func restoreContactIcon(_ item: GroupItem) {
        do {
            try applyCover(nil, to: CoverRequest(item: item, path: path, variants: nil))
        } catch {
            self.error = String(localized: "未能恢复默认联系人图标，当前设置未改变。请稍后再试。")
        }
    }

    private func discardAndExit() {
        // Keep a usable, clean editor until navigation actually disappears.
        // A presentation transition must not strand an editable closed session.
        draft = original
        groupName = original.name
        history = SavedGroupEditHistory()
        retainCoverAssets()
        while !path.isEmpty && draft.items(at: path) == nil { path.removeLast() }
        error = nil
        focusedField = nil
        exitRequested = true
        dismiss()
    }

    private func save() {
        guard !exitRequested else { return }
        canvasController.cancel()
        history.endCoalescing()
        var value = draftForSaving
        value.updatedAt = .now
        guard let coverSession else {
            error = String(localized: "文件夹封面暂时不可用，请稍后再试。")
            return
        }
        do { try coverSession.commit(value) }
        catch { self.error = String(localized: "分组没有保存成功，请稍后再试。"); return }
        exitRequested = true
        // A successful group commit is authoritative. Cleanup failures must not
        // strand an editor with a closed session or pretend the save failed.
        var cleanupFailures = 0
        let consumed = ShareInboxImport.consumableIDs(selectedIDs: claimedInboxIDs, in: value)
        for id in consumed {
            do { _ = try ShareInboxStore.remove(id: id) }
            catch { cleanupFailures += 1 }
        }
        onInboxCleanupFailure(cleanupFailures)
        AppFolderWidgetRefresh.libraryChanged()
        onSave(value)
        dismiss()
    }

    private func confirmExit(_ action: ExitAction) {
        pendingExitAction = action
        showsExitConfirmation = false
    }

    private func requestExit() {
        canvasController.cancel()
        history.endCoalescing()
        pendingExitAction = nil
        if hasUnsavedChanges { showsExitConfirmation = true }
        else { discardAndExit() }
    }

    private func undo() {
        canvasController.cancel()
        guard let snapshot = history.undo(current: historySnapshot) else { return }
        restore(snapshot)
    }

    private func redo() {
        canvasController.cancel()
        guard let snapshot = history.redo(current: historySnapshot) else { return }
        restore(snapshot)
    }

    private func restore(_ snapshot: SavedGroup) {
        var restored = snapshot
        groupName = snapshot.name
        // Tree operations require a valid internal group name even while the
        // visible name field contains an unfinished, empty, or whitespace edit.
        restored.name = original.name
        draft = restored
        retainCoverAssets()
        while !path.isEmpty && draft.items(at: path) == nil { path.removeLast() }
        error = nil
    }
}

private struct GroupItemNameRequest: Identifiable {
    enum Field { case displayName, bindingName, folderName, websiteName }
    let item: GroupItem
    let field: Field
    var id: UUID { item.id }

    var title: String {
        switch field {
        case .displayName: String(localized: "修改显示名称")
        case .bindingName: String(localized: "更换绑定动作")
        case .folderName, .websiteName: String(localized: "修改名称")
        }
    }

    var fieldTitle: String {
        switch field {
        case .displayName: String(localized: "显示名称")
        case .bindingName: String(localized: "动作名称")
        case .folderName: String(localized: "文件夹名称")
        case .websiteName: String(localized: "网站名称")
        }
    }
}

/// The input stays local until the entire edit validates. Unlike an alert's
/// Save button, this sheet closes only after the parent accepts the change.
private struct GroupItemNameEditor: View {
    let request: GroupItemNameRequest
    let onSave: (String) -> Bool
    @State private var value: String
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    init(request: GroupItemNameRequest, onSave: @escaping (String) -> Bool) {
        self.request = request
        self.onSave = onSave
        _value = State(initialValue: request.field == .displayName ? request.item.displayName ?? "" : request.item.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(request.fieldTitle, text: $value)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityIdentifier("groupItemName.value")
                        .onSubmit(save)
                    if request.field == .displayName {
                        Text("绑定动作：\(request.item.name)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } footer: {
                    switch request.field {
                    case .displayName:
                        Text("显示名称只影响这个格子的标题，不会更改动作绑定或图标。留空可恢复动作名称。")
                    case .bindingName:
                        Text("输入与小组件中系统动作完全相同的名称。更换绑定会改变打开目标；已有的自定义显示名称会保留。")
                    case .folderName, .websiteName:
                        Text("名称最多 80 个字符。")
                    }
                }
                if failed {
                    Section {
                        Label("名称未保存。请缩短名称（最多 80 个字符），并移除换行或不支持的字符。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("groupItemName.error")
                    }
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .accessibilityIdentifier("groupItemName.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .accessibilityIdentifier("groupItemName.save")
                }
            }
            .onChange(of: value) { _, _ in failed = false }
        }
    }

    private func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = (request.field == .displayName || !trimmed.isEmpty)
            && trimmed.count <= SavedGroup.maximumNameLength && trimmed.utf8.count <= 512
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        guard valid, onSave(trimmed) else { failed = true; return }
        dismiss()
    }
}

/// Reads only past provider observations. An editor draft must match the saved
/// report's exact revision before it can display any successful matching state.
private struct SavedGroupConfigurationSection: View {
    let group: SavedGroup
    @State private var reports: [SavedGroupBindingReport] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            NavigationLink {
                SavedGroupConfigurationDetails(group: group)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    if group.allActionNames.isEmpty && (group.websiteCount > 0 || group.contactItemCount > 0) {
                        Text("分组使用说明")
                    } else {
                        Text("所需动作：\(group.allActionNames.count) 个")
                    }
                    GroupBindingSummary(group: group, reports: reports)
                }
            }
            .accessibilityIdentifier("groupEditor.configurationCheck")
        } header: {
            Text("小组件配置检查")
        } footer: {
            if group.allActionNames.isEmpty && (group.websiteCount > 0 || group.contactItemCount > 0) {
                Text("联系人和网站无需配置系统动作。在小组件中选择这个分组即可。")
            } else {
                Text("这是最近刷新时的记录，不代表小组件现在仍在桌面。相同配置的多个小组件共用一份记录。")
            }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    }

    private func reload() { reports = SavedGroupBindingReportStore.reports(for: group.id) }
}

private struct GroupBindingSummary: View {
    let group: SavedGroup
    let reports: [SavedGroupBindingReport]
    var showsDate = true

    private var latest: SavedGroupBindingReport? { reports.first { $0.matches(group) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if group.allActionNames.isEmpty {
                if group.websiteCount > 0 || group.contactItemCount > 0 {
                    Text("无需配置系统动作").foregroundStyle(.secondary)
                } else {
                    Text("还没有需要配置的动作").foregroundStyle(.secondary)
                }
            } else if let latest {
                if latest.isReady {
                    Label("最近一份配置：名称已全部匹配", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label("最近一份配置：需要处理", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("缺失 \(latest.missingNames.count) 个，同名冲突 \(latest.ambiguousNames.count) 个")
                        .foregroundStyle(.secondary)
                }
                if showsDate {
                    Text(latest.checkedAt, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
            } else if reports.isEmpty {
                Text("尚未收到配置检查").foregroundStyle(.secondary)
            } else {
                Text("布局已更改，等待新的检查").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

struct SavedGroupConfigurationDetails: View {
    let group: SavedGroup
    var focusedItemID: UUID? = nil
    var preferredReportID: String? = nil
    var isWidgetHelp = false
    @State private var reports: [SavedGroupBindingReport] = []
    @State private var storedGroup: SavedGroup?
    @State private var copiedName = false
    @Environment(\.scenePhase) private var scenePhase
    private var isSaved: Bool { storedGroup?.revision == group.revision }
    private var current: [SavedGroupBindingReport] {
        guard isSaved, !group.allActionNames.isEmpty else { return [] }
        var result = reports.filter { $0.matches(group) }
        if let preferredReportID, let index = result.firstIndex(where: { $0.id == preferredReportID }) {
            let preferred = result.remove(at: index)
            result.insert(preferred, at: 0)
        }
        return result
    }
    private var preferredReport: SavedGroupBindingReport? {
        guard let preferredReportID else { return nil }
        return current.first { $0.id == preferredReportID }
    }
    private var focusedItem: GroupItem? {
        guard let focusedItemID else { return nil }
        func find(in items: [GroupItem]) -> GroupItem? {
            for item in items {
                if item.id == focusedItemID { return item }
                if item.kind == .folder, let found = find(in: item.children) { return found }
            }
            return nil
        }
        return find(in: group.items)
    }
    private var focusedStatus: SavedGroupBindingReport.Status? {
        guard let item = focusedItem, item.kind == .action else { return nil }
        return preferredReport?.actions.first {
            SavedGroupBinding.normalizedName($0.name) == SavedGroupBinding.normalizedName(item.name)
        }?.status
    }

    var body: some View {
        List {
            if isWidgetHelp { focusedHelp }
            Section {
                if !SavedGroupStore.isAvailable {
                    Text("共享空间不可用")
                    Text("分组暂时无法保存到小组件，请检查 App 的安装后再试。")
                } else if isSaved, let storedGroup {
                    if group.allActionNames.isEmpty {
                        Text("长按桌面小组件，进入「编辑小组件」，在「分组布局」中选择「\(storedGroup.name)」。这个分组无需额外配置系统动作。")
                    } else {
                        Text("长按桌面小组件，进入「编辑小组件」，在「分组布局」中选择「\(storedGroup.name)」，并在「动作」中保留或添加以下同名系统动作。")
                    }
                } else {
                    Text("当前布局还未保存。请返回编辑页保存，再到小组件中选择这个分组。只有 App 动作需要配置对应名称。")
                }
                if !group.allActionNames.isEmpty {
                    Text("同一名称只需配置一次；若有同名冲突，请移除多余的同名动作，或在来源 App 中改名后同步修改分组。")
                }
                Text("外观随分组保存。在「编辑小组件」中选择分组并开启「使用分组外观」即可应用；这个开关默认关闭，关闭时使用小组件自己的外观。预览尺寸不会改变桌面尺寸。")
            }
            if !group.allActionNames.isEmpty {
              Section("所需动作") {
                ForEach(group.allActionNames, id: \.self) { name in
                    Text(name).textSelection(.enabled)
                }
              }
              Section {
                if isWidgetHelp {
                    if let preferredReport {
                        GroupBindingSummary(group: group, reports: [preferredReport])
                    } else {
                        unavailableReport
                    }
                } else {
                    GroupBindingSummary(group: group, reports: isSaved ? reports : [])
                }
                Button("重新读取检查记录", systemImage: "arrow.clockwise") { reload() }
                    .accessibilityIdentifier("groupCheck.refresh")
            } header: {
                Text(isWidgetHelp ? LocalizedStringKey("此小组件") : LocalizedStringKey("最近检查"))
            } footer: {
                Text("这里只读取已有记录，不会替你修改系统配置。修改动作后，请回到桌面等待小组件刷新，再查看检查结果。")
              }
            }
            ForEach(Array(current.enumerated()), id: \.element.id) { index, report in
                Section {
                    HStack {
                        gridName(report)
                        Spacer()
                        familyName(report.familyRawValue).foregroundStyle(.secondary)
                    }
                    Text(report.checkedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(report.actions, id: \.name) { action in
                        HStack(alignment: .firstTextBaseline) {
                            Text(action.name)
                            Spacer()
                            statusLabel(action.status).font(.caption)
                        }
                    }
                } header: {
                    if isWidgetHelp && report.id == preferredReportID {
                        Text("此小组件")
                    } else if isWidgetHelp {
                        Text("其他小组件记录 \(index + 1)")
                    } else {
                        Text("配置记录 \(index + 1)")
                    }
                }
                .accessibilityIdentifier("groupCheck.report.\(report.id)")
            }
            Section {
                Text("这是最近刷新时的记录，不代表小组件现在仍在桌面。相同配置的多个小组件共用一份记录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("小组件配置检查")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: preferredReportID) { _, _ in reload() }
        .onChange(of: focusedItemID) { _, _ in copiedName = false }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .refreshable { reload() }
    }

    private func reload() {
        storedGroup = SavedGroupStore.group(id: group.id)
        reports = SavedGroupBindingReportStore.reports(for: group.id)
    }

    private var focusedHelp: some View {
        Section {
            Text(group.name).font(.subheadline).foregroundStyle(.secondary)
            if let item = focusedItem {
                Text(item.displayTitle).font(.headline)
                    .accessibilityIdentifier("widgetHelp.focusedItem")
                if item.kind == .action {
                    LabeledContent("真实动作名称") {
                        Text(item.name).textSelection(.enabled)
                    }
                    .accessibilityIdentifier("widgetHelp.actionName")
                    Button {
                        UIPasteboard.general.string = item.name
                        copiedName = true
                    } label: {
                        Label(copiedName ? LocalizedStringKey("已复制动作名称") : LocalizedStringKey("复制动作名称"),
                              systemImage: copiedName ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityIdentifier("widgetHelp.copyName")
                    if let focusedStatus {
                        statusLabel(focusedStatus)
                            .accessibilityIdentifier("widgetHelp.recordStatus")
                        repairSteps(for: focusedStatus)
                    } else {
                        unavailableReport
                        repairSteps(for: nil)
                    }
                } else {
                    Text("这个项目不是 App 动作，不需要配置同名系统动作。")
                }
            } else if focusedItemID != nil {
                Text("刚才点按的项目已不在当前分组中。下方按当前保存的布局提供配置说明。")
                    .accessibilityIdentifier("widgetHelp.missingItem")
            } else {
                Text("请按当前保存的布局检查刚才的小组件。")
            }
        } header: {
            Text(focusedItemID == nil ? LocalizedStringKey("此小组件") : LocalizedStringKey("刚才点按的项目"))
        } footer: {
            Text("这是最近刷新时的记录，不代表小组件现在仍在桌面。相同配置的多个小组件共用一份记录。")
        }
    }

    private var unavailableReport: some View {
        Text("找不到与这次点按和当前布局对应的检查记录，可能已过期或被替换。其他小组件的记录不能确认这次配置。")
            .font(.subheadline).foregroundStyle(.secondary)
            .accessibilityIdentifier("widgetHelp.recordUnavailable")
    }

    @ViewBuilder
    private func repairSteps(for status: SavedGroupBindingReport.Status?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch status {
            case .missing:
                Text("回到桌面，长按刚才的小组件，选择「编辑小组件」。在「动作」中添加与上方真实名称完全相同的系统动作。")
            case .ambiguous:
                Text("在刚才的小组件的「动作」中，只保留一个这个名称的动作。若需同时保留，请在来源 App 中改名，并到「我的分组」同步更换绑定名称。")
            case .ready:
                Text("这份记录显示名称已匹配。若桌面仍提示问题，请等待小组件刷新，再从原小组件重试。")
            case .none:
                Text("请在刚才的小组件的「动作」中检查上方真实名称：缺少时添加，同名有多个时只保留一个。")
            }
        }
        .font(.subheadline)
        .accessibilityIdentifier("widgetHelp.repairSteps")
    }

    @ViewBuilder
    private func statusLabel(_ status: SavedGroupBindingReport.Status) -> some View {
        switch status {
        case .ready: Label("已匹配", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .missing: Label("缺少动作", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .ambiguous: Label("同名冲突", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    private func familyName(_ value: Int) -> Text {
        switch WidgetFamily(rawValue: value) {
        case .systemSmall: Text("小号")
        case .systemMedium: Text("中号")
        case .systemLarge: Text("大号")
        case .systemExtraLarge: Text("超大号")
        case .systemExtraLargePortrait: Text("竖向超大")
        default: Text("其他尺寸")
        }
    }

    private func gridName(_ report: SavedGroupBindingReport) -> Text {
        guard let family = WidgetFamily(rawValue: report.familyRawValue) else {
            return Text("其他尺寸")
        }
        if family == .systemSmall { return report.grid == .four ? Text("四宫格") : Text("九宫格") }
        let columns = report.grid.columns(for: family, density: report.density)
        let capacity = report.grid.cellCount(for: family, density: report.density)
        return Text("\(columns) 列 × \(capacity / columns) 行（\(capacity) 格）")
    }
}

private enum GroupActionCandidates {
    static func read() -> [String] {
        ActionLibrarySourceData.read().entries().filter { $0.canAdd && !$0.isArchived }.map(\.name)
    }
}

private struct GroupMovePicker: View {
    let group: SavedGroup
    let itemID: UUID
    let currentPath: [UUID]
    let onMove: ([UUID]) -> Bool
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    private struct Destination: Identifiable {
        let path: [UUID]
        let title: String
        var id: String { path.map(\.uuidString).joined(separator: "/") }
    }

    private var destinations: [Destination] {
        var result = [Destination(path: [], title: String(localized: "分组首页"))]
        func visit(_ items: [GroupItem], path: [UUID], titles: [String]) {
            for item in items where item.kind == .folder && item.id != itemID {
                let next = path + [item.id]
                let names = titles + [item.name]
                result.append(Destination(path: next, title: names.joined(separator: " / ")))
                visit(item.children, path: next, titles: names)
            }
        }
        visit(group.items, path: [], titles: [])
        return result
    }

    var body: some View {
        NavigationStack {
            List(destinations) { destination in
                Button {
                    if onMove(destination.path) { dismiss() }
                    else { failed = true }
                } label: {
                    Label(destination.title, systemImage: destination.path.isEmpty ? "square.grid.2x2" : "folder")
                }
                .disabled(destination.path == currentPath)
            }
            .navigationTitle("移到文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .alert("未能完成", isPresented: $failed) {
                Button("好", role: .cancel) {}
            } message: {
                Text("无法移动到这里。文件夹不能移入自身，嵌套最多四层。")
            }
        }
    }
}

/// Shared with the editor's rows. Artwork is local and cannot launch an action.
struct GroupItemArtwork: View {
    let item: GroupItem
    var cornerRadius: CGFloat = 8
    var placeholderForeground: AnyShapeStyle? = nil
    var placeholderFill: AnyShapeStyle? = nil
    var websiteVariants: CustomIconVariants? = nil
    var contactVariants: CustomIconVariants? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if item.kind == .action {
                if let custom = CustomIconStore.variants(name: item.name)?.resolved(isDark: colorScheme == .dark) {
                    CustomIconArtwork(icon: custom, cornerRadius: cornerRadius)
                } else {
                    AutomaticActionArtwork(name: item.name, cornerRadius: cornerRadius,
                                           placeholderForeground: placeholderForeground,
                                           placeholderFill: placeholderFill)
                }
            } else if item.kind == .website {
                WebsiteArtwork(variants: websiteVariants ?? FolderCoverAssetStore.variants(for: item.websiteIcon),
                               cornerRadius: cornerRadius)
            } else if item.kind == .contact, let target = item.contactTarget {
                ContactArtwork(target: target, variants: contactVariants ?? FolderCoverAssetStore.variants(for: item.contactIcon),
                               cornerRadius: cornerRadius)
            } else if item.kind == .folder {
                SavedFolderArtwork(folder: item, cornerRadius: cornerRadius,
                                   titleStyle: placeholderForeground ?? AnyShapeStyle(.primary),
                                   miniaturePlaceholderFill: placeholderFill,
                                   variants: FolderCoverAssetStore.variants(for: item.folderCover))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(placeholderFill ?? AnyShapeStyle(HierarchicalShapeStyle.quaternary))
                    .overlay {
                        Image(systemName: item.kind == .folder ? "folder.fill" : "square.dashed")
                            .font(.body)
                            .foregroundStyle(placeholderForeground ?? AnyShapeStyle(item.kind == .folder ? Color.accentColor : Color.secondary))
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
