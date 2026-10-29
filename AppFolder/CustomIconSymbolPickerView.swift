import AppFolderKit
import SwiftUI

/// Browsing only filters the catalog. The caller's draft changes after one
/// explicit selection, and the enclosing icon editor still owns persistence.
struct CustomIconSymbolPickerView: View {
    let selectedSymbol: String
    let onSelect: (String) -> Void
    @State private var query = ""
    @State private var category: CustomIconSymbolCatalog.Category?
    @State private var isSelecting = false
    @Environment(\.dismiss) private var dismiss

    private var results: [CustomIconSymbolCatalog.Entry] {
        CustomIconSymbolCatalog.search(query: query, category: category) {
            String(localized: String.LocalizationValue($0))
        }
    }

    var body: some View {
        let matching = results
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    if let selected = CustomIconSymbolCatalog.entry(id: selectedSymbol) {
                        HStack(spacing: 10) {
                            Image(systemName: selected.id).font(.title2).frame(width: 36, height: 36)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("当前符号").font(.caption).foregroundStyle(.secondary)
                                Text(LocalizedStringKey(selected.titleKey))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("symbolPicker.current")
                    }
                    HStack {
                        Picker("符号分类", selection: $category) {
                            Text("全部符号").tag(CustomIconSymbolCatalog.Category?.none)
                            ForEach(CustomIconSymbolCatalog.Category.allCases) { value in
                                Text(LocalizedStringKey(value.titleKey)).tag(Optional(value))
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("symbolPicker.category")
                        Spacer()
                        Text("共 \(matching.count) 个符号")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("symbolPicker.count")
                    }
                }
                .padding()
                Divider()

                if matching.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配的符号", systemImage: "magnifyingglass")
                    } description: {
                        Text("试试其他名称或分类，当前符号保持不变。")
                    } actions: {
                        Button("清除筛选") { query = ""; category = nil }
                            .accessibilityIdentifier("symbolPicker.clearFilters")
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                                ForEach(matching) { entry in
                                    symbolButton(entry)
                                }
                            }
                            .padding()
                            .id("symbolPicker.results.top")
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .accessibilityIdentifier("symbolPicker.results")
                        .onChange(of: query) { _, _ in
                            proxy.scrollTo("symbolPicker.results.top", anchor: .top)
                        }
                        .onChange(of: category) { _, _ in
                            proxy.scrollTo("symbolPicker.results.top", anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle("选择符号")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索符号")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .accessibilityIdentifier("symbolPicker.cancel")
                }
            }
        }
    }

    private func symbolButton(_ entry: CustomIconSymbolCatalog.Entry) -> some View {
        let isSelected = selectedSymbol == entry.id
        return Button {
            guard !isSelecting else { return }
            isSelecting = true
            onSelect(entry.id)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: entry.id)
                    .font(.system(size: 26))
                    .frame(height: 36)
                Text(LocalizedStringKey(entry.titleKey))
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 30, alignment: .top)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07),
                        in: .rect(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.caption).padding(5)
                }
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isSelecting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(entry.titleKey)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("symbolPicker.symbol.\(entry.id)")
    }
}
