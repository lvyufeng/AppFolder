import AppFolderKit
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

private extension UTType {
    static let appFolderBackup = UTType(exportedAs: "com.lvyufeng.appfolder.backup", conformingTo: .json)
}

private struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.appFolderBackup, .json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct BackupImportPreview: Identifiable, Sendable {
    let id = UUID()
    let createdAt: Date
    let plan: LibraryBackup.ImportPlan
}

/// Export and inspection are read-only. Only the preview's Import button writes.
struct BackupView: View {
    let initialImportURL: URL?
    private let onClose: (() -> Void)?
    @State private var readInitialURL = false
    @State private var isBusy = false
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var exportDocument: BackupFileDocument?
    @State private var preview: BackupImportPreview?
    @State private var notice: String?
    @State private var noticeAfterDismissal: String?
    @Environment(\.dismiss) private var dismiss

    init(initialImportURL: URL? = nil, onClose: (() -> Void)? = nil) {
        self.initialImportURL = initialImportURL
        self.onClose = onClose
    }

    var body: some View {
        List {
            Section {
                Text("备份包含分组内容、联系人姓名和号码、完整网站链接、相关图标照片及商店匹配；不含系统动作或桌面配置。")
                Text("备份也包含动作资料库的名称、标签和归档状态。同名资料保留设备上的记录。")
                Text("命名外观预设随完整备份保存；同名预设保留设备上的版本，导入不会自动应用到分组。")
                Button {
                    Task { await prepareExport() }
                } label: { Label("导出备份", systemImage: "square.and.arrow.up") }
                .disabled(isBusy || !LibraryBackup.isAvailable)
                .accessibilityIdentifier("backup.export")
                Button { showsImporter = true } label: {
                    Label("导入备份", systemImage: "square.and.arrow.down")
                }
                .disabled(isBusy || !LibraryBackup.isAvailable)
                .accessibilityIdentifier("backup.import")
            } footer: {
                Text("文件由你保存。可以在「文件」中选择 iCloud Drive；AppFolder 不会自动上传或同步。")
            }
            if isBusy {
                Section { HStack { ProgressView(); Text("正在处理备份…") } }
            }
            if !LibraryBackup.isAvailable {
                Section {
                    Text("共享空间不可用")
                    Text("共享空间暂时无法读取，请检查 App 的安装后再试。")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("恢复会新增分组副本；已有同名图标和商店匹配会保留。选取文件后可以先查看内容，确认导入才会保存。")
                Text("恢复后，在小组件中选择分组。只有 App 动作需要重新配置同名系统动作；联系人和网站无需额外动作。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if initialImportURL != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { if let onClose { onClose() } else { dismiss() } }.disabled(isBusy)
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
        .fileExporter(isPresented: $showsExporter, document: exportDocument,
                      contentType: .appFolderBackup, defaultFilename: "AppFolder-Backup") { result in
            exportDocument = nil
            switch result {
            case .success: notice = String(localized: "备份已保存。")
            case .failure(let error):
                if !isCancellation(error) { notice = String(localized: "无法保存备份，请检查可用空间后重试。") }
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.appFolderBackup, .json],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { Task { await prepareImport(from: url) } }
            case .failure(let error):
                if !isCancellation(error) { notice = String(localized: "无法读取这个文件。请确认文件已下载并重新选择。") }
            }
        }
        .sheet(item: $preview, onDismiss: {
            if let noticeAfterDismissal {
                notice = noticeAfterDismissal
                self.noticeAfterDismissal = nil
            }
        }) { value in
            BackupImportConfirmation(preview: value, isBusy: $isBusy) {
                Task { await apply(value.plan) }
            }
        }
        .alert("备份与恢复", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("好", role: .cancel) {}
        } message: { if let notice { Text(notice) } }
        .task {
            guard !readInitialURL, let initialImportURL else { return }
            readInitialURL = true
            await prepareImport(from: initialImportURL)
        }
    }

    private func prepareExport() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await Task.detached(priority: .userInitiated) { try LibraryBackup.exportData() }.value
            try Task.checkCancellation()
            exportDocument = BackupFileDocument(data: data)
            showsExporter = true
        } catch {
            if !isCancellation(error) { notice = message(for: error) }
        }
    }

    private func prepareImport(from url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let suffix = " (" + String(localized: "副本") + ")"
        do {
            let value = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let document = try LibraryBackup.read(from: url)
                return BackupImportPreview(createdAt: document.createdAt,
                                           plan: LibraryBackup.prepareImport(document, copyNameSuffix: suffix))
            }.value
            try Task.checkCancellation()
            preview = value
        } catch {
            if !isCancellation(error) { notice = message(for: error) }
        }
    }

    private func apply(_ plan: LibraryBackup.ImportPlan) async {
        guard !isBusy else { return }
        isBusy = true
        let result = await Task.detached(priority: .userInitiated) { LibraryBackup.apply(plan) }.value
        isBusy = false
        if result.imported.groups + result.imported.icons + result.imported.mappings + result.imported.folderCovers
            + result.imported.actionLibraryEntries > 0 {
            AppFolderWidgetRefresh.libraryChanged()
        }
        switch result.status {
        case .completed:
            noticeAfterDismissal = String(localized: "已导入 \(result.imported.groups) 个分组、\(result.imported.icons) 个图标、\(result.imported.folderCovers) 个分组图像和 \(result.imported.mappings) 条商店匹配。")
                + "\n" + String(localized: "新增 \(result.imported.actionLibraryEntries) 条动作资料，其中 \(result.imported.archivedEntries) 条已归档。")
                + "\n" + String(localized: "新增 \(result.imported.appearancePresets) 个外观预设。")
                + "\n\n" + String(localized: "恢复后，在小组件中选择分组。只有 App 动作需要重新配置同名系统动作；联系人和网站无需额外动作。")
        case .rolledBack:
            noticeAfterDismissal = String(localized: "导入没有完成，新增内容已撤销。原有分组和图标保持不变。")
        case .partial:
            noticeAfterDismissal = String(localized: "导入没有全部完成，部分新增内容已保留。请先检查「我的分组」和「图标工作室」，避免重复导入。原有内容没有被覆盖。")
                + "\n\n" + String(localized: "仍有 \(result.imported.groups) 个分组、\(result.imported.icons) 个图标、\(result.imported.folderCovers) 个分组图像和 \(result.imported.mappings) 条匹配记录需要检查。")
                + "\n" + String(localized: "仍有 \(result.imported.actionLibraryEntries) 条动作资料需要检查，其中 \(result.imported.archivedEntries) 条已归档。")
                + "\n" + String(localized: "仍有 \(result.imported.appearancePresets) 个外观预设需要检查。")
        case .unavailable:
            noticeAfterDismissal = String(localized: "共享空间暂时无法读取，请检查 App 的安装后再试。")
        }
        preview = nil
    }

    private func isCancellation(_ error: any Error) -> Bool {
        let cocoa = error as NSError
        return error is CancellationError || (cocoa.domain == NSCocoaErrorDomain && cocoa.code == CocoaError.userCancelled.rawValue)
    }

    private func message(for error: any Error) -> String {
        guard let error = error as? LibraryBackupError else {
            return String(localized: "无法读取这个文件。请确认文件已下载并重新选择。")
        }
        switch error {
        case .fileTooLarge:
            return String(localized: "备份内容过大，无法处理。请选择较小的备份，或减少照片后重新导出。")
        case .unsupportedVersion:
            return String(localized: "此备份由更新版本创建。请更新 AppFolder 后再试。")
        case .invalidFormat, .invalidContents:
            return String(localized: "此备份文件已损坏或格式不正确。请选择 AppFolder 导出的文件。")
        case .storageUnavailable:
            return String(localized: "共享空间暂时无法读取，请检查 App 的安装后再试。")
        case .readFailed:
            return String(localized: "无法读取这个文件。请确认文件已下载并重新选择。")
        case .exportFailed:
            return String(localized: "无法完整导出备份。请确认分组和图标可读取，并检查可用空间后重试。")
        }
    }
}

private struct BackupImportConfirmation: View {
    let preview: BackupImportPreview
    @Binding var isBusy: Bool
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("将导入") {
                    LabeledContent("分组副本") { Text(preview.plan.counts.groups, format: .number) }
                    LabeledContent("联系人图块") { Text(preview.plan.counts.contactItems, format: .number) }
                    LabeledContent("自定义图标") { Text(preview.plan.counts.icons, format: .number) }
                    LabeledContent("其中照片图标") { Text(preview.plan.counts.photos, format: .number) }
                    LabeledContent("分组图像") { Text(preview.plan.counts.folderCovers, format: .number) }
                    LabeledContent("其中照片图像") { Text(preview.plan.counts.folderCoverPhotos, format: .number) }
                    LabeledContent("商店图标匹配") { Text(preview.plan.counts.mappings, format: .number) }
                    LabeledContent("动作资料") { Text(preview.plan.counts.actionLibraryEntries, format: .number) }
                    LabeledContent("外观预设") { Text(preview.plan.counts.appearancePresets, format: .number) }
                    LabeledContent("其中归档资料") { Text(preview.plan.counts.archivedEntries, format: .number) }
                    LabeledContent("备份日期") { Text(preview.createdAt, style: .date) }
                    if preview.plan.counts.contactItems + preview.plan.keptExisting.contactItems > 0 {
                        Text("这份备份包含联系人姓名和电话号码。导入不会发起电话、短信或 FaceTime。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if preview.plan.counts.photos + preview.plan.counts.folderCoverPhotos
                        + preview.plan.keptExisting.photos + preview.plan.keptExisting.folderCoverPhotos > 0 {
                        Text("这份备份包含照片图像，恢复后会保存在设备上。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !preview.plan.groups.isEmpty {
                    Section("新增分组副本") {
                        ForEach(preview.plan.groups) { group in Text(group.name) }
                    }
                }
                if !preview.plan.appearancePresets.isEmpty {
                    Section("备份中的外观预设") {
                        ForEach(preview.plan.appearancePresets) { preset in Text(preset.name) }
                    }
                }
                Section {
                    LabeledContent("保留现有自定义图标") { Text(preview.plan.keptExisting.icons, format: .number) }
                    LabeledContent("复用已有分组图像") { Text(preview.plan.keptExisting.folderCovers, format: .number) }
                    LabeledContent("保留现有商店匹配") { Text(preview.plan.keptExisting.mappings, format: .number) }
                    LabeledContent("保留现有动作资料") { Text(preview.plan.keptExisting.actionLibraryEntries, format: .number) }
                    LabeledContent("保留现有外观预设") { Text(preview.plan.keptExisting.appearancePresets, format: .number) }
                    LabeledContent("其中归档资料") { Text(preview.plan.keptExisting.archivedEntries, format: .number) }
                    Text("备份也包含动作资料库的名称、标签和归档状态。同名资料保留设备上的记录。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("命名外观预设随完整备份保存；同名预设保留设备上的版本，导入不会自动应用到分组。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("已有同名自定义图标或商店匹配时，会保留设备上的设置，并跳过备份中的同名图标和匹配。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("导入的动作图标用于所有同名动作图块；联系人、网站图标和文件夹封面只用于各自的分组内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("恢复后，在小组件中选择分组。只有 App 动作需要重新配置同名系统动作；联系人和网站无需额外动作。")
                        .foregroundStyle(.secondary)
                }
                if !preview.plan.isAvailable {
                    Section { Text("共享空间暂时无法读取，请检查 App 的安装后再试。") }
                }
            }
            .navigationTitle("恢复前确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isBusy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onImport) {
                    HStack {
                        if isBusy { ProgressView().tint(.white) }
                        if isBusy { Text("正在处理备份…").fontWeight(.semibold) }
                        else { Text("确认导入").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(isBusy || !preview.plan.isAvailable)
                .accessibilityIdentifier("backup.confirmImport")
                .padding().background(.bar)
            }
            .interactiveDismissDisabled(isBusy)
        }
    }
}
