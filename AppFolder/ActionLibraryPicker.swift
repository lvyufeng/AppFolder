import AppFolderKit
import SwiftUI

/// Selection is local; neither manual names nor metadata are saved by this view.
struct ActionLibraryPicker: View {
    private let dataSource: ActionLibraryDataSource
    let onChoose: ([String]) -> Bool
    @State private var source: ActionLibrarySourceData?
    @State private var selection: [String] = []
    @State private var query = ""
    @State private var manualName = ""
    @State private var category = ActionLibraryCategory.all
    @State private var archived = false
    @State private var libraryReadFailed = false
    @State private var isReading = false
    @State private var activeReadID: UUID?
    @State private var isSubmitting = false
    @State private var failed = false
    @State private var refreshToken = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(dataSource: ActionLibraryDataSource = .live, onChoose: @escaping ([String]) -> Bool) {
        self.dataSource = dataSource
        self.onChoose = onChoose
    }

    private struct ReadRequest: Equatable { let active: Bool; let token: UUID }
    private var readRequest: ReadRequest { ReadRequest(active: scenePhase == .active, token: refreshToken) }
    private var entries: [ActionLibraryEntry] { source?.entries() ?? [] }
    private var selectedIDs: Set<String> { Set(selection.map(SavedGroupBinding.normalizedName)) }

    var body: some View {
        NavigationStack {
            List {
                manualEntry
                ActionLibraryReadNotice(libraryFailed: libraryReadFailed, groupsFailed: source?.groupReadFailed ?? false) {
                    refreshToken = UUID()
                }
                if !selection.isEmpty { selectionSection }
                Section {
                    Button("重新读取动作", systemImage: "arrow.clockwise") { refreshToken = UUID() }
                        .disabled(isSubmitting).accessibilityIdentifier("groupAction.refresh")
                    if isReading { ProgressView() }
                }
                ActionLibraryBrowserSections(entries: entries, query: $query, category: $category, archived: $archived,
                                             selectedIDs: selectedIDs,
                                             onToggle: { toggle($0.name) },
                                             onSelectVisible: { values in values.forEach { select($0.name) } },
                                             canInteract: !isSubmitting,
                                             isReadComplete: source != nil && !libraryReadFailed && !(source?.groupReadFailed ?? false))
            }
            .navigationTitle("添加动作")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: readRequest) { await refresh() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSubmitting) }
            }
            .safeAreaInset(edge: .bottom) { addButton }
            .alert("未能完成", isPresented: $failed) { Button("好", role: .cancel) {} } message: {
                Text("没有添加任何动作。分组最多 200 项内容，请减少本次选择，或返回分组删减内容后重试。")
            }
        }
    }

    private var manualEntry: some View {
        Section {
            TextField("动作名称", text: $manualName)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityIdentifier("groupAction.name")
            Button("加入本次选择") { select(manualName); manualName = "" }
                .disabled(isSubmitting || !ActionLibraryRecord.isValidName(manualName)
                          || selectedIDs.contains(SavedGroupBinding.normalizedName(manualName)))
                .accessibilityIdentifier("groupAction.add")
        } footer: {
            Text("手动输入只加入本次选择，不会保存资料记录、安装 App 或创建系统动作。仍需配置同名系统动作。")
        }
    }

    private var selectionSection: some View {
        Section {
            ForEach(Array(selection.enumerated()), id: \.element) { index, name in
                Button { toggle(name) } label: {
                    HStack {
                        Text(index + 1, format: .number).monospacedDigit().foregroundStyle(.secondary)
                        Text(name).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain).disabled(isSubmitting)
                .accessibilityHint("从本次选择中移除")
            }
            Button("清空选择") { selection.removeAll() }.disabled(isSubmitting)
        } header: { Text("本次选择") } footer: {
            Text("按选择顺序添加。切换分类、搜索或刷新不会清空选择；已有布局中的同名动作也可以再次添加。")
        }
    }

    private var addButton: some View {
        Button {
            guard !isSubmitting, !selection.isEmpty else { return }
            isSubmitting = true
            if onChoose(selection) { dismiss() }
            else { isSubmitting = false; failed = true }
        } label: {
            Text("添加 \(selection.count) 个动作").fontWeight(.semibold).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(selection.isEmpty || isSubmitting)
        .accessibilityIdentifier("groupAction.confirm")
        .padding().background(.bar)
    }

    private func select(_ name: String) {
        guard !isSubmitting, ActionLibraryRecord.isValidName(name),
              !selectedIDs.contains(SavedGroupBinding.normalizedName(name)) else { return }
        selection.append(name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping)
    }
    private func toggle(_ name: String) {
        guard !isSubmitting else { return }
        if let index = selection.firstIndex(where: { SavedGroupBinding.normalizedName($0) == SavedGroupBinding.normalizedName(name) }) {
            selection.remove(at: index)
        } else { select(name) }
    }

    @MainActor private func refresh() async {
        guard !Task.isCancelled, scenePhase == .active else { return }
        let readID = UUID()
        activeReadID = readID
        isReading = true
        // Only the current refresh owns its loading indicator and results.
        defer {
            if activeReadID == readID { activeReadID = nil; isReading = false }
        }
        let read = dataSource.read
        for delay in [0, 500, 1_000, 2_000, 4_000, 8_000] {
            do { if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) } }
            catch { return }
            guard activeReadID == readID, !Task.isCancelled, scenePhase == .active else { return }
            let latest = await Task.detached(priority: .utility) { read() }.value
            guard activeReadID == readID, !Task.isCancelled, scenePhase == .active else { return }
            libraryReadFailed = latest.library.status != .available
            if latest.library.status == .available || source == nil { source = latest }
            isReading = false
        }
    }
}
