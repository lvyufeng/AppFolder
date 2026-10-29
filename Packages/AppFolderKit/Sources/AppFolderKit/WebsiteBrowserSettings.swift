import Foundation

/// A preference for this app installation. Widgets carry saved identities to
/// the host for appDefault websites; only the host reads this local setting.
/// The setting itself is not part of a library backup or a shared app group.
public enum WebsiteBrowserSettings {
    public static let defaultsKey = "websiteBrowser.default"

    public static func selectedBrowser(in defaults: UserDefaults = .standard) -> WebsiteBrowser {
        guard let raw = defaults.object(forKey: defaultsKey) as? String,
              let browser = WebsiteBrowser(rawValue: raw),
              WebsiteBrowser.concreteCases.contains(browser) else { return .systemDefault }
        return browser
    }

    /// No network request, installation scan or widget refresh is performed.
    /// Rejected recursive selections leave the previous preference untouched.
    @discardableResult
    public static func setBrowser(_ browser: WebsiteBrowser, in defaults: UserDefaults = .standard) -> Bool {
        guard WebsiteBrowser.concreteCases.contains(browser) else { return false }
        defaults.set(browser.rawValue, forKey: defaultsKey)
        return defaults.object(forKey: defaultsKey) as? String == browser.rawValue
    }
}
