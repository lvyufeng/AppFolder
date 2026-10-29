import Darwin
import Foundation

/// App-owned name organization. Widget observations remain in their existing,
/// independently written store; merely reading candidates never writes here.
public enum ActionLibraryStore {
    static let repository: ActionLibraryRepository = {
        #if os(iOS)
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
        )
        return .init(directory: container?.appendingPathComponent("ActionLibrary", isDirectory: true))
        #else
        return .init(directory: nil)
        #endif
    }()

    public static let maximumRecords = ActionLibraryRepository.maximumRecords
    public static let maximumFileBytes = ActionLibraryRepository.maximumFileBytes
    public static var isAvailable: Bool { repository.isAvailable }
    public static var snapshot: ActionLibrarySnapshot { repository.snapshot }
    public static func apply(_ mutations: [ActionLibraryMutation]) throws -> ActionLibrarySnapshot {
        try repository.apply(mutations)
    }
}

/// One bounded JSON document permits an all-or-nothing batch without repeatedly
/// rewriting the file for each imported name. The stable lock file is separate
/// from that atomically replaced document. No snapshot or image cache is kept.
public struct ActionLibraryRepository: Sendable {
    public static let maximumRecords = 4_096
    public static let maximumFileBytes = 8 * 1_024 * 1_024
    public let directory: URL?
    private static let filename = "library.json"
    private static let lockFilename = ".lock"
    private let writeData: @Sendable (Data, URL) throws -> Void

    public init(directory: URL?) {
        self.directory = directory
        self.writeData = { try $0.write(to: $1, options: .atomic) }
    }

    /// I/O injection keeps failure tests on real isolated directories. It does
    /// not change the public store's behavior or enable a product test mode.
    init(directory: URL?, writeData: @escaping @Sendable (Data, URL) throws -> Void) {
        self.directory = directory
        self.writeData = writeData
    }

    /// Container availability, not a guarantee of successful reads or writes.
    public var isAvailable: Bool { directory != nil }

    public var snapshot: ActionLibrarySnapshot {
        do { return .init(records: try exportRecords(), status: .available) }
        catch ActionLibraryError.unavailable { return .init(status: .unavailable) }
        catch ActionLibraryError.busy { return .init(status: .busy) }
        catch { return .init(status: .unreadable) }
    }

    /// A damaged document is never treated as an empty organization library.
    public func exportRecords() throws -> [ActionLibraryRecord] {
        try FolderCoverAssetCoordinator.withLock {
            try withLock(create: false, exclusive: false) { descriptor, _ in
                try read(descriptor).records
            } ?? []
        }
    }

    /// A group without system-action leaves is independent of this store.
    /// Otherwise the whole small metadata document must be readable before its
    /// relevant rows can be selected; no corrupt name silently disappears.
    public func exportRecords(for normalizedNames: Set<String>) throws -> [ActionLibraryRecord] {
        guard !normalizedNames.isEmpty else { return [] }
        return try exportRecords().filter { normalizedNames.contains($0.id) }
    }

    /// Every expected record is compared with the fresh file under one lock.
    /// A stale row cancels the complete batch, preserving edits to other names.
    public func apply(_ mutations: [ActionLibraryMutation]) throws -> ActionLibrarySnapshot {
        try validate(mutations)
        return try FolderCoverAssetCoordinator.withLock {
            guard let result = try withLock(create: true, exclusive: true, { descriptor, directory in
                let original = try read(descriptor)
                var values = Dictionary(uniqueKeysWithValues: original.records.map { ($0.id, $0) })
                let conflicts = mutations.compactMap { mutation -> String? in
                    let key = SavedGroupBinding.normalizedName(mutation.name)
                    return values[key] == mutation.expected ? nil : key
                }
                guard conflicts.isEmpty else { throw ActionLibraryError.conflict(conflicts.sorted()) }
                for mutation in mutations {
                    values[SavedGroupBinding.normalizedName(mutation.name)] = mutation.replacement
                }
                let records = values.values.sorted { $0.id < $1.id }
                if records == original.records { return ActionLibrarySnapshot(records: records, status: .available) }
                let data = try encoded(records)
                guard commit(data, descriptor: descriptor, directory: directory) else {
                    throw ActionLibraryError.writeFailed
                }
                return ActionLibrarySnapshot(records: records, status: .available)
            }) else { throw ActionLibraryError.writeFailed }
            return result
        }
    }

    /// Existing names always win, including equal records. The receipt names
    /// only rows that were absent at the locked read and then attempted by this
    /// call; an importer must never infer ownership from its older preview.
    public func insertMissing(_ records: [ActionLibraryRecord]) -> ActionLibraryInsertResult {
        var attempted: [ActionLibraryRecord] = []
        var kept: [ActionLibraryRecord] = []
        do {
            try validate(records)
            return try FolderCoverAssetCoordinator.withLock {
                guard let result = try withLock(create: true, exclusive: true, { descriptor, directory in
                    let original = try read(descriptor)
                    var values = Dictionary(uniqueKeysWithValues: original.records.map { ($0.id, $0) })
                    var pending: [ActionLibraryRecord] = []
                    for record in records {
                        if let existing = values[record.id] { kept.append(existing) }
                        else { pending.append(record); values[record.id] = record }
                    }
                    guard !pending.isEmpty else {
                        return ActionLibraryInsertResult(didCommit: true, keptExistingRecords: kept)
                    }
                    // Capacity/encoding failures happen before any ownership is
                    // claimed. No import rollback may touch those names.
                    let data = try encoded(values.values.sorted { $0.id < $1.id })
                    attempted = pending
                    let committed = commit(data, descriptor: descriptor, directory: directory)
                    return ActionLibraryInsertResult(didCommit: committed, attemptedRecords: attempted,
                                                     keptExistingRecords: kept, error: committed ? nil : .writeFailed)
                }) else { throw ActionLibraryError.writeFailed }
                return result
            }
        } catch {
            return .init(didCommit: false, attemptedRecords: attempted, keptExistingRecords: kept,
                         error: (error as? ActionLibraryError) ?? .writeFailed)
        }
    }

    /// Rollback is also one batch. A later edit, archive or tag change is not
    /// erased, even when it has the same binding name as our attempted insert.
    public func rollbackMatching(_ records: [ActionLibraryRecord]) throws -> ActionLibraryRollbackResult {
        try validate(records)
        guard !records.isEmpty else { return .init(remainingNames: []) }
        return try FolderCoverAssetCoordinator.withLock {
            try withLock(create: false, exclusive: true) { descriptor, directory in
                let original = try read(descriptor)
                var values = Dictionary(uniqueKeysWithValues: original.records.map { ($0.id, $0) })
                let names = Set(records.map(\.id))
                for record in records where values[record.id] == record { values[record.id] = nil }
                let remaining = values.values.sorted { $0.id < $1.id }
                if remaining != original.records {
                    let data = try encoded(remaining)
                    if !commit(data, descriptor: descriptor, directory: directory) {
                        // A write might have reached disk despite an I/O error.
                        // Strict readback, never an assumed successful rollback.
                        let actual = try read(descriptor).records
                        return .init(remainingNames: Set(actual.map(\.id)).intersection(names))
                    }
                }
                return .init(remainingNames: Set(values.keys).intersection(names))
            } ?? .init(remainingNames: [])
        }
    }

    private func validate(_ records: [ActionLibraryRecord]) throws {
        guard records.count <= Self.maximumRecords else { throw ActionLibraryError.capacityExceeded }
        guard records.allSatisfy(\.isValid), Set(records.map(\.id)).count == records.count else {
            throw ActionLibraryError.invalidChanges
        }
    }

    private func validate(_ mutations: [ActionLibraryMutation]) throws {
        // Replacing every old name can require one deletion and one insertion
        // per slot; the final document, not its change count, has the row cap.
        guard mutations.count <= 2 * Self.maximumRecords else { throw ActionLibraryError.capacityExceeded }
        var names = Set<String>()
        for mutation in mutations {
            let key = SavedGroupBinding.normalizedName(mutation.name)
            guard ActionLibraryRecord.isValidName(mutation.name), names.insert(key).inserted,
                  mutation.expected.map({ $0.isValid && $0.id == key }) ?? true,
                  mutation.replacement.map({ $0.isValid && $0.id == key }) ?? true else {
                throw ActionLibraryError.invalidChanges
            }
        }
    }

    private func encoded(_ records: [ActionLibraryRecord]) throws -> Data {
        try validate(records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(records: records))
        guard data.count <= Self.maximumFileBytes else { throw ActionLibraryError.capacityExceeded }
        return data
    }

    /// If the exact desired file is confirmed, a post-rename I/O error does not
    /// turn a committed change into failure. No temporary cleanup can roll it
    /// back. False means callers must retain their owned-attempt receipt.
    private func commit(_ data: Data, descriptor: Int32, directory: URL) -> Bool {
        do { try writeData(data, directory.appendingPathComponent(Self.filename)) }
        catch { /* Read back even when an error was reported after replacement. */ }
        return (try? readData(descriptor)) == data
    }

    private func read(_ descriptor: Int32) throws -> Document {
        guard let data = try readData(descriptor) else { return .init(records: []) }
        do { return try JSONDecoder().decode(Document.self, from: data) }
        catch { throw ActionLibraryError.unreadable }
    }

    private func readData(_ directoryDescriptor: Int32) throws -> Data? {
        let file = openat(directoryDescriptor, Self.filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else {
            if errno == ENOENT { return nil }
            throw ActionLibraryError.unreadable
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= Self.maximumFileBytes else { throw ActionLibraryError.unreadable }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        var data = Data()
        do {
            while let chunk = try handle.read(upToCount: min(64 * 1_024, Self.maximumFileBytes + 1 - data.count)),
                  !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= Self.maximumFileBytes else { throw ActionLibraryError.unreadable }
            }
        } catch { throw ActionLibraryError.unreadable }
        guard !data.isEmpty else { throw ActionLibraryError.unreadable }
        return data
    }

    /// Lock order is always the shared process coordinator, then this file lock.
    /// flock is the cross-process exclusion; the recursive coordinator alone is
    /// not claimed as a transaction with an extension or another process.
    private func withLock<T>(create: Bool, exclusive: Bool,
                             _ body: (Int32, URL) throws -> T) throws -> T? {
        guard let directory else { throw ActionLibraryError.unavailable }
        guard directory.isFileURL, !directory.path.utf8.contains(0),
              directory.absoluteString.removingPercentEncoding?.utf8.contains(0) == false else {
            throw ActionLibraryError.unreadable
        }
        if create {
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { throw ActionLibraryError.unreadable }
        }
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if !create && errno == ENOENT { return nil }
            throw ActionLibraryError.unreadable
        }
        defer { close(descriptor) }
        let lock = openat(descriptor, Self.lockFilename, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK,
                          S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw ActionLibraryError.unreadable }
        defer { close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
            throw ActionLibraryError.unreadable
        }
        guard flock(lock, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw ActionLibraryError.busy }
            throw ActionLibraryError.unreadable
        }
        defer { flock(lock, LOCK_UN) }
        return try body(descriptor, directory)
    }

    private struct Document: Codable {
        let version: Int
        let records: [ActionLibraryRecord]
        init(records: [ActionLibraryRecord]) { self.version = 1; self.records = records }
        private enum CodingKeys: String, CodingKey, CaseIterable { case version, records }
        private struct AnyKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        init(from decoder: any Decoder) throws {
            let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
            guard keys == Set(CodingKeys.allCases.map(\.rawValue)) else { throw ActionLibraryError.unreadable }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            guard version == 1 else { throw ActionLibraryError.unreadable }
            var array = try values.nestedUnkeyedContainer(forKey: .records)
            var records: [ActionLibraryRecord] = []
            var names = Set<String>()
            while !array.isAtEnd {
                guard records.count < ActionLibraryRepository.maximumRecords else { throw ActionLibraryError.unreadable }
                let record = try array.decode(ActionLibraryRecord.self)
                guard names.insert(record.id).inserted else { throw ActionLibraryError.unreadable }
                records.append(record)
            }
            self.records = records.sorted { $0.id < $1.id }
        }
    }
}
