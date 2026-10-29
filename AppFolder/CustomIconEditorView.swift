import AppFolderKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// A draft stays local to this editor until the user taps Save.
struct CustomIconEditorView: View {
    let name: String
    private let initialVariants: CustomIconVariants?
    private let localItem: GroupItem?
    private let leafVariants: (FolderCover?) -> CustomIconVariants?
    private let onCommit: (CustomIconVariants?) throws -> Void

    private enum CommitFailure: Error { case rejected }

    init(name: String, onSave: @escaping () -> Void) {
        self.name = name
        initialVariants = CustomIconStore.variants(name: name)
        localItem = nil
        leafVariants = { FolderCoverAssetStore.variants(for: $0, maxSide: 32) }
        onCommit = { variants in
            guard CustomIconStore.setVariants(variants, name: name) else { throw CommitFailure.rejected }
            AppFolderWidgetRefresh.libraryChanged()
            onSave()
        }
    }

    /// Folder edits return to the parent's draft; only Save Group persists them.
    init(folder: GroupItem, initialVariants: CustomIconVariants?,
         leafVariants: @escaping (FolderCover?) -> CustomIconVariants? = { FolderCoverAssetStore.variants(for: $0, maxSide: 32) },
         onCommit: @escaping (CustomIconVariants?) throws -> Void) {
        name = folder.name
        localItem = folder
        self.leafVariants = leafVariants
        self.initialVariants = initialVariants
        self.onCommit = onCommit
    }

    init(website: GroupItem, initialVariants: CustomIconVariants?,
         onCommit: @escaping (CustomIconVariants?) throws -> Void) {
        name = website.name
        localItem = website
        leafVariants = { FolderCoverAssetStore.variants(for: $0, maxSide: 32) }
        self.initialVariants = initialVariants
        self.onCommit = onCommit
    }

    init(contact: GroupItem, initialVariants: CustomIconVariants?,
         onCommit: @escaping (CustomIconVariants?) throws -> Void) {
        name = contact.name
        localItem = contact
        leafVariants = { FolderCoverAssetStore.variants(for: $0, maxSide: 32) }
        self.initialVariants = initialVariants
        self.onCommit = onCommit
    }

    private enum Mode: String, CaseIterable, Identifiable {
        case symbol, emoji, photo, date
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .symbol: "符号"
            case .emoji: "表情或文字"
            case .photo: "照片"
            case .date: "日期"
            }
        }
    }

    private enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case standard, dark
        var id: Self { self }
        var title: LocalizedStringKey { self == .standard ? "普通" : "深色" }
        var editTitle: LocalizedStringKey { self == .standard ? "编辑普通外观" : "编辑深色外观" }
        var loadingTitle: LocalizedStringKey { self == .standard ? "正在读取普通图片…" : "正在读取深色图片…" }
    }

    /// Each appearance retains its source and uncropped photo while editing the other.
    private struct EditorDraft {
        var isCustom = false
        var mode: Mode = .symbol
        var symbol = "star.fill"
        var text = "✨"
        var colorHex = "#0A84FF"
        var photo: UIImage?
        var originalIcon: CustomIcon?
        var photoWasReplaced = false
        var zoom: Double = 1
        var offset: CGSize = .zero
        var dragOrigin: CGSize = .zero
        var isLoading = false
        var importID: UUID?

        var nonPhotoIcon: CustomIcon? {
            switch mode {
            case .symbol: CustomIcon.symbol(symbol, backgroundHex: colorHex)
            case .emoji: CustomIcon.emoji(text, backgroundHex: colorHex)
            case .photo: nil
            case .date: CustomIcon.date(backgroundHex: colorHex)
            }
        }
        var canSave: Bool { !isCustom || (mode == .photo ? photo != nil : nonPhotoIcon != nil) }
        var incompleteReason: LocalizedStringKey? {
            // An active import has its own progress and cancellation explanation.
            guard isCustom, !canSave, !isLoading else { return nil }
            switch mode {
            case .photo: return "请选择照片或图片文件。"
            case .emoji: return "请输入一至两个可见字符。"
            case .symbol: return "请选择一个有效符号。"
            case .date: return "请重新选择背景颜色。"
            }
        }
        var editFingerprint: DraftFingerprint {
            DraftFingerprint(isCustom: isCustom, mode: mode, symbol: symbol, text: text,
                             colorHex: colorHex, photoID: photo.map(ObjectIdentifier.init),
                             photoWasReplaced: photoWasReplaced, zoom: zoom, offset: offset)
        }
    }

    private struct DraftFingerprint: Equatable {
        let isCustom: Bool
        let mode: Mode
        let symbol: String
        let text: String
        let colorHex: String
        let photoID: ObjectIdentifier?
        let photoWasReplaced: Bool
        let zoom: Double
        let offset: CGSize
    }

    private struct GenerationUndo {
        let previous: EditorDraft
        let generatedFingerprint: DraftFingerprint
    }

    private struct GeneratedCandidate: Identifiable {
        let id: UUID
        let sessionID: UUID
        let result: DarkIconGenerator.Result
    }

    private enum GenerationInput: Sendable {
        case custom(CustomIcon)
        case cached(appStoreID: Int, country: String?)
    }

    private enum GenerationFailure: Error {
        case noCachedArtwork
    }

    @State private var appearance: Appearance = .standard
    @State private var standardDraft = EditorDraft()
    @State private var darkDraft = EditorDraft()
    @State private var loaded = false
    @State private var isSubmitting = false
    @State private var acceptsImports = true
    @State private var showsPhotoPicker = false
    @State private var showsFileImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoPickerRequest: PickerRequest?
    @State private var filePickerRequest: PickerRequest?
    @State private var symbolPickerRequest: SymbolPickerRequest?
    @State private var standardImportTask: Task<Void, Never>?
    @State private var darkImportTask: Task<Void, Never>?
    @State private var generationSessionID = UUID()
    @State private var generationRequestID: UUID?
    @State private var generationPresentationID: UUID?
    @State private var generationTask: Task<Void, Never>?
    @State private var isGeneratingDarkIcon = false
    @State private var generatedCandidate: GeneratedCandidate?
    @State private var generationUndo: GenerationUndo?
    @State private var error: LocalizedStringKey?
    @Environment(\.dismiss) private var dismiss

    private let cropSide: CGFloat = 132
    private let colors = ["#0A84FF", "#5856D6", "#AF52DE", "#FF2D55", "#D70015", "#A65300", "#00854A", "#007C91", "#48484A", "#1C1C1E"]
    private var active: Binding<EditorDraft> { binding(for: appearance) }
    private var current: EditorDraft { active.wrappedValue }
    private var isLoading: Bool {
        standardDraft.isLoading || darkDraft.isLoading
    }

    private struct PickerRequest: Equatable {
        let id = UUID()
        let destination: Appearance
    }

    private struct SymbolPickerRequest: Identifiable {
        let id = UUID()
        let destination: Appearance
        let selectedSymbol: String
    }

    private enum PhotoSource {
        case library(PhotosPickerItem)
        case file(URL)
    }
    private var sourceTitle: LocalizedStringKey {
        if localItem?.kind == .folder { return appearance == .standard ? "内容缩略图" : "跟随普通封面" }
        if localItem?.kind == .website { return appearance == .standard ? "默认网站图标" : "跟随普通图标" }
        if localItem?.kind == .contact { return appearance == .standard ? "默认联系人图标" : "跟随普通图标" }
        return appearance == .standard ? "自动图标" : "跟随普通图标"
    }
    private var customSourceTitle: LocalizedStringKey { localItem?.kind == .folder ? "自定义封面" : "自定义图标" }
    private var navigationTitle: LocalizedStringKey {
        if localItem?.kind == .folder { return "文件夹封面" }
        if localItem?.kind == .website { return "网站图标" }
        if localItem?.kind == .contact { return "联系人图标" }
        return "自定义图标"
    }
    private var saveTitle: LocalizedStringKey {
        if localItem?.kind == .folder { return "使用封面" }
        if localItem?.kind == .website || localItem?.kind == .contact { return "使用图标" }
        return "保存"
    }
    private var saveFailure: LocalizedStringKey {
        if localItem?.kind == .folder { return "封面没有应用到分组，当前设置未改变。请稍后再试。" }
        if localItem?.kind == .website || localItem?.kind == .contact { return "图标没有应用到分组，当前设置未改变。请稍后再试。" }
        return "图标没有保存成功，当前图标未改变。请稍后再试。"
    }
    private var canSave: Bool {
        !isSubmitting && !isLoading && !showsPhotoPicker && !showsFileImporter && symbolPickerRequest == nil
            && generationRequestID == nil && generationPresentationID == nil
            && standardDraft.canSave && darkDraft.canSave
    }
    private var canGenerateDarkIcon: Bool {
        acceptsImports && !isSubmitting && !isLoading && !showsPhotoPicker && !showsFileImporter
            && symbolPickerRequest == nil && generationRequestID == nil && generationPresentationID == nil
            && (standardDraft.isCustom ? standardDraft.canSave : localItem == nil)
    }

    private func binding(for appearance: Appearance) -> Binding<EditorDraft> {
        appearance == .standard ? $standardDraft : $darkDraft
    }

    var body: some View {
        // Keep the destination captured by this presentation, including the
        // interval after SwiftUI clears isPresented but before its callback.
        let presentedPhotoRequest = photoPickerRequest
        let presentedFileRequest = filePickerRequest
        Form {
            Group {
                Section {
                    Picker("编辑外观", selection: $appearance) {
                        ForEach(Appearance.allCases) { value in Text(value.title).tag(value) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("iconEditor.appearance")
                    VStack(spacing: 12) {
                        preview
                            .frame(width: cropSide, height: cropSide)
                            .accessibilityLabel("图标预览")
                        Text(name).font(.headline).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    Picker("图标来源", selection: active.isCustom) {
                        Text(sourceTitle).tag(false)
                        Text(customSourceTitle).tag(true)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("iconEditor.source")
                    if current.isCustom {
                        Picker("图标类型", selection: active.mode) {
                            ForEach(Mode.allCases) { item in Text(item.title).tag(item) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("iconEditor.mode")
                    }
                } footer: {
                    if localItem?.kind == .folder {
                        Text("封面只用于这个文件夹，保存分组后应用。未设置深色封面时跟随普通，普通未自定义时显示内容缩略图。文件夹内容不变。")
                    } else if localItem?.kind == .website {
                        Text("图标只用于这个网站，保存分组后应用。未设置深色图标时跟随普通，普通未自定义时显示地球图标。网址不变。")
                    } else if localItem?.kind == .contact {
                        Text("图标只用于这个联系人图块，保存分组后应用。未设置深色图标时跟随普通，普通未自定义时使用联系操作图标。姓名、号码和操作不变。")
                    } else {
                        Text("图标跟随当前界面的明暗外观；桌面的透明和色调效果由系统决定。未设置深色图标时使用普通图标，普通未自定义时使用自动图标。动作目标不变。")
                    }
                }

                if appearance == .dark {
                    Section {
                        Button { generateDarkIcon() } label: {
                            Label("从普通生成深色", systemImage: "moon.stars")
                        }
                        .disabled(!canGenerateDarkIcon)
                        .accessibilityIdentifier("iconEditor.generateDark")
                        if generationUndo != nil {
                            Button("撤销生成") { undoDarkGeneration() }
                                .disabled(isLoading || isSubmitting)
                                .accessibilityIdentifier("iconEditor.undoGeneration")
                        }
                        if !standardDraft.isCustom && localItem != nil {
                            Text("先为普通外观设置有效的自定义图标。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("在设备上生成，不会下载图片；效果不代表 App 官方提供的深色图标。")
                    }
                }

                if isLoading {
                    Section {
                        ForEach(Appearance.allCases) { destination in
                            if binding(for: destination).wrappedValue.isLoading {
                                HStack {
                                    ProgressView()
                                    Text(destination.loadingTitle)
                                    Spacer()
                                    Button("取消读取") { cancelImport(for: destination) }
                                        .buttonStyle(.borderless)
                                        .accessibilityIdentifier("iconEditor.cancelImport.\(destination.rawValue)")
                                }
                            }
                        }
                    }
                }

                if current.isCustom && current.mode != .photo {
                    Section("背景颜色") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                            ForEach(colors, id: \.self) { hex in
                                Button { active.wrappedValue.colorHex = hex } label: {
                                    Circle()
                                        .fill(iconColor(hex))
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            if current.colorHex == hex { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white) }
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(colorTitle(hex))
                                .accessibilityAddTraits(current.colorHex == hex ? .isSelected : [])
                                .accessibilityIdentifier("iconEditor.color.\(hex.dropFirst())")
                            }
                        }
                    }
                }

                if current.isCustom && current.mode == .symbol {
                    Section("选择符号") {
                        Button {
                            guard symbolPickerRequest == nil, !isSubmitting else { return }
                            symbolPickerRequest = SymbolPickerRequest(destination: appearance, selectedSymbol: current.symbol)
                        } label: {
                            HStack(spacing: 12) {
                                if let icon = current.nonPhotoIcon {
                                    CustomIconArtwork(icon: icon, cornerRadius: 10)
                                        .frame(width: 44, height: 44)
                                }
                                Text(symbolTitle(current.symbol)).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .accessibilityLabel("选择符号")
                        .accessibilityValue(Text(symbolTitle(current.symbol)))
                        .accessibilityIdentifier("iconEditor.chooseSymbol")
                    }
                } else if current.isCustom && current.mode == .emoji {
                    Section {
                        TextField("输入表情或文字", text: active.text)
                            .font(.title2)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("iconEditor.text")
                            .onChange(of: current.text) { _, value in
                                if value.count > 2 { active.wrappedValue.text = String(value.prefix(2)) }
                            }
                    } header: {
                        Text("表情或文字")
                    } footer: {
                        Text("最多两个字符，也可以输入姓名首字母。")
                    }
                } else if current.isCustom && current.mode == .date {
                    Section {
                        DateIconCurrentDateLabel()
                            .accessibilityIdentifier("iconEditor.currentDate")
                    } header: {
                        Text("日期")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("按设备当前日历和时区显示月份与日号。不读取日历事件，也不需要日历访问权限。")
                            Text("日期随时间更新；桌面小组件的刷新由系统安排，跨日后可能稍有延迟。")
                        }
                    }
                } else if current.isCustom && current.mode == .photo {
                    Section {
                        let hasPhoto = current.photo != nil
                        Button {
                            guard !showsPhotoPicker, !showsFileImporter else { return }
                            if filePickerRequest?.destination == appearance { filePickerRequest = nil }
                            selectedPhotoItem = nil
                            photoPickerRequest = PickerRequest(destination: appearance)
                            showsPhotoPicker = true
                        } label: {
                            Label(hasPhoto ? "更换照片" : "选择照片", systemImage: "photo")
                        }
                        .disabled(current.isLoading || isSubmitting)
                        .accessibilityIdentifier("iconEditor.photo")
                        Button {
                            guard !showsPhotoPicker, !showsFileImporter else { return }
                            if photoPickerRequest?.destination == appearance { photoPickerRequest = nil }
                            filePickerRequest = PickerRequest(destination: appearance)
                            showsFileImporter = true
                        } label: {
                            Label("从文件选择图片", systemImage: "folder")
                        }
                        .disabled(current.isLoading || isSubmitting)
                        .accessibilityIdentifier("iconEditor.imageFile")
                        if current.photo != nil {
                            VStack(spacing: 4) {
                                HStack {
                                    Text("缩放")
                                    Spacer()
                                    Text(current.zoom, format: .percent.precision(.fractionLength(0)))
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Button { adjustZoom(by: -0.1) } label: {
                                        Label("缩小", systemImage: "minus.magnifyingglass")
                                            .labelStyle(.iconOnly).frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(current.zoom <= 1)
                                    .accessibilityIdentifier("iconEditor.zoomOut")
                                    Slider(value: active.zoom, in: 1...3) { Text("缩放") }
                                        .accessibilityValue(Text(current.zoom, format: .percent.precision(.fractionLength(0))))
                                        .accessibilityIdentifier("iconEditor.zoom")
                                        .onChange(of: current.zoom) { _, _ in clampOffset() }
                                    Button { adjustZoom(by: 0.1) } label: {
                                        Label("放大", systemImage: "plus.magnifyingglass")
                                            .labelStyle(.iconOnly).frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(current.zoom >= 3)
                                    .accessibilityIdentifier("iconEditor.zoomIn")
                                }
                            }
                            Button("居中") { centerPhoto() }
                        }
                    } header: {
                        Text("裁剪照片")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("拖动预览调整位置。只读取你选中的照片或图片文件，裁剪后保存在设备上。")
                            Text("支持 PNG、JPEG 和 HEIC/HEIF 静态图片。读取失败时保留当前图片和裁剪。")
                        }
                    }
                }
            }
            .disabled(isGeneratingDarkIcon || isSubmitting)
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                if localItem != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { finishImporting(); dismiss() }
                            .accessibilityIdentifier("iconEditor.cancel")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if isGeneratingDarkIcon {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在生成深色图标…").font(.footnote)
                            Spacer(minLength: 0)
                            Button("取消生成") { cancelDarkGeneration() }
                                .font(.footnote).buttonStyle(.borderless)
                                .accessibilityIdentifier("iconEditor.cancelGeneration")
                        }
                    }
                    ForEach(Appearance.allCases) { destination in
                        if let reason = binding(for: destination).wrappedValue.incompleteReason {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(destination.title).font(.subheadline.weight(.semibold))
                                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if destination != appearance {
                                    Button(destination.editTitle) { appearance = destination }
                                        .font(.footnote)
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    Button { save() } label: {
                        Text(saveTitle).fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSave)
                    .accessibilityIdentifier("iconEditor.save")
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                .background(.bar)
            }
            .onAppear { acceptsImports = true; loadExisting() }
            .onDisappear {
                // A full-screen system picker may temporarily cover this view.
                // Its captured destination must survive until its own callback.
                if !showsPhotoPicker && !showsFileImporter && symbolPickerRequest == nil && generatedCandidate == nil {
                    finishImporting()
                }
            }
            .onChange(of: darkDraft.editFingerprint) { _, next in
                if let generationUndo, generationUndo.generatedFingerprint != next {
                    self.generationUndo = nil
                }
            }
            .sheet(item: $symbolPickerRequest) { request in
                CustomIconSymbolPickerView(selectedSymbol: request.selectedSymbol) { symbol in
                    guard !isSubmitting, symbolPickerRequest?.id == request.id,
                          CustomIconSymbolCatalog.entry(id: symbol) != nil else { return }
                    // A picker belongs to the appearance that opened it, never
                    // whichever appearance happens to be visible at callback time.
                    binding(for: request.destination).wrappedValue.symbol = symbol
                    symbolPickerRequest = nil
                }
            }
            .sheet(item: $generatedCandidate, onDismiss: generationSheetDidDismiss) { candidate in
                generationPreview(candidate)
            }
            .photosPicker(isPresented: $showsPhotoPicker,
                          selection: photoSelection(for: presentedPhotoRequest),
                          matching: .images, preferredItemEncoding: .automatic)
            .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.png, .jpeg, .heic, .heif],
                          allowsMultipleSelection: false) { result in
                receiveFile(result, request: presentedFileRequest)
            } onCancellation: {
                if filePickerRequest?.id == presentedFileRequest?.id { filePickerRequest = nil }
            }
            .alert("未能完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好", role: .cancel) {}
            } message: { if let error { Text(error) } }
    }

    private func generationPreview(_ candidate: GeneratedCandidate) -> some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 20) {
                        generationArtwork(candidate.result.source, appearance: .standard)
                        generationArtwork(candidate.result.icon, appearance: .dark)
                    }
                    .accessibilityElement(children: .contain)
                    .padding(.vertical, 12)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if candidate.result.treatment == .photograph {
                            Text("照片与复杂图片只做轻度明暗调整，效果可能不明显。")
                        }
                        Text("确认后仅更新深色草稿；仍需保存图标或分组。")
                    }
                }
            }
            .navigationTitle("深色图标预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancelDarkGeneration() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    applyGeneratedCandidate(candidate)
                } label: {
                    Text(darkDraft.isCustom ? "替换当前深色图标" : "使用深色版本")
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("iconEditor.useGeneratedDark")
                .keyboardShortcut(.defaultAction)
                .padding()
                .background(.bar)
            }
        }
    }

    private func generationArtwork(_ icon: CustomIcon, appearance: Appearance) -> some View {
        VStack(spacing: 12) {
            Text(appearance.title).font(.subheadline.weight(.semibold))
            CustomIconArtwork(icon: icon, cornerRadius: 24)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 160)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.title)
        .accessibilityIdentifier("iconEditor.generatedPreview.\(appearance.rawValue)")
        .dateIconAccessibilityValue(CustomIconVariants(standard: icon, dark: icon))
    }

    @ViewBuilder
    private var preview: some View {
        let selected = current.isCustom ? current : (appearance == .dark && standardDraft.isCustom ? standardDraft : nil)
        if let selected, selected.mode == .photo, let photo = selected.photo {
            let size = photoSize(photo, zoom: selected.zoom)
            Image(uiImage: photo)
                .resizable()
                .frame(width: size.width, height: size.height)
                .offset(selected.offset)
                .frame(width: cropSide, height: cropSide)
                .background(iconColor(selected.colorHex))
                .clipped()
                .clipShape(.rect(cornerRadius: cropSide * 0.22))
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { value in
                    guard current.isCustom else { return }
                    active.wrappedValue.offset = bounded(
                        CGSize(width: current.dragOrigin.width + value.translation.width,
                               height: current.dragOrigin.height + value.translation.height),
                        image: photo, zoom: current.zoom
                    )
                }.onEnded { _ in
                    if current.isCustom { active.wrappedValue.dragOrigin = current.offset }
                })
                .accessibilityAction(named: Text("向左移动")) { movePhoto(dx: -12, dy: 0) }
                .accessibilityAction(named: Text("向右移动")) { movePhoto(dx: 12, dy: 0) }
                .accessibilityAction(named: Text("向上移动")) { movePhoto(dx: 0, dy: -12) }
                .accessibilityAction(named: Text("向下移动")) { movePhoto(dx: 0, dy: 12) }
                .accessibilityAction(named: Text("居中")) { if current.isCustom { centerPhoto() } }
        } else if let icon = selected?.nonPhotoIcon {
            CustomIconArtwork(icon: icon, cornerRadius: cropSide * 0.22)
        } else if selected != nil {
            RoundedRectangle(cornerRadius: cropSide * 0.22)
                .fill(.quaternary)
                .overlay { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) }
        } else if let localItem, localItem.kind == .folder {
            FolderContentsArtwork(folder: localItem, cornerRadius: cropSide * 0.22, leafVariants: leafVariants)
                .environment(\.colorScheme, appearance == .dark ? .dark : .light)
        } else if localItem?.kind == .website {
            WebsiteArtwork(cornerRadius: cropSide * 0.22)
                .environment(\.colorScheme, appearance == .dark ? .dark : .light)
        } else if let localItem, localItem.kind == .contact, let target = localItem.contactTarget {
            ContactArtwork(target: target, cornerRadius: cropSide * 0.22)
                .environment(\.colorScheme, appearance == .dark ? .dark : .light)
        } else {
            AutomaticActionArtwork(name: name, cornerRadius: cropSide * 0.22)
        }
    }

    private func photoSize(_ image: UIImage, zoom: Double) -> CGSize {
        let scale = max(cropSide / image.size.width, cropSide / image.size.height) * zoom
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func bounded(_ proposal: CGSize, image: UIImage, zoom: Double) -> CGSize {
        let size = photoSize(image, zoom: zoom)
        let x = max(0, (size.width - cropSide) / 2)
        let y = max(0, (size.height - cropSide) / 2)
        return CGSize(width: min(x, max(-x, proposal.width)), height: min(y, max(-y, proposal.height)))
    }

    private func clampOffset() {
        guard let photo = current.photo else { return }
        active.wrappedValue.offset = bounded(current.offset, image: photo, zoom: current.zoom)
        active.wrappedValue.dragOrigin = current.offset
    }

    private func movePhoto(dx: CGFloat, dy: CGFloat) {
        guard current.isCustom, let photo = current.photo else { return }
        active.wrappedValue.offset = bounded(CGSize(width: current.offset.width + dx, height: current.offset.height + dy),
                                             image: photo, zoom: current.zoom)
        active.wrappedValue.dragOrigin = current.offset
    }

    private func adjustZoom(by change: Double) {
        active.wrappedValue.zoom = min(3, max(1, current.zoom + change))
        clampOffset()
    }

    private func centerPhoto() {
        active.wrappedValue.zoom = 1
        active.wrappedValue.offset = .zero
        active.wrappedValue.dragOrigin = .zero
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        let variants = initialVariants
        standardDraft = editorDraft(from: variants?.standard)
        darkDraft = editorDraft(from: variants?.dark)
    }

    private func editorDraft(from icon: CustomIcon?) -> EditorDraft {
        guard let icon else { return EditorDraft() }
        var draft = EditorDraft()
        draft.isCustom = true
        draft.originalIcon = icon
        draft.colorHex = icon.backgroundHex
        switch icon.kind {
        case .symbol: draft.mode = .symbol; draft.symbol = icon.value
        case .emoji: draft.mode = .emoji; draft.text = icon.value
        case .photo: draft.mode = .photo; draft.photo = icon.pngData.flatMap(UIImage.init(data:))
        case .date: draft.mode = .date
        }
        return draft
    }

    private func generateDarkIcon() {
        guard canGenerateDarkIcon else { return }
        let input: GenerationInput
        if standardDraft.isCustom {
            guard let icon = savedIcon(from: standardDraft) else {
                error = "普通图标无法读取或已损坏，当前草稿未改变。"
                return
            }
            input = .custom(icon)
        } else {
            guard localItem == nil, let appStoreID = AutomaticActionIcon.appStoreID(name: name) else {
                error = "没有可用的普通图标缓存。请先设置自定义普通图标。"
                return
            }
            input = .cached(appStoreID: appStoreID, country: AutomaticActionIcon.country(name: name, appStoreID: appStoreID))
        }

        // A dismissed picker can still deliver its completion. Generation owns
        // this edit interval, so invalidate both pending picker selections first.
        photoPickerRequest = nil
        filePickerRequest = nil
        let requestID = UUID()
        let sessionID = generationSessionID
        generationRequestID = requestID
        isGeneratingDarkIcon = true
        generationTask = Task { @MainActor in
            defer {
                if generationRequestID == requestID {
                    generationTask = nil
                    isGeneratingDarkIcon = false
                    if generatedCandidate?.id != requestID { generationRequestID = nil }
                }
            }
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let source: DarkIconGenerator.Source
                    switch input {
                    case .custom(let icon): source = .custom(icon)
                    case .cached(let appStoreID, let country):
                        guard let data = DirectLaunchIcons.cachedIcon(appStoreID: appStoreID, country: country) else {
                            throw GenerationFailure.noCachedArtwork
                        }
                        source = .cachedArtwork(data)
                    }
                    try Task.checkCancellation()
                    let result = try DarkIconGenerator.generate(from: source)
                    try Task.checkCancellation()
                    return result
                }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard acceptsImports, !isSubmitting, generationSessionID == sessionID,
                      generationRequestID == requestID else { return }
                generationPresentationID = requestID
                generatedCandidate = GeneratedCandidate(id: requestID, sessionID: sessionID, result: result)
            } catch {
                guard acceptsImports, generationSessionID == sessionID, generationRequestID == requestID,
                      !Task.isCancelled, !isCancellation(error) else { return }
                self.error = generationMessage(for: error)
            }
        }
    }

    private func cancelDarkGeneration(matching requestID: UUID? = nil) {
        if let requestID, generationRequestID != requestID { return }
        generationRequestID = nil
        generationTask?.cancel()
        generationTask = nil
        isGeneratingDarkIcon = false
        generatedCandidate = nil
    }

    private func generationSheetDidDismiss() {
        // Keep the presentation ID until dismissal completes. A new generation
        // cannot start in that interval, and this callback only owns its request.
        let dismissedID = generationPresentationID
        generationPresentationID = nil
        if let dismissedID { cancelDarkGeneration(matching: dismissedID) }
    }

    private func applyGeneratedCandidate(_ candidate: GeneratedCandidate) {
        guard acceptsImports, !isSubmitting, generationSessionID == candidate.sessionID,
              generationRequestID == candidate.id, generationPresentationID == candidate.id,
              generatedCandidate?.id == candidate.id else { return }
        let previous = darkDraft
        let generated = editorDraft(from: candidate.result.icon)
        // Keep the complete previous draft, including any unsaved photo crop.
        generationUndo = GenerationUndo(previous: previous, generatedFingerprint: generated.editFingerprint)
        darkDraft = generated
        appearance = .dark
        cancelDarkGeneration()
    }

    private func undoDarkGeneration() {
        guard !isSubmitting, !isLoading, generationRequestID == nil, let generationUndo else { return }
        // A control or import may have changed the draft before SwiftUI delivers
        // onChange. Never let the previous generation overwrite that newer edit.
        guard darkDraft.editFingerprint == generationUndo.generatedFingerprint else {
            self.generationUndo = nil
            return
        }
        darkDraft = generationUndo.previous
        self.generationUndo = nil
    }

    private func generationMessage(for failure: Error) -> LocalizedStringKey {
        if failure is GenerationFailure {
            return "没有可用的普通图标缓存。请先设置自定义普通图标。"
        }
        if let failure = failure as? DarkIconGenerationError, failure == .invalidImage {
            return "普通图标无法读取或已损坏，当前草稿未改变。"
        }
        return "无法生成深色图标，当前草稿未改变。请稍后再试。"
    }

    private func photoSelection(for request: PickerRequest?) -> Binding<PhotosPickerItem?> {
        Binding(get: { selectedPhotoItem }, set: { item in
            guard let request, acceptsImports,
                  photoPickerRequest?.id == request.id else { return }
            selectedPhotoItem = item
            guard let item else { return }
            photoPickerRequest = nil
            startImport(.library(item), for: request.destination)
        })
    }

    private func receiveFile(_ result: Result<[URL], Error>, request: PickerRequest?) {
        guard let request, acceptsImports, filePickerRequest?.id == request.id else { return }
        filePickerRequest = nil
        switch result {
        case .success(let urls):
            guard urls.count == 1, let url = urls.first, url.isFileURL else {
                error = "请选择一个图片文件。"
                return
            }
            startImport(.file(url), for: request.destination)
        case .failure(let failure):
            if !isCancellation(failure) { error = "无法读取这个图片文件，请确认文件可用后重新选择。" }
        }
    }

    private func startImport(_ source: PhotoSource, for destination: Appearance) {
        guard acceptsImports, !isSubmitting else { return }
        cancelImport(for: destination)
        let target = binding(for: destination)
        let requestID = UUID()
        target.wrappedValue.importID = requestID
        target.wrappedValue.isLoading = true
        let task = Task { @MainActor in
            defer {
                if target.wrappedValue.importID == requestID {
                    target.wrappedValue.importID = nil
                    target.wrappedValue.isLoading = false
                    setImportTask(nil, for: destination)
                }
            }
            do {
                let data: Data
                switch source {
                case .library(let item):
                    guard let selected = try await item.loadTransferable(type: Data.self) else {
                        throw IconPhotoImportError.invalidImage
                    }
                    data = selected
                case .file(let url):
                    data = try await IconPhotoFileReader.read(url: url)
                }
                try Task.checkCancellation()
                guard acceptsImports, target.wrappedValue.importID == requestID else { return }
                let worker = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let image = try IconPhotoImport.prepare(data)
                    try Task.checkCancellation()
                    return image
                }
                let image = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard acceptsImports, target.wrappedValue.importID == requestID else { return }
                // No image or crop state changes until every read and validation
                // step succeeds. The other appearance is never touched.
                var next = target.wrappedValue
                next.photo = UIImage(cgImage: image)
                next.photoWasReplaced = true
                next.zoom = 1
                next.offset = .zero
                next.dragOrigin = .zero
                target.wrappedValue = next
            } catch {
                guard acceptsImports, target.wrappedValue.importID == requestID,
                      !Task.isCancelled, !isCancellation(error) else { return }
                self.error = importMessage(for: error)
            }
        }
        setImportTask(task, for: destination)
    }

    private func setImportTask(_ task: Task<Void, Never>?, for destination: Appearance) {
        switch destination {
        case .standard: standardImportTask = task
        case .dark: darkImportTask = task
        }
    }

    private func cancelImport(for destination: Appearance) {
        let target = binding(for: destination)
        target.wrappedValue.importID = nil
        target.wrappedValue.isLoading = false
        switch destination {
        case .standard: standardImportTask?.cancel()
        case .dark: darkImportTask?.cancel()
        }
        setImportTask(nil, for: destination)
    }

    private func finishImporting() {
        acceptsImports = false
        generationSessionID = UUID()
        cancelDarkGeneration()
        photoPickerRequest = nil
        filePickerRequest = nil
        cancelImport(for: .standard)
        cancelImport(for: .dark)
    }

    private func isCancellation(_ failure: Error) -> Bool {
        if failure is CancellationError { return true }
        let value = failure as NSError
        return value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError
    }

    private func importMessage(for failure: Error) -> LocalizedStringKey {
        guard let failure = failure as? IconPhotoImportError else {
            return "无法读取这张图片，请重新选择或稍后重试。"
        }
        return switch failure {
        case .tooManyBytes: "图片文件过大，请选择不超过 30 MB 的图片。"
        case .tooManyPixels: "图片尺寸过大，请选择较小的图片。"
        case .unsupportedFormat: "请选择单张 PNG、JPEG 或 HEIC/HEIF 图片。"
        case .invalidImage: "这张图片无法读取或已损坏，请重新选择。"
        }
    }

    private func savedIcon(from draft: EditorDraft) -> CustomIcon? {
        guard draft.isCustom else { return nil }
        guard draft.mode == .photo, let photo = draft.photo else { return draft.nonPhotoIcon }
        // Editing the other appearance, or switching sources and back, must not
        // recompress a saved photograph that still has its original crop.
        if let original = draft.originalIcon, original.kind == .photo,
           !draft.photoWasReplaced, draft.zoom == 1, draft.offset == .zero {
            if original.backgroundHex == draft.colorHex { return original }
            guard let png = original.pngData else { return nil }
            return CustomIcon.photo(pngData: png, backgroundHex: draft.colorHex)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format)
        let size = photoSize(photo, zoom: draft.zoom)
        let factor = 256 / cropSide
        let rect = CGRect(x: (cropSide - size.width) / 2 + draft.offset.width,
                          y: (cropSide - size.height) / 2 + draft.offset.height,
                          width: size.width, height: size.height)
        let png = renderer.pngData { context in
            context.cgContext.scaleBy(x: factor, y: factor)
            photo.draw(in: rect)
        }
        return CustomIcon.photo(pngData: png, backgroundHex: draft.colorHex)
    }

    private func save() {
        guard canSave else { return }
        // The successful callback must run once, including during dismissal.
        // This also avoids staging or re-encoding the same artwork twice.
        isSubmitting = true
        let standard = savedIcon(from: standardDraft)
        let dark = savedIcon(from: darkDraft)
        guard (!standardDraft.isCustom || standard != nil), (!darkDraft.isCustom || dark != nil) else {
            isSubmitting = false
            error = saveFailure
            return
        }
        let variants = standard == nil && dark == nil ? nil : CustomIconVariants(standard: standard, dark: dark)
        do {
            try onCommit(variants)
            finishImporting()
            dismiss()
        } catch {
            isSubmitting = false
            self.error = saveFailure
        }
    }

    private func iconColor(_ hex: String) -> Color {
        let rgb = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double(rgb >> 16 & 255) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)
    }

    private func colorTitle(_ hex: String) -> LocalizedStringKey {
        switch hex {
        case "#0A84FF": "蓝"
        case "#5856D6": "靛"
        case "#AF52DE": "紫"
        case "#FF2D55": "粉"
        case "#D70015": "红"
        case "#A65300": "棕"
        case "#00854A": "绿"
        case "#007C91": "青"
        case "#48484A": "灰"
        default: "黑"
        }
    }

    private func symbolTitle(_ value: String) -> LocalizedStringKey {
        LocalizedStringKey(CustomIconSymbolCatalog.entry(id: value)?.titleKey ?? "符号")
    }
}
