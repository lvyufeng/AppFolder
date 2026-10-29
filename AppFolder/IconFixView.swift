import AppFolderKit
import SwiftUI
import UIKit
import WidgetKit

/// The screen that fixes a wrong icon.
///
/// ## The problem it solves, stated plainly
///
/// A widget slot knows the app behind it only by **name** — the system hands over
/// a `SystemShortcut` whose display representation is a title and nothing else.
/// Names collide: "Authenticator" is eight different apps in the store, and the
/// search can only guess which one is meant. Its guess is a real app's icon, so a
/// wrong one looks exactly like a right one until the user notices.
///
/// No rule can do better, because the right answer is "the one they installed" and
/// nothing the widget can read knows that. So this screen is how the user says so.
///
/// ## Why it can list anything at all
///
/// The app cannot read a widget's configuration — the slots are the system's — and
/// cannot enumerate the Home Screen. It learns what is on a widget only because the
/// widget reports what it drew, into the shared container, on every timeline build.
/// That is ``DirectLaunchOverrides/observedSlots``, and it is why the list here is
/// empty until a widget has drawn at least once.
///
/// The manual field at the bottom exists for exactly that gap: a name can be typed
/// before any widget has reported, because an override is keyed on the name alone.
struct IconFixView: View {
    /// What the widget last drew, newest first. Reloaded when the screen appears,
    /// because the widget may have run while this screen was not on top.
    @State private var slots: [DirectLaunchOverrides.SlotRecord] = []
    @State private var customIcons: [String: CustomIconVariants] = [:]
    @State private var libraryReadFailed = false
    @Environment(\.scenePhase) private var scenePhase
    private let storageAvailable = WidgetState.isAvailable

    /// The name the user is typing for a manual fix.
    @State private var manualName = ""

    var body: some View {
        List {
            Section {
                NavigationLink { ActionLibraryView() } label: { Label("动作资料库", systemImage: "tag") }
                Text("标签和归档只整理动作资料库；这里仍显示可读取的图标与小组件记录。")
                    .font(.footnote).foregroundStyle(.secondary)
                if libraryReadFailed {
                    Text("动作资料库暂时无法读取，整理功能不可用。已保留上次读取的内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !storageAvailable {
                Section {
                    Text("这个安装读不到 AppFolder 与小组件之间的共享空间，图标修正传不到桌面。")
                        .font(.body.weight(.medium))
                    Text("重新安装 AppFolder 后再试。重新安装会移除这个共享空间里的旧数据。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("共享空间不可用")
                }
            } else if slots.isEmpty {
                Section {
                    Text("还没有读到桌面上的小组件。")
                        .font(.body.weight(.medium))
                    Text("把一个「直接启动」小组件放到桌面上、让它画一次，它上面的 App 就会出现在这里。App 读不到桌面配置——这些是小组件自己报回来的。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("动作与图标")
                } footer: {
                    Text("等不及的话，用下面的「手动指定」直接输入格子上显示的名字。")
                }
            } else {
                Section {
                    ForEach(slots) { slot in
                        NavigationLink {
                            IconPickView(name: slot.name)
                        } label: {
                            SlotRow(slot: slot, variants: customIcons[slot.id])
                        }
                    }
                } header: {
                    Text("动作与图标")
                } footer: {
                    Text("这里包含小组件记录、分组引用和本地保存的名称。图标设置不会创建系统动作。")
                }
            }

            if storageAvailable {
                Section {
                    HStack(spacing: 12) {
                        TextField("格子上的名字，如 Authenticator", text: $manualName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        NavigationLink {
                            IconPickView(name: manualName)
                        } label: {
                            Text("指定")
                        }
                        .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("手动指定")
                } footer: {
                    Text("名字要和小组件上显示的一模一样——大小写和空格无所谓。")
                }
            }
        }
        .navigationTitle("图标工作室")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshSlots() }
        .refreshable { refreshSlots() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSlots() }
        }
    }

    private func refreshSlots() {
        customIcons = CustomIconStore.all
        var records = Dictionary(uniqueKeysWithValues: DirectLaunchOverrides.observedSlots.map { ($0.id, $0) })
        let source = ActionLibrarySourceData.read()
        libraryReadFailed = source.library.status != .available
        for entry in source.entries() where records[entry.id] == nil {
            records[entry.id] = .init(name: entry.name,
                                 appStoreID: DirectLaunchOverrides.appStoreID(name: entry.name),
                                 source: DirectLaunchIcons.Source.override.rawValue,
                                 updatedAt: .distantPast)
        }
        if libraryReadFailed || source.groupReadFailed {
            for slot in slots where records[slot.id] == nil { records[slot.id] = slot }
        }
        slots = records.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

/// One row: the icon the widget is currently drawing, its name, and whether that
/// icon was the user's choice or a guess.
private struct SlotRow: View {
    let slot: DirectLaunchOverrides.SlotRecord
    let variants: CustomIconVariants?

    private var isPinned: Bool { variants != nil || DirectLaunchOverrides.hasOverride(name: slot.name) }

    /// A short, honest description of where the icon came from.
    ///
    /// The distinction that matters to the user is "I chose this" versus "it was
    /// worked out", so that is what the row says — not the names of the internal
    /// rules.
    /// `LocalizedStringKey`, not `String`: a plain `String` here would render
    /// verbatim through `Text` and never reach the string catalog.
    private var detail: LocalizedStringKey {
        if let variants {
            return variants.standard == nil ? "仅深色自定义" : variants.dark == nil ? "普通自定义 · 深色跟随" : "普通与深色均已自定义"
        }
        if isPinned { return "已指定" }
        // `?? .none` because the record stores the source as a raw string, so a
        // value written by a different build of the app must decode to something
        // rather than crash the list.
        switch DirectLaunchIcons.Source(rawValue: slot.source) ?? .none {
        case .catalogue: return "自动 · 内置目录"
        case .system: return "自动 · 系统 App"
        case .search: return "自动 · 商店搜索"
        case .miss: return "自动 · 没找到，显示占位方块"
        case .override, .none: return "自动"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            SlotIcon(name: slot.name, appStoreID: DirectLaunchOverrides.appStoreID(name: slot.name) ?? slot.appStoreID, variants: variants)

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name).font(.body.weight(.medium))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()

            if isPinned {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.footnote)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The icon the widget is actually drawing for a slot.
///
/// Reads the same `Icons/<id>.png` the widget reads — via
/// ``DirectLaunchIcons/cachedIcon(appStoreID:)``, which fetches nothing — rather
/// than downloading the artwork again. That matters: the point of this screen is
/// to show a *wrong* icon, and a fresh download could differ from what is on the
/// Home Screen if the cache and the store disagree.
///
/// Falls back to the same neutral square the widget draws, so a slot with no
/// artwork looks here exactly as it looks on the Home Screen.
private struct SlotIcon: View {
    let name: String
    let appStoreID: Int?
    var variants: CustomIconVariants? = nil
    var side: CGFloat = 30
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let custom = variants?.resolved(isDark: colorScheme == .dark) {
                CustomIconArtwork(icon: custom, cornerRadius: side * 0.22)
            } else {
                AutomaticActionArtwork(name: name, appStoreID: appStoreID, cornerRadius: side * 0.22)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side * 0.22))
    }
}

/// Offline fallback shared by the icon editor, library rows, and group preview.
/// Choosing a different artwork never changes the system-owned action target.
struct AutomaticActionArtwork: View {
    let name: String
    var appStoreID: Int? = nil
    var cornerRadius: CGFloat = 8
    var placeholderForeground: AnyShapeStyle? = nil
    var placeholderFill: AnyShapeStyle? = nil

    var body: some View {
        Group {
            if let id = appStoreID ?? AutomaticActionIcon.appStoreID(name: name),
               let data = DirectLaunchIcons.cachedIcon(appStoreID: id, country: AutomaticActionIcon.country(name: name, appStoreID: id)),
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(placeholderFill ?? AnyShapeStyle(HierarchicalShapeStyle.quaternary))
                    .overlay {
                        GeometryReader { proxy in
                            Image(systemName: AutomaticActionIcon.symbolName(name: name) ?? "app.dashed")
                                .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.45))
                                .foregroundStyle(placeholderForeground ?? AnyShapeStyle(HierarchicalShapeStyle.secondary))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}

/// Names and catalog data only; never starts a network request.
enum AutomaticActionIcon {
    static func appStoreID(name: String) -> Int? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DirectLaunchOverrides.appStoreID(name: name)
            ?? DirectLaunchOverrides.observedSlots.first(where: { $0.id == normalized })?.appStoreID
            ?? AppCatalog.match(name: name)?.appStoreID
    }

    static func symbolName(name: String) -> String? { AppCatalog.match(name: name)?.symbolName }

    static func country(name: String, appStoreID: Int) -> String? {
        guard let mapping = DirectLaunchOverrides.mapping(name: name), mapping.appStoreID == appStoreID else { return nil }
        return mapping.country
    }
}

/// Picks the correct app for one slot name.
///
/// Search, look, choose. The result rows carry the seller name on purpose: it is
/// the only field that distinguishes eight apps all called "Authenticator", and it
/// is precisely the information the automatic matcher could not weigh.
struct IconPickView: View {
    let name: String

    @State private var query: String
    @AppStorage("iconSearchRegion", store: .standard) private var regionRawValue = AppStoreSearchRegion.automatic.rawValue
    @State private var initialized = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchRequest: SearchRequest?
    @State private var searchReceipt: SearchReceipt?
    @State private var activeCountry: String?
    @State private var failedCountry: String?
    @State private var regionPickerRequest: RegionPickerRequest?
    @State private var isCommitting = false
    @State private var isSearching = false
    /// Distinguishes "the search found nothing" from "the search could not run".
    /// The two need different words, and conflating them is the bug the store
    /// client already fixed once — see the commit about non-200 responses.
    @State private var failed = false
    @State private var showsCustomEditor = false
    @State private var variants: CustomIconVariants?
    /// Whether the answer could not be recorded, which is not the same as "the
    /// search failed" and must not dismiss the sheet as though it had worked.
    ///
    /// ``DirectLaunchOverrides/set(appStoreID:name:)`` refuses when the shared
    /// domain is unreachable, precisely so a choice cannot be written somewhere
    /// only this screen can see. The screen then has to *say* so: quietly closing
    /// would leave the user believing they had fixed an icon that is still wrong,
    /// which is the failure this whole view exists to let them escape.
    @State private var failure: SaveFailure?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    private enum SaveFailure {
        case storageUnavailable
        case writeFailed
        case rollbackFailed
    }

    private struct SearchRequest {
        let id = UUID()
        let term: String
        let countries: [String]
        let regionRawValue: String
    }

    private struct SearchReceipt {
        let id: UUID
        let term: String
        let country: String
        let regionRawValue: String
        let searchedCountries: [String]
        let rows: [AppStoreLookup]
    }

    private struct RegionPickerRequest: Identifiable {
        let id = UUID()
        let region: AppStoreSearchRegion
    }

    init(name: String) {
        self.name = name
        _query = State(initialValue: name)
    }

    private var region: AppStoreSearchRegion { AppStoreSearchRegion(rawValue: regionRawValue) ?? .automatic }
    private var regionName: String {
        region.countryCode.map { countryName($0) } ?? String(localized: "自动（美国、中国大陆）")
    }
    private var currentMapping: DirectLaunchOverrides.Mapping? { DirectLaunchOverrides.mapping(name: name) }
    private var currentID: Int? { currentMapping?.appStoreID }
    private var variantDescription: LocalizedStringKey {
        guard let variants else { return "自动图标" }
        if variants.standard == nil { return "仅深色自定义" }
        return variants.dark == nil ? "普通自定义 · 深色跟随" : "普通与深色均已自定义"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    SlotIcon(name: name, appStoreID: currentID, variants: variants, side: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.headline)
                        Text(variantDescription)
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let country = currentMapping?.country {
                            Text("已指定来源：\(countryName(country))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    showsCustomEditor = true
                } label: {
                    Label("自定义图标", systemImage: "paintpalette")
                }
                .accessibilityIdentifier("iconPicker.custom")
            } footer: {
                Text("可为普通和深色外观分别设置照片、符号、文字或当前日期，只改变小组件图标。")
            }

            Section {
                LabeledContent("格子上的名字") {
                    Text(name).font(.body.weight(.medium))
                }
            } footer: {
                Text("按 App Store 里搜到的选。同名 App 会有多个，看开发者那一行区分。")
            }

            Section {
                Button {
                    guard regionPickerRequest == nil, !isCommitting else { return }
                    regionPickerRequest = RegionPickerRequest(region: region)
                } label: {
                    HStack {
                        Text("商店国家/地区").foregroundStyle(.primary)
                        Spacer()
                        Text(regionName).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .accessibilityIdentifier("iconPicker.region")
            } footer: {
                Text("仅选择图标搜索来源，不会更改系统动作或 Apple 账户的国家/地区。")
            }

            Section {
                HStack(spacing: 8) {
                    TextField("搜索 App Store", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { startSearch() }
                        .accessibilityIdentifier("iconPicker.query")
                    Button("搜索") { startSearch() }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                        .accessibilityIdentifier("iconPicker.search")
                }

                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        if let activeCountry {
                            Text("正在搜索：\(countryName(activeCountry))").foregroundStyle(.secondary)
                        } else {
                            Text("搜索中…").foregroundStyle(.secondary)
                        }
                    }
                } else if failed {
                    if let failedCountry {
                        Text("搜索来源：\(countryName(failedCountry))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("连不上 App Store，检查网络后再试。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if let receipt = searchReceipt {
                    Text("搜索来源：\(sourceName(for: receipt))")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("iconPicker.resultSource")
                    if receipt.rows.isEmpty {
                        Text("没搜到。换个关键词试试，比如用英文名。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(receipt.rows, id: \.id) { app in
                        Button {
                            choose(app, receipt: receipt)
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: app.artworkURL.flatMap(URL.init(string:))) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary)
                                }
                                .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(app.sellerName ?? "—")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }

                                Spacer()

                                if variants?.standard == nil && app.trackID == currentID && currentMapping?.country == receipt.country {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityIdentifier("iconPicker.result.\(app.trackID)")
                    }
                }
            } header: {
                Text("选择正确的 App")
            } footer: {
                Text("选择 App Store 图标会替换普通图标，保留你单独设置的深色图标。")
            }

            if currentID != nil || variants != nil {
                Section {
                    Button("全部恢复自动图标", role: .destructive) {
                        restore()
                    }
                } footer: {
                    Text("清除普通、深色自定义图标和 App Store 指定，重新按名字自动匹配。")
                }
            }
        }
        .disabled(isCommitting)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsCustomEditor) {
            CustomIconEditorView(name: name) {
                variants = CustomIconStore.variants(name: name)
            }
        }
        .sheet(item: $regionPickerRequest) { request in
            AppStoreRegionPickerView(selectedRegion: request.region) { selected in
                guard regionPickerRequest?.id == request.id, !isCommitting else { return }
                regionPickerRequest = nil
                if regionRawValue != selected.rawValue {
                    cancelSearch()
                    regionRawValue = selected.rawValue
                }
            }
        }
        // The refusal has exactly one cause worth naming to a user: the App Group
        // is not reachable from here, so nothing this screen writes can be seen by
        // the widget. Naming the cause beats "失败" — it tells them the install is
        // the thing to look at, not the app they picked.
        .alert("没能记下这个选择", isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            switch failure {
            case .storageUnavailable:
                Text("AppFolder 和小组件之间的共享空间现在读不到，改了也传不过去。重新安装 AppFolder 后可以再试——这次的选择没有生效。")
            case .writeFailed, .none:
                Text("这次的选择没有保存成功。稍后再试；当前图标没有改变。")
            case .rollbackFailed:
                Text("图标更改未能完整保存或撤销，请重新选择图标。")
            }
        }
        .onAppear {
            variants = CustomIconStore.variants(name: name)
            guard !initialized else { return }
            initialized = true
            if variants?.standard == nil { startSearch() }
        }
        .onChange(of: query) { _, _ in cancelSearch() }
        .onChange(of: regionRawValue) { _, _ in startSearch() }
        .onDisappear {
            if regionPickerRequest == nil { cancelSearch(clearResults: false) }
        }
    }

    /// Pins this slot name to an app, and makes the change visible.
    ///
    /// The order matters. The artwork is fetched **before** the reload, because the
    /// widget never does network at draw time — reloading first would render the
    /// new id with no icon on disk and flash a placeholder until a later timeline.
    private func choose(_ app: AppStoreLookup, receipt: SearchReceipt) {
        guard !isCommitting, !isSearching, searchReceipt?.id == receipt.id,
              receipt.term == query.trimmingCharacters(in: .whitespacesAndNewlines),
              receipt.regionRawValue == region.rawValue else { return }
        guard let mapping = DirectLaunchOverrides.Mapping(appStoreID: app.trackID, country: receipt.country) else {
            failure = .writeFailed
            return
        }
        guard WidgetState.isAvailable else {
            failure = .storageUnavailable
            return
        }
        isCommitting = true
        cancelSearch(clearResults: false)
        let retainedDark = CustomIconStore.variants(name: name)?.dark
        let retainedVariants = retainedDark.map { CustomIconVariants(dark: $0) }
        guard saveSelection(mapping: mapping, variants: retainedVariants) else {
            isCommitting = false
            return
        }
        DirectLaunchIcons.diagnose("app override name=«\(name)» id=\(app.trackID) country=\(receipt.country)")
        Task {
            _ = await DirectLaunchIcons.ensureIcon(appStoreID: mapping.appStoreID, country: mapping.country)
            AppFolderWidgetRefresh.libraryChanged()
        }
        dismiss()
    }

    private func restore() {
        guard !isCommitting else { return }
        guard WidgetState.isAvailable else {
            failure = .storageUnavailable
            return
        }
        isCommitting = true
        cancelSearch(clearResults: false)
        guard saveSelection(mapping: nil, variants: nil) else {
            isCommitting = false
            return
        }
        DirectLaunchIcons.diagnose("app override cleared name=«\(name)»")
        AppFolderWidgetRefresh.libraryChanged()
        dismiss()
    }

    /// Commit artwork before its fallback, and compare the full mapping so a
    /// same-ID change of storefront is persisted and can be rolled back too.
    private func saveSelection(mapping nextMapping: DirectLaunchOverrides.Mapping?, variants nextVariants: CustomIconVariants?) -> Bool {
        let previousMapping = DirectLaunchOverrides.mapping(name: name)
        let previousVariants = CustomIconStore.variants(name: name)
        guard CustomIconStore.setVariants(nextVariants, name: name) else {
            failure = .writeFailed
            return false
        }
        _ = DirectLaunchOverrides.set(mapping: nextMapping, name: name)
        guard DirectLaunchOverrides.mapping(name: name) == nextMapping else {
            _ = DirectLaunchOverrides.set(mapping: previousMapping, name: name)
            let mappingRestored = DirectLaunchOverrides.mapping(name: name) == previousMapping
            let artworkRestored = CustomIconStore.setVariants(previousVariants, name: name)
            failure = mappingRestored && artworkRestored ? .writeFailed : .rollbackFailed
            return false
        }
        return true
    }

    private func cancelSearch(clearResults: Bool = true) {
        // Invalidate before cancelling: transport may complete at the same time,
        // and a cancellation can be represented by storeData as a nil payload.
        searchRequest = nil
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        activeCountry = nil
        if clearResults {
            searchReceipt = nil
            failed = false
            failedCountry = nil
        }
    }

    private func countryName(_ code: String) -> String {
        AppStoreCountry.displayName(for: code, locale: locale)
    }

    private func sourceName(for receipt: SearchReceipt) -> String {
        let countries = receipt.rows.isEmpty ? receipt.searchedCountries : [receipt.country]
        return countries.map { countryName($0) }.joined(separator: " · ")
    }

    private func startSearch() {
        guard !isCommitting else { return }
        cancelSearch()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let selectedRegion = region
        let request = SearchRequest(term: term, countries: selectedRegion.queryCountries, regionRawValue: selectedRegion.rawValue)
        searchRequest = request
        isSearching = true
        activeCountry = request.countries.first
        searchTask = Task { @MainActor in
            defer {
                if searchRequest?.id == request.id {
                    searchRequest = nil
                    searchTask = nil
                    isSearching = false
                    activeCountry = nil
                }
            }
            var searchedCountries: [String] = []
            for country in request.countries {
                guard !Task.isCancelled, searchRequest?.id == request.id else { return }
                activeCountry = country
                guard let url = AppStoreLookup.searchURL(term: request.term, country: country, limit: 15) else {
                    failed = true
                    failedCountry = country
                    return
                }
                let payload = await DirectLaunchIcons.storeData(url: url)
                guard !Task.isCancelled, searchRequest?.id == request.id else { return }
                guard let payload, let rows = AppStoreLookup.parseResponse(payload) else {
                    failed = true
                    failedCountry = country
                    return
                }
                searchedCountries.append(country)
                if !rows.isEmpty {
                    searchReceipt = SearchReceipt(id: request.id, term: request.term, country: country, regionRawValue: request.regionRawValue,
                                                  searchedCountries: searchedCountries, rows: rows)
                    return
                }
            }
            guard !Task.isCancelled, searchRequest?.id == request.id,
                  let lastCountry = searchedCountries.last else { return }
            searchReceipt = SearchReceipt(id: request.id, term: request.term, country: lastCountry, regionRawValue: request.regionRawValue,
                                          searchedCountries: searchedCountries, rows: [])
        }
    }
}
