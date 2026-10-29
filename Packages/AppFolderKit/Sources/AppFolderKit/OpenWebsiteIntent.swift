import AppIntents
import Foundation

public enum OpenWebsiteError: Error, Equatable, Sendable {
    case invalidURL
}

/// The background wrapper has metadata in both app and widget bundles. Returning
/// the system URL intent delegates routing without requesting AppFolder's foreground.
public struct OpenWebsiteIntent: AppIntent {
    public static let title: LocalizedStringResource = "打开网站"
    public static let isDiscoverable = false

    @Parameter(title: "网址") public var url: String

    public init() {}
    public init(url: String) { self.url = url }

    public func perform() async throws -> some IntentResult & OpensIntent {
        guard let destination = WebsiteURL.validated(url) else { throw OpenWebsiteError.invalidURL }
        return .result(opensIntent: OpenURLIntent(destination))
    }
}
