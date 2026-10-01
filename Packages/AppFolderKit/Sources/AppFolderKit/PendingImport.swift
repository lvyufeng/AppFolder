import Foundation

/// An app the user shared into AppFolder, waiting to be turned into a tile.
///
/// ## Why a queue and not a direct write
///
/// The share extension sees the App Store link. The main app owns
/// `library.json`. Letting the extension write the library directly would mean
/// two processes doing read-modify-write on one file with no lock —
/// ``FolderStore/save(_:)`` rewrites the whole document atomically, so the second
/// writer silently discards the first's changes. Atomic writes prevent reading a
/// half-written file; they do nothing about lost updates.
///
/// So the extension deposits a record here and the app picks it up. The app stays
/// the only writer of the library, which is the invariant the whole storage
/// design rests on.
///
/// ## Why one file per import
///
/// A single `pending-imports.json` would reintroduce the same race one level down:
/// append is read-modify-write too. One file per record makes both sides
/// single-operation — the extension only ever creates, the app only ever reads
/// and unlinks — so there is no window in which either can clobber the other.
public struct PendingImport: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    /// The App Store track id from the shared link.
    public let trackID: Int
    /// The storefront the link named, if it named one. A hint for resolving the
    /// app's metadata; see ``AppStoreLink/region``.
    public let region: String?
    /// Which folder the user chose in the share sheet.
    public let folderID: UUID
    /// When it arrived, so a stale queue is visible rather than silent.
    public let addedAt: Date

    public init(id: UUID = UUID(), trackID: Int, region: String?, folderID: UUID, addedAt: Date = .now) {
        self.id = id
        self.trackID = trackID
        self.region = region
        self.folderID = folderID
        self.addedAt = addedAt
    }
}

/// Reads and writes the pending-import queue in the shared container.
///
/// Deliberately not a `Store` in the ``FolderStore`` sense: it never reads or
/// writes the library, and the two sides of it do different things. The extension
/// only calls ``deposit(_:)``; the app only calls ``drain()``.
public struct PendingImportStore: Sendable {
    private let containerURL: URL?

    public init() {
        containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier)
    }

    /// The directory holding one file per pending import.
    private var directoryURL: URL? {
        containerURL?.appending(path: AppFolderShared.importsDirectoryName, directoryHint: .isDirectory)
    }

    /// Whether the shared container is reachable. False means a deposit would go
    /// nowhere the app can read — the same condition ``FolderStore`` reports.
    public var hasSharedContainer: Bool { containerURL != nil }

    /// Records one import. Returns whether it was written somewhere the app can see.
    ///
    /// The file name is the record's own id, so two deposits can never collide and
    /// neither has to read the directory first.
    @discardableResult
    public func deposit(_ item: PendingImport) -> Bool {
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

    /// Takes everything waiting, and removes it.
    ///
    /// Removing as it reads means a record is delivered once. An import that fails
    /// to become a tile afterwards is *not* retried, which is the right trade: the
    /// alternative is a queue that can never be cleared because one entry is
    /// permanently malformed, and the user's remedy — share it again — costs one tap.
    public func drain() -> [PendingImport] {
        guard let directoryURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        else { return [] }

        let decoder = FolderCoding.makeDecoder()
        var items: [PendingImport] = []

        for name in names where name.hasSuffix(".json") {
            let file = directoryURL.appending(path: name)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let item = try? decoder.decode(PendingImport.self, from: data)
            else { continue }
            items.append(item)
        }

        // Oldest first, so imports land in the order they were shared.
        return items.sorted { $0.addedAt < $1.addedAt }
    }
}