import AppFolderKit
import SwiftUI

enum ShareInboxUI {
    enum Failure: Error { case unreadable, selectionChanged, destinationUnavailable }

    static func title(_ entry: ShareInboxEntry) -> String {
        (try? ShareInboxImport.title(for: entry, fallbackName: String(localized: "网站"))) ?? String(localized: "网站")
    }

    /// Revalidate the selected identities without resurrecting stale rows.
    static func freshEntries(_ selected: [ShareInboxEntry]) throws -> [ShareInboxEntry] {
        let snapshot = ShareInboxStore.snapshot
        guard snapshot.status == .available else { throw Failure.unreadable }
        let byID = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.id, $0) })
        guard selected.allSatisfy({ byID[$0.id] != nil }) else { throw Failure.selectionChanged }
        return selected.compactMap { byID[$0.id] }
    }

    static func message(for error: Error) -> String {
        if let error = error as? Failure {
            switch error {
            case .unreadable: return String(localized: "暂时无法读取待添加网页，请重试。")
            case .selectionChanged: return String(localized: "部分所选网页已不存在或无法读取。请重新选择，当前分组未改变。")
            case .destinationUnavailable: return String(localized: "这个分组暂时无法读取。请重试，或到「我的分组」检查读取状态。")
            }
        }
        if let error = error as? ShareInboxImport.Error, error == .capacityExceeded {
            return String(localized: "所选网页超过分组剩余容量。请减少选择后重试，当前分组未改变。")
        }
        return String(localized: "网页未加入草稿，当前分组未改变。请重试或选择其他分组。")
    }
}

/// Reused in the home screen and group library. Receiving a share only changes
/// this count; it never presents a screen over an existing editor.
struct ShareInboxShortcut: View {
    @State private var snapshot: ShareInboxSnapshot?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationLink {
            ShareInboxView()
        } label: {
            HStack {
                Label("待添加网页", systemImage: "tray")
                Spacer()
                if let snapshot {
                    if snapshot.status == .available {
                        Text(snapshot.recordCount, format: .number).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("inbox.open")
        .onAppear { snapshot = ShareInboxStore.snapshot }
        .onChange(of: scenePhase) { _, phase in if phase == .active { snapshot = ShareInboxStore.snapshot } }
    }
}

/// With onAdd, this is a local picker for an existing editor. Without it, the
/// user chooses a destination before opening a normal, independently undoable draft.
struct ShareInboxView: View {
    var onAdd: (([ShareInboxEntry]) throws -> Void)? = nil
    @State private var entries: [ShareInboxEntry] = []
    @State private var snapshot: ShareInboxSnapshot?
    @State private var selection: [UUID] = []
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var inspectedEntry: ShareInboxEntry?
    @State private var showsDestinations = false
    @State private var selectedEntries: [ShareInboxEntry] = []
    @State private var destination: SavedGroup?
    @State private var showsEditor = false
    @State private var savedName: String?
    @State private var cleanupFailureCount = 0
    @State private var removalCandidate: ShareInboxEntry?
    @State private var showsRemovalConfirmation = false
    @State private var pendingRemoval: ShareInboxEntry?
    @State private var undoEntry: ShareInboxEntry?
    @State private var isMutating = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(onAdd: (([ShareInboxEntry]) throws -> Void)? = nil) { self.onAdd = onAdd }

    private var allSelected: Bool { !entries.isEmpty && selection.count == entries.count }
    private var canModifyInbox: Bool {
        snapshot?.status == .available && !isSubmitting && !isMutating
            && !showsDestinations && !showsEditor && inspectedEntry == nil
            && !showsRemovalConfirmation && pendingRemoval == nil
    }
    private var canAdd: Bool { !selection.isEmpty && canModifyInbox }
    private var confirmedRemoval: ShareInboxEntry? { showsRemovalConfirmation ? nil : pendingRemoval }

    var body: some View {
        List {
            if let undoEntry {
                Section {
                    Label("网页已移出待添加列表。", systemImage: "tray.and.arrow.up")
                    Text(verbatim: ShareInboxUI.title(undoEntry)).foregroundStyle(.secondary)
                    Button("撤销", systemImage: "arrow.uturn.backward", action: undoRemoval)
                        .disabled(!canModifyInbox)
                        .accessibilityIdentifier("inbox.undoRemoval")
                }
            }
            if let savedName {
                Section {
                    Label("已保存「\(savedName)」", systemImage: "checkmark.circle")
                    if cleanupFailureCount > 0 { cleanupWarning }
                }
            }
            if let snapshot, snapshot.hasReadFailures {
                Section {
                    if snapshot.status != .available {
                        Text("暂时无法读取待添加网页，请重试。")
                        if !entries.isEmpty { Text("下方显示上次读取的网页，暂时不能加入分组。") }
                    } else {
                        Text("有 \(snapshot.unreadableCount) 条网页记录无法读取，其余网页仍可添加。")
                    }
                    Button("重新读取", systemImage: "arrow.clockwise", action: reload)
                        .accessibilityIdentifier("inbox.retry")
                } footer: {
                    Text("读取失败不会移除待添加记录。")
                }
            }
            if snapshot?.isEmpty == true {
                ContentUnavailableView("没有待添加网页", systemImage: "tray",
                    description: Text("在 Safari 或其他 App 分享网页时，选择 AppFolder 保存到待添加列表，再回到这里整理。"))
            } else if !entries.isEmpty {
                Section {
                    Button(allSelected ? LocalizedStringKey("清空选择") : LocalizedStringKey("全选")) {
                        guard canModifyInbox else { return }
                        selection = allSelected ? [] : entries.map(\.id)
                    }
                    .disabled(!canModifyInbox)
                    .accessibilityIdentifier("inbox.selectAll")
                    ForEach(entries) { entry in entryRow(entry) }
                } footer: {
                    Text("按选择顺序加入草稿。保存分组后，仍在布局中的网页会自动移出待添加列表；取消或撤销添加会保留。也可以左滑移出不需要的网页。")
                }
            }
        }
        .navigationTitle("待添加网页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onAdd != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSubmitting || isMutating)
                        .accessibilityIdentifier("inbox.cancel")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: addSelection) {
                Text("加入 \(selection.count) 个网页").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!canAdd)
            .accessibilityIdentifier("inbox.add")
            .padding().background(.bar)
        }
        .sheet(item: $inspectedEntry) { entry in
            NavigationStack {
                List {
                    Section { Text(ShareInboxUI.title(entry)).font(.headline) }
                    Section("完整网址") { Text(entry.url).textSelection(.enabled) }
                    Section { Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute()) }
                }
                .navigationTitle("网页详情")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { inspectedEntry = nil } } }
            }
        }
        .sheet(isPresented: $showsDestinations, onDismiss: openDestination) {
            ShareInboxDestinationPicker { selected in
                let fresh = try ShareInboxUI.freshEntries(selectedEntries)
                _ = try ShareInboxImport.apply(entries: fresh, to: selected, fallbackName: String(localized: "网站"))
                selectedEntries = fresh
                destination = selected
            }
        }
        .navigationDestination(isPresented: $showsEditor) {
            if let destination {
                SavedGroupEditor(group: destination, initialInboxEntries: selectedEntries,
                                 onInboxCleanupFailure: { cleanupFailureCount = $0 }) { saved in
                    savedName = saved.name
                    reload()
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .onChange(of: showsEditor) { _, showing in if !showing { reload() } }
        .refreshable { reload() }
        .confirmationDialog("移出待添加列表", isPresented: $showsRemovalConfirmation,
                            titleVisibility: .visible, presenting: removalCandidate) { entry in
            Button("移出待添加列表", role: .destructive) {
                pendingRemoval = entry
                showsRemovalConfirmation = false
            }
            Button("取消", role: .cancel) {}
        } message: { entry in
            Text(ShareInboxUI.title(entry) + "\n\n" + String(localized: "只从待添加列表移除此网页，已保存分组中的内容不变。"))
        }
        .onChange(of: confirmedRemoval) { _, entry in
            guard let entry else { return }
            // Finish the confirmation presentation before a failure can show
            // an alert. The bounded, nonblocking-lock write then runs locally.
            DispatchQueue.main.async {
                guard !showsRemovalConfirmation, pendingRemoval == entry else { return }
                pendingRemoval = nil
                removalCandidate = nil
                remove(entry)
            }
        }
        .alert("未能完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) {}
        } message: { if let error { Text(error) } }
    }

    private var cleanupWarning: some View {
        Text("分组已保存，但有 \(cleanupFailureCount) 条待添加记录暂未移除。再次选择同一分组不会重复加入。")
            .font(.subheadline).foregroundStyle(.secondary)
            .accessibilityIdentifier("inbox.cleanupWarning")
    }

    private func entryRow(_ entry: ShareInboxEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                guard canModifyInbox else { return }
                if let index = selection.firstIndex(of: entry.id) { selection.remove(at: index) }
                else { selection.append(entry.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selection.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(entry.id) ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ShareInboxUI.title(entry)).foregroundStyle(.primary)
                        Text(entry.url).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!canModifyInbox)
            .accessibilityAddTraits(selection.contains(entry.id) ? .isSelected : [])
            .accessibilityIdentifier("inbox.item.\(entry.id.uuidString)")
            Button { inspectedEntry = entry } label: {
                Image(systemName: "info.circle").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isSubmitting || isMutating)
            .accessibilityLabel("查看完整网址")
            .accessibilityIdentifier("inbox.details.\(entry.id.uuidString)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                guard canModifyInbox else { return }
                removalCandidate = entry
                showsRemovalConfirmation = true
            } label: {
                Label("移出待添加列表", systemImage: "trash")
            }
            .disabled(!canModifyInbox)
            .accessibilityIdentifier("inbox.remove.\(entry.id.uuidString)")
        }
    }

    private func remove(_ entry: ShareInboxEntry) {
        guard canModifyInbox else {
            error = String(localized: "网页未移出待添加列表，请重新读取后重试。")
            return
        }
        isMutating = true
        defer { isMutating = false }
        do {
            guard try ShareInboxStore.remove(ifMatching: entry) else {
                // Another consumer already removed it; no local deletion means
                // no permission to resurrect it through a new undo receipt.
                reload()
                error = String(localized: "这条网页已不在待添加列表中。")
                return
            }
            undoEntry = entry
            entries.removeAll { $0.id == entry.id }
            selection.removeAll { $0 == entry.id }
            reload()
        } catch {
            self.error = String(localized: "网页未移出待添加列表，请重新读取后重试。")
        }
    }

    private func undoRemoval() {
        guard canModifyInbox, let entry = undoEntry else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try ShareInboxStore.restore(entry)
            undoEntry = nil
            // Restore the record only, never the old selection or an import flow.
            reload()
        } catch {
            self.error = String(localized: "暂时无法撤销移除，请重新读取后重试。")
        }
    }

    private func reload() {
        let latest = ShareInboxStore.snapshot
        snapshot = latest
        guard latest.status == .available else { return }
        entries = latest.entries
        let available = Set(entries.map(\.id))
        selection.removeAll { !available.contains($0) }
    }

    private func addSelection() {
        guard canAdd else { return }
        isSubmitting = true
        do {
            let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            let fresh = try ShareInboxUI.freshEntries(selection.compactMap { byID[$0] })
            guard !fresh.isEmpty else { throw ShareInboxUI.Failure.selectionChanged }
            if let onAdd {
                try onAdd(fresh)
                dismiss()
            } else {
                selectedEntries = fresh
                destination = nil
                showsDestinations = true
            }
        } catch {
            isSubmitting = false
            self.error = ShareInboxUI.message(for: error)
            reload()
        }
    }

    private func openDestination() {
        isSubmitting = false
        guard destination != nil else { return }
        savedName = nil
        cleanupFailureCount = 0
        showsEditor = true
    }
}

private struct ShareInboxDestinationPicker: View {
    let onSelect: (SavedGroup) throws -> Void
    @State private var groups: [SavedGroup] = []
    @State private var snapshot: SavedGroupReadSnapshot?
    @State private var error: String?
    @State private var selected = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("新建分组", systemImage: "folder.badge.plus") {
                        choose(SavedGroup(name: String(localized: "新分组")))
                    }
                    .disabled(!SavedGroupStore.isAvailable || selected)
                    .accessibilityIdentifier("inbox.destination.new")
                }
                if let snapshot, snapshot.hasReadFailures || !snapshot.isAvailable {
                    Section {
                        Text("暂时无法读取全部分组，请重试。")
                        Button("重新读取", systemImage: "arrow.clockwise", action: reload)
                    }
                }
                Section("我的分组") {
                    ForEach(groups) { group in
                        Button(group.name) {
                            guard let fresh = SavedGroupStore.group(id: group.id) else {
                                error = ShareInboxUI.message(for: ShareInboxUI.Failure.destinationUnavailable)
                                return
                            }
                            choose(fresh)
                        }
                        .disabled(selected || snapshot?.directoryFailure == true)
                        .accessibilityIdentifier("inbox.destination.\(group.id.uuidString)")
                    }
                }
            }
            .navigationTitle("选择分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onAppear(perform: reload)
            .alert("未能完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                if let error { Text(error) }
            }
        }
    }

    private func choose(_ group: SavedGroup) {
        guard !selected else { return }
        selected = true
        do {
            try onSelect(group)
            dismiss()
        } catch {
            selected = false
            self.error = ShareInboxUI.message(for: error)
        }
    }

    private func reload() {
        let latest = SavedGroupStore.snapshot
        snapshot = latest
        if !latest.directoryFailure { groups = latest.groups }
    }
}
