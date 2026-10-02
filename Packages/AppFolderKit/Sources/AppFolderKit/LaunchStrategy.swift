import Foundation

/// How a tile asks the system to open its target.
///
/// Three routes, and the choice is forced by two documented platform rules
/// rather than by preference:
///
/// 1. A widget's `Link`/`widgetURL` can only open *the containing app*:
///    "the system activates the containing app and passes the URL to
///    `onOpenURL`."
/// 2. `OpenURLIntent` reaches an app through its **universal link**, not its
///    custom scheme. Apple's docs require universal-link support for
///    `URLRepresentableIntent`, and DTS has stated custom schemes are not
///    supported. A custom scheme handed to `OpenURLIntent` does nothing.
///
/// So a target's *URL shape* decides the route, not our preference.
public enum LaunchStrategy: String, Codable, Sendable {
    /// The target is an `https://` universal link. Hand it to the system and it
    /// opens the right app — or the browser, if no app claims it.
    ///
    /// This is the only route with no visible hop, and it is the route the
    /// system is designed around. It is available exactly when the target
    /// publishes a universal link, which many large apps do for their own web
    /// URLs but few do for a bare "open the app" action.
    case universalLink

    /// The target is a custom scheme (`weixin://`). The widget opens AppFolder
    /// with the target attached; AppFolder calls `open(_:)` and the target app
    /// takes over.
    ///
    /// One visible hop, and it is the reason third-party launchers have a
    /// reputation for feeling worse than the Home Screen. It is also the only
    /// route that works for a custom scheme on iOS 18–26, and custom schemes are
    /// what most apps actually expose.
    case bounce

    /// The target is a `SystemShortcut` the user picked when configuring the
    /// widget (iOS 27+).
    ///
    /// Neither we nor the widget ever learn which app this is — the system holds
    /// an opaque reference and opens it directly. No hop, any app, including
    /// ones with no URL scheme and no universal link. The constraint is that it
    /// cannot back a grid: the user picks one action per configuration slot, so
    /// this route suits a few tiles the user configures by hand, not nine tiles
    /// assembled from a catalogue.
    case systemShortcut

    /// The default route for a target we only know a scheme for.
    public static let `default`: LaunchStrategy = .bounce
}

// `isHopFree`, `canFailSilently`, `localizedName` and `localizedExplanation`
// used to live here, describing each route to the user so the editor could offer
// them as a menu. The menu is gone — the route is derived, see
// ``FolderTile/launchRoute`` — and with it the only caller of these. They are
// not kept "just in case": a route the user cannot pick does not need a display
// name, and a `canFailSilently` that nothing branches on would be a claim about
// behaviour that no longer has a consequence in the code.
