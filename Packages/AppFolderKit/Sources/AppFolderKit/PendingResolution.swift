import Foundation

/// An app the user shared in, which could not be turned into a tile on its own.
///
/// ## Why this exists instead of a guessed tile
///
/// The share flow can resolve an app the catalogue knows completely: the entry
/// carries a **verified** scheme. For anything else all the App Store can supply is
/// a name, an icon and a bundle id — and the scheme has to be guessed, by
/// ``SchemeGuess``, whose own documentation says its ordering is "a coin toss and
/// should not be trusted".
///
/// The old behaviour was to take the first guess and save it as a tile. That
/// produced, for every app outside the catalogue, a tile with roughly even odds of
/// doing nothing when tapped — and the failure was invisible on the Home Screen, so
/// the user had no way to tell a guess that worked from one that did not. 票牛 is
/// the worked example: the guess was `pner://`, the real scheme is
/// `piaoniu://home`, and nothing in the bundle id or the store name leads from one
/// to the other.
///
/// So a stranger does not become a tile. It becomes *this* — a record saying "the
/// user shared this app, here is where it goes, and nobody has yet established how
/// to open it" — and it waits for a confirmation, which is one tap in the editor
/// where ``SchemeEntryView`` can try candidates for real.
///
/// ## Why it is not a tile that is merely hidden
///
/// A hidden tile would still be a tile: it would need a scheme, which is the thing
/// that is unknown. There is nothing to hide until the question is answered, which
/// is what makes this a queue of unresolved *questions* rather than a set of
/// withheld tiles.
///
/// ## Why it carries only a track id
///
/// The name, the icon and the bundle id all have to be looked up, and the lookup
/// can fail for a reason that has nothing to do with the App: no network. Storing
/// the resolved metadata would mean a lookup failure at import time loses the
/// import — which is exactly what the old code did, silently, because
/// ``PendingImportStore/drain()`` removes records as it reads them. Keeping only
/// what the link itself carried means an offline share **waits** instead of being
/// dropped, and the editor resolves the metadata when it can actually reach the
/// App Store.
public struct PendingResolution: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    /// The App Store track id from the shared link.
    public let trackID: Int
    /// The storefront the link named, if it named one. A hint for the lookup —
    /// see ``AppStoreLink/region``.
    public let region: String?
    /// Which folder the user chose in the share sheet, so confirming lands the
    /// tile where they asked for it rather than in whichever folder is first.
    ///
    /// Best-effort, and the reader must tolerate a miss: the folder can be deleted
    /// between the share and the confirmation, and that is a reason to fall back,
    /// never a reason to drop the record.
    public let folderID: UUID
    /// When it arrived, so the queue can be shown oldest-first.
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        trackID: Int,
        region: String?,
        folderID: UUID,
        addedAt: Date = .now
    ) {
        self.id = id
        self.trackID = trackID
        self.region = region
        self.folderID = folderID
        self.addedAt = addedAt
    }
}

/// Reads and writes the queue of shared-in apps waiting for a launch target.
///
/// Same shape as ``PendingImportStore``, and for the same reason: one file per
/// record, so neither side ever does read-modify-write on a shared document. The
/// difference is who writes. ``PendingImportStore`` is written by the share
/// extension and drained by the app; this one is written *and* drained by the app,
/// because the decision it records — "this app cannot be resolved automatically" —
/// is one only the app's catalogue lookup can make.
///
/// The `remove(of:)` / `drain()` pair is what keeps the two roles honest: the badge
/// has to be able to count the queue without consuming it, and the editor has to
/// consume one entry at a time as the user works through them.
public struct PendingResolutionStore: Sendable {
    private let directoryURL: URL?

    public init() {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier)
        directoryURL = container?
            .appending(path: AppFolderShared.pendingResolutionsDirectoryName, directoryHint: .isDirectory)
    }

    /// Records one unresolved share.
    @discardableResult
    public func deposit(_ item: PendingResolution) -> Bool {
        guard let directoryURL else { return false }
        guard let data = try? FolderCoding.makeEncoder().encode(item) else { return false }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: directoryURL.appending(path: "\(item.id.uuidString).json"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Everything waiting, oldest first, without removing anything.
    ///
    /// Non-destructive on purpose. The badge and the editor both need to *look* at
    /// the queue, and a look that consumes would make the count depend on how many
    /// times it was read. Entries leave through ``remove(_:)``, when the user has
    /// actually made a decision.
    public func all() -> [PendingResolution] {
        guard let directoryURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        else { return [] }

        let decoder = FolderCoding.makeDecoder()
        var items: [PendingResolution] = []
        for name in names where name.hasSuffix(".json") {
            let file = directoryURL.appending(path: name)
            guard let data = try? Data(contentsOf: file),
                  let item = try? decoder.decode(PendingResolution.self, from: data)
            else { continue }
            items.append(item)
        }
        return items.sorted { $0.addedAt < $1.addedAt }
    }

    /// How many shares are waiting. What the app icon's badge shows.
    public func count() -> Int {
        guard let directoryURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        else { return 0 }
        // Counted by file name rather than by decoding: the badge is read on every
        // foreground, and a number that is one parse away from the truth is worth
        // not paying for. A malformed file would then be counted and never shown,
        // which is a cosmetic error in the safe direction — under-counting would
        // hide a waiting app.
        return names.filter { $0.hasSuffix(".json") }.count
    }

    /// Drops one entry, once the user has confirmed or discarded it.
    ///
    /// By id rather than by re-encoding the record, so a record this build cannot
    /// fully decode can still be cleared. The alternative is an entry that can
    /// never leave the queue and a badge that never goes down.
    public func remove(_ id: UUID) {
        guard let directoryURL else { return }
        let file = directoryURL.appending(path: "\(id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    /// What the pending queue would look like from a store pointed at `root`.
    ///
    /// Exists so the tests can drive the real encode/decode/sort/remove logic
    /// against a temporary directory instead of the App Group container, which a
    /// test host cannot reach.
    public init(directoryURL: URL?) {
        self.directoryURL = directoryURL
    }
}