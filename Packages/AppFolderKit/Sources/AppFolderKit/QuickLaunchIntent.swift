import AppIntents
import Foundation

/// The iOS 27 route: let the *system* own the user's choice of app.
///
/// Everything else in this package works around a limitation — a widget cannot
/// name another app, so we either hand the system a URL and hope it routes there
/// (``LaunchStrategy/direct``), or make a visible hop through AppFolder
/// (``LaunchStrategy/bounce``). `RunSystemShortcutIntent` removes the limitation
/// instead of working around it. Apple's documentation:
///
/// > An app intent you use in widgets to open another app or perform an App
/// > Shortcut, custom shortcut, or system action.
/// >
/// > When a person configures the widget, they choose the button's action. It
/// > can: Open another installed app. Perform an App Shortcut. Perform a custom
/// > shortcut a person creates in Shortcuts. Perform a system action.
///
/// The price is that *the user* picks the app, not us. `SystemShortcut` is
/// opaque on purpose:
///
/// > An opaque reference to a user-configured action for use in a widget button.
/// > … It doesn't provide the app or widget with a custom shortcut's actions,
/// > parameters, or implementation details.
///
/// So this cannot back a folder — a grid of nine tiles needs nine app choices,
/// and the configuration UI offers one action per widget. What it can back is the
/// single most-used tile, and that is a genuinely better answer than either
/// workaround: one tap, no hop, for an app the user named themselves.
///
/// Available on iOS 27 and later only. Below that, `supportedFamilies` and the
/// widget's own availability gate it out.
///
/// The `os(iOS)` gate is a build-system concession, not a product decision:
/// `SystemShortcut` is declared `@available(macOS, unavailable)`, and this
/// package also compiles on the host so `swift build` can type-check it in
/// seconds without a device build.
#if os(iOS)
@available(iOS 27.0, *)
public struct QuickLaunchIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "快速启动"
    public static let description: IntentDescription = "选择一个 App 或快捷指令，在小组件上一点即开。"

    /// The action the user configured. The system resolves this; we never learn
    /// what it is.
    @Parameter(title: "动作")
    public var shortcut: SystemShortcut?

    public init() {}

    public init(shortcut: SystemShortcut?) {
        self.shortcut = shortcut
    }
}
#endif
