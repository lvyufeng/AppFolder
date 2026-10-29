import CryptoKit
import Foundation

public enum FolderCoverAssetError: Error, Sendable, Equatable {
    case storageUnavailable, invalidArtwork, invalidGroup, writeFailed, readFailed, closedSession
    case missingAsset(FolderCoverAssetID)
}

/// The app is the only writer. This lock serializes its group/asset writes,
/// editor leases and backup operations; it makes no cross-process lock claim.
enum FolderCoverAssetCoordinator {
    private static let lock = NSRecursiveLock()
    nonisolated(unsafe) private static var leases: [String: [UUID: Set<FolderCoverAssetID>]] = [:]

    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    static func retain(_ ids: Set<FolderCoverAssetID>, token: UUID, scope: String) {
        withLock { leases[scope, default: [:]][token] = ids }
    }

    static func release(token: UUID, scope: String) {
        withLock {
            leases[scope]?.removeValue(forKey: token)
            if leases[scope]?.isEmpty == true { leases.removeValue(forKey: scope) }
        }
    }

    static func retainedIDs(scope: String) -> Set<FolderCoverAssetID> {
        withLock {
            let retained = leases[scope] ?? [:]
            return retained.values.reduce(into: Set<FolderCoverAssetID>()) { $0.formUnion($1) }
        }
    }
}

/// Keeps assets available for an editor or an undo-delete stack. Releasing a
/// lease does not itself delete files. The owner closes it when its history ends.
public final class FolderCoverAssetLease: @unchecked Sendable {
    private let scope: String
    private let token = UUID()
    private var closed = false

    init(repository: FolderCoverAssetRepository, retaining ids: Set<FolderCoverAssetID>) throws {
        guard let scope = repository.scope else { throw FolderCoverAssetError.storageUnavailable }
        self.scope = scope
        FolderCoverAssetCoordinator.retain(ids, token: token, scope: scope)
    }

    public func update(retaining ids: Set<FolderCoverAssetID>) {
        FolderCoverAssetCoordinator.withLock {
            guard !closed else { return }
            FolderCoverAssetCoordinator.retain(ids, token: token, scope: scope)
        }
    }

    public func close() {
        FolderCoverAssetCoordinator.withLock {
            guard !closed else { return }
            closed = true
            FolderCoverAssetCoordinator.release(token: token, scope: scope)
        }
    }

    deinit { close() }
}

public enum FolderCoverAssetStore {
    static let repository: FolderCoverAssetRepository = {
        #if os(iOS)
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier)
        return .init(directory: root?.appendingPathComponent("FolderCoverAssets", isDirectory: true),
                     groupDirectory: root?.appendingPathComponent("SavedGroups", isDirectory: true))
        #else
        return .init(directory: nil, groupDirectory: nil)
        #endif
    }()

    public static var isAvailable: Bool { repository.isAvailable }

    public static func icon(id: FolderCoverAssetID, maxSide: Int = 256) -> CustomIcon? {
        repository.icon(id: id).flatMap { $0.limited(to: maxSide) }
    }

    public static func variants(for cover: FolderCover?, maxSide: Int = 256) -> CustomIconVariants? {
        guard let cover else { return nil }
        let result = CustomIconVariants(standard: cover.standard.flatMap { icon(id: $0, maxSide: maxSide) },
                                        dark: cover.dark.flatMap { icon(id: $0, maxSide: maxSide) })
        return result.isValid ? result : nil
    }

    public static func lease(retaining ids: Set<FolderCoverAssetID>) throws -> FolderCoverAssetLease {
        try FolderCoverAssetLease(repository: repository, retaining: ids)
    }

    @discardableResult
    public static func collectGarbage() throws -> Int { try repository.collectGarbage() }
}

extension CustomIcon {
    func limited(to maxSide: Int) -> CustomIcon? {
        maxSide >= Self.maximumPhotoSide ? self : thumbnail(maxSide: maxSide)
    }
}

/// Immutable, bounded assets. Content identity includes kind, text, background
/// and original PNG bytes; identical assets can safely be shared by group copies.
struct FolderCoverAssetRepository: Sendable {
    let directory: URL?
    let groupDirectory: URL?
    var isAvailable: Bool { directory != nil }
    var scope: String? { directory?.standardizedFileURL.path }
    static let maximumRecordBytes = (CustomIcon.maximumPhotoBytes + 2) / 3 * 4 + 8_192

    static func id(for icon: CustomIcon) -> FolderCoverAssetID? {
        guard let data = canonicalData(icon) else { return nil }
        var hash = SHA256()
        hash.update(data: Data("appfolder.folder-cover.v1\n".utf8))
        hash.update(data: data)
        return FolderCoverAssetID(rawValue: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private static func canonicalData(_ icon: CustomIcon) -> Data? {
        guard icon.isValid else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(icon), data.count <= maximumRecordBytes else { return nil }
        return data
    }

    func contains(id: FolderCoverAssetID) -> Bool {
        url(id).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func icon(id: FolderCoverAssetID) -> CustomIcon? {
        guard let url = url(id), let data = readData(url),
              let icon = try? JSONDecoder().decode(CustomIcon.self, from: data),
              Self.id(for: icon) == id else { return nil }
        return icon
    }

    @discardableResult
    func save(_ icon: CustomIcon, id: FolderCoverAssetID) -> Bool {
        FolderCoverAssetCoordinator.withLock {
            guard let directory, let url = url(id), Self.id(for: icon) == id,
                  let data = Self.canonicalData(icon) else { return false }
            if contains(id: id) { return self.icon(id: id) == icon }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                return self.icon(id: id) == icon
            } catch { return false }
        }
    }

    /// Low-level rollback primitive. The caller must first establish ownership
    /// and protect durable group references and active leases under the lock.
    @discardableResult
    func remove(id: FolderCoverAssetID) -> Bool {
        FolderCoverAssetCoordinator.withLock {
            guard let url = url(id) else { return false }
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                return !contains(id: id)
            } catch { return false }
        }
    }

    func protectedAssetIDs() throws -> Set<FolderCoverAssetID> {
        try FolderCoverAssetCoordinator.withLock {
            guard let groupDirectory, let scope else { throw FolderCoverAssetError.storageUnavailable }
            // Unlike `all`, this throws if even one group cannot be read. An
            // unreadable layout may still reference assets that must survive.
            let groups = try SavedGroupRepository(directory: groupDirectory).backupRecords()
            return groups.reduce(into: FolderCoverAssetCoordinator.retainedIDs(scope: scope)) {
                $0.formUnion($1.coverAssetIDs)
            }
        }
    }

    @discardableResult
    func collectGarbage() throws -> Int {
        try FolderCoverAssetCoordinator.withLock {
            let protected = try protectedAssetIDs()
            guard let directory else { throw FolderCoverAssetError.storageUnavailable }
            let files: [URL]
            do { files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) }
            catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return 0 }
            // Finish every potentially failing scan before deleting any asset.
            var candidates: [FolderCoverAssetID] = []
            for file in files where file.pathExtension == "json" {
                guard let id = FolderCoverAssetID(rawValue: file.deletingPathExtension().lastPathComponent),
                      !protected.contains(id) else { continue }
                let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw FolderCoverAssetError.readFailed }
                candidates.append(id)
            }
            var removed = 0
            for id in candidates {
                guard remove(id: id) else { throw FolderCoverAssetError.writeFailed }
                removed += 1
            }
            return removed
        }
    }

    private func url(_ id: FolderCoverAssetID) -> URL? {
        directory?.appendingPathComponent(id.rawValue + ".json", isDirectory: false)
    }

    private func readData(_ url: URL) -> Data? {
        guard let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let count = attributes.fileSize, count > 0, count <= Self.maximumRecordBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumRecordBytes + 1),
              !data.isEmpty, data.count <= Self.maximumRecordBytes else { return nil }
        return data
    }
}
