import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Reads and writes the folder library.
///
/// The app owns writes; the widget only reads. Both go through this type so the
/// on-disk format has exactly one definition.
///
/// Storage has two backends, tried in order:
///
/// 1. The App Group container. This is the real one — it is the only location
///    both processes can see.
/// 2. `UserDefaults` keyed by ``AppFolderShared/fallbackDefaultsKey``.
///
/// (2) is not a real fallback: without an App Group the app and the extension do
/// not share a defaults domain either, so a widget built this way renders empty.
/// It exists so the app itself still runs and can be used for editing when it is
/// signed with a Personal Team, which cannot provision App Groups.
public struct FolderStore: Sendable {
    private let containerURL: URL?

    public init() {
        containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier)
    }

    /// Whether the shared container is reachable. False means widgets will not
    /// see anything written here.
    public var hasSharedContainer: Bool { containerURL != nil }

    private var fileURL: URL? {
        containerURL?.appending(path: AppFolderShared.libraryFileName)
    }

    // MARK: - Reading

    public func load() -> FolderLibrary {
        let fallback = fallbackLoad()

        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return LibraryRepair.repair(fallback)
        }
        do {
            let decoded = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: data)
            // Both copies exist, which means a previous `save` took the
            // `UserDefaults` path while the group still holds an older file. Take
            // the newer one rather than the group's by default: the group's copy
            // is the one that was abandoned mid-fork, and preferring it would
            // discard everything the user did while the fork was in effect —
            // silently, on the launch that was supposed to fix things.
            return LibraryRepair.repair(Self.newer(fallback, decoded))
        } catch {
            // A library we cannot decode is worse than no library: keep the
            // unreadable bytes around so the failure is diagnosable, and start
            // clean rather than crashing the widget.
            let quarantine = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: quarantine)
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            return LibraryRepair.repair(fallback)
        }
    }

    /// Whichever of two copies of the library was touched more recently.
    ///
    /// Internal rather than private so the tie-break can be tested without a real
    /// container — see `FolderStoreTests`. The decision is small but it is the one
    /// that either recovers the user's library or discards it.
    static func newer(_ a: FolderLibrary, _ b: FolderLibrary) -> FolderLibrary {
        freshness(b) > freshness(a) ? b : a
    }

    /// How recently a library was touched, for choosing between two copies.
    ///
    /// The newest thing in it, across folders and the install probe — there is no
    /// single top-level timestamp, and the folders are what the user actually
    /// edits.
    private static func freshness(_ library: FolderLibrary) -> Date {
        let folderDates = library.folders.map(\.updatedAt)
        let probe = library.lastProbeAt.map { [$0] } ?? []
        return (folderDates + probe).max() ?? .distantPast
    }

    private func fallbackLoad() -> FolderLibrary {
        guard let data = UserDefaults.standard.data(forKey: AppFolderShared.fallbackDefaultsKey) else {
            return .empty
        }
        return (try? FolderCoding.makeDecoder().decode(FolderLibrary.self, from: data)) ?? .empty
    }

    // MARK: - Writing

    /// Persists the library, preferring the App Group.
    ///
    /// Returns whether the library reached the **shared** container — the one the
    /// widget, the share extension and the intents read. `false` means it did
    /// not, and callers surface that rather than letting the app drift away from
    /// its own widget in silence.
    ///
    /// ## Why the fallback is now the last resort, not the first
    ///
    /// The `UserDefaults` backend exists for one case: a build with no App Group
    /// entitlement, where there is genuinely nowhere shared to write. It used to
    /// be taken on *any* write error — so a container that was momentarily
    /// unreachable, or a full disk, produced a permanent fork. The app went on
    /// reading and writing its own private copy while the widget and the share
    /// extension kept reading the group's `library.json`, frozen at the instant
    /// of the failure — and nothing surfaced, because the app's own screen still
    /// worked.
    ///
    /// That fork is not hypothetical. On 2026-10-02 it was the reason 分享 App
    /// stopped adding anything: the extension was listing folders from a group
    /// library a day out of date, depositing against folder ids the app no longer
    /// had, and ``LibraryModel/drainSharedImports()`` was dropping every one of
    /// them. A write that does not reach the group is a failure, and it is
    /// reported as one.
    @discardableResult
    public func save(_ library: FolderLibrary) -> Bool {
        var library = library
        library.schemaVersion = FolderLibrary.currentSchemaVersion

        guard let encoded = try? FolderCoding.makeEncoder().encode(library) else {
            return false
        }

        guard let fileURL else {
            // No App Group at all — the Personal Team case this fallback is for.
            // The app still runs and can be edited; the widget cannot see any of
            // it, and the caller is told so.
            UserDefaults.standard.set(encoded, forKey: AppFolderShared.fallbackDefaultsKey)
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomic: a widget can be reading this file while the app writes.
            try encoded.write(to: fileURL, options: .atomic)
            return true
        } catch {
            // The container exists and the write failed. Deliberately no
            // `UserDefaults` fallback here: forking is what hid this last time,
            // and the last good copy is still on disk for the user to come back
            // to once the underlying problem is fixed.
            return false
        }
    }

    /// Whether the shared container can be written right now, by writing to it.
    ///
    /// A real round trip rather than a check for the container's existence.
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` reports a container
    /// that exists but cannot be written — a stale install record, a revoked
    /// capability — and the UI would then promise 可用 while every save silently
    /// failed behind it.
    public func isSharedStorageWritable() -> Bool {
        guard let directory = fileURL?.deletingLastPathComponent() else { return false }
        let probe = directory.appending(path: ".write-probe-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: probe)
            try? FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }
}
