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
    /// Written without depending on the marker file, for the reason above: on a Mac
    /// the failure came from the search finding nothing, and on a device it may come
    /// from the marker. Both are ``DirectLaunchIcons/Source/miss``, and that — not
    /// which of the two produced it — is what the caller reads.
    @Test("Without a pin, an unresolvable name reports a miss")
    func missWithoutOverrideStillMisses() async {
        let resolved = await DirectLaunchIcons.resolve(name: "不存在的应用名zzz测试")
        #expect(resolved.source == .miss)
        #expect(resolved.appStoreID == nil)
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
        #expect(stored.count <= limit)
        #expect(stored.contains { $0.name == "OldPinned" }, "a pinned row must not be aged out")
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