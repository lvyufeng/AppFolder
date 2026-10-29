import AppFolderKit
import SwiftUI

/// Choosing a search source never changes the account or a saved action target.
struct AppStoreRegionPickerView: View {
    let selectedRegion: AppStoreSearchRegion
    let onSelect: (AppStoreSearchRegion) -> Void
    @State private var query = ""
    @State private var isSelecting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        let countries = AppStoreCountry.search(query: query, locale: locale)
        NavigationStack {
            List {
                Section {
                    regionButton(.automatic, title: String(localized: "自动（美国、中国大陆）"))
                } footer: {
                    Text("先搜索美国；没有结果时再搜索中国大陆。")
                }

                Section("国家或地区") {
                    if countries.isEmpty {
                        ContentUnavailableView {
                            Label("没有匹配的国家或地区", systemImage: "magnifyingglass")
                        } description: {
                            Text("可搜索当地名称、英文名称或两位地区代码。")
                        } actions: {
                            Button("清除搜索") { query = "" }
                                .accessibilityIdentifier("storeRegion.clearSearch")
                        }
                    } else {
                        ForEach(countries, id: \.self) { code in
                            if let region = AppStoreSearchRegion(countryCode: code) {
                                regionButton(region, title: AppStoreCountry.displayName(for: code, locale: locale), code: code)
                            }
                        }
                    }
                }
            }
            .navigationTitle("商店国家/地区")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索国家或地区")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .accessibilityIdentifier("storeRegion.cancel")
                }
            }
        }
    }

    private func regionButton(_ region: AppStoreSearchRegion, title: String, code: String? = nil) -> some View {
        let selected = selectedRegion == region
        return Button {
            guard !isSelecting else { return }
            isSelecting = true
            onSelect(region)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: title).foregroundStyle(.primary)
                Spacer()
                if let code {
                    Text(code.uppercased()).font(.caption).foregroundStyle(.secondary)
                }
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .disabled(isSelecting)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("storeRegion.\(region.rawValue)")
    }
}
