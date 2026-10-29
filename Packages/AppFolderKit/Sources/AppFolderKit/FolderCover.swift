import Foundation

/// An opaque content digest, never a user-supplied file path.
public struct FolderCoverAssetID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.utf8.count == 64,
              rawValue.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let id = Self(rawValue: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid cover asset ID"))
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(rawValue)
    }
}

/// Only references enter layouts, undo snapshots and widget navigation entries.
/// Nil standard uses the folder's content preview; nil dark inherits standard.
public struct FolderCover: Codable, Sendable, Equatable {
    public let standard: FolderCoverAssetID?
    public let dark: FolderCoverAssetID?

    public init(standard: FolderCoverAssetID? = nil, dark: FolderCoverAssetID? = nil) {
        self.standard = standard
        self.dark = dark
    }

    public var isValid: Bool { standard != nil || dark != nil }
    public var assetIDs: Set<FolderCoverAssetID> { Set([standard, dark].compactMap { $0 }) }
    public func resolved(isDark: Bool) -> FolderCoverAssetID? { isDark ? dark ?? standard : standard }

    /// Compare this cover with its validated read result. An absent optional
    /// appearance is intentional; a referenced appearance that failed to load
    /// needs a later read, including when the other appearance still renders.
    public func hasMissingArtwork(in artwork: CustomIconVariants?) -> Bool {
        (standard != nil && artwork?.standard == nil) || (dark != nil && artwork?.dark == nil)
    }
}
