import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

/// Leaves the host's independently requested glass visible in the default Home
/// Screen appearance. Custom solid and gradient plates live in the content layer.
/// The host request below uses an unpublished API; App Store readiness is pending.
extension View {
    func appFolderWidgetContainerBackground() -> some View {
        containerBackground(for: .widget) {
            Color.clear
        }
    }
}

/// Opens the system actions selected in Edit Widget without routing through the app.
/// Saved groups arrange named references into folders; the system retains the actual
/// actions. The default layout instead reserves its last cell for an overflow folder.
/// Artwork is resolved by the timeline provider before the widget renders.
struct DirectLaunchWidget: Widget {
    private static let families: [WidgetFamily] = [
        .systemSmall, .systemMedium, .systemLarge, .systemExtraLargePortrait
    ]

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppFolderShared.directLaunchWidgetKind,
            intent: QuickLaunchIntent.self,
            provider: DirectLaunchProvider()
        ) { entry in
            DirectLaunchView(entry: entry)
        }
        .configurationDisplayName("直接启动")
        .description("把常用 App、动作、联系人和网站排在一起，点按打开。")
        .supportedFamilies(Self.families)
        // FolderGridMetrics supplies the content margins for each family.
        .contentMarginsDisabled()
        // Let the system remove or replace the declared background as appropriate.
        .containerBackgroundRemovable(true)
        // Restore the previously verified per-widget glass request. This is
        // independent of the user's global Clear/Tinted Home Screen setting.
        // Scripts/widgetkit-overlay.sh imports the OS's real declaration; this
        // unpublished API remains a separate App Store compatibility issue.
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
    var country: String? = nil
    let symbolName: String?
    var customIcons: CustomIconVariants? = nil
}

struct DirectLaunchEntry: TimelineEntry {
    var date: Date
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

    /// Missing artwork or a temporary lookup failure needs a later retry.
    var needsArtworkRetry: Bool = false

    var selectedGroupID: UUID? = nil
    var savedGroup: SavedGroup? = nil
    /// Root configuration identifies this widget and its binding report. The
    /// displayed style may instead come from the currently open folder.
    var rootStyle: FolderStyle? = nil
    var savedGroupLayout: SavedGroupPageLayout? = nil
    var groupNavigation: SavedGroupNavigation.Snapshot = .init()
    /// Only folders on the current page retain custom artwork. The saved tree
    /// contains small immutable references, never the photo bytes themselves.
    var tileArtwork: [UUID: CustomIconVariants] = [:]
    var artworkPixelSize: Int = 256
    var dateCalendar: Calendar = .current

    var containsDateIcon: Bool {
        slots.contains { $0.customIcons?.containsDate == true }
            || tileArtwork.values.contains { $0.containsDate }
    }
}

struct DirectLaunchProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DirectLaunchEntry {
        DirectLaunchIcons.diagnose("geometry placeholder family=\(context.family.rawValue) size=\(context.displaySize.width)x\(context.displaySize.height)")
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
        DirectLaunchIcons.diagnose("geometry snapshot family=\(context.family.rawValue) size=\(context.displaySize.width)x\(context.displaySize.height)")
        return await entry(for: configuration, family: context.family, recordsBindingReport: false)
    }

    func timeline(for configuration: QuickLaunchIntent, in context: Context) async -> Timeline<DirectLaunchEntry> {
        DirectLaunchIcons.diagnose("geometry timeline family=\(context.family.rawValue) size=\(context.displaySize.width)x\(context.displaySize.height)")
        let entry = await entry(for: configuration, family: context.family, recordsBindingReport: true)
        let plan = DateIconTimelinePlan(now: entry.date, containsDateIcon: entry.containsDateIcon,
                                        needsArtworkRetry: entry.needsArtworkRetry, calendar: entry.dateCalendar)
        // Reuse resolved actions, navigation and bounded artwork. Future dates
        // must not perform lookups, write observations or advance navigation.
        let entries = plan.dates.map { date in
            var copy = entry
            copy.date = date
            return copy
        }
        return Timeline(entries: entries, policy: plan.reloadDate.map { .after($0) } ?? .never)
    }

    private func entry(for configuration: QuickLaunchIntent, family: WidgetFamily,
                       recordsBindingReport: Bool) async -> DirectLaunchEntry {
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
        if WidgetState.applyCollapseRequest(WidgetState.collapseRequest) {
            SavedGroupNavigation.reset()
        }

        let shortcuts = configuration.slots
        let selectedGroupID = configuration.savedGroup?.id
        let savedGroup = selectedGroupID.flatMap { SavedGroupStore.group(id: $0) }
        // Identity stays rooted in the widget configuration, even while a child
        // folder supplies a different grid. Otherwise entering that folder would
        // change the navigation key and immediately send the user back home.
        let rootStyle = savedGroup?.effectiveStyle(useGroupAppearance: configuration.useGroupAppearance,
                                                   widgetStyle: configuration.style) ?? configuration.style

        // The key is computed from the names the *system* gave, in configuration
        // order, and the same names are visible to the render — which is what lets
        // the door's tap and this provider agree without either storing the
        // shortcut. Taken from every configured slot rather than the truncated
        // list, so removing an app does not leave the key describing a grid that
        // no longer exists.
        let names = shortcuts.map { String(localized: $0.displayRepresentation.title) }
        let baseKey = WidgetState.directLaunchExpansionKey(slotNames: names, grid: rootStyle.grid,
                                                           family: family, density: rootStyle.density)
        let key = savedGroup?.navigationKey(baseKey: baseKey, useGroupAppearance: configuration.useGroupAppearance)
            ?? (baseKey + (selectedGroupID.map { "|group:\($0.uuidString)|missing" } ?? ""))
        let groupNavigation = SavedGroupNavigation.state(for: key)
        let groupLayout = savedGroup.map {
            SavedGroupPageLayout(group: $0, path: groupNavigation.path, page: groupNavigation.page,
                                 family: family, useGroupAppearance: configuration.useGroupAppearance,
                                 widgetStyle: configuration.style)
        }
        let style = groupLayout?.style ?? rootStyle
        let grid = style.grid
        let capacity = groupLayout?.page.capacity ?? grid.capacity(for: family, density: style.density)
        let artworkPixelSize = WidgetArtworkResolution.maximumPixelSize(
            cellCount: groupLayout?.page.capacity ?? grid.cellCount(for: family, density: style.density))

        // Only a grid that has a door can be opened, and the test for that is the
        // same ``FolderGrid/nestedCell(for:tileCount:)`` the collapsed grid uses
        // to decide the last cell *is* a door. A grid that fits has nothing to
        // expand, and expanding it anyway would draw a lone 返回 cell where the
        // user's apps used to be.
        let hasOverflow = grid.nestedCell(for: family, tileCount: names.count, density: style.density) != nil
        let isExpanded = selectedGroupID == nil && hasOverflow && WidgetState.directLaunchKey == key
        let visibleArtwork: Set<Int>
        var fullSizeArtwork = Set<Int>()
        var tileArtwork: [UUID: CustomIconVariants] = [:]
        var needsCoverArtworkRetry = false
        if let groupLayout {
            let page = groupLayout.page
            let binding = SavedGroupBinding(actionNames: names)
            // Only the selected four or nine leaves of visible folder miniatures
            // need pixels. Offscreen pages never retain full-size artwork.
            var visibleNames: [String] = []
            func loadArtwork(_ item: GroupItem, maxSide: Int) {
                guard let reference = item.artworkReference else { return }
                let artwork = FolderCoverAssetStore.variants(for: reference, maxSide: maxSide)
                tileArtwork[item.id] = artwork
                // A layout can change between reading the group and its assets.
                // Keep a usable fallback and schedule the existing slow retry.
                needsCoverArtworkRetry = needsCoverArtworkRetry || reference.hasMissingArtwork(in: artwork)
            }
            for item in page.visibleItems {
                switch item.kind {
                case .folder:
                    loadArtwork(item, maxSide: artworkPixelSize)
                    // Dark-only or missing covers still need the contents mini.
                    if tileArtwork[item.id]?.standard == nil {
                        for leaf in item.previewLeafItems {
                            if leaf.kind == .action { visibleNames.append(leaf.name) }
                            else if leaf.kind == .website || leaf.kind == .contact { loadArtwork(leaf, maxSide: 32) }
                        }
                    }
                case .website, .contact:
                    loadArtwork(item, maxSide: artworkPixelSize)
                case .action:
                    visibleNames.append(item.name)
                    if case .matched(let index) = binding.resolve(item.name) { fullSizeArtwork.insert(index) }
                case .spacer:
                    break
                }
            }
            visibleArtwork = Set(visibleNames.compactMap { name in
                if case .matched(let index) = binding.resolve(name) { return index }
                return nil
            })
        } else if selectedGroupID != nil {
            visibleArtwork = []
        } else {
            visibleArtwork = DirectLaunchArtworkSelection.visibleArtworkIndices(
                slotCount: names.count, family: family, grid: grid,
                isExpanded: isExpanded, page: WidgetState.expandedPage, density: style.density
            )
        }

        if selectedGroupID == nil {
            fullSizeArtwork = DirectLaunchArtworkSelection.fullSizeArtworkIndices(
                slotCount: names.count, family: family, grid: grid,
                isExpanded: isExpanded, page: WidgetState.expandedPage, density: style.density
            )
        }

        // One instant for the whole build: it stamps the observed-slot records and
        // the entry together, so a single timeline is internally consistent.
        let now = Date()
        if recordsBindingReport {
            // Candidate discovery must not wait for App Store artwork. Keep any
            // previously resolved image metadata until the final enrichment.
            DirectLaunchOverrides.noteConfiguredNames(names, observedAt: now)
        }
        // Gallery snapshots are not checks. This only records a timeline's name
        // matching, not the widget's continued presence on the Home Screen.
        if recordsBindingReport, let savedGroup,
           let report = SavedGroupBindingReport(group: savedGroup, configurationKey: key,
                                                grid: rootStyle.grid, familyRawValue: family.rawValue,
                                                actionNames: names, checkedAt: now, density: rootStyle.density) {
            SavedGroupBindingReportStore.record(report)
        }

        // The whole build runs inside a network budget. The provider is the only
        // caller that knows where a build starts and ends, which is why the budget
        // is opened here and not inside the resolver — see ``DirectLaunchIcons/Budget``
        // for what it buys. It is a `@TaskLocal`, so this build carries its own and
        // neither touches nor is touched by another build running at the same time.
        return await DirectLaunchIcons.withBudget {

            var slots: [DirectLaunchSlot] = []
            var observed: [DirectLaunchOverrides.SlotRecord] = []
            var needsArtworkRetry = needsCoverArtworkRetry
            let priorObserved = Dictionary(uniqueKeysWithValues: DirectLaunchOverrides.observedSlots.map { ($0.id, $0) })
            for (index, shortcut) in shortcuts.enumerated() {
                let name = String(localized: shortcut.displayRepresentation.title)

                if selectedGroupID != nil && !visibleArtwork.contains(index) {
                    let prior = priorObserved[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
                    slots.append(.init(id: index, name: name, appStoreID: prior?.appStoreID, symbolName: nil))
                    observed.append(.init(name: name, appStoreID: prior?.appStoreID,
                                          source: prior?.source ?? "none", updatedAt: now))
                    continue
                }

                let customIcons = CustomIconStore.variants(name: name)
                let retainedCustomIcons = visibleArtwork.contains(index)
                    ? customIcons?.thumbnail(maxSide: fullSizeArtwork.contains(index) ? artworkPixelSize : 32) : nil
                // A standard custom icon also supplies the dark fallback. A dark-only
                // override still needs automatic artwork for the light appearance.
                if customIcons?.standard != nil {
                    slots.append(DirectLaunchSlot(id: index, name: name, appStoreID: nil,
                                                  symbolName: nil, customIcons: retainedCustomIcons))
                    observed.append(.init(name: name, appStoreID: nil, source: "custom", updatedAt: now))
                    continue
                }

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
                // Validated cached artwork counts as available. A bounded ImageIO
                // decode rejects corrupt files without retaining a UIImage for
                // every configured action in the extension's render cache.
                let iconOnDisk = resolved.appStoreID.map { id in
                    DirectLaunchIcons.cachedIcon(appStoreID: id, country: resolved.country) != nil
                } ?? false
                needsArtworkRetry = needsArtworkRetry || resolved.shouldRetry
                    || (resolved.appStoreID != nil && !iconOnDisk)
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
                        country: resolved.country,
                        symbolName: resolved.symbolName,
                        customIcons: retainedCustomIcons
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

            // Record names and matches observed by this timeline for "修正图标".
            // These observations are not an inventory of current Home Screen widgets.
            // Merge rather than replace: this provider invocation only sees its own
            // configuration. See ``DirectLaunchOverrides/noteObservedSlots(_:)``.
            if recordsBindingReport { DirectLaunchOverrides.noteObservedSlots(observed) }

            return DirectLaunchEntry(
                date: .now,
                slots: slots,
                shortcuts: shortcuts,
                style: style,
                totalSlots: slots.count,
                isExpanded: isExpanded,
                expandedPage: WidgetState.expandedPage,
                expansionKey: key,
                capacity: capacity,
                iconRevision: DirectLaunchOverrides.revision + CustomIconStore.revision,
                needsArtworkRetry: needsArtworkRetry,
                selectedGroupID: selectedGroupID,
                savedGroup: savedGroup,
                rootStyle: rootStyle,
                savedGroupLayout: groupLayout,
                groupNavigation: groupNavigation,
                tileArtwork: tileArtwork,
                artworkPixelSize: artworkPixelSize
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
            if entry.selectedGroupID != nil {
                SavedGroupWidgetView(entry: entry, family: family)
            } else if entry.isExpanded {
                // Opened by tapping the door — see ``ToggleDirectLaunchIntent``.
                // Drawn from the same rectangle, so this is a redraw rather than a
                // presentation; nothing left the Home Screen to get here.
                DirectLaunchPanelView(entry: entry, family: family)
            } else {
                collapsed
            }
        }
        .environment(\.dateIconContent, entry.containsDateIcon
                     ? DateIconContent(date: entry.date, calendar: entry.dateCalendar) : nil)
    }

    private var collapsed: some View {
        Group {
            // A widget with nothing configured used to draw a bare rectangle — an
            // empty box on the Home Screen that reads as broken and gives no hint
            // that the setup step is behind a long press. It now says what to do.
            //
            // Keyed on `slots` being empty rather than on `shortcuts`, so the
            // gallery's sample faces — which arrive as slots with no shortcuts —
            // still draw.
            if entry.slots.isEmpty {
                DirectLaunchEmptyView(style: entry.style)
            } else {
                collapsedGrid
            }
        }
        // Explicit solid and gradient choices remain above the adaptive base.
        // Automatic leaves that base visible and follows the system appearance.
        .background {
            if let fill = entry.style.plateFill {
                Rectangle().fill(fill)
            }
        }
        .appFolderWidgetContainerBackground()
    }

    /// The grid the user configured.
    private var collapsedGrid: some View {
        // A grid that has overflowed draws one cell more than it has slots, and
        // that cell is the door. Sizing from the slot count instead would make the
        // icons grow the moment a ninth app was configured, which is the opposite
        // of what the door is for — the same rule, and the same reason, as
        // ``FolderGrid``.
        let hasDoor = entry.totalSlots > entry.capacity

        return GeometryReader { proxy in
            let metrics = FolderGridMetrics(
                tileCount: entry.style.grid.cellCount(for: family, density: entry.style.density),
                columns: columns,
                in: proxy.size,
                showsTitles: entry.style.showsTitles,
                iconScale: entry.style.iconScale, family: family, density: entry.style.density
            )

            // Keep a full grid shape even when few actions are configured. Larger
            // families center the complete rectangle; empty cells stay in place.
            ZStack(alignment: family == .systemSmall ? .top : .center) {
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
                                        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                                } else if entry.slots.indices.contains(index) {
                                    slot(at: index, metrics: metrics)
                                        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                                } else {
                                    // Empty cells exist only so the icons left-align
                                    // rather than centring. They need no tap handling
                                    // of their own — the shield behind the grid covers
                                    // them and the regions the grid cannot reach.
                                    Color.clear
                                        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                                }
                            }
                        }
                    }
                }
                .padding(metrics.margin)
            }
            .frame(width: proxy.size.width, height: proxy.size.height,
                   alignment: family == .systemSmall ? .top : .center)
        }
    }

    @ViewBuilder
    private func slot(at index: Int, metrics: FolderGridMetrics) -> some View {
        let slot = entry.slots[index]
        let face = DirectLaunchFace(slot: slot, style: entry.style, metrics: metrics, maxPixelSize: entry.artworkPixelSize)
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
            .accessibilityLabel(Text(slot.name))
            .accessibilityHint("运行此动作")
        }
    }

    /// The last cell of a grid that holds more than it can draw: a 2 × 2 glyph of
    /// what is behind it, and a tap that **expands the group in place**.
    ///
    /// Its geometry is ``FolderGridMetrics`` and its glyph is ``MiniGridDensity``,
    /// both shared types, so the cell cannot drift from anything else that draws
    /// the same thing.
    ///
    /// This is the only thing that draws the cell now. The folder widget drew it
    /// too, from `FolderTile`s carrying a cached `UIImage`, and the folder editor
    /// had a `NestedCell` preview of it; both are gone with the folder model. What
    /// is left reads `DirectLaunchSlot`s carrying an App Store id, because the
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("其他")
        .accessibilityHint("展开文件夹")
    }

    /// Use the selected grid shape for the collapsed layout.
    private var columns: Int { entry.style.grid.columns(for: family, density: entry.style.density) }
}

/// Displays only the default layout's overflow actions, keeping the selected grid
/// shape. FolderExpansionLayout reserves cells for back and page controls.
/// The panel uses the adaptive system background and matching semantic label styles.
struct DirectLaunchPanelView: View {
    let entry: DirectLaunchEntry
    let family: WidgetFamily

    /// The shape the panel lays out — the same one the collapsed grid drew.
    ///
    /// ## Why the panel does not choose its own shape
    ///
    /// It used to. The panel sized itself from the room it was given: keep the cell
    /// the collapsed small grid draws (about 37 pt), then take as many whole rows
    /// and columns as fit, on the reasoning that the panel's job is to show as much
    /// of the configuration as possible. What that produced is the bug this fixes —
    /// on a **四宫格** small widget the collapsed grid is a 2 × 2 the user chose and
    /// the door opened onto a **3 × 3**. The frame around the apps changed shape, the
    /// icons shrank, and the tap read as the widget being replaced rather than opened.
    ///
    /// So the panel takes the collapsed grid's own shape, from the same ``FolderGrid``
    /// the user picked. Opening then keeps everything still — the same cells at the
    /// same icon size, 九宫格 or 四宫格 — and only the *contents* change, which is what
    /// opening a folder does on iOS. It also means the panel can never disagree with
    /// the grid it came from, and the per-family shape search (and the fallback floor
    /// it needed) is gone with it.
    ///
    /// The cost is density: a medium panel now holds nine apps a page rather than
    /// eleven, so the largest overflows page a little more. That is the same trade the
    /// collapsed grid already made; the alternative was two different shapes for one
    /// group, depending on whether it was open.
    private var panelLayout: FolderExpansionLayout {
        FolderExpansionLayout(
            family: family,
            columns: entry.style.grid.columns(for: family, density: entry.style.density),
            cellCount: entry.style.grid.cellCount(for: family, density: entry.style.density),
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
            // The same shape the collapsed grid drew, so the panel is the grid with
            // different contents rather than a new arrangement — see
            // ``panelLayout``. The page is clamped through the resolved layout,
            // since `pageSize` is a property of the shape.
            let layout = panelLayout
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
                iconScale: style.iconScale, family: family, density: style.density
            )

            // Match the collapsed grid's shape and alignment across pages.
            ZStack(alignment: family == .systemSmall ? .top : .center) {
                // The exit. A tap anywhere that is not an app closes the panel, so
                // the shield is the *whole* widget rather than the grid's bounds —
                // hoisted out of the grid's `.background` so its area does not
                // depend on the grid's padding and the background's overflow
                // behaviour. Behind the grid, so app cells still take their own
                // taps and the uncovered regions land here.
                TapShield(intent: CollapseDirectLaunchIntent(key: entry.expansionKey))
                    .frame(width: proxy.size.width, height: proxy.size.height)

                // A subtle scrim and border distinguish the expanded surface.
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
            .frame(width: proxy.size.width, height: proxy.size.height,
                   alignment: family == .systemSmall ? .top : .center)
        }
        // The overflow panel uses the automatic plate and semantic label colors.
        .appFolderWidgetContainerBackground()
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
                accessibilityHint: "收起文件夹",
                metrics: metrics,
                style: style,
                intent: ToggleDirectLaunchIntent(key: entry.expansionKey)
            )
            .accessibilityValue(Text("第 \(page + 1) 页，共 \(layout.pageCount) 页"))

        case .next:
            DirectLaunchCellButton(
                systemImage: "ellipsis",
                title: "更多",
                accessibilityHint: "显示下一页",
                metrics: metrics,
                style: style,
                intent: AdvanceDirectLaunchPageIntent(key: entry.expansionKey, page: page)
            )
            .accessibilityValue(Text("第 \(page + 1) 页，共 \(layout.pageCount) 页"))

        case .app(let index):
            if panelSlots.indices.contains(index) {
                let slot = panelSlots[index]
                Button(intent: RunSystemShortcutIntent(shortcut: entry.shortcuts[shortcutIndex(index)])) {
                    DirectLaunchFace(slot: slot, style: style, metrics: metrics, maxPixelSize: entry.artworkPixelSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                .accessibilityLabel(Text(slot.name))
                .accessibilityHint("运行此动作")
            } else {
                Color.clear.frame(width: metrics.cellWidth, height: metrics.cellHeight)
            }

        case .empty:
            Color.clear.frame(width: metrics.cellWidth, height: metrics.cellHeight)
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
    /// `LocalizedStringKey` so 「返回」/「更多」 come from the catalog rather than
    /// being rendered verbatim as `Text(String)` would.
    let title: LocalizedStringKey
    let accessibilityHint: LocalizedStringKey
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
                        .frame(width: metrics.cellWidth)
                }
            }
            .frame(width: metrics.cellWidth, height: metrics.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(accessibilityHint))
    }
}

/// A low-opacity tint and border distinguish the expanded default layout without
/// replacing the system background. Semantic colors adapt to light and dark modes.
private struct PanelSurface: View {
    /// Keep the system appearance visible beneath the panel decoration.
    private var scrimOpacity: Double { 0.12 }

    /// A semantic tint maintains contrast against both light and dark backgrounds.
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

            // Match the system widget corner radius.
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
        .accessibilityHidden(true)
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
        .accessibilityHidden(true)
    }
}

/// The door cell: a miniature grid of what is hidden, and a name.
private struct DirectLaunchDoorLabel: View {
    let hidden: [DirectLaunchSlot]
    let style: FolderStyle
    let metrics: FolderGridMetrics

    /// How big the miniatures are, from the cell this is drawing in.
    ///
    /// The count is always four, from ``MiniGridDensity``; only their size follows
    /// the cell. See that type for why the glyph is fixed at 2 × 2 and why the
    /// block is inset rather than filling the cell.
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
                    .frame(width: metrics.cellWidth)
            }
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        .contentShape(Rectangle())
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
            DirectLaunchArtwork(slot: hidden[index], cornerRadius: side * 0.22, maxPixelSize: 32)
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
    var maxPixelSize: Int = 256

    var body: some View {
        VStack(spacing: metrics.titleSpacing) {
            DirectLaunchArtwork(slot: slot, cornerRadius: metrics.cornerRadius, maxPixelSize: maxPixelSize)
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
                    .frame(width: metrics.cellWidth)
            }
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        // Names remain available to VoiceOver when visual labels are switched off.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(slot.name))
        .dateIconAccessibilityValue(slot.customIcons)
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
struct DirectLaunchArtwork: View {
    @Environment(\.colorScheme) private var colorScheme
    let slot: DirectLaunchSlot
    let cornerRadius: CGFloat
    var maxPixelSize: Int = 256

    var body: some View {
        Group {
            // WidgetKit renders both appearances from the same timeline entry.
            // Tinted/clear widget rendering is independent of light/dark selection.
            if let customIcon = slot.customIcons?.resolved(isDark: colorScheme == .dark) {
                CustomIconArtwork(icon: customIcon, cornerRadius: cornerRadius, usesWidgetRendering: true,
                                  maxPixelSize: maxPixelSize)
            } else if let id = slot.appStoreID,
                      let image = WidgetIconCache.shared.image(appStoreID: id, country: slot.country, maxPixelSize: maxPixelSize) {
                Image(uiImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
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
        .accessibilityHidden(true)
    }
}

/// What an unconfigured widget draws.
///
/// A widget with no apps on it is a first-run state, not an error, and it used to
/// draw nothing at all — an empty rectangle that reads as broken and says nothing
/// about the setup step being behind a long press. This says the two things that
/// matter: where the setting is, and what to do once inside it.
///
/// The colour comes from the style's own title treatment, like every other label,
/// so it stays legible on the adaptive system background and on a 纯色/渐变 plate alike.
private struct DirectLaunchEmptyView: View {
    let style: FolderStyle

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26, weight: .regular))
                .accessibilityHidden(true)

            Text("长按 → 编辑小组件")
                .font(.footnote.weight(.semibold))

            Text("把 App 加进来")
                .font(.caption2)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(style.titleStyle)
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}
