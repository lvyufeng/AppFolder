import CryptoKit
import Darwin
import Foundation

/// A past timeline's name matching results, never a system action or proof that
/// a widget is still installed. Identical widget configurations share a report.
public struct SavedGroupBindingReport: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case ready, missing, ambiguous
    }

    public struct Action: Codable, Sendable, Equatable {
        public let name: String
        public let status: Status
    }

    public let groupID: UUID
    public let revision: String
    public let configurationKey: String
    public let grid: FolderGrid
    public let density: FolderDensity
    public let familyRawValue: Int
    public let checkedAt: Date
    public let actions: [Action]

    public var id: String {
        let value = "\(groupID.uuidString)|\(revision)|\(configurationKey)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public var requiredNames: [String] { actions.map(\.name) }
    public var missingNames: [String] { actions.filter { $0.status == .missing }.map(\.name) }
    public var ambiguousNames: [String] { actions.filter { $0.status == .ambiguous }.map(\.name) }
    public var isReady: Bool { !actions.isEmpty && actions.allSatisfy { $0.status == .ready } }

    public init?(group: SavedGroup, configurationKey: String, grid: FolderGrid,
                 familyRawValue: Int, actionNames: [String], checkedAt: Date = .now,
                 density: FolderDensity = .standard) {
        guard group.isValid else { return nil }
        groupID = group.id
        revision = group.revision
        self.configurationKey = configurationKey
        self.grid = grid
        self.density = density
        self.familyRawValue = familyRawValue
        self.checkedAt = checkedAt
        let binding = SavedGroupBinding(actionNames: actionNames)
        actions = group.allActionNames.map { name in
            let status: Status
            switch binding.resolve(name) {
            case .matched: status = .ready
            case .missing: status = .missing
            case .ambiguous: status = .ambiguous
            }
            return Action(name: name, status: status)
        }
        guard isValid else { return nil }
    }

    private enum CodingKeys: String, CodingKey {
        case groupID, revision, configurationKey, grid, density, familyRawValue, checkedAt, actions
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        groupID = try values.decode(UUID.self, forKey: .groupID)
        revision = try values.decode(String.self, forKey: .revision)
        configurationKey = try values.decode(String.self, forKey: .configurationKey)
        grid = try values.decode(FolderGrid.self, forKey: .grid)
        density = values.contains(.density) ? try values.decode(FolderDensity.self, forKey: .density) : .standard
        familyRawValue = try values.decode(Int.self, forKey: .familyRawValue)
        checkedAt = try values.decode(Date.self, forKey: .checkedAt)
        actions = try values.decode([Action].self, forKey: .actions)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(groupID, forKey: .groupID)
        try values.encode(revision, forKey: .revision)
        try values.encode(configurationKey, forKey: .configurationKey)
        try values.encode(grid, forKey: .grid)
        if density != .standard { try values.encode(density, forKey: .density) }
        try values.encode(familyRawValue, forKey: .familyRawValue)
        try values.encode(checkedAt, forKey: .checkedAt)
        try values.encode(actions, forKey: .actions)
    }

    /// Checking both revision and names prevents an incomplete/corrupt record
    /// from making the current editor look configured.
    public func matches(_ group: SavedGroup) -> Bool {
        groupID == group.id && revision == group.revision && requiredNames == group.allActionNames
    }

    var isValid: Bool {
        guard revision.count == 64, revision.allSatisfy({ $0.isHexDigit }),
              !configurationKey.isEmpty, configurationKey.utf8.count <= 2_048,
              (0...100).contains(familyRawValue), checkedAt.timeIntervalSince1970.isFinite,
              actions.count <= SavedGroup.maximumItems else { return false }
        var names = Set<String>()
        return actions.allSatisfy {
            let key = SavedGroupBinding.normalizedName($0.name)
            return !key.isEmpty && $0.name.count <= SavedGroup.maximumNameLength && names.insert(key).inserted
        }
    }
}

public enum SavedGroupBindingReportStore {
    public static let maximumReports = 24
    private static let repository: SavedGroupBindingReportRepository = {
        #if os(iOS)
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
        )?.appendingPathComponent("BindingReports", isDirectory: true)
        return SavedGroupBindingReportRepository(directory: directory)
        #else
        return SavedGroupBindingReportRepository(directory: nil)
        #endif
    }()

    public static var all: [SavedGroupBindingReport] { repository.all }

    public static func reports(for groupID: UUID) -> [SavedGroupBindingReport] {
        repository.all.filter { $0.groupID == groupID }
    }

    @discardableResult
    public static func record(_ report: SavedGroupBindingReport) -> Bool { repository.record(report) }
}

/// One bounded, atomically replaced file. A nonblocking advisory file lock keeps
/// concurrent extension processes from overwriting each other's configurations.
/// Diagnostics can skip a busy write; they never delay a widget's timeline.
struct SavedGroupBindingReportRepository: Sendable {
    static let maximumFileBytes = 2 * 1_024 * 1_024
    let directory: URL?
    private var file: URL? { directory?.appendingPathComponent("reports.json") }

    private struct Envelope: Codable {
        var version = 1
        let reports: [SavedGroupBindingReport]
    }

    var all: [SavedGroupBindingReport] {
        guard let file,
              let attributes = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              attributes.isRegularFile == true, let size = attributes.fileSize,
              size > 0, size <= Self.maximumFileBytes,
              let data = try? Data(contentsOf: file), data.count <= Self.maximumFileBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1, envelope.reports.count <= SavedGroupBindingReportStore.maximumReports,
              envelope.reports.allSatisfy(\.isValid),
              Set(envelope.reports.map(\.id)).count == envelope.reports.count else { return [] }
        return envelope.reports.sorted(by: Self.newestFirst)
    }

    @discardableResult
    func record(_ report: SavedGroupBindingReport) -> Bool {
        guard report.isValid, let directory, let file else { return false }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { return false }
        let descriptor = open(directory.appendingPathComponent("write.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return false }
        defer { flock(descriptor, LOCK_UN) }

        var reports = all
        if let previous = reports.first(where: { $0.id == report.id }), previous.checkedAt > report.checkedAt {
            return true // A slower, earlier timeline cannot replace a newer check.
        }
        reports.removeAll { $0.id == report.id }
        reports.append(report)
        reports.sort(by: Self.newestFirst)
        reports = Array(reports.prefix(SavedGroupBindingReportStore.maximumReports))
        do {
            let data = try JSONEncoder().encode(Envelope(reports: reports))
            guard data.count <= Self.maximumFileBytes else { return false }
            try data.write(to: file, options: .atomic)
            return true
        } catch { return false }
    }

    private static func newestFirst(_ lhs: SavedGroupBindingReport, _ rhs: SavedGroupBindingReport) -> Bool {
        if lhs.checkedAt != rhs.checkedAt { return lhs.checkedAt > rhs.checkedAt }
        return lhs.id < rhs.id
    }
}
