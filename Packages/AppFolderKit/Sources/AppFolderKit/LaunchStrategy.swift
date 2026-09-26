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
public enum LaunchStrategy: String, Codable, Sendable, CaseIterable {
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

    /// Whether the target app opens without AppFolder appearing on screen.
    public var isHopFree: Bool {
        switch self {
        case .universalLink, .systemShortcut: true
        case .bounce: false
        }
    }

    public var localizedName: String {
        switch self {
        case .universalLink: "直接打开"
        case .bounce: "经 AppFolder 中转"
        case .systemShortcut: "系统快捷启动"
        }
    }

    /// A one-line explanation for the tile editor, so the choice is not a
    /// mystery the user has to guess at.
    public var localizedExplanation: String {
        switch self {
        case .universalLink:
            "系统直接打开目标 App，AppFolder 不会出现在屏幕上。需要目标 App 支持通用链接。"
        case .bounce:
            "先打开 AppFolder，再由它跳转到目标 App。会有一次明显的切换，但任何 App 都适用。"
        case .systemShortcut:
            "由系统代为打开，最快且无切换。需要 iOS 27，且目标要在小组件配置里手动选择。"
        }
    }

    /// Whether a tap can fail with no feedback.
    ///
    /// Only the hop-free routes can: the system runs them out of process and
    /// reports nothing, so a target that refuses to open looks exactly like a
    /// target that opened. The bounce route always produces something visible,
    /// even when it fails — AppFolder comes to the front either way.
    public var canFailSilently: Bool { isHopFree }
}
