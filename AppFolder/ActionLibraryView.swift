import AppFolderKit
import SwiftUI

struct ActionLibraryView: View {
    private let dataSource: ActionLibraryDataSource
    @State private var source: ActionLibrarySourceData?
    @State private var baseline: [String: ActionLibraryRecord] = [:]
    @State private var draft: [String: ActionLibraryRecord] = [:]
    @State private var selected = Set<String>()
    @State private var query = ""
    @State private var category = ActionLibraryCategory.all
    @State private var archived = false
    @State private var libraryReadFailed = false
    @State private var isReading = false
    @State private var activeReadID: UUID?
    @State private var isSaving = false
    @State private var refreshToken = UUID()
    @State private var editRequest: RecordRequest?
    @State private var batchTagRequest: BatchTagRequest?
    @State private var message: LocalizedStringKey?
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(dataSource: ActionLibraryDataSource = .live) { self.dataSource = dataSource }

    private struct RecordRequest: Identifiable {
        let id = UUID()
        let entry: ActionLibraryEntry?
        let persisted: Bool
    }
    private struct BatchTagRequest: Identifiable {
        let id = UUID()
        let entries: [ActionLibraryEntry]
    }
    private struct ReadRequest: Equatable { let active: Bool; let token: UUID }
    private var readRequest: ReadRequest { ReadRequest(active: scenePhase == .active, token: refreshToken) }
    private var entries: [ActionLibraryEntry] { source?.entries(records: Array(draft.values)) ?? [] }
    private var selectedEntries: [ActionLibraryEntry] { entries.filter { selected.contains($0.id) && $0.canAdd } }
    private var hasChanges: Bool { baseline != draft }
    private var canOrganize: Bool { source?.library.status == .available && !libraryReadFailed && !isSaving && !isReading }

    var body: some View {
        List {
            introduction
            ActionLibraryReadNotice(libraryFailed: libraryReadFailed, groupsFailed: source?.groupReadFailed ?? false) {
                refreshToken = UUID()
            }
            if isReading { ProgressView() }
            if !selected.isEmpty { batchControls }
            ActionLibraryBrowserSections(entries: entries, query: $query, category: $category, archived: $archived,
                                         selectedIDs: selected, onToggle: toggle,
                                         onSelectVisible: { selected.formUnion($0.map(\.id)) },
                                         onEdit: { editRequest = RecordRequest(entry: $0, persisted: baseline[$0.id] != nil) },
                                         onArchive: { setArchived(!$0.isArchived, entries: [$0]) },
                                         canInteract: canOrganize,
                                         isReadComplete: source != nil && !libraryReadFailed && !(source?.groupReadFailed ?? false))
        }
        .navigationTitle("动作资料库")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .interactiveDismissDisabled(isSaving)
        .task(id: readRequest) { await refresh() }
        .sheet(item: $editRequest) { request in
            ActionLibraryRecordEditor(entry: request.entry, persisted: request.persisted,
                                      hasDraftRecord: request.entry.map { draft[$0.id] != nil } ?? false,
                                      onSave: { record in
                if request.entry == nil && draft[record.id] != nil {
                    return "这个名称已有资料记录，请编辑现有记录。"
                }
                return storeDraft(record)
            }, onRemove: {
                if let entry = request.entry { draft.removeValue(forKey: entry.id); selected.remove(entry.id); saved = false }
            })
        }
        .sheet(item: $batchTagRequest) { request in
            ActionLibraryBatchTagEditor { tags, operation in applyTags(tags, operation: operation, to: request) }
        }
        .alert("未能完成", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) {}
        } message: { if let message { Text(message) } }
    }

    private var introduction: some View {
        Section {
            Text("标签用于分类；归档只隐藏候选，不删除分组内容、图标或系统动作。")
            Button("记录动作名称", systemImage: "plus") {
                editRequest = RecordRequest(entry: nil, persisted: false)
            }
            .disabled(!canOrganize)
            Button("重新读取", systemImage: "arrow.clockwise") { refreshToken = UUID() }
                .disabled(isReading || isSaving)
            if saved { Text("整理已保存。").foregroundStyle(.secondary) }
        } footer: {
            Text("修改先保留在整理草稿中。点击「保存整理」才会保存；取消不会改变资料库。")
        }
    }

    private var batchControls: some View {
        Section {
            Text("已选择 \(selected.count) 项")
            Button("批量编辑标签", action: openBatchTagEditor).disabled(!canOrganize)
            HStack {
                Button("归档所选") { setSelectedArchived(true) }
                Spacer()
                Button("恢复所选") { setSelectedArchived(false) }
            }
            .buttonStyle(.borderless)
            .disabled(!canOrganize)
            Button("清空选择") { selected.removeAll() }
        }
    }

    private var saveBar: some View {
        Button { Task { await save() } } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Text("保存整理").fontWeight(.semibold)
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(!hasChanges || !canOrganize)
        .padding().background(.bar)
    }

    private func toggle(_ entry: ActionLibraryEntry) {
        guard canOrganize, entry.canAdd else { return }
        if !selected.insert(entry.id).inserted { selected.remove(entry.id) }
    }

    private func storeDraft(_ record: ActionLibraryRecord) -> LocalizedStringKey? {
        // An already-open editor may finish locally during a failed or pending
        // read. Only save() writes storage and still requires canOrganize/CAS.
        guard editRequest != nil, !isSaving else { return "资料没有加入整理草稿，请检查名称、标签和资料库容量后重试。" }
        var next = draft
        next[record.id] = record
        guard next.count <= ActionLibraryStore.maximumRecords else { return "资料库已满，请先移除不需要的记录。" }
        draft = next
        saved = false
        return nil
    }

    private func setArchived(_ value: Bool, entries: [ActionLibraryEntry]) {
        guard canOrganize else { return }
        var next = draft
        for entry in entries {
            guard let record = ActionLibraryRecord(name: entry.name, tags: entry.tags, isArchived: value) else { return }
            // Unarchiving a derived candidate must not turn it into a saved name.
            if entry.record == nil && record.tags.isEmpty && !record.isArchived { continue }
            next[record.id] = record
        }
        guard next.count <= ActionLibraryStore.maximumRecords else { message = "资料库已满，请先移除不需要的记录。"; return }
        draft = next
        saved = false
    }

    private func completeSelectedEntries() -> [ActionLibraryEntry]? {
        let targets = selectedEntries
        guard !targets.isEmpty, targets.count == selected.count else {
            message = "所选动作暂时无法完整读取，未开始批量编辑。请重新读取，或清空后重新选择。"
            return nil
        }
        return targets
    }

    private func setSelectedArchived(_ value: Bool) {
        guard canOrganize, let targets = completeSelectedEntries() else { return }
        setArchived(value, entries: targets)
    }

    private func openBatchTagEditor() {
        guard canOrganize, let targets = completeSelectedEntries() else { return }
        // Candidate sources may disappear during a refresh. This edit owns the
        // complete target snapshot until it finishes or is cancelled.
        batchTagRequest = BatchTagRequest(entries: targets)
    }

    private func applyTags(_ tags: [String], operation: ActionLibraryTagOperation,
                           to request: BatchTagRequest) -> LocalizedStringKey? {
        // Keep the sheet's input in the draft even when the latest read failed.
        guard batchTagRequest?.id == request.id, !isSaving else { return "资料没有加入整理草稿，请检查名称、标签和资料库容量后重试。" }
        let removed = Set(tags.map(SavedGroupBinding.normalizedName))
        var next = draft
        for entry in request.entries {
            let values: [String]
            switch operation {
            case .add:
                var seen = Set<String>()
                values = (entry.tags + tags).filter { seen.insert(SavedGroupBinding.normalizedName($0)).inserted }
            case .remove: values = entry.tags.filter { !removed.contains(SavedGroupBinding.normalizedName($0)) }
            case .replace: values = tags
            }
            guard let record = ActionLibraryRecord(name: entry.name, tags: values, isArchived: entry.isArchived) else {
                return "标签超过限制，没有修改任何记录。"
            }
            // Clearing absent metadata is a no-op; existing empty records remain.
            if entry.record == nil && record.tags.isEmpty && !record.isArchived { continue }
            next[record.id] = record
        }
        guard next.count <= ActionLibraryStore.maximumRecords else { return "资料库已满，请先移除不需要的记录。" }
        draft = next
        saved = false
        return nil
    }

    @MainActor private func refresh() async {
        guard !Task.isCancelled, scenePhase == .active, !isSaving else { return }
        let readID = UUID()
        activeReadID = readID
        isReading = true
        // A cancelled read may finish after its replacement has started.
        defer {
            if activeReadID == readID { activeReadID = nil; isReading = false }
        }
        let read = dataSource.read
        let latest = await Task.detached(priority: .utility) { read() }.value
        guard activeReadID == readID, !Task.isCancelled, scenePhase == .active else { return }
        libraryReadFailed = latest.library.status != .available
        if latest.library.status == .available {
            // A sheet owns its own draft. Keep its original CAS baseline until
            // it finishes, even before that draft has reached this parent view.
            if !hasChanges && editRequest == nil && batchTagRequest == nil {
                baseline = Dictionary(uniqueKeysWithValues: latest.library.records.map { ($0.id, $0) })
                draft = baseline
            }
            source = latest
        } else if source == nil { source = latest }
    }

    @MainActor private func save() async {
        guard hasChanges, canOrganize else { return }
        isSaving = true
        defer { isSaving = false }
        let changes = Set(baseline.keys).union(draft.keys).compactMap { key -> ActionLibraryMutation? in
            guard baseline[key] != draft[key], let name = draft[key]?.name ?? baseline[key]?.name else { return nil }
            return ActionLibraryMutation(name: name, expected: baseline[key], replacement: draft[key])
        }
        do {
            let apply = dataSource.apply
            let result = try await Task.detached(priority: .userInitiated) { try apply(changes) }.value
            acceptSaved(result)
        } catch {
            if let failure = error as? ActionLibraryError, failure == .writeFailed {
                // The write may have reached disk before its verification failed.
                // Read back before offering another CAS; never claim it was undone.
                let read = dataSource.read
                let latest = await Task.detached(priority: .utility) { read() }.value
                libraryReadFailed = latest.library.status != .available
                if latest.library.status == .available {
                    source = latest
                    let current = Dictionary(uniqueKeysWithValues: latest.library.records.map { ($0.id, $0) })
                    if changes.allSatisfy({ current[SavedGroupBinding.normalizedName($0.name)] == $0.replacement }) {
                        acceptSaved(latest.library)
                        return
                    }
                }
                message = "无法确认整理是否保存，草稿仍保留。请重试，或取消后重新打开检查。"
                return
            }
            message = "整理没有保存，草稿仍保留。请重试；若资料库已在其他地方修改，请取消后重新打开。"
        }
    }

    private func acceptSaved(_ snapshot: ActionLibrarySnapshot) {
        baseline = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0) })
        draft = baseline
        selected.formIntersection(entries.map(\.id))
        saved = true
    }
}
