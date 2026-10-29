import Foundation

/// A local navigation request containing identifiers and help context only. This
/// never supplies a website, an action name, or an instruction to run an action.
public struct SavedGroupHelpRoute: Sendable, Equatable {
    public enum Surface: Sendable, Equatable {
        case homeScreen, lockScreen
    }

    public static let maximumUTF8Bytes = 1_024

    public let groupID: UUID
    public let itemID: UUID?
    public let reportID: String?
    public let surface: Surface

    private static let prefix = "appfolder://group-help?"

    /// Invalid optional report hints are omitted, so typed callers always get
    /// a valid URL without a precondition failure. Untrusted URLs are stricter:
    /// an explicitly supplied invalid report causes parsing to fail entirely.
    public init(groupID: UUID, itemID: UUID? = nil, reportID: String? = nil, surface: Surface = .homeScreen) {
        self.groupID = groupID
        self.itemID = itemID
        self.reportID = reportID.flatMap { Self.isValidReportID($0) ? $0 : nil }
        self.surface = surface
    }

    public var url: URL {
        var query = "group=\(groupID.uuidString)"
        if let itemID { query += "&item=\(itemID.uuidString)" }
        if let reportID { query += "&report=\(reportID)" }
        if surface == .lockScreen { query += "&surface=lock-screen" }
        // Constants, UUIDs and the validated ASCII hash cannot need escaping.
        return URL(string: Self.prefix + query)!
    }

    public init?(url: URL) {
        let value = url.absoluteString
        guard url.baseURL == nil, value.utf8.count <= Self.maximumUTF8Bytes,
              value.hasPrefix(Self.prefix) else { return nil }

        // Parse the small ASCII protocol directly rather than accepting URL
        // normalization or percent-encoded aliases. The exact authority prefix
        // also excludes credentials, ports, paths and other schemes or hosts.
        let fields = value.dropFirst(Self.prefix.count)
            .split(separator: "&", omittingEmptySubsequences: false)
        guard (1...4).contains(fields.count) else { return nil }
        var values: [String: String] = [:]
        for field in fields {
            let pair = field.split(separator: "=", omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            let key = String(pair[0])
            guard ["group", "item", "report", "surface"].contains(key), values[key] == nil else { return nil }
            values[key] = String(pair[1])
        }
        guard let group = values["group"], let groupID = Self.uuid(group) else { return nil }
        let itemID: UUID?
        if let item = values["item"] {
            guard let parsed = Self.uuid(item) else { return nil }
            itemID = parsed
        } else {
            itemID = nil
        }
        if let report = values["report"], !Self.isValidReportID(report) { return nil }
        let surface: Surface
        if let value = values["surface"] {
            guard value == "lock-screen" else { return nil }
            surface = .lockScreen
        } else {
            surface = .homeScreen
        }
        self.init(groupID: groupID, itemID: itemID, reportID: values["report"], surface: surface)
    }

    private static func uuid(_ value: String) -> UUID? {
        guard value.utf8.count == 36, let id = UUID(uuidString: value),
              id.uuidString.lowercased() == value.lowercased() else { return nil }
        return id
    }

    private static func isValidReportID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
