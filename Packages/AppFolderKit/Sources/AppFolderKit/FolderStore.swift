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
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return LibraryRepair.repair(fallbackLoad())
        }
        do {
            let decoded = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: data)
            return LibraryRepair.repair(decoded)
        } catch {
            // A library we cannot decode is worse than no library: keep the
            // unreadable bytes around so the failure is diagnosable, and start
            // clean rather than crashing the widget.
            let quarantine = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: quarantine)
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            return .empty
        }
    }

    private func fallbackLoad() -> FolderLibrary {
        guard let data = UserDefaults.standard.data(forKey: AppFolderShared.fallbackDefaultsKey) else {
            return .empty
        }
        return (try? FolderCoding.makeDecoder().decode(FolderLibrary.self, from: data)) ?? .empty
    }

    // MARK: - Writing

    /// Persists the library and asks the widget to redraw.
    @discardableResult
    public func save(_ library: FolderLibrary) -> Bool {
        var library = library
        library.schemaVersion = FolderLibrary.currentSchemaVersion

        let encoded = try? FolderCoding.makeEncoder().encode(library)

        if let fileURL, let encoded {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                // Atomic: a widget can be reading this file while the app writes.
                try encoded.write(to: fileURL, options: .atomic)
            } catch {
                return false
            }
        }

        UserDefaults.standard.set(encoded, forKey: AppFolderShared.fallbackDefaultsKey)
        return fileURL != nil
    }
}
