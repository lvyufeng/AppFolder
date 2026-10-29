import Foundation

/// A per-website opening choice. Resolving a choice performs no I/O and does
/// not inspect installed apps; the host handles an explicit open's result.
public enum WebsiteBrowser: String, Codable, CaseIterable, Sendable {
    case systemDefault, inAppSafari, chrome, firefox, appDefault

    /// Choices that can be stored as the app's local default. Following that
    /// default is a per-website choice, never a recursively stored preference.
    public static let concreteCases: [WebsiteBrowser] = [.systemDefault, .inAppSafari, .chrome, .firefox]

    public var displayName: String {
        switch self {
        case .systemDefault: "系统默认浏览器"
        case .inAppSafari: "App 内浏览"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .appDefault: "跟随 App 设置"
        }
    }

    /// Old nil/system-default website records remain explicit system routing.
    /// Only a website that opts in to appDefault follows the local preference.
    public func resolved(using appBrowser: WebsiteBrowser) -> WebsiteBrowser {
        guard self == .appDefault else { return self }
        return appBrowser == .appDefault ? .systemDefault : appBrowser
    }

    /// The original HTTP(S) URL remains the saved destination. Browser schemes
    /// are transport URLs only and must never replace it in the library.
    /// In-app Safari uses the original URL directly and has no external URL.
    /// Resolve appDefault with the current local preference before calling.
    public func externalURL(for url: URL) -> URL? {
        let original = url.absoluteString
        guard url.baseURL == nil, WebsiteURL.validated(original) != nil else { return nil }
        switch self {
        case .systemDefault:
            return url
        case .inAppSafari, .appDefault:
            return nil
        case .chrome:
            // Chromium's documented mapping replaces only the scheme, keeping
            // the original path, percent escapes, query order and fragment.
            // https://chromium.googlesource.com/chromium/src/+/main/docs/ios/opening_links.md
            guard let colon = original.firstIndex(of: ":") else { return nil }
            let scheme = url.scheme?.lowercased() == "https" ? "googlechromes" : "googlechrome"
            return URL(string: scheme + original[colon...])
        case .firefox:
            // FirefoxURLBuilder uses a single encoded `url` query parameter.
            // URLScanner appends later outer parameters to the target; keep it
            // the only parameter and do not pre-decode the original URL.
            // https://github.com/mozilla-mobile/firefox-ios/blob/3316313c0f2401bff42b26fea7014cb5dfbbd0f4/BrowserKit/Sources/ActionExtensionKit/FirefoxURLBuilding.swift
            // Firefox itself may reserialize the target query after receiving
            // it. This transport preserves the original payload, not that
            // browser's subsequent navigation representation.
            let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            guard let encoded = original.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
            return URL(string: "firefox://open-url?url=" + encoded)
        }
    }
}
