import CryptoKit
import Darwin
import Foundation

/// The requested UUID's state, independent of failures in unrelated groups.
public enum SavedGroupReadResult: Sendable, Equatable {
    case loaded(SavedGroup)
    case missing
    case unreadable
    case unavailable
}

/// A read-only view of the library. Missing first-use directories are empty;
/// unreadable directories and individual records are reported separately.
public struct SavedGroupReadSnapshot: Sendable, Equatable {
    public let groups: [SavedGroup]
    public let unreadableCount: Int
    public let directoryFailure: Bool
    /// Whether an App Group directory was supplied, not a writeability check.
    public let isAvailable: Bool

    public var hasReadFailures: Bool { directoryFailure || unreadableCount > 0 }
}

/// Layouts are durable app-owned data shared with the widget. System action
/// tokens are never serialized here, and an unavailable group has no fallback.
public enum SavedGroupStore {
    private static let repository: SavedGroupRepository = {
        #if os(iOS)
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
        )
        return SavedGroupRepository(directory: container?.appendingPathComponent("SavedGroups", isDirectory: true))
        #else
        return SavedGroupRepository(directory: nil)
        #endif
    }()

    public static var isAvailable: Bool { repository.isAvailable }
    public static var snapshot: SavedGroupReadSnapshot { repository.snapshot }
    public static var all: [SavedGroup] { repository.all }
    public static func group(id: UUID) -> SavedGroup? { repository.group(id: id) }
    public static func readResult(id: UUID) -> SavedGroupReadResult { repository.readResult(id: id) }
    public static var revision: String { repository.revision }
    static func containsBackupRecord(id: UUID) -> Bool { repository.containsRecord(id: id) }
    static func backupRecords() throws -> [SavedGroup] { try repository.backupRecords() }

    @discardableResult
    public static func save(_ group: SavedGroup) -> Bool { repository.save(group) }

    @discardableResult
    public static func remove(id: UUID) -> Bool { repository.remove(id: id) }
}

/// Independent UUID files make an edit atomic without rewriting another group.
/// The injected directory keeps host tests away from any real app data.
struct SavedGroupRepository: Sendable {
    let directory: URL?
    // Two hundred 2 KiB website addresses plus titles and artwork references.
    static let maximumFileBytes = 1_024 * 1_024
    var isAvailable: Bool { directory != nil }

    func containsRecord(id: UUID) -> Bool {
        guard let url = url(id: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func backupRecords() throws -> [SavedGroup] {
        try LibraryBackupRecordFiles.jsonFiles(in: directory, maximumRecords: LibraryBackup.maximumGroups).map { url in
            guard let group = read(url), url.lastPathComponent == filename(id: group.id) else {
                throw LibraryBackupError.exportFailed
            }
            return group
        }
    }

    func group(id: UUID) -> SavedGroup? {
        if case .loaded(let group) = readResult(id: id) { return group }
        return nil
    }

    func readResult(id: UUID) -> SavedGroupReadResult {
        guard let directory else { return .unavailable }
        // URL.path preserves an encoded NUL as the literal text "%00" on
        // Foundation, so inspect the URL's decoded spelling as well as its path.
        guard directory.isFileURL, !directory.path.utf8.contains(0),
              directory.absoluteString.removingPercentEncoding?.utf8.contains(0) == false,
              let url = url(id: id) else { return .unreadable }
        // Use the actual POSIX failure rather than a broad Cocoa "not found"
        // category: ENOTDIR, EACCES and ELOOP are unreadable, never missing.
        // Nonblocking/no-follow also prevents a damaged FIFO or symlink record
        // from hanging the help page or resolving to some other group's file.
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return errno == ENOENT ? .missing : .unreadable }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= Self.maximumFileBytes else { return .unreadable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.read(upToCount: Self.maximumFileBytes + 1),
              !data.isEmpty, data.count <= Self.maximumFileBytes,
              let group = try? JSONDecoder().decode(SavedGroup.self, from: data), group.id == id else { return .unreadable }
        return .loaded(group)
    }

    var all: [SavedGroup] { snapshot.groups }

    var snapshot: SavedGroupReadSnapshot {
        guard let directory else {
            return .init(groups: [], unreadableCount: 0, directoryFailure: false, isAvailable: false)
        }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]
            ).filter {
                $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil
            }
        } catch CocoaError.fileReadNoSuchFile {
            // Saving the first group creates this directory. Do not create it
            // just to read an empty library.
            return .init(groups: [], unreadableCount: 0, directoryFailure: false, isAvailable: true)
        } catch {
            return .init(groups: [], unreadableCount: 0, directoryFailure: true, isAvailable: true)
        }
        var groups: [SavedGroup] = []
        var unreadableCount = 0
        for url in files {
            guard let group = read(url), url.lastPathComponent == filename(id: group.id) else {
                unreadableCount += 1
                continue
            }
            groups.append(group)
        }
        groups.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        return .init(groups: groups, unreadableCount: unreadableCount, directoryFailure: false, isAvailable: true)
    }

    var revision: String {
        let content = all.sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString):\($0.revision)" }.joined(separator: "\n")
        return SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// True means that the complete requested layout is persisted, including a
    /// no-op save. Invalid input and write failures leave the prior file intact.
    @discardableResult
    func save(_ group: SavedGroup) -> Bool {
        FolderCoverAssetCoordinator.withLock {
            guard let directory, let url = url(id: group.id), group.isValid else { return false }
            let assets = FolderCoverAssetRepository(
                directory: directory.deletingLastPathComponent().appendingPathComponent("FolderCoverAssets", isDirectory: true),
                groupDirectory: directory
            )
            // Promotion happens before the layout write. A new layout must
            // never make a reference durable before the artwork is durable.
            guard group.coverAssetIDs.allSatisfy({ assets.icon(id: $0) != nil }) else { return false }
            let group = group.normalized
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                // Date's native reference epoch retains its exact floating-point
                // value; converting to Unix seconds can lose a fraction on reload.
                let data = try encoder.encode(group)
                guard data.count <= Self.maximumFileBytes else { return false }
                if readData(url) == data { return true }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                return readData(url) == data
            } catch { return false }
        }
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        FolderCoverAssetCoordinator.withLock {
            guard let url = url(id: id) else { return false }
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                return true
            } catch { return false }
        }
    }

    private func filename(id: UUID) -> String { id.uuidString.lowercased() + ".json" }
    private func url(id: UUID) -> URL? { directory?.appendingPathComponent(filename(id: id), isDirectory: false) }

    private func readData(_ url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= Self.maximumFileBytes,
              let data = try? Data(contentsOf: url), data.count <= Self.maximumFileBytes else { return nil }
        return data
    }

    private func read(_ url: URL) -> SavedGroup? {
        guard let data = readData(url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(SavedGroup.self, from: data)
    }
}
