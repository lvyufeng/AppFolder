import Foundation

/// The user's own answer to "which app is this tile?".
///
/// ## Why this type has to exist
///
/// A direct-launch slot's only handle on the app behind it is a **name** — the
/// system hands the widget a `SystemShortcut` whose `displayRepresentation`
/// carries a title and nothing else (measured on device: `subtitle` nil, `image`
/// nil, synonyms empty; the struct itself is one opaque 16-byte token plus the
/// name). See ``DirectLaunchIcons`` for the probe.
///
/// Names collide, and no rule can resolve a collision correctly, because the
/// right answer is "whichever one the user installed" and nothing available to
/// the widget knows that. The store's own ranking is the best automatic guess
/// and it is still a guess: searching `Authenticator` returns Microsoft's first,
/// and a user running Google's gets a Microsoft icon. The id it lands on is a
/// real app's, so it looks like a working tile — which is exactly why the user
/// has to be able to say otherwise.
///
/// So this is a plain user-editable map, name → App Store id. When it has an
/// entry, ``DirectLaunchIcons/resolve(name:)`` takes it before anything else.
///
/// ## Why it is a separate type rather than another ``WidgetState`` accessor
///
/// ``WidgetState`` is documented as *transient* display state — "changes on every
/// tap". This is durable configuration that changes maybe once ever. Folding it
/// in would make that doc comment false and bury a user setting among render
/// state. It shares ``WidgetState``'s storage, but reads and writes through its
/// own keys, so the two cannot interfere.
///
/// ## Who writes what, and why the split matters
///
/// Two separate keys, each with exactly one writer:
///
/// * ``iconOverridesKey`` — written **only by the app**, read by the widget.
/// * ``observedSlotsKey`` — written **only by the widget**, read by the app.
///
/// That is deliberate. Neither process ever read-modify-writes a key the other
/// also writes, so an edit in the app can never be clobbered by a widget render
/// happening at the same moment, and vice versa. The alternative — one shared
/// record — would need cross-process locking for a setting that changes once a
/// year.
public enum DirectLaunchOverrides {
    // MARK: - Overrides

    /// The map the app writes and the widget reads: normalised name → App Store id.
    private static let iconOverridesKey = "widget.directLaunchOverrides"

    /// The normalised form of a slot name, which is the map's key.
    ///
    /// The same trim-and-lowercase every other name comparison in
    /// ``DirectLaunchIcons`` uses, and for the same reason: the string comes from
    /// the system and the user types their own, so they differ in case and spacing
    /// more often than in words. Deliberately not public — a caller should not be
    /// able to build a key that ``DirectLaunchIcons`` would not agree with.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The id the user chose for this slot name, or `nil` to resolve automatically.
    public static func appStoreID(name: String) -> Int? {
        let needle = key(name)
        guard !needle.isEmpty else { return nil }
        return overrides()[needle]
    }

    /// Every override, keyed the way ``key(_:)`` produces.
    public static var all: [String: Int] {
        overrides()
    }

    /// Whether the user has pinned this name to an app.
    public static func hasOverride(name: String) -> Bool {
        appStoreID(name: name) != nil
    }

    /// Points a slot name at an app, or clears it back to automatic.
    ///
    /// - Parameter appStoreID: `nil` removes the entry rather than storing it,
    ///   because "resolve this automatically" is the absence of a choice, not a
    ///   choice of nothing.
    /// - Returns: whether anything changed, so the caller only asks WidgetKit to
    ///   reload when the answer actually moved. A no-op edit should not spend a
    ///   reload — they are throttled, and spending one on a non-change would delay
    ///   the next real one.
    @discardableResult
    public static func set(appStoreID: Int?, name: String) -> Bool {
        let needle = key(name)
        guard !needle.isEmpty else { return false }

        var map = overrides()
        let previous = map[needle]
        guard previous != appStoreID else { return false }

        if let appStoreID {
            map[needle] = appStoreID
        } else {
            map.removeValue(forKey: needle)
        }
        write(map)

        // Setting an override also forgets any miss recorded for this name. Step 0
        // of `resolve` already wins over a miss, so this is belt-and-braces — but
        // it means *removing* the override falls back to a fresh search rather than
        // to a "the store has never heard of this" written under an older rule.
        if appStoreID != nil {
            DirectLaunchIcons.clearMiss(name: name)
        }
        return true
    }

    /// Forgets every override. The escape hatch, and what the tests reset through.
    public static func removeAll() {
        WidgetState.widgetDefaults.removeObject(forKey: iconOverridesKey)
    }

    /// A token that changes on every mutation.
    ///
    /// Folded into the timeline entry so a requested reload is provably a
    /// *different* entry. WidgetKit is free to serve byte-identical content from
    /// its cache, and the classic failure is calling `reloadAllTimelines()` and
    /// seeing no change because nothing in the entry moved. This is the field that
    /// moves.
    ///
    /// Built from ``DirectLaunchIcons/stableHash(_:)`` over a sorted rendering of
    /// the map rather than from `Dictionary.hashValue`, which is seeded per process
    /// and would give the same map different tokens in the app and the widget. The
    /// same stable hash is what keys the icon and miss caches, so there is one
    /// notion of "the same string" in this package rather than two.
    public static var revision: String {
        let rendered = overrides()
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\u{1F}")
        return DirectLaunchIcons.stableHash(rendered)
    }

    private static func overrides() -> [String: Int] {
        guard let blob = WidgetState.widgetDefaults.dictionary(forKey: iconOverridesKey) else {
            return [:]
        }
        // Stored as a property list dictionary, so the values come back as `NSNumber`
        // rather than `Int`. Casting through `NSNumber` rather than `as? Int` because
        // the latter is not guaranteed to bridge from an `NSNumber` in every case.
        return blob.compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    private static func write(_ map: [String: Int]) {
        WidgetState.widgetDefaults.set(map, forKey: iconOverridesKey)
    }

    // MARK: - Observed slots

    /// What the widget most recently drew, so the app can list it.
    ///
    /// The app cannot enumerate the Home Screen, and a widget's configuration is a
    /// set of `SystemShortcut`s the system holds and will not hand over — so the
    /// only way the app can learn what is on a widget is for the widget to say so.
    /// That is what this is, and it is why the app's list is empty until a timeline
    /// has been built at least once.
    private static let observedSlotsKey = "widget.directLaunchSlots"

    /// A cap on the remembered list.
    ///
    /// It grows as the user edits widgets and nothing else prunes it, so without a
    /// bound it would grow for the life of the install. A record the user has
    /// pinned is never dropped for age, because it is still the only thing tying
    /// that override to a visible row — see ``merge(_:into:)``.
    static let observedSlotLimit = 64

    /// One slot the widget drew.
    ///
    /// `appStoreID` is what the widget actually resolved, so the app shows the
    /// user the icon that is really on their Home Screen — a wrong one is visible
    /// before they change anything, which is the whole point of the screen.
    public struct SlotRecord: Codable, Sendable, Hashable, Identifiable {
        public let name: String
        public let appStoreID: Int?
        /// Which rule produced ``appStoreID``. Kept as the raw string rather than
        /// the enum so an older or newer writer cannot fail to decode it.
        public let source: String
        /// Seconds since the reference date. A `Date` rather than a counter because
        /// it is what orders the list, and it survives the record being rewritten.
        public let updatedAt: Date

        /// The normalised name, which is also the override map's key — so a row and
        /// its override are addressed identically.
        public var id: String { DirectLaunchOverrides.key(name) }

        public init(name: String, appStoreID: Int?, source: String, updatedAt: Date) {
            self.name = name
            self.appStoreID = appStoreID
            self.source = source
            self.updatedAt = updatedAt
        }
    }

    /// What the widget has reported, newest first.
    public static var observedSlots: [SlotRecord] {
        records().sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Records the slots from one timeline build, merged into what is already known.
    ///
    /// A merge rather than a replace, because there can be more than one widget and
    /// each build only knows its own slots; replacing would make the list flip
    /// between them depending on which refreshed last.
    ///
    /// Called from the widget's timeline provider, so it runs on the render path.
    /// It is a small property-list write and no network, which is cheaper than the
    /// icon reads and store lookups already on that path — but it is still guarded
    /// on the storage being readable, and it is skipped entirely when nothing
    /// changed, so a steady-state reload writes nothing at all.
    public static func noteObservedSlots(_ incoming: [SlotRecord]) {
        guard WidgetState.widgetStateIsAvailable else { return }
        guard !incoming.isEmpty else { return }

        let merged = merge(incoming, into: records())
        guard merged != records() else { return }
        writeRecords(merged)
    }

    /// Folds one build's records into the stored list.
    ///
    /// Keyed by name so a name that moved keeps one row and takes the newer id —
    /// which is also what makes a name that appears on two widgets collapse to one
    /// entry rather than two rows the user cannot tell apart. There is no widget
    /// identity to key on anyway: the system gives a widget's configuration no id.
    static func merge(_ incoming: [SlotRecord], into existing: [SlotRecord]) -> [SlotRecord] {
        var byID: [String: SlotRecord] = [:]
        for record in existing { byID[record.id] = record }
        for record in incoming {
            // Keep whichever is newer, so a stale widget refreshing late cannot
            // overwrite a fresh answer with an old one.
            if let current = byID[record.id], current.updatedAt > record.updatedAt { continue }
            byID[record.id] = record
        }

        var result = Array(byID.values)
        guard result.count > observedSlotLimit else { return result }

        // Over the cap: drop the oldest that the user has *not* pinned. A pinned
        // record is the only thing that puts its override on screen, so dropping it
        // would silently orphan a setting the user can then no longer find.
        result.sort { $0.updatedAt > $1.updatedAt }
        var kept: [SlotRecord] = []
        var over = result.count - observedSlotLimit
        for record in result {
            if over > 0, !hasOverride(name: record.name) {
                over -= 1
                continue
            }
            kept.append(record)
        }
        return kept
    }

    /// Forgets the observed list. For tests and the app's own reset.
    public static func removeObservedSlots() {
        WidgetState.widgetDefaults.removeObject(forKey: observedSlotsKey)
    }

    private static func records() -> [SlotRecord] {
        guard let data = WidgetState.widgetDefaults.data(forKey: observedSlotsKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([SlotRecord].self, from: data)) ?? []
    }

    private static func writeRecords(_ records: [SlotRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(records) else { return }
        WidgetState.widgetDefaults.set(data, forKey: observedSlotsKey)
    }
}