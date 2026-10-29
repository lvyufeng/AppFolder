import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

struct LockScreenLaunchWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: AppFolderShared.lockScreenWidgetKind,
                               intent: LockScreenLaunchIntent.self,
                               provider: LockScreenLaunchProvider()) { entry in
            LockScreenLaunchView(entry: entry)
        }
        .configurationDisplayName("锁屏启动")
        .description("圆形打开一个项目，矩形打开两个项目。锁定时按系统要求解锁。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct LockScreenLaunchSlot: Identifiable {
    enum Destination {
        case website(String)
        case websiteViaHost(URL)
        case contact(URL)
        case action(Int)
        case help(URL)
        case empty
        case sample
    }

    let id: Int
    let title: String
    let destination: Destination
    var status: String? = nil
    var actionArtwork: DirectLaunchSlot? = nil
    var websiteArtwork: CustomIconVariants? = nil
    var isWebsite = false
    var contactTarget: ContactTarget? = nil
    var contactArtwork: CustomIconVariants? = nil
}

struct LockScreenLaunchEntry: TimelineEntry {
    var date: Date
    let slots: [LockScreenLaunchSlot]
    let shortcuts: [SystemShortcut]
    var needsArtworkRetry = false
    var revision = ""
    var dateCalendar: Calendar = .current

    var containsDateIcon: Bool {
        slots.contains {
            $0.actionArtwork?.customIcons?.containsDate == true
                || $0.websiteArtwork?.containsDate == true || $0.contactArtwork?.containsDate == true
        }
    }
}

struct LockScreenLaunchProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LockScreenLaunchEntry {
        .init(date: .now, slots: [
            .init(id: 0, title: String(localized: "日历"), destination: .sample,
                  actionArtwork: .init(id: 0, name: "", appStoreID: nil, symbolName: "calendar")),
            .init(id: 1, title: String(localized: "网站"), destination: .sample, isWebsite: true)
        ], shortcuts: [])
    }

    func snapshot(for configuration: LockScreenLaunchIntent, in context: Context) async -> LockScreenLaunchEntry {
        if context.isPreview && configuration.firstItem == nil && configuration.secondItem == nil {
            return placeholder(in: context)
        }
        return await entry(for: configuration, family: context.family, recordsObservations: false)
    }

    func timeline(for configuration: LockScreenLaunchIntent, in context: Context) async -> Timeline<LockScreenLaunchEntry> {
        let entry = await entry(for: configuration, family: context.family, recordsObservations: true)
        let plan = DateIconTimelinePlan(now: entry.date, containsDateIcon: entry.containsDateIcon,
                                        needsArtworkRetry: entry.needsArtworkRetry, calendar: entry.dateCalendar)
        let entries = plan.dates.map { date in
            var copy = entry
            copy.date = date
            return copy
        }
        return Timeline(entries: entries, policy: plan.reloadDate.map { .after($0) } ?? .never)
    }

    private func entry(for configuration: LockScreenLaunchIntent, family: WidgetFamily,
                       recordsObservations: Bool) async -> LockScreenLaunchEntry {
        let shortcuts = configuration.shortcuts ?? []
        let names = shortcuts.map { String(localized: $0.displayRepresentation.title) }
        let binding = SavedGroupBinding(actionNames: names)
        let selections = family == .accessoryCircular
            ? [configuration.firstItem] : [configuration.firstItem, configuration.secondItem]

        return await DirectLaunchIcons.withBudget {
            var slots: [LockScreenLaunchSlot] = []
            var revisions: [String] = []
            var needsRetry = false
            var observations: [DirectLaunchOverrides.SlotRecord] = []
            for (index, selection) in selections.enumerated() {
                guard let selection else {
                    slots.append(.init(id: index, title: String(localized: "选择项目"), destination: .empty))
                    continue
                }
                guard let id = LockScreenItemID(rawValue: selection.id) else {
                    slots.append(.init(id: index, title: String(localized: "项目不可用"), destination: .empty))
                    continue
                }
                let helpURL = SavedGroupHelpRoute(groupID: id.groupID, itemID: id.itemID, surface: .lockScreen).url
                let savedGroup: SavedGroup?
                switch SavedGroupStore.readResult(id: id.groupID) {
                case .loaded(let value): savedGroup = value
                case .missing: savedGroup = nil
                case .unavailable, .unreadable:
                    savedGroup = nil
                    needsRetry = true
                }
                guard let group = savedGroup,
                      let choice = LockScreenItemChoice.resolve(id, in: group) else {
                    slots.append(.init(id: index, title: String(localized: "项目不可用"),
                                       destination: .help(helpURL), status: String(localized: "重新选择")))
                    continue
                }
                revisions.append(group.revision)
                let item = choice.item
                if item.kind == .contact, let target = item.contactTarget {
                    let artwork = item.contactIcon.flatMap { FolderCoverAssetStore.variants(for: $0, maxSide: 96) }
                    needsRetry = needsRetry || (item.contactIcon?.hasMissingArtwork(in: artwork) ?? false)
                    slots.append(.init(id: index, title: choice.title,
                                       destination: .contact(ContactLaunchRoute(groupID: group.id, itemID: item.id).url),
                                       contactTarget: target, contactArtwork: artwork))
                } else if item.kind == .website, let address = item.websiteURL,
                   WebsiteURL.validated(address) != nil {
                    let artwork = item.websiteIcon.flatMap { FolderCoverAssetStore.variants(for: $0, maxSide: 96) }
                    needsRetry = needsRetry || (item.websiteIcon?.hasMissingArtwork(in: artwork) ?? false)
                    let destination: LockScreenLaunchSlot.Destination = item.effectiveWebsiteBrowser == .systemDefault
                        ? .website(address)
                        : .websiteViaHost(WebsiteLaunchRoute(groupID: group.id, itemID: item.id).url)
                    slots.append(.init(id: index, title: choice.title, destination: destination,
                                       websiteArtwork: artwork, isWebsite: true))
                } else if item.kind == .action {
                    switch binding.resolve(item.name) {
                    case .matched(let actionIndex) where shortcuts.indices.contains(actionIndex):
                        let custom = CustomIconStore.variants(name: item.name)?.thumbnail(maxSide: 96)
                        var artwork = DirectLaunchSlot(id: actionIndex, name: item.name,
                                                       appStoreID: nil, symbolName: "app", customIcons: custom)
                        if custom?.standard == nil {
                            let resolved = await DirectLaunchIcons.resolve(name: item.name)
                            artwork = .init(id: actionIndex, name: item.name, appStoreID: resolved.appStoreID,
                                            country: resolved.country,
                                            symbolName: resolved.symbolName ?? "app", customIcons: custom)
                            needsRetry = needsRetry || resolved.shouldRetry
                                || (resolved.appStoreID.map { DirectLaunchIcons.cachedIcon(appStoreID: $0, country: resolved.country) == nil } ?? false)
                            observations.append(.init(name: item.name, appStoreID: resolved.appStoreID,
                                                      source: resolved.source.rawValue, updatedAt: .now))
                        } else {
                            observations.append(.init(name: item.name, appStoreID: nil, source: "custom", updatedAt: .now))
                        }
                        slots.append(.init(id: index, title: choice.title, destination: .action(actionIndex),
                                           actionArtwork: artwork))
                    case .ambiguous:
                        slots.append(.init(id: index, title: choice.title, destination: .help(helpURL),
                                           status: String(localized: "同名冲突")))
                    default:
                        slots.append(.init(id: index, title: choice.title, destination: .help(helpURL),
                                           status: String(localized: "未配置")))
                    }
                } else {
                    slots.append(.init(id: index, title: choice.title, destination: .help(helpURL),
                                       status: String(localized: "项目不可用")))
                }
            }
            if recordsObservations {
                DirectLaunchOverrides.noteConfiguredNames(names, observedAt: .now)
                DirectLaunchOverrides.noteObservedSlots(observations)
            }
            // A lock-screen selection verifies at most two leaves, never a whole
            // group's binding report. Keep Home Screen reports independent.
            return .init(date: .now, slots: slots, shortcuts: shortcuts, needsArtworkRetry: needsRetry,
                         revision: revisions.joined(separator: "|") + DirectLaunchOverrides.revision + CustomIconStore.revision)
        }
    }
}

private struct LockScreenLaunchView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LockScreenLaunchEntry

    var body: some View {
        Group {
            if family == .accessoryCircular {
                if let slot = entry.slots.first {
                    cell(slot, circular: true).widgetURL(circularURL)
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(entry.slots.prefix(2)) { slot in cell(slot, circular: false) }
                }
                .padding(.horizontal, 2)
            }
        }
        .privacySensitive()
        .environment(\.dateIconContent, entry.containsDateIcon
                     ? DateIconContent(date: entry.date, calendar: entry.dateCalendar) : nil)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circularURL: URL? {
        guard let slot = entry.slots.first else { return nil }
        switch slot.destination {
        case .help(let url), .contact(let url), .websiteViaHost(let url): return url
        default: return nil
        }
    }

    @ViewBuilder private func cell(_ slot: LockScreenLaunchSlot, circular: Bool) -> some View {
        switch slot.destination {
        case .contact(let url):
            if circular {
                face(slot, circular: true).accessibilityHint("通过 AppFolder 联系此人")
            } else {
                Link(destination: url) { face(slot, circular: false) }
                    .buttonStyle(.plain).accessibilityHint("通过 AppFolder 联系此人")
            }
        case .website(let address):
            Button(intent: OpenWebsiteIntent(url: address)) { face(slot, circular: circular) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(slot.title))
                .accessibilityHint("打开网站链接")
        case .websiteViaHost(let url):
            if circular {
                face(slot, circular: true).accessibilityHint("通过 AppFolder 按所选方式打开网站")
            } else {
                Link(destination: url) { face(slot, circular: false) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(slot.title))
                    .accessibilityHint("通过 AppFolder 按所选方式打开网站")
            }
        case .action(let index):
            if entry.shortcuts.indices.contains(index) {
                Button(intent: RunSystemShortcutIntent(shortcut: entry.shortcuts[index])) {
                    face(slot, circular: circular)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(slot.title))
                .accessibilityHint("运行此动作")
            }
        case .help(let url):
            if circular {
                face(slot, circular: true).accessibilityHint("打开此项目的配置帮助")
            } else {
                Link(destination: url) { face(slot, circular: false) }
                    .buttonStyle(.plain).accessibilityHint("打开此项目的配置帮助")
            }
        case .empty:
            face(slot, circular: circular).accessibilityHint("编辑小组件，选择已保存分组中的项目。")
        case .sample:
            face(slot, circular: circular)
        }
    }

    private func face(_ slot: LockScreenLaunchSlot, circular: Bool) -> some View {
        VStack(spacing: 2) {
            Group {
                if slot.status != nil {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 20))
                } else if let target = slot.contactTarget {
                    ContactArtwork(target: target, variants: slot.contactArtwork, cornerRadius: 6,
                                   usesWidgetRendering: true, maxPixelSize: 96)
                } else if slot.isWebsite {
                    WebsiteArtwork(variants: slot.websiteArtwork, cornerRadius: 6,
                                   usesWidgetRendering: true, maxPixelSize: 96)
                } else if let artwork = slot.actionArtwork {
                    DirectLaunchArtwork(slot: artwork, cornerRadius: 6, maxPixelSize: 96)
                } else {
                    Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                }
            }
            .frame(width: circular ? 26 : 28, height: circular ? 26 : 28)
            Text(slot.status ?? slot.title)
                .font(.system(size: circular ? 9 : 11, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: slot.title + (slot.contactTarget.map { " · " + $0.operation.widgetLocalizedName } ?? "")))
        .accessibilityValue(Text(slot.status ?? ""))
        .dateIconAccessibilityValue(slot.status == nil
                                   ? slot.contactArtwork ?? slot.websiteArtwork ?? slot.actionArtwork?.customIcons : nil)
    }
}
