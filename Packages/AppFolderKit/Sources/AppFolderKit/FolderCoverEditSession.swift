import Foundation

/// One editor owns one session across all cover sheets and its undo/redo stack.
/// New artwork stays in a private staging directory until the group is saved.
/// Every mutable field is protected by the shared, recursive coordinator lock.
public final class FolderCoverEditSession: @unchecked Sendable {
    private let repository: FolderCoverAssetRepository
    private let staging: FolderCoverAssetRepository
    private let groupID: UUID
    private let originalIDs: Set<FolderCoverAssetID>
    private let lease: FolderCoverAssetLease
    private var stagedIDs = Set<FolderCoverAssetID>()
    private var retainedIDs = Set<FolderCoverAssetID>()
    private var closed = false

    // Only the app creates sessions. This registry prevents a newly opened
    // editor from collecting another live editor's temporary artwork.
    nonisolated(unsafe) private static var activeStagingPaths = Set<String>()

    public convenience init(group: SavedGroup) throws {
        try self.init(group: group, repository: FolderCoverAssetStore.repository)
    }

    init(group: SavedGroup, repository: FolderCoverAssetRepository) throws {
        guard group.isValid else { throw FolderCoverAssetError.invalidGroup }
        guard let directory = repository.directory, repository.groupDirectory != nil else {
            throw FolderCoverAssetError.storageUnavailable
        }
        self.repository = repository
        self.groupID = group.id
        self.originalIDs = group.coverAssetIDs
        self.lease = try FolderCoverAssetLease(repository: repository, retaining: group.coverAssetIDs)
        let drafts = directory.deletingLastPathComponent().appendingPathComponent("FolderCoverDrafts", isDirectory: true)
        let temporary = drafts.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        self.staging = .init(directory: temporary, groupDirectory: nil)
        FolderCoverAssetCoordinator.withLock {
            Self.removeAbandonedStaging(in: drafts)
            Self.activeStagingPaths.insert(temporary.standardizedFileURL.path)
        }
        // No committed file or staging directory is written during init.
    }

    /// Nil clears a cover successfully; malformed artwork or I/O failure throws.
    /// Fallback appearances are references, never duplicated photo payloads.
    public func stage(variants: CustomIconVariants?) throws -> FolderCover? {
        try FolderCoverAssetCoordinator.withLock {
            try requireOpen()
            guard let variants else { return nil }
            guard variants.isValid else { throw FolderCoverAssetError.invalidArtwork }
            let previousIDs = stagedIDs
            var newlyAttempted = Set<FolderCoverAssetID>()
            func stageOne(_ icon: CustomIcon?) throws -> FolderCoverAssetID? {
                guard let icon else { return nil }
                guard let id = FolderCoverAssetRepository.id(for: icon) else { throw FolderCoverAssetError.invalidArtwork }
                if repository.contains(id: id) {
                    guard repository.icon(id: id) == icon else { throw FolderCoverAssetError.readFailed }
                } else {
                    if !staging.contains(id: id) { newlyAttempted.insert(id) }
                    guard staging.save(icon, id: id) else { throw FolderCoverAssetError.writeFailed }
                }
                stagedIDs.insert(id)
                // Pin reused durable artwork immediately, before the caller can
                // insert the returned reference into its history snapshot.
                updateLease()
                return id
            }
            do {
                return try FolderCover(standard: stageOne(variants.standard), dark: stageOne(variants.dark))
            } catch {
                // A failed second appearance must not accumulate the first
                // appearance's files/lease across repeated attempts.
                for id in newlyAttempted { _ = staging.remove(id: id) }
                stagedIDs = previousIDs
                updateLease()
                throw error
            }
        }
    }

    /// Used when opening the artwork editor. Reads exact original PNG bytes and
    /// fails visibly if either explicitly selected appearance is unavailable.
    public func load(_ cover: FolderCover?) throws -> CustomIconVariants? {
        try FolderCoverAssetCoordinator.withLock {
            try requireOpen()
            guard let cover else { return nil }
            guard cover.isValid else { throw FolderCoverAssetError.invalidArtwork }
            return try CustomIconVariants(standard: cover.standard.map(requireIcon), dark: cover.dark.map(requireIcon))
        }
    }

    /// Best-effort display path; each requested photo is reduced before retention.
    public func variants(for cover: FolderCover?, maxSide: Int = 256) -> CustomIconVariants? {
        FolderCoverAssetCoordinator.withLock {
            guard !closed, let cover else { return nil }
            let result = CustomIconVariants(
                standard: cover.standard.flatMap { icon($0)?.limited(to: maxSide) },
                dark: cover.dark.flatMap { icon($0)?.limited(to: maxSide) }
            )
            return result.isValid ? result : nil
        }
    }

    /// Call after every history transition with current + undo + redo references.
    /// Original saved assets remain pinned until save or explicit cancellation.
    public func retain(_ ids: Set<FolderCoverAssetID>) {
        FolderCoverAssetCoordinator.withLock {
            guard !closed else { return }
            retainedIDs = ids
            let keep = originalIDs.union(ids)
            for id in stagedIDs.subtracting(keep) { _ = staging.remove(id: id) }
            stagedIDs.formIntersection(keep)
            updateLease()
        }
    }

    /// Promotes immutable assets before committing the single group file. A
    /// failure leaves the session and old layout usable for retry or cancellation.
    public func commit(_ group: SavedGroup) throws {
        try FolderCoverAssetCoordinator.withLock {
            try requireOpen()
            guard group.id == groupID, group.isValid else { throw FolderCoverAssetError.invalidGroup }
            guard let groupDirectory = repository.groupDirectory else { throw FolderCoverAssetError.storageUnavailable }
            retainedIDs.formUnion(group.coverAssetIDs)
            updateLease()
            // Validate every reference before starting promotion. Promotion may
            // leave an orphan on I/O failure, which strict GC can remove later.
            for id in group.coverAssetIDs { _ = try requireIcon(id) }
            for id in group.coverAssetIDs {
                let artwork = try requireIcon(id)
                guard repository.save(artwork, id: id) else { throw FolderCoverAssetError.writeFailed }
            }
            guard SavedGroupRepository(directory: groupDirectory).save(group) else {
                throw FolderCoverAssetError.writeFailed
            }
            close()
        }
    }

    /// Called only when leaving the whole editor, not when closing a cover sheet.
    public func discard() {
        FolderCoverAssetCoordinator.withLock { close() }
    }

    deinit { discard() }

    private func requireOpen() throws {
        guard !closed else { throw FolderCoverAssetError.closedSession }
    }

    private func icon(_ id: FolderCoverAssetID) -> CustomIcon? {
        staging.icon(id: id) ?? repository.icon(id: id)
    }

    private func requireIcon(_ id: FolderCoverAssetID) throws -> CustomIcon {
        guard let artwork = icon(id) else { throw FolderCoverAssetError.missingAsset(id) }
        return artwork
    }

    private func updateLease() {
        lease.update(retaining: originalIDs.union(retainedIDs).union(stagedIDs))
    }

    private func close() {
        guard !closed else { return }
        closed = true
        if let directory = staging.directory {
            try? FileManager.default.removeItem(at: directory)
            Self.activeStagingPaths.remove(directory.standardizedFileURL.path)
        }
        lease.close()
        // A corrupt/unreadable saved layout aborts the entire collection scan.
        // The next successful session/explicit collection can retry safely.
        _ = try? repository.collectGarbage()
    }

    private static func removeAbandonedStaging(in directory: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) else { return }
        for entry in entries {
            guard UUID(uuidString: entry.lastPathComponent) != nil,
                  !activeStagingPaths.contains(entry.standardizedFileURL.path),
                  let properties = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  properties.isDirectory == true, properties.isSymbolicLink != true else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }
}
