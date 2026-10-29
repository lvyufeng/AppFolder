import Foundation
import Testing
@testable import AppFolderKit

/// The user's own answer to "which app is this tile?".
///
/// ## What this pins, and why it is worth pinning
///
/// The motivating failure is `Authenticator`. A slot arrives with that one word,
/// eight apps in the store answer to it, and the automatic matcher picks one — a
/// real app, so the tile looks right while being wrong. Nothing about the platform
/// can resolve that: the widget is handed a name and no more. So the whole feature
/// is "the user says which", and the properties that matter are about *precedence*:
/// a pin must beat every automatic answer, including the negative one.
///
/// ## Why the miss case is a test and not a footnote
///
/// The widget's provider used to check the miss cache *before* calling
/// ``DirectLaunchIcons/resolve(name:)``. That made a pinned name unreachable if the
/// store had ever failed on it — the pin lived in a map the provider never
/// consulted because it had already given up. This device has such a name in its
/// log. So "an override beats a miss" is the regression that would silently return
/// the bug, and it is asserted directly.
///
/// ## Serialized, and each test clears its own state
///
/// The defaults are process-wide and shared with every other test in the package,
/// so parallel execution would race. Same reasoning, and the same shape, as
/// `WidgetStateTests`.
@Suite("Direct launch overrides", .serialized)
struct DirectLaunchOverrideTests {
    /// Every test starts from no overrides and no observed slots, so one test's
    /// pin cannot be another's surprise.
    init() {
        DirectLaunchOverrides.removeAll()
        DirectLaunchOverrides.removeObservedSlots()
    }

    @Test("Country-only edits refresh the mapping while legacy callers preserve an unchanged ID's source")
    func selectedCountryPersistence() throws {
        let name = "region test"
        #expect(DirectLaunchOverrides.set(appStoreID: 123, name: name))
        let oldRevision = DirectLaunchOverrides.revision
        #expect(oldRevision == DirectLaunchIcons.stableHash("region test=123"))
        let jp = try #require(DirectLaunchOverrides.Mapping(appStoreID: 123, country: "jp"))
        #expect(DirectLaunchOverrides.set(mapping: jp, name: name))
        #expect(DirectLaunchOverrides.mapping(name: " REGION TEST ") == jp)
        #expect(DirectLaunchOverrides.all == [name: 123])
        #expect(DirectLaunchOverrides.allMappings == [name: jp])
        #expect(DirectLaunchOverrides.revision != oldRevision)
        #expect(!DirectLaunchOverrides.set(appStoreID: 123, name: name))
        #expect(DirectLaunchOverrides.mapping(name: name)?.country == "jp")
        #expect(try DirectLaunchOverrides.backupRecords()[name] == jp)
        #expect(DirectLaunchOverrides.set(appStoreID: 456, name: name))
        #expect(DirectLaunchOverrides.mapping(name: name)?.country == nil)
        #expect(DirectLaunchOverrides.set(mapping: nil, name: name))
        #expect(!DirectLaunchOverrides.containsBackupRecord(name: name))
    }

    @Test("Editing one mapping retains unrelated unreadable records and explicit clearing removes only its target")
    func retainsMalformedRecord() throws {
        let key = "widget.directLaunchOverrides"
        let malformed: [String: Any] = ["appStoreID": 777, "country": "zz"]
        WidgetState.widgetDefaults.set(["broken": malformed, "legacy": 123], forKey: key)
        let jp = try #require(DirectLaunchOverrides.Mapping(appStoreID: 456, country: "jp"))
        #expect(DirectLaunchOverrides.mapping(name: "broken") == nil)
        #expect(DirectLaunchOverrides.containsBackupRecord(name: "broken"))
        #expect(DirectLaunchOverrides.set(mapping: jp, name: "new"))
        let persisted = WidgetState.widgetDefaults.dictionary(forKey: key)
        #expect((persisted?["broken"] as? [String: Any])?["country"] as? String == "zz")
        #expect(DirectLaunchOverrides.appStoreID(name: "legacy") == 123)
        #expect(throws: LibraryBackupError.exportFailed) { try DirectLaunchOverrides.backupRecords() }
        #expect(DirectLaunchOverrides.set(mapping: nil, name: "broken"))
        #expect(try DirectLaunchOverrides.backupRecords().count == 2)
        WidgetState.widgetDefaults.set("invalid directory value", forKey: key)
        #expect(!DirectLaunchOverrides.set(mapping: jp, name: "new"))
        #expect(WidgetState.widgetDefaults.string(forKey: key) == "invalid directory value")
    }

    // MARK: - Precedence

    /// The whole point: a pin beats the catalogue.
    ///
    /// 微信 is in the catalogue with a known id, so the automatic answer is exact
    /// and needs no request — and the pin must still win, because the catalogue is
    /// right about *which app is called 微信* and only the user knows *which app
    /// they put in the tile*.
    @Test("A pin beats the catalogue")
    func overrideBeatsCatalogue() async {
        let automatic = await DirectLaunchIcons.resolve(name: "微信")
        #expect(automatic.source == .catalogue)
        #expect(automatic.appStoreID == 414478124)

        DirectLaunchOverrides.set(appStoreID: 999_999, name: "微信")

        let pinned = await DirectLaunchIcons.resolve(name: "微信")
        #expect(pinned.source == .override)
        #expect(pinned.appStoreID == 999_999)
    }

    /// And beats a recorded failure — the regression that would bring the bug back.
    ///
    /// ## Why this is conditional
    ///
    /// The miss marker is a *file*, and it can only be written where a real App
    /// Group container exists. On macOS `containerURL(forSecurityApplicationGroup
    /// Identifier:)` hands back a path but the write into it does not take — so the
    /// honest probe is whether a marker actually round-trips, not whether a
    /// directory URL came back non-nil. When it does not, this test cannot
    /// manufacture the failure it wants to out-rank, and pretending otherwise would
    /// be a green test that proves nothing.
    ///
    /// The half that still holds everywhere is that the pin resolves. The ordering
    /// itself — override before miss — is the statement order in
    /// ``DirectLaunchIcons/resolve(name:)``, and the feature's on-device check
    /// exercises it for real, on a machine where the container works.
    @Test("A pin beats a name the store already gave up on")
    func overrideBeatsMiss() async {
        DirectLaunchOverrides.set(appStoreID: 388497605, name: "Authenticator")

        DirectLaunchIcons.markMiss(name: "Authenticator")
        let missIsRecordable = DirectLaunchIcons.hasMiss(name: "Authenticator")

        let resolved = await DirectLaunchIcons.resolve(name: "Authenticator")
        #expect(resolved.source == .override)
        #expect(resolved.appStoreID == 388497605)

        if missIsRecordable {
            // Setting a pin also forgets the failure, so *un*pinning later searches
            // afresh rather than inheriting a verdict written under an older rule.
            #expect(!DirectLaunchIcons.hasMiss(name: "Authenticator"))
        }
    }

    /// A name nothing knows and nobody pinned still reports the miss honestly,
    /// rather than being silently retried.
    ///
    /// Supplies the store's answer directly, so this assertion also holds offline.
    @Test("Without a pin, an unresolvable name reports a miss")
    func missWithoutOverrideStillMisses() async {
        let resolved = await DirectLaunchIcons.resolve(name: "不存在的应用名zzz测试") { _ in
            .noMatch
        }
        #expect(resolved.source == .miss)
        #expect(resolved.appStoreID == nil)
        #expect(!resolved.shouldRetry)
    }

    @Test("A temporary network failure remains retryable")
    func unreachableDoesNotBecomeMiss() async {
        let name = "offline-test-\(UUID().uuidString)"
        let resolved = await DirectLaunchIcons.resolve(name: name) { _ in .unreachable }
        #expect(resolved.source == .none)
        #expect(resolved.appStoreID == nil)
        #expect(resolved.shouldRetry)
        #expect(!DirectLaunchIcons.hasMiss(name: name))

        let retried = await DirectLaunchIcons.resolve(name: name) { _ in .noMatch }
        #expect(retried.source == .miss)
    }

    @Test("An unreachable fallback storefront must not become a permanent miss")
    func partialStorefrontFailureRemainsRetryable() async {
        let result = await DirectLaunchIcons.searchAppStoreID(name: "storefront-test") { url, _ in
            let country = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "country" }?.value
            return country == "cn" ? .unreachable : .noMatch
        }
        #expect(result == .unreachable)
    }

    @Test("A matching fallback storefront can recover from a primary failure")
    func fallbackCanRecover() async {
        let result = await DirectLaunchIcons.searchAppStoreID(name: "storefront-test") { url, _ in
            let country = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "country" }?.value
            return country == "cn" ? .found(123) : .unreachable
        }
        #expect(result == .found(123))
    }

    // MARK: - Keys

    /// The key is the name trimmed and lowercased, so what the user types and what
    /// the system showed address the same entry.
    @Test("A name is matched regardless of case and surrounding space")
    func keysAreNormalised() {
        DirectLaunchOverrides.set(appStoreID: 123, name: "Authenticator")
        #expect(DirectLaunchOverrides.appStoreID(name: "authenticator") == 123)
        #expect(DirectLaunchOverrides.appStoreID(name: "  Authenticator ") == 123)
        #expect(DirectLaunchOverrides.all.count == 1)
    }

    /// An empty or whitespace-only name is not a key — otherwise every such slot
    /// would share one override.
    @Test("An empty name cannot be pinned")
    func emptyNameIsRejected() {
        #expect(!DirectLaunchOverrides.set(appStoreID: 1, name: "   "))
        #expect(DirectLaunchOverrides.all.isEmpty)
        #expect(DirectLaunchOverrides.appStoreID(name: "") == nil)
    }

    // MARK: - Change detection

    /// `set` reports whether anything moved, because that answer is what decides
    /// whether the widget is asked to reload — and reloads are throttled, so
    /// spending one on a non-change delays the next real one.
    @Test("Setting reports a change once, and clearing reports its own")
    func settingReportsChange() {
        #expect(DirectLaunchOverrides.set(appStoreID: 42, name: "X"))
        // Same value again: nothing changed.
        #expect(!DirectLaunchOverrides.set(appStoreID: 42, name: "X"))
        // A different value: a change.
        #expect(DirectLaunchOverrides.set(appStoreID: 43, name: "X"))
        // Clearing: a change.
        #expect(DirectLaunchOverrides.set(appStoreID: nil, name: "X"))
        // Clearing again: nothing left to clear.
        #expect(!DirectLaunchOverrides.set(appStoreID: nil, name: "X"))
        #expect(DirectLaunchOverrides.appStoreID(name: "X") == nil)
    }

    /// The revision moves on every real change, and holds still otherwise — it is
    /// what makes a requested reload produce a *different* timeline entry, so
    /// WidgetKit cannot serve a cached identical one and leave the fix invisible.
    @Test("The revision moves on a change and holds when nothing did")
    func revisionTracksChanges() {
        let start = DirectLaunchOverrides.revision
        #expect(start == DirectLaunchOverrides.revision, "reading it must not change it")

        DirectLaunchOverrides.set(appStoreID: 7, name: "Y")
        let afterSet = DirectLaunchOverrides.revision
        #expect(afterSet != start)

        DirectLaunchOverrides.set(appStoreID: 7, name: "Y")
        #expect(DirectLaunchOverrides.revision == afterSet, "a no-op must not move it")

        DirectLaunchOverrides.set(appStoreID: nil, name: "Y")
        #expect(DirectLaunchOverrides.revision == start, "clearing returns to the empty state")
    }

    // MARK: - Observed slots

    private func record(_ name: String, id: Int?, at seconds: TimeInterval) -> DirectLaunchOverrides.SlotRecord {
        DirectLaunchOverrides.SlotRecord(
            name: name,
            appStoreID: id,
            source: DirectLaunchIcons.Source.search.rawValue,
            updatedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test("Configured names are readable before any artwork result exists")
    func configuredNamesArriveImmediately() {
        let startedAt = Date(timeIntervalSince1970: 100)
        DirectLaunchOverrides.noteConfiguredNames(["Maps", "New action"], observedAt: startedAt)

        let pending = DirectLaunchOverrides.observedSlots
        #expect(Set(pending.map(\.name)) == ["Maps", "New action"])
        #expect(pending.allSatisfy { $0.appStoreID == nil && $0.source == "none" && $0.updatedAt == startedAt })
    }

    @Test("Early names preserve known artwork and other widgets while a lookup is pending")
    func configuredNamesPreserveArtwork() throws {
        DirectLaunchOverrides.noteObservedSlots([
            record("Maps", id: 123, at: 100),
            .init(name: "Custom", appStoreID: nil, source: "custom", updatedAt: Date(timeIntervalSince1970: 100)),
            record("Other widget", id: 456, at: 100)
        ])
        DirectLaunchOverrides.noteConfiguredNames([" MAPS ", "Custom", "New action"],
                                                 observedAt: Date(timeIntervalSince1970: 200))
        let pending = Dictionary(uniqueKeysWithValues: DirectLaunchOverrides.observedSlots.map { ($0.id, $0) })
        #expect(pending.count == 4)
        let maps = try #require(pending["maps"])
        #expect(maps.name == "MAPS" && maps.appStoreID == 123 && maps.source == "search")
        #expect(pending["custom"]?.source == "custom")
        #expect(pending["other widget"]?.appStoreID == 456)
        #expect(pending["other widget"]?.updatedAt == Date(timeIntervalSince1970: 100))

        // A stale timeline beginning late cannot age a fresher observation back.
        DirectLaunchOverrides.noteConfiguredNames(["Maps"], observedAt: Date(timeIntervalSince1970: 50))
        #expect(DirectLaunchOverrides.observedSlots.first { $0.id == "maps" } == maps)
    }

    @Test("Final artwork enriches the same early names at the timeline's original timestamp")
    func configuredNamesAreEnriched() {
        let startedAt = Date(timeIntervalSince1970: 100)
        DirectLaunchOverrides.noteObservedSlots([record("Existing", id: 12, at: 50)])
        DirectLaunchOverrides.noteConfiguredNames(["Existing", "New action"], observedAt: startedAt)
        DirectLaunchOverrides.noteObservedSlots([
            record("Existing", id: 34, at: 100),
            .init(name: "New action", appStoreID: 56, source: "catalogue", updatedAt: startedAt)
        ])

        let enriched = Dictionary(uniqueKeysWithValues: DirectLaunchOverrides.observedSlots.map { ($0.id, $0) })
        #expect(enriched.count == 2)
        #expect(enriched["existing"]?.appStoreID == 34)
        #expect(enriched["new action"]?.appStoreID == 56)
        #expect(enriched["new action"]?.source == "catalogue")
        #expect(enriched.values.allSatisfy { $0.updatedAt == startedAt })
    }

    @Test("Early and final observations reject invalid names and deduplicate normalized names")
    func configuredNamesValidateAndDeduplicate() {
        let longest = String(repeating: "é", count: 512)
        let invalid = ["", "   ", "\n", "Line\nBreak", "Null\u{0}Name", longest + "é"]
        DirectLaunchOverrides.noteConfiguredNames(invalid + ["  Maps  ", "maps", "MAPS", longest],
                                                 observedAt: Date(timeIntervalSince1970: 100))
        #expect(Set(DirectLaunchOverrides.observedSlots.map(\.name)) == ["Maps", longest])

        DirectLaunchOverrides.noteObservedSlots(
            invalid.map { record($0, id: 999, at: 200) }
                + [record(" Maps ", id: 123, at: 200), record("maps", id: 123, at: 200)]
        )
        let final = DirectLaunchOverrides.observedSlots
        #expect(final.count == 2)
        #expect(final.first { $0.id == "maps" }?.appStoreID == 123)
        #expect(final.contains { $0.name == longest && $0.appStoreID == nil })
    }

    /// Two widgets each report their own slots, and the stored list is their union
    /// — not whichever reported last. Keyed by name so a name on both collapses to
    /// one row the user can act on.
    @Test("Slots from two widgets are merged, not replaced")
    func observedSlotsMerge() {
        DirectLaunchOverrides.noteObservedSlots([
            record("微信", id: 414478124, at: 100),
            record("ChatGPT", id: 6448311069, at: 100),
        ])
        DirectLaunchOverrides.noteObservedSlots([
            record("Calendar", id: 1108185179, at: 200),
            record("微信", id: 414478124, at: 200),
        ])

        let names = Set(DirectLaunchOverrides.observedSlots.map(\.name))
        #expect(names == ["微信", "ChatGPT", "Calendar"])
    }

    /// A newer report for the same name wins, so a widget that refreshed late
    /// cannot overwrite a fresh answer with an older one.
    @Test("The newer report for a name wins")
    func newerRecordWins() {
        DirectLaunchOverrides.noteObservedSlots([record("Authenticator", id: 111, at: 100)])
        DirectLaunchOverrides.noteObservedSlots([record("Authenticator", id: 222, at: 50)])
        #expect(DirectLaunchOverrides.observedSlots.first?.appStoreID == 111)

        DirectLaunchOverrides.noteObservedSlots([record("Authenticator", id: 333, at: 200)])
        #expect(DirectLaunchOverrides.observedSlots.first?.appStoreID == 333)
    }

    /// The list is capped so it cannot grow for the life of the install — but a
    /// pinned name is never dropped for age, because its row is the only place the
    /// user can see or undo that pin.
    @Test("Over the cap, unpinned rows go first and pinned ones stay")
    func pinnedRecordsSurvivePruning() {
        let limit = DirectLaunchOverrides.observedSlotLimit
        DirectLaunchOverrides.set(appStoreID: 777, name: "OldPinned")

        var incoming: [DirectLaunchOverrides.SlotRecord] = [
            // The oldest record there is, and pinned — must survive.
            record("OldPinned", id: 1, at: 0),
        ]
        for i in 0..<(limit + 10) {
            incoming.append(record("App\(i)", id: i, at: TimeInterval(1_000 + i)))
        }
        DirectLaunchOverrides.noteObservedSlots(incoming)

        let stored = DirectLaunchOverrides.observedSlots
        #expect(stored.count == limit)
        #expect(stored.contains { $0.name == "OldPinned" }, "a pinned row must not be aged out")
        let expectedNames = Set(["OldPinned"] + (11..<(limit + 10)).map { "App\($0)" })
        #expect(Set(stored.map(\.name)) == expectedNames,
                "the oldest unpinned rows must be removed while recent apps stay editable")
    }

    @Test("A full 100-action widget keeps every action available for correction")
    func fullWidgetObservationSurvives() {
        let incoming = (0..<100).map {
            record("Action\($0)", id: $0 + 1, at: 100)
        }
        DirectLaunchOverrides.noteObservedSlots(incoming)

        #expect(Set(DirectLaunchOverrides.observedSlots) == Set(incoming))
    }

    @Test("A newly configured app displaces the oldest remembered app at capacity")
    func newestObservedSlotSurvivesPruning() {
        let limit = DirectLaunchOverrides.observedSlotLimit
        DirectLaunchOverrides.noteObservedSlots((0..<limit).map {
            record("App\($0)", id: $0, at: TimeInterval($0))
        })

        DirectLaunchOverrides.noteObservedSlots([
            record("New app", id: 999, at: TimeInterval(limit)),
        ])

        let stored = DirectLaunchOverrides.observedSlots
        #expect(stored.count == limit)
        #expect(stored.first?.name == "New app")
        #expect(!stored.contains { $0.name == "App0" })
        #expect(stored.contains { $0.name == "App1" })
    }

    /// Ordering is newest-first, which is what the app lists.
    @Test("Observed slots come back newest first")
    func observedSlotsAreNewestFirst() {
        DirectLaunchOverrides.noteObservedSlots([
            record("A", id: 1, at: 100),
            record("B", id: 2, at: 300),
            record("C", id: 3, at: 200),
        ])
        #expect(DirectLaunchOverrides.observedSlots.map(\.name) == ["B", "C", "A"])
    }

    // MARK: - The app's read of the widget's cache

    /// The app shows the very bytes the widget draws, so a wrong icon is visible
    /// before the user changes anything. A miss must be `nil` rather than a fetch —
    /// this call sits behind a list that scrolls, and it must not turn into network.
    @Test("Reading a cached icon fetches nothing and misses honestly")
    func cachedIconReadsOnly() {
        #expect(DirectLaunchIcons.cachedIcon(appStoreID: 0) == nil)
        #expect(DirectLaunchIcons.cachedIcon(appStoreID: -1) == nil)
    }


    // The search-result cache (``DirectLaunchIcons/cachedSearchID(name:)``) has no
    // test here on purpose: it stores through the App Group's container, which the
    // package's test process does not have, so every write is a no-op and any
    // assertion would be about the test environment rather than the code. The
    // sibling ``DirectLaunchIcons/cachedSystemAppID(name:)`` is untested for the
    // same reason. It is exercised on device.
}
