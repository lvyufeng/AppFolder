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
/// So this is a user-editable map, name → App Store id and optional source country. When it has an
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

    /// Artwork identity and its chosen lookup source. The source never changes
    /// the system action that launches when the user taps a widget tile.
    public struct Mapping: Codable, Sendable, Equatable {
        public let appStoreID: Int
        /// Nil preserves the legacy US-then-China lookup policy.
        public let country: String?

        public init?(appStoreID: Int, country: String? = nil) {
            guard appStoreID > 0 else { return nil }
            if let country {
                guard let normalized = AppStoreCountry.normalized(country) else { return nil }
                self.country = normalized
            } else { self.country = nil }
            self.appStoreID = appStoreID
        }

        private enum CodingKeys: String, CodingKey { case appStoreID, country }
        private struct AnyKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        public init(from decoder: any Decoder) throws {
            let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
            guard keys.isSubset(of: ["appStoreID", "country"]) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Unknown artwork mapping fields"))
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let id = try values.decode(Int.self, forKey: .appStoreID)
            let country = try values.decodeIfPresent(String.self, forKey: .country)
            guard country == nil || AppStoreCountry.normalized(country!) == country,
                  let mapping = Self(appStoreID: id, country: country) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Invalid App Store artwork mapping"))
            }
            self = mapping
        }
    }

    /// A single app-written property-list value. Numeric legacy records remain
    /// readable; a selected country is stored beside its ID in the same record.
    private static let iconOverridesKey = "widget.directLaunchOverrides"

    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func mapping(name: String) -> Mapping? {
        let needle = key(name)
        guard !needle.isEmpty, let value = rawOverrides()[needle] else { return nil }
        return decodeStoredMapping(value)
    }

    public static var allMappings: [String: Mapping] {
        rawOverrides().compactMapValues(decodeStoredMapping)
    }

    /// Compatibility readers expose the same App Store IDs as before.
    public static func appStoreID(name: String) -> Int? { mapping(name: name)?.appStoreID }
    public static var all: [String: Int] { allMappings.mapValues(\.appStoreID) }

    static func backupRecords() throws -> [String: Mapping] {
        try validatedBackupMappings(WidgetState.widgetDefaults.object(forKey: iconOverridesKey))
    }

    /// Export fails on an invalid record instead of silently omitting its source.
    static func validatedBackupMappings(_ object: Any?) throws -> [String: Mapping] {
        guard let object else { return [:] }
        guard let values = object as? [String: Any], values.count <= LibraryBackup.maximumMappings else {
            throw LibraryBackupError.exportFailed
        }
        var result: [String: Mapping] = [:]
        for (name, value) in values {
            guard LibraryBackup.validName(name), let mapping = decodeStoredMapping(value) else {
                throw LibraryBackupError.exportFailed
            }
            result[name] = mapping
        }
        return result
    }

    /// Even an unreadable existing record protects its name during import.
    static func containsBackupRecord(name: String) -> Bool { rawOverrides()[key(name)] != nil }

    public static func hasOverride(name: String) -> Bool { mapping(name: name) != nil }

    /// Returns whether a durable selection changed. As before, false can mean
    /// no change or failure; callers verify the complete mapping after writing.
    @discardableResult
    public static func set(mapping: Mapping?, name: String) -> Bool {
        let needle = key(name)
        guard LibraryBackup.validName(name), !needle.isEmpty, WidgetState.widgetStateIsAvailable else { return false }
        // Preserve unrelated raw records, including unreadable ones. A user edit
        // must not turn the tolerant display reader into a destructive rewrite.
        guard let map = rawOverridesForWrite() else { return false }
        var next = map
        if let mapping {
            guard map[needle].flatMap(decodeStoredMapping) != mapping else { return false }
            guard next[needle] != nil || next.count < LibraryBackup.maximumMappings else { return false }
            if let country = mapping.country {
                next[needle] = ["appStoreID": mapping.appStoreID, "country": country]
            } else {
                next[needle] = mapping.appStoreID
            }
        } else {
            guard next.removeValue(forKey: needle) != nil else { return false }
        }
        WidgetState.widgetDefaults.set(next, forKey: iconOverridesKey)
        guard self.mapping(name: name) == mapping,
              mapping != nil || !containsBackupRecord(name: name) else { return false }
        if mapping != nil { DirectLaunchIcons.clearMiss(name: name) }
        return true
    }

    /// Legacy callers retaining an unchanged ID also retain its selected source.
    /// A different ID has no known source, so it uses the legacy lookup policy.
    @discardableResult
    public static func set(appStoreID: Int?, name: String) -> Bool {
        guard let appStoreID else { return set(mapping: nil, name: name) }
        let country = mapping(name: name).flatMap { $0.appStoreID == appStoreID ? $0.country : nil }
        guard let value = Mapping(appStoreID: appStoreID, country: country) else { return false }
        return set(mapping: value, name: name)
    }

    public static func removeAll() {
        WidgetState.widgetDefaults.removeObject(forKey: iconOverridesKey)
    }

    /// A source-only change refreshes widget artwork; legacy nil-source maps
    /// retain the same revision bytes used by earlier versions.
    public static var revision: String {
        let rendered = allMappings.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value.appStoreID)" + ($0.value.country.map { "@" + $0 } ?? "")
        }.joined(separator: "\u{1F}")
        return DirectLaunchIcons.stableHash(rendered)
    }

    private static func rawOverrides() -> [String: Any] {
        WidgetState.widgetDefaults.dictionary(forKey: iconOverridesKey) ?? [:]
    }

    private static func rawOverridesForWrite() -> [String: Any]? {
        guard let value = WidgetState.widgetDefaults.object(forKey: iconOverridesKey) else { return [:] }
        return value as? [String: Any]
    }

    private static func positiveID(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.intValue > 0, number == NSNumber(value: number.intValue) else { return nil }
        return number.intValue
    }

    private static func decodeStoredMapping(_ value: Any) -> Mapping? {
        if let id = positiveID(value) { return Mapping(appStoreID: id) }
        guard let fields = value as? [String: Any],
              Set(fields.keys).isSubset(of: ["appStoreID", "country"]),
              let rawID = fields["appStoreID"], let id = positiveID(rawID) else { return nil }
        if let rawCountry = fields["country"] {
            guard let country = rawCountry as? String,
                  AppStoreCountry.normalized(country) == country else { return nil }
            return Mapping(appStoreID: id, country: country)
        }
        return Mapping(appStoreID: id)
    }

    // MARK: - Observed slots

    /// Action names reported by real widget timelines, so the app can list them.
    ///
    /// The app cannot enumerate the Home Screen, and a widget's configuration is a
    /// set of `SystemShortcut`s the system holds and will not hand over — so the
    /// only way the app can learn what is on a widget is for the widget to say so.
    /// Names are recorded before artwork lookup, so a slow lookup cannot delay
    /// the app's candidate list. Gallery snapshots do not report configuration.
    private static let observedSlotsKey = "widget.directLaunchSlots"

    /// A cap on the remembered list.
    ///
    /// It grows as the user edits widgets and nothing else prunes it, so without a
    /// bound it would grow for the life of the install. A record the user has
    /// pinned is never dropped for age, because it is still the only thing tying
    /// that override to a visible row — see ``merge(_:into:)``.
    // A single widget can contain 100 actions. Leave room for multiple widgets
    // without pruning a full configuration from the correction screen.
    static let observedSlotLimit = 256

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

    /// Publish a real timeline's configured names before awaiting artwork.
    /// Existing artwork metadata remains intact until the completed lookup
    /// enriches it through `noteObservedSlots`; new names start without artwork.
    public static func noteConfiguredNames(_ names: [String], observedAt: Date = Date()) {
        guard WidgetState.widgetStateIsAvailable else { return }
        let existing = Dictionary(records().map { ($0.id, $0) }, uniquingKeysWith: {
            $0.updatedAt > $1.updatedAt ? $0 : $1
        })
        var seen = Set<String>()
        let incoming = names.compactMap { name -> SlotRecord? in
            guard let name = observedName(name), seen.insert(key(name)).inserted else { return nil }
            let previous = existing[key(name)]
            return SlotRecord(name: name, appStoreID: previous?.appStoreID,
                              source: previous?.source ?? DirectLaunchIcons.Source.none.rawValue,
                              updatedAt: observedAt)
        }
        noteObservedSlots(incoming)
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
        let incoming = incoming.compactMap { record -> SlotRecord? in
            guard let name = observedName(record.name) else { return nil }
            return SlotRecord(name: name, appStoreID: record.appStoreID,
                              source: record.source, updatedAt: record.updatedAt)
        }
        guard !incoming.isEmpty else { return }

        let existing = records()
        let merged = merge(incoming, into: existing)
        guard merged != existing else { return }
        writeRecords(merged)
    }

    private static func observedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 1_024,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return trimmed
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
        // Visit oldest first: the rows removed here are the historical names,
        // never the apps from the user's newest widget configuration.
        result.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
            return $0.id < $1.id
        }
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
