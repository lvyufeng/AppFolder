import Darwin
import Foundation

/// All cooperating App/Extension readers and writers use the same persistent
/// lock inode. A nonblocking flock is cross-process and released on process
/// death; the lock file and inbox directory are never replaced or removed here.
struct ShareInboxRepository: ShareInboxStorage {
    let directory: URL?
    static let lockFilename = ".lock"

    var snapshot: ShareInboxSnapshot {
        guard directory != nil else { return result(status: .unavailable) }
        do {
            return try withLock(create: false, exclusive: false) { descriptor, directory in
                let files = try recordFiles(in: directory)
                guard files.count <= ShareInboxStore.maximumEntries else {
                    return result(status: .overCapacity, count: files.count)
                }
                var entries: [ShareInboxEntry] = []
                var unreadableCount = 0
                for file in files {
                    guard let entry = read(file.lastPathComponent, directoryDescriptor: descriptor),
                          file.lastPathComponent == filename(entry.id) else {
                        unreadableCount += 1
                        continue
                    }
                    entries.append(entry)
                }
                entries.sort {
                    if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
                return .init(entries: entries, unreadableCount: unreadableCount,
                             recordCount: files.count, status: .available)
            } ?? result(status: .available)
        } catch ShareInboxError.busy {
            return result(status: .busy)
        } catch {
            return result(status: .directoryFailure)
        }
    }

    func enqueue(url: String, title: String? = nil) throws -> ShareInboxEntry {
        try enqueue(url: url, title: title, id: UUID(), createdAt: .now)
    }

    // Identity and clock injection exercise collisions and restart behavior
    // without giving production consumers a way to overwrite a pending entry.
    func enqueue(url: String, title: String?, id: UUID, createdAt: Date) throws -> ShareInboxEntry {
        let entry = try ShareInboxEntry(id: id, url: url, title: title, createdAt: createdAt)
        let data = try encoded(entry)
        guard let saved = try withLock(create: true, exclusive: true, { descriptor, directory in
            guard try recordFiles(in: directory).count < ShareInboxStore.maximumEntries else {
                throw ShareInboxError.full
            }
            let name = filename(id)
            var existing = stat()
            if fstatat(descriptor, name, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
                throw ShareInboxError.recordAlreadyExists
            }
            guard errno == ENOENT else { throw ShareInboxError.storageFailure }
            do {
                // The capacity check, collision check and complete-file rename
                // share one exclusive lock. No caller observes a partial JSON.
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            } catch { throw ShareInboxError.storageFailure }
            return entry
        }) else { throw ShareInboxError.storageFailure }
        return saved
    }

    @discardableResult
    func remove(id: UUID) throws -> Bool {
        try withLock(create: false, exclusive: true) { descriptor, _ in
            let name = filename(id)
            var info = stat()
            guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno == ENOENT { return false }
                throw ShareInboxError.storageFailure
            }
            guard (info.st_mode & S_IFMT) == S_IFREG else { throw ShareInboxError.storageFailure }
            guard unlinkat(descriptor, name, 0) == 0 else { throw ShareInboxError.storageFailure }
            return true
        } ?? false
    }

    @discardableResult
    func remove(ifMatching entry: ShareInboxEntry) throws -> Bool {
        try withLock(create: false, exclusive: true) { descriptor, _ in
            guard let existing = try existingEntry(id: entry.id, directoryDescriptor: descriptor) else { return false }
            guard existing == entry else { throw ShareInboxError.recordAlreadyExists }
            guard unlinkat(descriptor, filename(entry.id), 0) == 0 else { throw ShareInboxError.storageFailure }
            return true
        } ?? false
    }

    func restore(_ entry: ShareInboxEntry) throws {
        let data = try encoded(entry)
        guard try withLock(create: true, exclusive: true, { descriptor, directory in
            // Check identity before capacity: retrying a successful undo is a
            // no-op even when another submission has since filled the inbox.
            if let existing = try existingEntry(id: entry.id, directoryDescriptor: descriptor) {
                guard existing == entry else { throw ShareInboxError.recordAlreadyExists }
                return true
            }
            guard try recordFiles(in: directory).count < ShareInboxStore.maximumEntries else {
                throw ShareInboxError.full
            }
            do {
                try data.write(to: directory.appendingPathComponent(filename(entry.id)), options: .atomic)
            } catch { throw ShareInboxError.storageFailure }
            return true
        }) == true else { throw ShareInboxError.storageFailure }
    }

    private func encoded(_ entry: ShareInboxEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(entry)
        guard data.count <= ShareInboxStore.maximumRecordBytes else { throw ShareInboxError.recordTooLarge }
        return data
    }

    /// Unlike remove(id:), user-facing removal/undo must read a single owned,
    /// valid record. Neither damaged contents nor links are a missing entry.
    private func existingEntry(id: UUID, directoryDescriptor: Int32) throws -> ShareInboxEntry? {
        let name = filename(id)
        var info = stat()
        guard fstatat(directoryDescriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw ShareInboxError.storageFailure
        }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1,
              let entry = read(name, directoryDescriptor: directoryDescriptor), entry.id == id else {
            throw ShareInboxError.storageFailure
        }
        return entry
    }

    private func recordFiles(in directory: URL) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "json" }
        } catch { throw ShareInboxError.storageFailure }
    }

    private func read(_ filename: String, directoryDescriptor: Int32) -> ShareInboxEntry? {
        let descriptor = openat(directoryDescriptor, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= ShareInboxStore.maximumRecordBytes else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.read(upToCount: ShareInboxStore.maximumRecordBytes + 1),
              !data.isEmpty, data.count <= ShareInboxStore.maximumRecordBytes else { return nil }
        return try? JSONDecoder().decode(ShareInboxEntry.self, from: data)
    }

    /// Nil means a first-use directory is absent. A read or removal never
    /// creates that directory. An existing symlink or non-directory is failure.
    private func withLock<T>(create: Bool, exclusive: Bool,
                             _ body: (Int32, URL) throws -> T) throws -> T? {
        guard let directory else { throw ShareInboxError.unavailable }
        if create {
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { throw ShareInboxError.storageFailure }
        }
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if !create && errno == ENOENT { return nil }
            throw ShareInboxError.storageFailure
        }
        defer { close(descriptor) }
        let lock = openat(descriptor, Self.lockFilename, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK,
                          S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw ShareInboxError.storageFailure }
        defer { close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else { throw ShareInboxError.storageFailure }
        guard flock(lock, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw ShareInboxError.busy }
            throw ShareInboxError.storageFailure
        }
        defer { flock(lock, LOCK_UN) }
        return try body(descriptor, directory)
    }

    private func filename(_ id: UUID) -> String { id.uuidString.lowercased() + ".json" }
    private func result(status: ShareInboxSnapshot.Status, count: Int = 0) -> ShareInboxSnapshot {
        .init(entries: [], unreadableCount: 0, recordCount: count, status: status)
    }
}
