import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

/// The widget whose tiles open another app in one tap, with no hop.
///
/// ## What it does that ``AppFolderWidget`` cannot
///
/// A tile in ``AppFolderWidget`` reaches its target through a URL scheme and a
/// visible bounce through AppFolder, or through a universal link the target may
/// not publish. This one reaches it through `RunSystemShortcutIntent`, which the
/// *system* resolves: the target is chosen by the user when they configure the
/// widget, so it can be any installed app at all — including one with no scheme
/// and no universal link. Nothing flashes in between; see
/// ``QuickLaunchIntent`` for the API and why it works.
///
/// ## Why it is a separate widget and not a mode of the other
///
/// Because it is the only arrangement the platform permits. A `SystemShortcut`
/// is opaque and has no public initializer, so it cannot be written into
/// `library.json` and cannot be assembled by AppFolder's own folder editor — the
/// slots exist only as parameters of *this* widget's configuration, set by the
/// user in the Edit Widget sheet. A folder's grid, by contrast, is built in the
/// app and saved. The two are different data sources, and trying to make one
/// drive the other is fighting the API rather than using it.
///
/// ## The icon, and where it comes from
///
/// The system gives back a display *name* and nothing else — no icon, no bundle
/// id. So each name is resolved to an App Store id (``AppCatalog/match(name:)``)
/// and its artwork downloaded into the App Group by ``DirectLaunchIcons``, where
/// the render below can read it synchronously. The name is resolved at timeline
/// time and never at draw time: a widget's body cannot wait on the network.
///
/// ## The extra slot, and why it is a door
///
/// A grid of nine draws eight apps and one door; a 四宫格 in the small widget
/// draws three and a door. That is not five missing apps — it is
/// ``FolderGrid/capacity(for:)``, which is one less than the cell count *always*,
/// whether or not anything has overflowed, so that adding a ninth app to an
/// eight-app grid rearranges nothing. Tapping the door opens the panel in place,
/// with no app launched, exactly as ``AppFolderWidget`` does — this widget reuses
/// that machinery rather than reimplementing it. See ``DirectLaunchPanelView``
/// for what is shared and what could not be.
struct DirectLaunchWidget: Widget {
    /// Every shape the direct-launch widget is offered in.
    ///
    /// ## Why the larger sizes came back
    ///
    /// They were removed when the *collapsed* grid was the whole product: measured,
    /// a nine-slot medium grid came out with **11.4 pt icons** at the default size
    /// setting — unreadable and too small to hit — because ``FolderGridMetrics``
    /// takes its margin as a share of the widget's *width*, and 349 × 166 spends
    /// more of its height on margin than a square does, leaving three rows in what
    /// is left. Not offering the shape removed the cause.
    ///
    /// What changed is what the extra area is *for*. The panel is the reason to be
    /// large: it lays every configured app out at a fixed cell count
    /// (``panelGrid``), so the icons are the same size in a large widget as in a
    /// small one and the extra width buys **more apps per page** instead of bigger
    /// ones. The collapsed grid still fills whatever shape it is given, and a
    /// medium collapsed grid is still a cramped one — that trade is knowingly
    /// accepted here, and this is the place to revisit it if a real Home Screen
    /// says otherwise.
    ///
    /// `systemExtraLarge` is excluded rather than forgotten: it is an iPad-only
    /// family, and this app is iPhone-only (`UISupportedInterfaceOrientations`,
    /// portrait, iPhone). `systemExtraLargePortrait` is the iOS 27 square-ish
    /// family and *is* offered — it is the biggest panel available on a phone.
    ///
    /// Widgets already placed at the old sizes keep working; the system does not
    /// evict them, and there is no API to enumerate what is already there.
    private static var families: [WidgetFamily] {
        if #available(iOS 27.0, *) {
            return [.systemSmall, .systemMedium, .systemLarge, .systemExtraLargePortrait]
        }
        return [.systemSmall, .systemMedium, .systemLarge]
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppFolderShared.directLaunchWidgetKind,
            intent: QuickLaunchIntent.self,
            provider: DirectLaunchProvider()
        ) { entry in
            DirectLaunchView(entry: entry)
        }
        .configurationDisplayName("直接启动")
        .description("每个格子一个 App，点一下直接打开，不经过 AppFolder。")
        // Every family that has a shape this layout was built for.
        //
        // The two wider ones were withheld once, and the reason was real: with the
        // margin and the gap taken as shares of the widget's *width*, a 349 × 166
        // medium spent 37 pt of its 166 pt height on margin and ran out of room for
        // three rows — measured, a nine-slot grid came out with **11.4 pt icons**.
        // The clamp in ``FolderGridMetrics/legibleMarginShare`` is what made them
        // offerable, and it was checked at all three icon-size settings rather than
        // only at 大, which is where the first fix had left 中 at 22.7 pt.
        //
        // Legible was not the same as *proportioned*, though, and it took drawing
        // the frames to notice: three columns of a height-sized cell came to 94 pt
        // of a 349 pt width — 27%, with 127 pt of empty plate on each side. Medium
        // is now 5 × 2 and large 4 × 4 (``FolderGrid/columns(for:)``), which measure
        // 227 pt and 232 pt wide and give 41 pt and 48.5 pt icons instead of 28 and
        // 68. Large also showed *fewer* apps than medium until it changed, which is
        // the wrong way round for a launcher.
        //
        // Widgets placed on a Home Screen at the old sizes keep working — the system
        // does not evict them — but no new one can be added at them. There is no API
        // to enumerate what is already there, so that is the whole of the handling.
        .supportedFamilies(Self.families)
        // The grid insets itself (``FolderGridMetrics/margin``), so the system's
        // own 18 pt content margin would be a second inset on top of it — the
        // icons would sit in a grid noticeably smaller than the widget and than
        // the folder widget beside it. Same call, same reason as ``AppFolderWidget``.
        .contentMarginsDisabled()
        // Same reason as ``AppFolderWidget``: this layout is not built around a
        // plate the system supplies, so the system is free to drop it where one is
        // not wanted.
        .containerBackgroundRemovable(true)
        // Asks the host for the system's Liquid Glass plate, exactly as
        // ``AppFolderWidget`` does. Without this the widget gets the ordinary flat
        // background and the two widgets do not match on the same Home Screen.
        //
        // Glass is not drawn here and cannot be: it is a grant from the system, and
        // this call is the request. It compiles only because
        // `Scripts/widgetkit-overlay.sh` publishes the declaration ahead of this
        // target's Swift compile — see that script for why an ordinary `import
        // WidgetKit` cannot see it.
        .preferredBackgroundStyle(.blur)
    }
}

/// One configured slot, resolved to something drawable.
///
/// A `SystemShortcut` cannot be stored or compared by anything but the system, so
/// the entry carries this beside it rather than trying to persist the shortcut
/// itself.
struct DirectLaunchSlot: Identifiable {
    /// Stable per position: the shortcut has no id of its own and its name is not
    /// unique, so the slot's place in the grid is its identity.
    let id: Int
    let name: String
    let appStoreID: Int?
    let symbolName: String?
}

struct DirectLaunchEntry: TimelineEntry {
    let date: Date
    /// The resolved slots, in the order the user configured them.
    let slots: [DirectLaunchSlot]
    /// The shortcuts themselves, which only the buttons may touch.
    ///
    /// Kept as a parallel array to ``slots`` and indexed identically — the system
    /// value cannot ride inside ``DirectLaunchSlot``, which has to be `Equatable`
    /// and carry the resolved artwork information.
    let shortcuts: [SystemShortcut]
    let style: FolderStyle
    /// How many slots the user configured, before the grid truncated them.
    ///
    /// Carried rather than read off ``slots``, because the door is drawn when
    /// the configuration holds more than the grid shows and by the time the view
    /// runs the list has already been cut to the capacity — asking it whether
    /// anything overflowed would always answer no.
    let totalSlots: Int
    /// Whether *this* widget is the one whose grid the user opened.
    ///
    /// Resolved here against the grid's own key rather than read as a bare flag,
    /// so the shared state — one key for the whole device — cannot expand a
    /// different widget's grid. See ``WidgetState/directLaunchKey``.
    let isExpanded: Bool
    /// Which page of the expanded grid to draw. Meaningless unless
    /// ``isExpanded``; clamped to the group's real length at draw time.
    let expandedPage: Int
    /// The digest the expansion is keyed on, so the door and the back cell can
    /// both carry it without either of them reading the slots to work it out.
    let expansionKey: String

    /// The slots the door is hiding — the ones its miniature grid previews, and the
/// ones the panel lays out when the door is tapped.
    ///
    /// Two readers now, both making the same promise: the door's miniature grid says
    /// *these* are what is behind it, and the panel draws exactly this list rather
    /// than the whole configuration. Nothing on the Home Screen is repeated.
    ///
    /// Kept as its own accessor rather than a slice at each call site because the
    /// two lists must not be confused: this one starts after the capacity, and a
    /// list that wrongly started at zero would put the apps already visible on the
    /// door's own preview — and, in the panel, fill the first page with what the
    /// user could already see.
    var hiddenSlots: [DirectLaunchSlot] {
        guard slots.count > capacity else { return [] }
        return Array(slots.dropFirst(capacity))
    }

    /// How many apps this grid shows directly — the number the door is drawn
    /// after.
    ///
    /// Defaulted to a large number rather than required, so the placeholder and
    /// any test that only cares about the slots do not have to invent a family.
    /// ``DirectLaunchProvider`` always supplies the real one.
    var capacity: Int = .max

    /// A token that moves whenever the user's icon overrides change.
    ///
    /// Present for one reason: to make a requested reload provably produce a
    /// *different* entry. WidgetKit may serve a byte-identical entry from its
    /// cache, so "call `reloadAllTimelines()` after editing" can silently show no
    /// change at all — and the user, having just fixed an icon and seen nothing
    /// happen, would conclude the fix did not work. This field is what differs.
    ///
    /// Defaulted so the placeholder and tests need not supply it.
    var iconRevision: String = ""
}

struct DirectLaunchProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DirectLaunchEntry {
        let slots = [
            DirectLaunchSlot(id: 0, name: "微信", appStoreID: 414478124, symbolName: nil),
            DirectLaunchSlot(id: 1, name: "相机", appStoreID: nil, symbolName: "camera.fill"),
        ]
        return DirectLaunchEntry(
            date: .now,
            slots: slots,
            // The placeholder has no real shortcuts and no buttons are built from
            // it — ``DirectLaunchView`` draws the sample as plain faces.
            shortcuts: [],
            style: FolderStyle(),
            totalSlots: slots.count,
            isExpanded: false,
            expandedPage: 0,
            expansionKey: ""
        )
    }

    func snapshot(for configuration: QuickLaunchIntent, in context: Context) async -> DirectLaunchEntry {
        await entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: QuickLaunchIntent, in context: Context) async -> Timeline<DirectLaunchEntry> {
        // `never`: the slots only change when the user edits the widget, which
        // WidgetKit reloads on its own, and the entries carry no time-varying
        // content. A refresh policy here would spend widget budget re-reading a
        // configuration that cannot have changed.
        Timeline(entries: [await entry(for: configuration, family: context.family)], policy: .never)
    }

    private func entry(for configuration: QuickLaunchIntent, family: WidgetFamily) async -> DirectLaunchEntry {
        // The app asks for any expansion to be dropped when it comes to the
        // foreground, and it says so through the shared defaults — see
        // ``WidgetState/requestCollapse()`` for why the request is a counter and
        // why it moved out of the library file. Applied before the entry is built
        // so the frame this very reload draws is already collapsed, with no second
        // beat.
        //
        // This used to live in the folder widget's provider and moved here when
        // that widget was deleted: it is the only timeline provider left, so if it
        // does not apply the request, nothing does.
        WidgetState.applyCollapseRequest(WidgetState.collapseRequest)

        let shortcuts = configuration.slots
        let grid = configuration.style.grid
        let capacity = grid.capacity(for: family)

        // The key is computed from the names the *system* gave, in configuration
        // order, and the same names are visible to the render — which is what lets
        // the door's tap and this provider agree without either storing the
        // shortcut. Taken from every configured slot rather than the truncated
        // list, so removing an app does not leave the key describing a grid that
        // no longer exists.
        let names = shortcuts.map { String(localized: $0.displayRepresentation.title) }
        let key = WidgetState.directLaunchExpansionKey(slotNames: names)

        // Only a grid that has a door can be opened, and the test for that is the
        // same ``FolderGrid/nestedCell(for:tileCount:)`` the collapsed grid uses
        // to decide the last cell *is* a door. A grid that fits has nothing to
        // expand, and expanding it anyway would draw a lone 返回 cell where the
        // user's apps used to be.
        let hasOverflow = grid.nestedCell(for: family, tileCount: names.count) != nil
        let isExpanded = hasOverflow && WidgetState.directLaunchKey == key

        // One instant for the whole build: it stamps the observed-slot records and
        // the entry together, so a single timeline is internally consistent.
        let now = Date()

        // The whole build runs inside a network budget. The provider is the only
        // caller that knows where a build starts and ends, which is why the budget
        // is opened here and not inside the resolver — see ``DirectLaunchIcons/Budget``
        // for what it buys. It is a `@TaskLocal`, so this build carries its own and
        // neither touches nor is touched by another build running at the same time.
        return await DirectLaunchIcons.withBudget {

            var slots: [DirectLaunchSlot] = []
            var observed: [DirectLaunchOverrides.SlotRecord] = []
            for (index, shortcut) in shortcuts.enumerated() {
                let name = String(localized: shortcut.displayRepresentation.title)

                // Resolved here, not at draw time: a widget's body cannot wait on the
                // network, so everything a slot needs must already be on disk by the
                // time the view runs.
                //
                // The "already gave up on this name" check used to be a branch right
                // here, in front of this call. It moved *inside* ``resolve(name:)``
                // because it was shadowing the user's own answer: a name the store once
                // failed to resolve was skipped before the override map was ever
                // consulted, so pinning such a name did nothing. Precedence belongs in
                // one place, and that place is the resolver.
                let resolved = await DirectLaunchIcons.resolve(name: name)
                // Whether the bytes are on disk, read as **data** — not decoded into a
                // `UIImage`. This used to call the icon cache, which decodes; the decode
                // was kept only to answer this one log field, and it ran for every
                // configured slot (up to 100), each retained in a process-wide cache with
                // no eviction. The slot the view actually draws still decodes lazily, so
                // scoping the decode to what is drawn costs nothing on screen. `cachedIcon`
                // reads the same file without the decode, so the log stays truthful.
                let iconOnDisk = resolved.appStoreID.map { id in
                    DirectLaunchIcons.cachedIcon(appStoreID: id) != nil
                } ?? false
                DirectLaunchIcons.diagnose(
                    "slot \(index) name=«\(name)» id=\(resolved.appStoreID.map(String.init) ?? "nil") "
                    + "symbol=\(resolved.symbolName ?? "nil") source=\(resolved.source.rawValue) "
                    + "iconOnDisk=\(iconOnDisk)"
                )
                slots.append(
                    DirectLaunchSlot(
                        id: index,
                        name: resolved.name,
                        appStoreID: resolved.appStoreID,
                        symbolName: resolved.symbolName
                    )
                )
                observed.append(
                    DirectLaunchOverrides.SlotRecord(
                        name: resolved.name,
                        appStoreID: resolved.appStoreID,
                        source: resolved.source.rawValue,
                        // One timestamp for the whole build, so the records of a single
                        // timeline tie rather than ordering against each other by the
                        // microseconds between iterations.
                        updatedAt: now
                    )
                )
            }
            DirectLaunchIcons.diagnose(
                "-- timeline done, \(slots.count) slot(s), capacity \(capacity), expanded \(isExpanded) --"
            )

            // Tell the app which slots are on a widget. It cannot find out any other
            // way — the configuration lives in the system, and the app can neither read
            // it nor enumerate the Home Screen — so this is what fills the "修正图标"
            // screen. Merged, not replaced: there can be more than one widget, and this
            // build only knows its own. See ``DirectLaunchOverrides/noteObservedSlots(_:)``.
            DirectLaunchOverrides.noteObservedSlots(observed)

            return DirectLaunchEntry(
                date: .now,
                slots: slots,
                shortcuts: shortcuts,
                style: configuration.style,
                totalSlots: slots.count,
                isExpanded: isExpanded,
                expandedPage: WidgetState.expandedPage,
                expansionKey: key,
                capacity: capacity,
                iconRevision: DirectLaunchOverrides.revision
            )
        }
    }
}

private struct DirectLaunchView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DirectLaunchEntry

    /// Whether the slots are the sample from ``placeholder(in:)`` rather than a
    /// real configuration — sample faces are drawn with no button, because there
    /// is no shortcut behind them to run.
    private var isSample: Bool { entry.shortcuts.isEmpty }

    var body: some View {
        Group {
            if entry.isExpanded {
                // Opened by tapping the door — see ``ToggleDirectLaunchIntent``.
                // Drawn from the same rectangle, so this is a redraw rather than a
                // presentation; nothing left the Home Screen to get here.
                DirectLaunchPanelView(entry: entry, family: family)
            } else {
                collapsed
            }
        }
    }

    private var collapsed: some View {
        // A grid that has overflowed draws one cell more than it has slots, and
        // that cell is the door. Sizing from the slot count instead would make the
        // icons grow the moment a ninth app was configured, which is the opposite
        // of what the door is for — the same rule, and the same reason, as
        // ``FolderGrid``.
        let hasDoor = entry.totalSlots > entry.capacity

        return GeometryReader { proxy in
            let metrics = FolderGridMetrics(
                tileCount: hasDoor ? entry.capacity + 1 : max(entry.slots.count, 1),
                columns: columns,
                in: proxy.size,
                showsTitles: entry.style.showsTitles,
                iconScale: entry.style.iconScale
            )

            ZStack {
                // The widget's whole surface opens AppFolder by default, and the
                // gaps in a short grid must not be taps that launch it — see
                // ``TapShield``. Collapsed, a blank tap still does nothing.
                //
                // Hoisted to the outermost frame in both states rather than left as
                // the grid's `.background`, so its area is the widget rectangle
                // instead of whatever the grid's own frame and the background's
                // overflow happen to produce. The panel depends on that area being
                // complete (it is the exit), and the two states should not disagree
                // about where the surface ends.
                TapShield(intent: InertTapIntent(cell: 0))
                    .frame(width: proxy.size.width, height: proxy.size.height)

                Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                    ForEach(0..<metrics.rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<metrics.columns, id: \.self) { column in
                                let index = row * metrics.columns + column
                                if hasDoor, index == entry.capacity {
                                    directLaunchDoor(metrics: metrics)
                                        .frame(width: metrics.iconSide, height: metrics.cellHeight)
                                } else if entry.slots.indices.contains(index) {
                                    slot(at: index, metrics: metrics)
                                        .frame(width: metrics.iconSide, height: metrics.cellHeight)
                                } else {
                                    // Empty cells exist only so the icons left-align
                                    // rather than centring. They need no tap handling
                                    // of their own — the shield behind the grid covers
                                    // them and the regions the grid cannot reach.
                                    Color.clear
                                        .frame(width: metrics.iconSide, height: metrics.cellHeight)
                                }
                            }
                        }
                    }
                }
                .padding(metrics.margin)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        // The plate, drawn in the **content layer** and above the glass. Same call,
        // same layer, same reason as ``AppFolderWidget``: 自动 paints nothing and
        // the system's plate shows through, while 纯色 and 渐变 cover it and are
        // therefore exactly the colour asked for.
        .background {
            if let fill = entry.style.plateFill {
                Rectangle().fill(fill)
            }
        }
        // Required on iOS 17+: without it the system refuses to lay the widget out
        // and shows "Please adopt containerBackground API" in its place. `clear`
        // because this widget paints no plate of its own — the system's is the one
        // that should show through, which is also what makes the tiles react to the
        // user's 图标外观 setting.
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func slot(at index: Int, metrics: FolderGridMetrics) -> some View {
        let slot = entry.slots[index]
        let face = DirectLaunchFace(slot: slot, style: entry.style, metrics: metrics)
            // The whole cell is the target, not just the artwork. With no button
            // style set, the tap area follows the drawn content, and a slot whose
            // icon has not resolved draws a mostly-empty rounded rect — the user
            // would be aiming at a face whose only solid part is a few points tall.
            .contentShape(Rectangle())

        if isSample {
            face
        } else {
            // The whole reason this widget exists: the system opens the target, so
            // there is no URL for us to know and nothing to bounce through.
            //
            // Deliberately no `.buttonStyle(.plain)` here in the sense of relying
            // on the default: the probe that established this API works on-device
            // had none, and adding one is the only thing this button does that the
            // probe's did not. Restored below is the plain style — removing it was
            // a wrong guess that exposed the system's default button chrome (a blue
            // circle) and did not cause the tap failure, which was a stale widget
            // configuration bound to the intent's old type identity.
            Button(intent: RunSystemShortcutIntent(shortcut: entry.shortcuts[index])) {
                face
            }
            .buttonStyle(.plain)
        }
    }

    /// The last cell of a grid that holds more than it can draw: a small grid of
    /// what is behind it, and a tap that **expands the group in place**.
    ///
    /// Everything about the cell that is not its content is shared with the app
    /// editor's preview of the same thing — ``MiniGridDensity`` for the miniatures
    /// and ``FolderGridMetrics`` for the geometry — so the block and the 其他 label
    /// are drawn from the same numbers in both places rather than written twice and
    /// kept in step by hand.
    ///
    /// The folder widget used to draw this cell too, from `FolderTile`s carrying a
    /// cached `UIImage`. It has been removed; what is left is the app's preview and
    /// this, which read `DirectLaunchSlot`s carrying an App Store id, because the
    /// system gives a slot no artwork.
    ///
    /// ## Why this is a `Button(intent:)` and not a `Link`
    ///
    /// The tap runs ``ToggleDirectLaunchIntent`` in the widget's own process, so the
    /// group opens **in place** with no app launched and nothing leaving the Home
    /// Screen. Its key is the digest the entry already computed, so the door does
    /// not have to read the slots to work out what it is opening. A later build
    /// routed this through a `Link` into the app to draw a full-screen library; that
    /// is gone, and the in-place expansion is the whole of the door's job again.
    ///
    /// The rest of the grid is untouched: its cells are `Button(intent:)` tiles that
    /// open their target with no hop, the same way this one toggles with none.
    @ViewBuilder
    private func directLaunchDoor(metrics: FolderGridMetrics) -> some View {
        Button(intent: ToggleDirectLaunchIntent(key: entry.expansionKey)) {
            DirectLaunchDoorLabel(
                hidden: entry.hiddenSlots,
                style: entry.style,
                metrics: metrics
            )
        }
        // `.plain` so the label is not tinted like a button, and `contentShape` so
        // the whole cell — not just the drawn block — is the target, matching how
        // the app tiles size their hit area.
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// The shape ``FolderGrid/columns(for:)`` gives a grid of this size, and for the
    /// same reason: the icons here are meant to be full size, and a wider grid than
    /// the widget needs only shrinks them.
    ///
    /// The choice of 四宫格 over 九宫格 reaches the small widget only — that is the
    /// folder's rule too, and reading it from the same type is what keeps the two
    /// widgets identical rather than merely similar.
    private var columns: Int { entry.style.grid.columns(for: family) }
}

/// The panel: what the door was hiding, and a way forward when that is more than
/// one page holds.
///
/// ## What makes this a panel and not another page of the grid
///
/// Tapping the door swaps the grid's *contents*: same cells, same rectangle, but
/// drawn as a different surface — no plate of its own, so the **system's** glass
/// shows through, and full-size faces where the door had been a miniature of them.
/// See ``FolderStyle/usingSystemPlate`` for why the plate has to be dropped as a
/// whole style rather than merely skipped, and for what that costs the 纯色/渐变
/// setting.
///
/// The glass is the whole of the effect, and it is not painted here. A widget
/// cannot paint its own — measured, `.ultraThinMaterial` and `.glassEffect` both
/// come back flat — so the panel's glass is the widget's glass, and the only way to
/// keep it is to draw nothing over it.
///
/// ## What it draws: the hidden apps, not the whole configuration
///
/// The apps the collapsed grid already draws are on the Home Screen behind this
/// widget. Drawing them again filled the first page with what the user could
/// already see — on a small widget, the *identical* eight faces plus a 更多 — so a
/// tap on the door changed one cell and the apps the door was holding needed a
/// second tap to reach. That is the bug this shape fixes: the panel lays out
/// ``DirectLaunchEntry/hiddenSlots``, so its first page **is** what the door
/// promised.
///
/// ## Why there is a 返回 cell again
///
/// With only the overflow drawn, a list that fits can be short. A 返回 cell in
/// cell 0 gives a short expansion an exit that is always in the same place, rather
/// than relying on the user to find the blank space. The cost is one cell off each
/// page — nine-slot grid, eight per page — which is exactly how a system folder
/// reads.
///
/// ## Where the paging comes from
///
/// The arithmetic is ``FolderExpansionLayout`` — that type is pure and takes only a
/// family, a grid and a count. "No app is lost and none is drawn twice" is a
/// property of the layout rather than of any one widget, so it is read from there
/// instead of reimplemented, and there is only one copy to get wrong. The panel
/// uses the type's default of reserving the way back, and its shape is the one
/// resolved from the room the widget was given rather than the user's 九宫格
/// setting.
///
/// The app cell is the part that cannot be shared: a slot carries a
/// `SystemShortcut` and opens through ``RunSystemShortcutIntent``, with no URL
/// involved at all.
struct DirectLaunchPanelView: View {
    let entry: DirectLaunchEntry
    let family: WidgetFamily

    /// The shape the panel lays out, fitted to the room it was actually given.
    ///
    /// ## Why this is measured rather than tabulated per family
    ///
    /// The same reason the collapsed grid's table is a table and not a guess: a
    /// hand-written "three rows for Medium" is what shipped **11.4 pt icons** on a
    /// medium widget, because a widget's margin is a share of its *width* and a
    /// short wide rectangle spends more of its height on margin than a square does.
    /// A second hand-written table would be a second chance to make that mistake,
    /// and the panel is the case where the mistake would cost the most — its whole
    /// reason to exist at Large is that the icons there are not cramped.
    ///
    /// So the panel asks the geometry what it can afford: keep the cell size the
    /// collapsed small grid already draws, and take as many whole rows and columns
    /// as the rectangle allows. ``FolderGridMetrics/cell(in:columns:rows:)`` answers
    /// that question for a candidate shape, and the candidates are tried densest
    /// first so a wide widget gets columns before rows.
    ///
    /// ## Why this is not the user's 九宫格/四宫格 setting
    ///
    /// That setting is about the *collapsed* grid: how many apps sit on the Home
    /// Screen before a door appears. The panel is a different surface with a
    /// different job — show as much of the configuration as fits — and reusing the
    /// setting would make a 四宫格 folder's panel four cells with a vast empty
    /// rectangle under it.
    ///
    /// A small widget resolves to 3 × 3, the shape it already drew, so nothing about
    /// the small panel is new — the same cells, now holding the overflow instead of
    /// the eight apps already on the Home Screen.
    private func panelGrid(in size: CGSize) -> (columns: Int, rows: Int) {
        // The size the collapsed small grid draws at the default setting, which the
        // tests pin at about 37 pt. The panel holds itself to that so a bigger
        // widget buys apps rather than bigger icons.
        let target: CGFloat = 37
        let gapShare = FolderGridMetrics.standardGapShare
        let marginShare = FolderGridMetrics.standardMarginShare

        // Dense enough to hit the target, and — separately — the best on offer when
        // none does. Falling back to a hardcoded shape would be falling back to the
        // wrong one: the small widget is *narrower than the target allows on some
        // devices* (a non-Max iPhone's ~158 pt slot puts a 3 × 3 at ~34 pt), and a
        // `1 × 1` seed would collapse the panel to a single cell where the collapsed
        // grid the user just tapped draws nine. So the panel falls back to the
        // shape the collapsed grid draws — a square that fills the room — rather
        // than to a corner of it.
        var best: (columns: Int, rows: Int)?
        var fill = (columns: 3, rows: 3)

        for columns in 2...8 {
            for rows in 1...8 {
                let cell = FolderGridMetrics.cell(
                    in: size, columns: columns, rows: rows,
                    gapShare: gapShare, marginShare: marginShare
                )
                guard cell > 0 else { continue }
                let area = columns * rows
                if cell >= target, area > (best.map { $0.columns * $0.rows } ?? 0) {
                    best = (columns, rows)
                }
                // The densest shape whose *cells* clear the panel's own margin, so
                // the fallback fills the rectangle instead of shrinking into it.
                if cell >= Self.fallbackCellFloor, area > fill.columns * fill.rows {
                    fill = (columns, rows)
                }
            }
        }
        return best ?? fill
    }

    /// The smallest a cell may be and still count as a usable panel cell when no
    /// shape reaches ``target`` — about 22 pt, the point below which an icon is no
    /// longer comfortably tappable. Small widgets on every device clear it; it
    /// exists so a pathological size still resolves to *something* rather than to
    /// the `3 × 3` default.
    private static let fallbackCellFloor: CGFloat = 22

    /// The apps the door was hiding, laid out over the whole widget and paged, with
    /// cell 0 reserved for the way back.
    ///
    /// ## Cells come from the shape, apps page; the panel does not grow
    ///
    /// The shape is `columns × rows`, resolved from the room the widget has. That is
    /// the cell count, whatever the overflow is: nine apps behind the door on a
    /// nine-cell panel put eight on the first page and one on the second, exactly as a
    /// system folder does. Growing the grid to fit the apps instead would add a
    /// fourth row to a 3 × 3 the moment the ninth app arrived.
    ///
    /// The count is floored at two — not at the shape — for the one case the shape
    /// cannot cover: ``panelGrid(in:)`` answers `1 × 1` while it still has no room to
    /// measure, and with a single cell the way back would fill the panel and no app
    /// could ever be drawn.
    private func layout(in size: CGSize) -> FolderExpansionLayout {
        let shape = panelGrid(in: size)
        return FolderExpansionLayout(
            family: family,
            columns: shape.columns,
            cellCount: max(shape.columns * shape.rows, 2),
            appCount: panelSlots.count,
            reservesBackCell: true
        )
    }

    /// The apps the panel draws, in configuration order: what the door hid. Its
    /// tile indices address this array directly; see ``shortcutIndex(_:)`` for the
    /// last step.
    private var panelSlots: [DirectLaunchSlot] { entry.hiddenSlots }

    /// What the panel draws with: the entry's style, on the system's plate.
    ///
    /// Read once rather than at each use, so the plate the faces are drawn *for* and
    /// the plate actually painted cannot come apart.
    private var style: FolderStyle { entry.style.usingSystemPlate }

    /// The configuration index a panel index runs.
    ///
    /// Taken from the slot's own ``DirectLaunchSlot/id`` rather than computed from
    /// its position. That id *is* the configuration index — the provider sets it
    /// from the loop index — so it is right whether the panel draws the whole list or
    /// a sub-list of it, where a `capacity + index` offset would be right for exactly
    /// one of those and would silently run a neighbouring app's shortcut for the
    /// other. The panel draws the overflow now, so it is the sub-list case that
    /// matters here.
    private func shortcutIndex(_ index: Int) -> Int { panelSlots[index].id }

    var body: some View {
        GeometryReader { proxy in
            // The shape is chosen from the room the widget actually has — see
            // ``panelGrid(in:)`` — so it is resolved here, where `proxy.size` is
            // known, rather than read off a per-family table. The page is clamped
            // through the same resolved layout, since `pageSize` — and so the page
            // count — is a property of the shape rather than of the family.
            let layout = layout(in: proxy.size)
            let page = layout.clampedPage(entry.expandedPage)
            // Sized for the *cell count*, not the app count on this page, so pages
            // are pixel-identical and the icons do not resize as the user pages.
            // Sizing from the apps on the page would make a light final page draw
            // bigger icons than the full one before it, which reads as the widget
            // zooming.
            let metrics = FolderGridMetrics(
                tileCount: layout.cellCount,
                columns: layout.columns,
                in: proxy.size,
                showsTitles: style.showsTitles,
                iconScale: style.iconScale
            )

            ZStack {
                // The exit. A tap anywhere that is not an app closes the panel, so
                // the shield is the *whole* widget rather than the grid's bounds —
                // hoisted out of the grid's `.background` so its area does not
                // depend on the grid's padding and the background's overflow
                // behaviour. Behind the grid, so app cells still take their own
                // taps and the uncovered regions land here.
                TapShield(intent: CollapseDirectLaunchIntent(key: entry.expansionKey))
                    .frame(width: proxy.size.width, height: proxy.size.height)

                // What makes the panel read as a surface rather than as the grid
                // showing different apps.
                //
                // ## Why this is safe on glass, and why it is not a plate
                //
                // The content layer sits **above** the system's glass, so anything
                // drawn here covers the glass in proportion to its opacity. That is
                // what ruled out a custom plate: a solid fill erases the glass
                // (measured — a `backgroundStyle = 2` widget with a content fill
                // shows glass only where the fill misses). What was never measured
                // is a *low*-opacity fill over glass; the one semi-transparent
                // reading on record was taken before this widget had any glass at
                // all, composited onto an opaque white plate, so it says nothing
                // about this case.
                //
                // A barely-there scrim is the deliberate bet: enough to separate the
                // panel from the Home Screen behind it, not enough to grey the glass
                // out. It is a fixed neutral rather than the user's tint on purpose —
                // the panel is glass whatever appearance they picked, and tinting it
                // would break that.
                PanelSurface()

                Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                    ForEach(0..<metrics.rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<metrics.columns, id: \.self) { column in
                                let cell = row * metrics.columns + column
                                cellView(cell, layout: layout, page: page, metrics: metrics)
                            }
                        }
                    }
                }
                .padding(metrics.margin)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        // No plate, deliberately. This is the glass, and anything painted over it —
        // the user's 纯色/渐变 included — would cover the very thing the panel is
        // for. See ``FolderStyle/usingSystemPlate`` for why dropping the fill is not
        // enough on its own.
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func cellView(_ cell: Int, layout: FolderExpansionLayout, page: Int, metrics: FolderGridMetrics) -> some View {
        switch layout.role(forCell: cell, onPage: page) {
        case .back:
            // Cell 0, on every page. Closing is the door's own intent, so the same
            // key that opened this panel is the one that shuts it — see
            // ``ToggleDirectLaunchIntent``. Drawn in the panel's own style, not the
            // entry's, so a name here and a name on an app cell cannot end up needing
            // different treatments.
            DirectLaunchCellButton(
                systemImage: "chevron.backward",
                title: "返回",
                metrics: metrics,
                style: style,
                intent: ToggleDirectLaunchIntent(key: entry.expansionKey)
            )

        case .next:
            DirectLaunchCellButton(
                systemImage: "ellipsis",
                title: "更多",
                metrics: metrics,
                style: style,
                intent: AdvanceDirectLaunchPageIntent(key: entry.expansionKey, page: page)
            )

        case .app(let index):
            if panelSlots.indices.contains(index) {
                let slot = panelSlots[index]
                Button(intent: RunSystemShortcutIntent(shortcut: entry.shortcuts[shortcutIndex(index)])) {
                    DirectLaunchFace(slot: slot, style: style, metrics: metrics)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: metrics.iconSide, height: metrics.cellHeight)
            } else {
                Color.clear.frame(width: metrics.iconSide, height: metrics.cellHeight)
            }

        case .empty:
            Color.clear.frame(width: metrics.iconSide, height: metrics.cellHeight)
        }
    }
}

/// A cell that runs an intent rather than opening an app: the way back, and the
/// way forward.
///
/// Shares ``DirectLaunchFace``'s shape — a rounded tile with a symbol and an
/// optional name — because these sit in a grid of app icons and a differently
/// shaped cell would read as chrome rather than as part of the group. It carries
/// the same ``FolderStyle`` both cells draw their title colour from, so a name on
/// the back cell and a name on an app cell cannot end up needing different
/// treatments.
private struct DirectLaunchCellButton<Intent: AppIntent>: View {
    let systemImage: String
    let title: String
    let metrics: FolderGridMetrics
    let style: FolderStyle
    let intent: Intent

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: metrics.titleSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                        .fill(.fill.tertiary)
                    Image(systemName: systemImage)
                        .font(.system(size: metrics.iconSide * 0.34, weight: .semibold))
                        .foregroundStyle(style.titleStyle)
                }
                .frame(width: metrics.iconSide, height: metrics.iconSide)

                if style.showsTitles {
                    Text(title)
                        .font(.system(size: metrics.titleFontSize))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(style.titleStyle)
                        .frame(width: metrics.iconSide)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: metrics.iconSide, height: metrics.cellHeight)
    }
}

/// The faint tint and hairline that make the panel read as its own surface.
///
/// ## What it is for
///
/// Without it the panel and the collapsed grid are the same glass with a different
/// set of apps in it, and on a small widget the first page of each shows *the same
/// apps* — so a tap on the door changes one cell and nothing else, which the user
/// reads as a tap that did nothing. The fix is not to draw more; it is to make the
/// two states visibly separate surfaces.
///
/// ## Why it does not kill the glass
///
/// The content layer is above the system's glass, so a fill here covers the glass
/// in proportion to its opacity — and at 100% it erases it outright, which is the
/// measurement that ruled out a custom plate. At this opacity it only *tints* what
/// is behind it, and the hairline paints a ring and leaves the whole interior
/// alone. Both are deliberately small numbers, and the interior is deliberately
/// unpainted: the middle of the panel is the glass, untouched.
///
/// It is a fixed neutral rather than the user's tint because the panel is glass
/// whatever appearance they chose — see ``FolderStyle/usingSystemPlate``.
///
/// ## What to tune, and what would say it is wrong
///
/// ``scrimOpacity`` is the one number to move, and it is unmeasured: the only
/// semi-transparent reading on record was taken on a widget with no glass at all.
/// If the panel looks grey or flat, this is too high — the glass should still be
/// a window onto the wallpaper, only dimmed. If the panel still reads as the grid,
/// it is too low. The hairline is what keeps the "too low" case honest, since it
/// separates the surfaces without dimming anything.
private struct PanelSurface: View {
    /// How much the panel dims what is behind it.
    ///
    /// Low by design. The task is separation from a bright wallpaper, not
    /// legibility — the icons carry their own contrast — so this is set to the
    /// smallest value that still reads as a tint rather than as nothing.
    private var scrimOpacity: Double { 0.12 }

    /// In dark mode the glass is already dark, so the same scrim does nothing
    /// visible; a *light* wash separates the panel there. `primary` is the label
    /// colour, so it is black in light mode and white in dark — one value that
    /// means "the opposite of whatever is behind it".
    private var scrimColor: Color {
        Color.primary.opacity(scrimOpacity)
    }

    var body: some View {
        ZStack {
            // Full-bleed, and it needs no corner radius of its own: the system
            // clips widget content to the widget's own shape (``FolderGridMetrics/
            // widgetCornerRadius``). Adding a radius here would be a second radius
            // to keep in step with the system's.
            Rectangle()
                .fill(scrimColor)

            // The hairline shares a radius with the system's clip on purpose. A
            // line a few points inside the glass edge reads as a cheap outline
            // rather than as the panel's boundary.
            RoundedRectangle(
                cornerRadius: FolderGridMetrics.widgetCornerRadius,
                style: .continuous
            )
            .strokeBorder(
                Color.primary.opacity(0.18),
                lineWidth: 1
            )
        }
        // The surface is decoration; it must not take a tap. The shield beneath it
        // is what handles a tap in the gaps.
        .allowsHitTesting(false)
    }
}

/// The button that decides what a tap on this widget's *non-icon* surface means.
///
/// A widget's whole surface opens the containing app when tapped, and the SDK
/// publishes no hit-region API. A grid of two apps should not launch AppFolder
/// because someone tapped the space where the other seven are not.
///
/// ## Why it covers the whole widget, and why two simpler attempts failed
///
/// It started as one no-op button per *empty cell*, which did not work, for two
/// reasons that are worth keeping because both make the failure look identical
/// from the Home Screen:
///
/// 1. A transparent `Color.clear` label has no hit area, so the button was never
///    clickable and every tap went straight through. Fixed by `contentShape`.
/// 2. Even clickable, the cells were the wrong region. The `Grid` is built from
///    `metrics.rows`, and `rows` is derived from the *slot count* — so a grid of
///    two lays out one row and the rest of the widget is not part of that `Grid`
///    at all. Neither is the outer margin, nor the slack under a grid shorter than
///    its container. Taps there met no button, empty cell or not.
///
/// Covering the whole widget removes the need to reason about which regions the
/// layout happens to leave bare. It is placed behind the grid, so slots still take
/// their own taps; everything else lands here.
///
/// ## Why the intent is a parameter
///
/// Because what a blank tap should *do* depends on which surface is showing, and
/// the two answers are opposites: collapsed, nothing (launching AppFolder from a
/// gap is the bug this exists to prevent); panel, close it. Making that a parameter
/// keeps both call sites explicit rather than hiding a state test inside here.
///
/// It draws nothing on purpose: no shape, no tint, no highlight, and no accessible
/// element for what is genuinely a gap.
private struct TapShield<Intent: AppIntent>: View {
    let intent: Intent

    var body: some View {
        Button(intent: intent) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The door cell: a miniature grid of what is hidden, and a name.
private struct DirectLaunchDoorLabel: View {
    let hidden: [DirectLaunchSlot]
    let style: FolderStyle
    let metrics: FolderGridMetrics

    /// How many miniatures to draw, and how big, from the cell this is drawing in.
    ///
    /// The arithmetic lives in ``MiniGridDensity`` rather than here because the
    /// folder widget draws this same cell and cannot import this view — see that
    /// type for why the block is inset rather than filling the cell, and why the
    /// density follows the size instead of being fixed at four.
    private var density: MiniGridDensity { MiniGridDensity(cellSide: metrics.iconSide) }

    var body: some View {
        VStack(spacing: metrics.titleSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(.fill.tertiary)

                VStack(spacing: density.spacing) {
                    ForEach(0..<density.rows, id: \.self) { row in
                        HStack(spacing: density.spacing) {
                            ForEach(0..<density.columns, id: \.self) { column in
                                miniIcon(at: row * density.columns + column)
                            }
                        }
                    }
                }
            }
            .frame(width: metrics.iconSide, height: metrics.iconSide)

            if style.showsTitles {
                // 其他, matching the folder's door. The cell is a folder, not a
                // "show me more" button — 更多 is what the expansion's own next
                // cell says, and the two are different actions.
                Text("其他")
                    .font(.system(size: metrics.titleFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(style.titleStyle)
                    .frame(width: metrics.iconSide)
            }
        }
    }

    /// One miniature, or a blank if fewer apps are hidden than this density draws.
    ///
    /// A blank rather than a repeat: with three hidden and room for four, three
    /// miniatures plus an empty slot is the truth, and filling the fourth would
    /// overstate what the door opens onto.
    @ViewBuilder
    private func miniIcon(at index: Int) -> some View {
        let side = density.miniSide
        if hidden.indices.contains(index) {
            DirectLaunchArtwork(slot: hidden[index], cornerRadius: side * 0.22)
                .frame(width: side, height: side)
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }
}

/// One slot: the app's icon, and its name underneath.
private struct DirectLaunchFace: View {
    let slot: DirectLaunchSlot
    let style: FolderStyle
    let metrics: FolderGridMetrics

    var body: some View {
        VStack(spacing: metrics.titleSpacing) {
            DirectLaunchArtwork(slot: slot, cornerRadius: metrics.cornerRadius)
                .frame(width: metrics.iconSide, height: metrics.iconSide)

            // The name is shown only when the grid asks for it, it shrinks rather
            // than truncates — a name is worth reading, and 「微信」 cut to 「微…」
            // tells the user nothing — and its colour comes from
            // ``FolderStyle/titleStyle`` so it follows the plate.
            if style.showsTitles {
                Text(slot.name)
                    .font(.system(size: metrics.titleFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(style.titleStyle)
                    .frame(width: metrics.iconSide)
            }
        }
    }
}

/// A slot's artwork: the downloaded App Store icon, an SF Symbol, or a neutral
/// square.
///
/// Three steps, in order, because a slot with no image must still read as a slot
/// rather than as a hole in the grid: the downloaded artwork, an SF Symbol for an
/// app the catalogue knows but the store does not carry, and a neutral square for
/// one that resolved to nothing at all.
///
/// It takes a ``DirectLaunchSlot`` rather than a tile, because that is what a grid
/// has — see ``DirectLaunchIcons`` for why the system hands over a name and not an
/// icon, and what turns that name into artwork.
private struct DirectLaunchArtwork: View {
    let slot: DirectLaunchSlot
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let id = slot.appStoreID, let image = WidgetIconCache.shared.image(appStoreID: id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let symbolName = slot.symbolName {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.fill.tertiary)
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.system(size: cornerRadius * 2.3))
                            .foregroundStyle(.secondary)
                    }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.fill.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}