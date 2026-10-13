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

    /// The name the user is typing for a manual fix.
    @State private var manualName = ""

    var body: some View {
        List {
            if slots.isEmpty {
                Section {
                    Text("还没有读到桌面上的小组件。")
                        .font(.body.weight(.medium))
                    Text("把一个「直接启动」小组件放到桌面上、让它画一次，它上面的 App 就会出现在这里。App 读不到桌面配置——这些是小组件自己报回来的。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("桌面上的 App")
                } footer: {
                    Text("等不及的话，用下面的「手动指定」直接输入格子上显示的名字。")
                }
            } else {
                Section {
                    ForEach(slots) { slot in
                        NavigationLink {
                            IconPickView(name: slot.name)
                        } label: {
                            SlotRow(slot: slot)
                        }
                    }
                } header: {
                    Text("桌面上的 App")
                } footer: {
                    Text("这些是你在小组件里挑的 App。图标认错时点进去，换成正确的那个。")
                }
            }

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
        .navigationTitle("修正图标")
        .navigationBarTitleDisplayMode(.inline)
        .task { slots = DirectLaunchOverrides.observedSlots }
    }
}

/// One row: the icon the widget is currently drawing, its name, and whether that
/// icon was the user's choice or a guess.
private struct SlotRow: View {
    let slot: DirectLaunchOverrides.SlotRecord

    private var isPinned: Bool { DirectLaunchOverrides.hasOverride(name: slot.name) }

    /// A short, honest description of where the icon came from.
    ///
    /// The distinction that matters to the user is "I chose this" versus "it was
    /// worked out", so that is what the row says — not the names of the internal
    /// rules.
    private var detail: String {
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
            SlotIcon(appStoreID: slot.appStoreID)

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
    let appStoreID: Int?

    var body: some View {
        Group {
            if let appStoreID,
               let data = DirectLaunchIcons.cachedIcon(appStoreID: appStoreID),
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                // The widget's own placeholder: a rounded rectangle with a
                // dashed outline, so an unresolved slot reads the same in both
                // places. See `DirectLaunchArtwork` in the widget target.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "app.dashed")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 30, height: 30)
    }
}

/// Picks the correct app for one slot name.
///
/// Search, look, choose. The result rows carry the seller name on purpose: it is
/// the only field that distinguishes eight apps all called "Authenticator", and it
/// is precisely the information the automatic matcher could not weigh.
struct IconPickView: View {
    let name: String

    @State private var query = ""
    @State private var results: [AppStoreLookup] = []
    @State private var isSearching = false
    /// Distinguishes "the search found nothing" from "the search could not run".
    /// The two need different words, and conflating them is the bug the store
    /// client already fixed once — see the commit about non-200 responses.
    @State private var failed = false
    @State private var didSearch = false
    /// Whether the answer could not be recorded, which is not the same as "the
    /// search failed" and must not dismiss the sheet as though it had worked.
    ///
    /// ``DirectLaunchOverrides/set(appStoreID:name:)`` refuses when the shared
    /// domain is unreachable, precisely so a choice cannot be written somewhere
    /// only this screen can see. The screen then has to *say* so: quietly closing
    /// would leave the user believing they had fixed an icon that is still wrong,
    /// which is the failure this whole view exists to let them escape.
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss

    private var currentID: Int? { DirectLaunchOverrides.appStoreID(name: name) }

    var body: some View {
        List {
            Section {
                LabeledContent("格子上的名字") {
                    Text(name).font(.body.weight(.medium))
                }
            } footer: {
                Text("按 App Store 里搜到的选。同名 App 会有多个，看开发者那一行区分。")
            }

            Section {
                HStack(spacing: 8) {
                    TextField("搜索 App Store", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await search() } }
                    Button("搜索") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }

                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("搜索中…").foregroundStyle(.secondary)
                    }
                } else if failed {
                    Text("连不上 App Store，检查网络后再试。")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if didSearch && results.isEmpty {
                    Text("没搜到。换个关键词试试，比如用英文名。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                ForEach(results, id: \.id) { app in
                    Button {
                        choose(app)
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

                            if app.trackID == currentID {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("选择正确的 App")
            }

            if currentID != nil {
                Section {
                    Button("恢复自动匹配", role: .destructive) {
                        restore()
                    }
                } footer: {
                    Text("恢复后由 AppFolder 按名字自动找，可能又会认错。")
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        // The refusal has exactly one cause worth naming to a user: the App Group
        // is not reachable from here, so nothing this screen writes can be seen by
        // the widget. Naming the cause beats "失败" — it tells them the install is
        // the thing to look at, not the app they picked.
        .alert("没能记下这个选择", isPresented: $saveFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("AppFolder 和小组件之间的共享空间现在读不到，改了也传不过去。重新安装 AppFolder 后可以再试——这次的选择没有生效。")
        }
        .task {
            // Prefill with the name itself: the store's own search for a display
            // name is the best starting point, and it is exactly what the
            // automatic matcher ran.
            query = name
            await search()
        }
    }

    /// Pins this slot name to an app, and makes the change visible.
    ///
    /// The order matters. The artwork is fetched **before** the reload, because the
    /// widget never does network at draw time — reloading first would render the
    /// new id with no icon on disk and flash a placeholder until a later timeline.
    private func choose(_ app: AppStoreLookup) {
        // A refusal is "could not record", not "nothing to do": the sheet stays
        // open and says so, rather than dismissing over a change that did not
        // happen.
        guard DirectLaunchOverrides.set(appStoreID: app.trackID, name: name) else {
            saveFailed = true
            return
        }
        DirectLaunchIcons.diagnose("app override name=«\(name)» id=\(app.trackID)")
        Task {
            _ = await DirectLaunchIcons.ensureIcon(appStoreID: app.trackID)
            WidgetCenter.shared.reloadAllTimelines()
        }
        dismiss()
    }

    private func restore() {
        guard DirectLaunchOverrides.set(appStoreID: nil, name: name) else {
            saveFailed = true
            return
        }
        DirectLaunchIcons.diagnose("app override cleared name=«\(name)»")
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isSearching = true
        defer { isSearching = false; didSearch = true }

        // The device's own storefront first, then `cn`, matching the sweep the
        // widget's automatic matcher performs — so what the user sees here is what
        // they would have got automatically.
        //
        // ## Why `failed` is set on one path and cleared on another
        //
        // `failed` means *unreachable*, and "the store has no such app" is not that:
        // the view renders the empty case on its own, from `didSearch &&
        // results.isEmpty`, with a different message. Telling a user to reword a
        // search that never left the device is the worse of the two errors.
        //
        // A second `cn` request is only worth making when the *first* storefront
        // answered and had nothing. If it was unreachable, `cn` is almost certainly
        // unreachable for the same reason, and spending a second timeout to conclude
        // otherwise is a wait the user feels and learns nothing from.
        var unreachable = false
        for country in [nil, "cn"] as [String?] {
            guard let url = AppStoreLookup.searchURL(term: term, country: country, limit: 15) else {
                continue
            }
            guard let payload = await DirectLaunchIcons.storeData(url: url) else {
                unreachable = true
                break
            }
            let rows = AppStoreLookup.parse(payload)
            if !rows.isEmpty {
                results = rows
                // Cleared *here*, and this is the bug: `failed` used to be set by a
                // first-storefront failure and never reset, so a search that then
                // succeeded on the fallback drew its results underneath a
                // 「连不上 App Store」 line — the two contradicting each other on
                // screen, both of them ours.
                failed = false
                return
            }
        }
        failed = unreachable
        results = []
    }
}