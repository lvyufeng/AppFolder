import Foundation

/// A link from a widget back into AppFolder, carrying where to go.
///
/// Two hosts so far, and the split matters because they do opposite things to
/// the URL they carry:
///
/// * `launch` — open this *other* URL for me. The app is a way-station; see
///   ``bounceURL(for:)``.
/// * `folder` — open this folder of *mine*, expanded. The app is the
///   destination; see ``folderURL(for:)``.
///
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

    // MARK: - Opening a folder

    /// The host for "open one of my folders, expanded".
    private static let folderHost = "folder"
    private static let folderKey = "id"

    /// A link that opens AppFolder showing this folder's whole contents.
    ///
    /// This is what the grid's last cell points at once a folder holds more apps
    /// than cells. A widget cannot expand anything itself — it is a snapshot, not
    /// a view hierarchy — so the tap has to leave the widget, and the only place
    /// it can go is the app that owns it.
    ///
    /// The id is the folder's `UUID`, which is stable across launches and already
    /// in the library file. Carrying the *name* instead would break the moment
    /// two folders shared one, which is allowed.
    public static func folderURL(for id: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = folderHost
        components.queryItems = [URLQueryItem(name: folderKey, value: id.uuidString)]
        return components.url
    }

    /// The folder id carried by a folder link, or `nil` if this is not one.
    ///
    /// Returns `nil` for a well-formed folder link whose id is not a UUID: the
    /// caller's next step is a library lookup, and an id that cannot match
    /// anything is the same answer as no id at all.
    public static func folderID(from incoming: URL) -> UUID? {
        guard incoming.scheme == scheme, incoming.host == folderHost else { return nil }
        guard
            let components = URLComponents(url: incoming, resolvingAgainstBaseURL: false),
            let raw = components.queryItems?.first(where: { $0.name == folderKey })?.value
        else { return nil }
        return UUID(uuidString: raw)
    }
}
