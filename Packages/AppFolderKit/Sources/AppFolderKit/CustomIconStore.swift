import CryptoKit
import Foundation
import Darwin

/// Durable custom artwork shared by the app and widget. Only the app writes it.
public enum CustomIconStore {
    private static let repository: CustomIconRepository = {
        #if os(iOS)
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
        )
        return CustomIconRepository(directory: container?.appendingPathComponent("CustomIcons", isDirectory: true))
        #else
        // Host-side tests use an explicitly injected temporary directory.
        return CustomIconRepository(directory: nil)
        #endif
    }()

    public static var isAvailable: Bool { repository.isAvailable }
    public static func icon(name: String) -> CustomIcon? { repository.icon(name: name) }
    public static func variants(name: String) -> CustomIconVariants? { repository.variants(name: name) }
    public static var all: [String: CustomIconVariants] { repository.all }
    public static var displayNames: [String: String] { repository.displayNames }
    public static var revision: String { repository.revision }
    static func containsBackupRecord(name: String) -> Bool { repository.containsRecord(name: name) }
    static func backupRecords() throws -> [LibraryBackup.IconRecord] { try repository.backupRecords() }
    static func backupIcon(name: String) throws -> CustomIconVariants? { try repository.backupIcon(name: name) }

    /// Returns true when the requested state is on disk, including a successful no-op.
    /// Compatibility replacement: a non-nil icon replaces the whole record with
    /// standard artwork and clears any dark override. Nil clears both variants.
    /// New editors should use setVariants to preserve the untouched appearance.
    @discardableResult
    public static func set(_ icon: CustomIcon?, name: String) -> Bool { repository.set(icon, name: name) }

    /// The pair is validated and written atomically. Nil removes the whole record;
    /// an empty non-nil pair is invalid and leaves existing artwork untouched.
    @discardableResult
    public static func setVariants(_ variants: CustomIconVariants?, name: String) -> Bool {
        repository.setVariants(variants, name: name)
    }

    public static func photoData(for icon: CustomIcon) -> Data? { icon.pngData }
}

/// A file per name keeps one edit atomic without rewriting every saved photograph.
/// The small PNG lives in that same file, so a widget never sees a dangling image path.
struct CustomIconRepository: Sendable {
    let directory: URL?
    var isAvailable: Bool { directory != nil }

    func containsRecord(name: String) -> Bool {
        guard Self.key(name) != nil else { return false }
        // An inaccessible directory cannot establish that a user record is absent.
        guard let urls = candidates(name: name) else { return true }
        return !urls.isEmpty
    }

    func backupRecords() throws -> [LibraryBackup.IconRecord] {
        guard let discovery = discovery(), discovery.recoveryDirectories.isEmpty else { throw LibraryBackupError.exportFailed }
        let urls = try LibraryBackupRecordFiles.jsonFiles(in: directory, maximumRecords: LibraryBackup.maximumIcons)
        var records: [String: Record] = [:]
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let record = read(url), let key = Self.key(record.name), Self.belongs(url, to: record.name) else {
                throw LibraryBackupError.exportFailed
            }
            // Identical legacy spellings are one logical record. Conflicting
            // artwork must be resolved explicitly, never selected by file order.
            if let prior = records[key], prior.icon != record.icon { throw LibraryBackupError.exportFailed }
            if records[key] == nil || url.lastPathComponent == Self.filename(for: key) { records[key] = record }
        }
        return records.values.sorted { $0.name < $1.name }
    }

    /// A corrupt legacy SHA file with no recoverable name cannot be proved
    /// unrelated to this action. Only strict exports fail closed globally;
    /// ordinary widget reads still use the known identity's candidate files.
    func backupIcon(name: String) throws -> CustomIconVariants? {
        guard let discovery = discovery(), discovery.unidentified.isEmpty, discovery.recoveryDirectories.isEmpty,
              let urls = candidates(name: name, discovery: discovery) else { throw LibraryBackupError.exportFailed }
        guard !urls.isEmpty else { return nil }
        guard let record = resolved(urls, name: name) else { throw LibraryBackupError.exportFailed }
        return record.icon
    }

    private static let maximumRecordBytes = 2 * ((CustomIcon.maximumPhotoBytes + 2) / 3 * 4) + 8_192
    private typealias Record = LibraryBackup.IconRecord

    private static func key(_ name: String) -> String? {
        let key = SavedGroupBinding.normalizedName(name)
        guard !key.isEmpty, key.utf8.count <= 1_024 else { return nil }
        return key
    }

    private static func legacyKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func filename(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }

    private static func belongs(_ url: URL, to name: String) -> Bool {
        guard let key = key(name) else { return false }
        return url.lastPathComponent == filename(for: key) || url.lastPathComponent == filename(for: legacyKey(name))
    }

    private func url(for name: String) -> URL? {
        guard let directory = directory?.resolvingSymlinksInPath(), let key = Self.key(name) else { return nil }
        return directory.appendingPathComponent(Self.filename(for: key), isDirectory: false)
    }

    func icon(name: String) -> CustomIcon? { variants(name: name)?.standard }

    func variants(name: String) -> CustomIconVariants? {
        guard let urls = candidates(name: name) else { return nil }
        return resolved(urls, name: name)?.icon
    }

    var all: [String: CustomIconVariants] { readableRecords.mapValues(\.icon) }
    var displayNames: [String: String] { readableRecords.mapValues(\.name) }

    private var readableRecords: [String: Record] {
        guard let discovery = discovery() else { return [:] }
        var result: [String: Record] = [:]
        for key in discovery.names.keys {
            guard let urls = candidates(name: key, discovery: discovery), let record = resolved(urls, name: key) else { continue }
            result[key] = record
        }
        return result
    }

    private func resolved(_ urls: [URL], name: String) -> Record? {
        guard let key = Self.key(name), !urls.isEmpty else { return nil }
        var result: Record?
        for url in urls {
            guard let record = read(url), Self.key(record.name) == key, Self.belongs(url, to: record.name),
                  result == nil || result?.icon == record.icon else { return nil }
            if result == nil || url.lastPathComponent == Self.filename(for: key) { result = record }
        }
        return result
    }

    private func candidates(name: String, discovery supplied: CustomIconIdentityDiscovery? = nil) -> [URL]? {
        guard let directory = directory?.resolvingSymlinksInPath(), let key = Self.key(name), let discovery = supplied ?? discovery() else { return nil }
        var filenames = Set((discovery.names[key] ?? []).map(\.lastPathComponent))
        // Known hashes remain protective even if the file's JSON is unreadable.
        // Name-only discovery also covers partially composed legacy spellings.
        for spelling in [key, Self.legacyKey(name), Self.legacyKey(key.decomposedStringWithCanonicalMapping)] {
            let url = directory.appendingPathComponent(Self.filename(for: spelling))
            if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil { filenames.insert(url.lastPathComponent) }
        }
        return filenames.sorted().map { directory.appendingPathComponent($0, isDirectory: false) }
    }

    private func discovery() -> CustomIconIdentityDiscovery? {
        guard let directory = directory?.resolvingSymlinksInPath() else { return nil }
        return CustomIconIdentityCache.shared.value(in: directory) {
            let urls: [URL]
            do {
                urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                  options: [])
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                return CustomIconIdentityDiscovery()
            } catch { return nil }
            struct NameOnly: Decodable { let name: String }
            var result = CustomIconIdentityDiscovery()
            result.recoveryDirectories = urls.filter { $0.lastPathComponent.hasPrefix(".IconBackup-") }
            for url in urls where Self.isRecordFilename(url.lastPathComponent) {
                guard let data = readData(url), let name = try? JSONDecoder().decode(NameOnly.self, from: data).name,
                      let key = Self.key(name), Self.belongs(url, to: name) else {
                    result.unidentified.append(url)
                    continue
                }
                result.names[key, default: []].append(url)
            }
            return result
        }
    }

    private static func isRecordFilename(_ name: String) -> Bool {
        name.utf8.count == 69 && name.hasSuffix(".json")
            && name.dropLast(5).utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Hashes one bounded file at a time, avoiding decoding all photo pixels to
    /// discover whether the artwork changed since the last widget entry.
    var revision: String {
        var hash = SHA256()
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = readData(url) else { continue }
            hash.update(data: Data(url.lastPathComponent.utf8))
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func set(_ icon: CustomIcon?, name: String) -> Bool {
        setVariants(icon.map { CustomIconVariants(standard: $0) }, name: name)
    }

    @discardableResult
    func setVariants(_ icon: CustomIconVariants?, name: String,
                     removing remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
                     cleaningCommitted cleanup: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) -> Bool {
        FolderCoverAssetCoordinator.withLock {
            guard let directory, let canonical = url(for: name), let candidates = candidates(name: name) else { return false }
            // An explicit edit can repair one damaged record. Multiple aliases
            // must agree before replacement; explicit removal resolves conflicts.
            if icon != nil && candidates.count > 1 && resolved(candidates, name: name) == nil { return false }
            if icon == nil && candidates.isEmpty {
                cleanCommittedBackups(in: directory, using: cleanup)
                return true
            }
            var backupDirectory: URL?
            var backups: [URL: URL] = [:]
            let hadCanonical = candidates.contains { $0.lastPathComponent == canonical.lastPathComponent }
            var replacedCanonical = false
            do {
                let replacement: Data?
                if let icon {
                    guard icon.isValid else { return false }
                    let record = Record(name: name.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    let data = try encoder.encode(record)
                    guard data.count <= Self.maximumRecordBytes else { return false }
                    if candidates.count == 1, hadCanonical, readData(canonical) == data {
                        cleanCommittedBackups(in: directory, using: cleanup)
                        return true
                    }
                    replacement = data
                } else { replacement = nil }

                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !candidates.isEmpty {
                    let staging = directory.appendingPathComponent(".IconBackup-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
                    backupDirectory = staging
                    for url in candidates {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileReadCorruptFile) }
                        let backup = staging.appendingPathComponent(url.lastPathComponent)
                        // Same-volume hard links preserve original bytes without
                        // loading oversized/corrupt records or every alias's PNG.
                        try FileManager.default.linkItem(at: url, to: backup)
                        backups[url] = backup
                    }
                }
                if let replacement {
                    try replacement.write(to: canonical, options: .atomic)
                    replacedCanonical = true
                    for url in candidates where url.lastPathComponent != canonical.lastPathComponent { try remove(url) }
                    CustomIconIdentityCache.shared.invalidate(directory)
                    guard readData(canonical) == replacement else { throw CocoaError(.fileWriteUnknown) }
                } else {
                    for url in candidates { try remove(url) }
                    CustomIconIdentityCache.shared.invalidate(directory)
                    guard self.candidates(name: name)?.isEmpty == true else { throw CocoaError(.fileWriteUnknown) }
                }
                if let backupDirectory {
                    // Mark commit before destroying any rollback link. Renaming
                    // within this directory is atomic; if it fails, all original
                    // links still exist and compensation remains possible.
                    let committed = directory.appendingPathComponent(".IconCleanup-" + UUID().uuidString, isDirectory: true)
                    guard rename(backupDirectory.path, committed.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
                }
            } catch {
                // Best-effort compensation, not a cross-file/crash transaction.
                // Atomic rename can restore large originals without reading them.
                // Keep recovery links if any restore fails; never erase the only
                // remaining old bytes in an unconditional cleanup defer.
                var restored = true
                for (url, backup) in backups {
                    if rename(backup.path, url.path) != 0 { restored = false }
                }
                if replacedCanonical && !hadCanonical {
                    do { try FileManager.default.removeItem(at: canonical) }
                    catch { if FileManager.default.fileExists(atPath: canonical.path) { restored = false } }
                }
                if restored, let backupDirectory { try? FileManager.default.removeItem(at: backupDirectory) }
                CustomIconIdentityCache.shared.invalidate(directory)
                return false
            }
            // The requested state is verified and committed. A partial cleanup
            // cannot trigger rollback using links that may already be destroyed.
            // A true result refers to the requested icon state, not to temporary
            // cleanup; remaining committed directories are retried on later edits.
            cleanCommittedBackups(in: directory, using: cleanup)
            return true
        }
    }

    private func cleanCommittedBackups(in directory: URL, using remove: (URL) throws -> Void) {
        let prefix = ".IconCleanup-"
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
            guard UUID(uuidString: String(entry.lastPathComponent.dropFirst(prefix.count))) != nil,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: entry.path),
                  attributes[.type] as? FileAttributeType == .typeDirectory else { continue }
            try? remove(entry)
        }
    }

    private var files: [URL] {
        guard let directory else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]
        )) ?? []).filter { Self.isRecordFilename($0.lastPathComponent) }
    }

    private func readData(_ url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= Self.maximumRecordBytes,
              let data = try? Data(contentsOf: url), data.count <= Self.maximumRecordBytes else { return nil }
        return data
    }

    private func read(_ url: URL) -> Record? {
        guard let data = readData(url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
}

/// Derived metadata only: no persisted index and no image/PNG retention. Atomic
/// record replacement changes the parent directory's inode timestamps, even when
/// the filename set stays unchanged. Targets are still fully validated on read.
private struct CustomIconIdentityDiscovery {
    var names: [String: [URL]] = [:]
    var unidentified: [URL] = []
    // A prior failed compensation may have its only remaining bytes here.
    // Exports must not silently omit those records; ordinary reads stay usable.
    var recoveryDirectories: [URL] = []
}

private final class CustomIconIdentityCache: @unchecked Sendable {
    static let shared = CustomIconIdentityCache()
    private let lock = NSLock()
    private struct Stamp: Equatable {
        let inode: UInt64
        let device: Int32
        let modifiedSeconds: Int
        let modifiedNanos: Int
        let changedSeconds: Int
        let changedNanos: Int
        init?(_ url: URL) {
            var value = stat()
            guard lstat(url.path, &value) == 0, (value.st_mode & S_IFMT) == S_IFDIR else { return nil }
            inode = value.st_ino
            device = value.st_dev
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanos = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanos = value.st_ctimespec.tv_nsec
        }
    }
    private var entries: [String: (Stamp, CustomIconIdentityDiscovery)] = [:]

    func value(in directory: URL, load: () -> CustomIconIdentityDiscovery?) -> CustomIconIdentityDiscovery? {
        lock.lock()
        defer { lock.unlock() }
        let path = directory.path
        let before = Stamp(directory)
        if let before, let cached = entries[path], cached.0 == before { return cached.1 }
        guard let result = load() else { entries.removeValue(forKey: path); return nil }
        if let before, Stamp(directory) == before {
            if entries.count >= 16 { entries.removeAll() }
            entries[path] = (before, result)
        } else { entries.removeValue(forKey: path) }
        return result
    }

    func invalidate(_ directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: directory.resolvingSymlinksInPath().path)
    }
}
