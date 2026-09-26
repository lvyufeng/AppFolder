import Foundation

/// The bounce link: how a widget tile hands a target URL to the system on
/// versions and apps where the direct route doesn't apply.
///
/// This exists because of a hard platform rule, documented by Apple for
/// `Link`/`widgetURL`:
///
/// > The system activates the containing app and passes the URL to `onOpenURL`.
///
/// A widget can therefore never launch *another* app by pointing a link at it.
/// What it can do is open its own app with the target tucked into the URL — and
/// then the app, which is allowed to call `open(_:)` freely, makes the second
/// hop. Hence "bounce".
///
/// The direct alternative is ``LaunchTileIntent``, which asks the system to run
/// `OpenURLIntent` on the widget's behalf and skips the hop. Which one a given
/// tile can use depends on the target app and the OS; ``LaunchStrategy`` picks.
public enum LaunchLink {
    /// The app's own scheme, declared in `Config/AppFolder-Info.plist`.
    public static let scheme = "appfolder"

    private static let host = "launch"
    private static let targetKey = "u"

    /// Wraps a target URL so the host app will receive it and bounce onward.
    ///
    /// Returns `nil` only if the target is not a URL at all, which the compiler
    /// already makes hard to express.
    public static func bounceURL(for target: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: targetKey, value: target.absoluteString)]
        return components.url
    }

    /// The target URL carried by a bounce link, or `nil` if this is not one.
    public static func targetURL(from incoming: URL) -> URL? {
        guard incoming.scheme == scheme, incoming.host == host else { return nil }
        guard
            let components = URLComponents(url: incoming, resolvingAgainstBaseURL: false),
            let raw = components.queryItems?.first(where: { $0.name == targetKey })?.value
        else { return nil }
        return URL(string: raw)
    }
}
