import AppIntents
import Foundation

/// Opens a tile whose target is an `https://` universal link.
///
/// Why this exists at all, given that a widget can already render a `Link`: a
/// `Link` in a widget opens *the containing app*, so pointing one at another
/// app's URL just opens AppFolder. The only way to get the *system* to open a
/// third-party URL from a widget is to return it from an intent as an
/// `opensIntent`, which asks the system to run `OpenURLIntent` — and the system,
/// unlike a widget, is allowed to route anywhere.
///
/// `OpenURLIntent` reaches apps through their universal links. Apple requires
/// universal-link support for `URLRepresentableIntent` and states that custom
/// schemes are not supported, so this intent is used for `.universalLink` tiles
/// only; custom schemes go through ``LaunchLink`` and the host app instead.
///
/// `openAppWhenRun` stays `false`: the point is to reach the target app, not
/// ours.
public struct OpenLinkIntent: AppIntent {
    public static let title: LocalizedStringResource = "打开链接"

    @Parameter(title: "标识")
    public var tileID: String

    /// An `https://` URL the target app claims.
    @Parameter(title: "链接")
    public var url: URL

    public init() {}

    public init(tileID: String, url: URL) {
        self.tileID = tileID
        self.url = url
    }

    /// Resolves the URL for a tile, refusing anything that cannot work.
    ///
    /// The check is worth having even though the strategy is stored: a universal
    /// link tile whose URL was later edited to a custom scheme would otherwise
    /// be a tile that silently does nothing when tapped.
    public init(tile: FolderTile) throws {
        guard let url = tile.url else {
            throw TileError.malformedURL(tile.urlString)
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw TileError.notAUniversalLink(tile.urlString)
        }
        self.init(tileID: tile.id.uuidString, url: url)
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("打开 \(\.$url)")
    }

    public func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(url))
    }
}

public enum TileError: Error, CustomLocalizedStringResourceConvertible {
    case malformedURL(String)
    case notAUniversalLink(String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .malformedURL(let raw):
            "「\(raw)」不是有效的链接"
        case .notAUniversalLink(let raw):
            "「\(raw)」不是 https 链接，无法直接打开，请改用中转方式"
        }
    }
}
