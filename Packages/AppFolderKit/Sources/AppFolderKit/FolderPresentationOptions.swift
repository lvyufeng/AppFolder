import Foundation

/// The symbol for returning to the containing saved-group folder.
public enum FolderBackButtonStyle: String, Codable, Sendable, CaseIterable {
    case chevronUp, turnUpLeft, folder

    public var systemImage: String {
        switch self {
        case .chevronUp: "chevron.up"
        case .turnUpLeft: "arrow.turn.up.left"
        case .folder: "folder"
        }
    }
}

/// A folder node's own content miniature, independent of inherited page styles.
/// The default overflow cell keeps its existing fixed miniature arrangement.
public enum FolderPreviewGrid: String, Codable, Sendable, CaseIterable {
    case four, nine

    public var columns: Int { self == .four ? 2 : 3 }
    public var capacity: Int { columns * columns }
}
