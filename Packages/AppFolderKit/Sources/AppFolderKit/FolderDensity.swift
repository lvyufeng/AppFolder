import WidgetKit

/// Larger-family grid density. Small keeps its separate four/nine-cell choice;
/// the unregistered landscape extra-large family retains its legacy shape.
public enum FolderDensity: String, Codable, Sendable, Hashable, CaseIterable {
    case standard, spacious, dense

    public static let `default`: FolderDensity = .standard

    func effective(for family: WidgetFamily) -> Self {
        switch family {
        case .systemMedium, .systemLarge, .systemExtraLargePortrait: self
        default: .standard
        }
    }
}
