import AppFolderKit
import SwiftUI

struct ActionLibraryRecordEditor: View {
    let entry: ActionLibraryEntry?
    let persisted: Bool
    let hasDraftRecord: Bool
    let onSave: (ActionLibraryRecord) -> LocalizedStringKey?
    let onRemove: () -> Void
    @State private var name: String
    @State private var tags: String
    @State private var archived: Bool
    @State private var submitting = false
    @State private var confirmsRemoval = false
    @State private var removalPending = false
    @State private var failure: LocalizedStringKey?
    @Environment(\.dismiss) private var dismiss

    init(entry: ActionLibraryEntry?, persisted: Bool, hasDraftRecord: Bool,
         onSave: @escaping (ActionLibraryRecord) -> LocalizedStringKey?, onRemove: @escaping () -> Void) {
        self.entry = entry; self.persisted = persisted; self.hasDraftRecord = hasDraftRecord
        self.onSave = onSave; self.onRemove = onRemove
        _name = State(initialValue: entry?.name ?? "")
        _tags = State(initialValue: entry?.tags.joined(separator: "\n") ?? "")
        _archived = State(initialValue: entry?.isArchived ?? false)
    }

    private var record: ActionLibraryRecord? {
        ActionLibraryRecord(name: name, tags: ActionLibraryTagOperation.parsed(tags), isArchived: archived)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("动作名称", text: $name)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .disabled(entry != nil)
                    Text("记录名称不会安装 App 或创建系统动作。使用时仍需在小组件中配置同名动作。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    TextField("标签（每行一个）", text: $tags, axis: .vertical)
                        .lineLimit(3...8).autocorrectionDisabled()
                    Toggle("已归档", isOn: $archived)
                } footer: {
                    Text("最多 16 个标签；每个标签最多 32 个字符。标签不会改变动作名称或目标。")
                }
                if record == nil && (!name.isEmpty || !tags.isEmpty) {
                    Text("名称或标签不符合限制，请检查后再保存。")
                        .foregroundStyle(.secondary)
                }
                if hasDraftRecord {
                    Section {
                        Button(LocalizedStringKey(persisted ? "移除资料库记录" : "取消本次添加"), role: .destructive) {
                            if persisted { confirmsRemoval = true }
                            else { remove() }
                        }
                    } footer: {
                        Text("仅移除资料库标签与归档记录，不删除分组或图标。若其他来源仍提供这个名称，它会继续显示。保存整理后才生效。")
                    }
                }
            }
            .navigationTitle(Text(LocalizedStringKey(entry == nil ? "记录动作名称" : "编辑资料")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        guard !submitting, let record else { return }
                        submitting = true
                        if let reason = onSave(record) { submitting = false; failure = reason }
                        else { dismiss() }
                    }.disabled(record == nil || submitting)
                }
            }
            .confirmationDialog("移除资料库记录", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("移除资料库记录", role: .destructive) {
                    removalPending = true
                    confirmsRemoval = false
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("仅移除资料库标签与归档记录，不删除分组或图标。若其他来源仍提供这个名称，它会继续显示。保存整理后才生效。")
            }
            .onChange(of: confirmsRemoval) { _, shown in
                guard !shown, removalPending else { return }
                removalPending = false
                Task { @MainActor in
                    await Task.yield()
                    remove()
                }
            }
            .alert("未能完成", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                if let failure { Text(failure) }
            }
        }
    }

    private func remove() {
        guard !submitting else { return }
        submitting = true
        onRemove()
        dismiss()
    }
}

enum ActionLibraryTagOperation: String, CaseIterable, Identifiable {
    case add, remove, replace
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self { case .add: "添加标签"; case .remove: "移除标签"; case .replace: "替换标签" }
    }
    static func parsed(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

struct ActionLibraryBatchTagEditor: View {
    let onApply: ([String], ActionLibraryTagOperation) -> LocalizedStringKey?
    @State private var operation = ActionLibraryTagOperation.add
    @State private var text = ""
    @State private var submitted = false
    @State private var failure: LocalizedStringKey?
    @Environment(\.dismiss) private var dismiss
    private var normalizedTags: [String]? {
        ActionLibraryRecord(name: "validation", tags: ActionLibraryTagOperation.parsed(text))?.tags
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("标签操作", selection: $operation) {
                    ForEach(ActionLibraryTagOperation.allCases) { Text($0.title).tag($0) }
                }
                TextField("标签（每行一个）", text: $text, axis: .vertical).lineLimit(3...8)
                Text("最多 16 个标签；每个标签最多 32 个字符。标签不会改变动作名称或目标。")
                    .font(.footnote).foregroundStyle(.secondary)
                if normalizedTags == nil {
                    Text("名称或标签不符合限制，请检查后再保存。")
                        .foregroundStyle(.secondary)
                }
                Text("替换会移除所选项目原有的全部标签；留空可清除标签。修改仍需保存整理。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("批量编辑标签")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        guard !submitted, let tags = normalizedTags else { return }
                        submitted = true
                        if let reason = onApply(tags, operation) { submitted = false; failure = reason }
                        else { dismiss() }
                    }
                    .disabled(submitted || normalizedTags == nil || (operation != .replace && normalizedTags?.isEmpty != false))
                }
            }
            .alert("未能完成", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                if let failure { Text(failure) }
            }
        }
    }
}
