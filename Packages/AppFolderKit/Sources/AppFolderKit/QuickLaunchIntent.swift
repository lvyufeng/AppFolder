import AppIntents
import Foundation

/// The iOS 27 route: let the *system* own the user's choice of app.
///
/// Everything else in this package works around a limitation — a widget cannot
/// name another app, so we either hand the system a URL and hope it routes there,
/// or make a visible hop through AppFolder. `RunSystemShortcutIntent` removes the
/// limitation instead of working around it. Apple's documentation:
///
/// > An app intent you use in widgets to open another app or perform an App
/// > Shortcut, custom shortcut, or system action.
/// >
/// > When a person configures the widget, they choose the button's action. It
/// > can: Open another installed app. Perform an App Shortcut. Perform a custom
/// > shortcut a person creates in Shortcuts. Perform a system action.
///
/// The price is that *the user* picks the app, not us. `SystemShortcut` is opaque
/// on purpose:
///
/// > An opaque reference to a user-configured action for use in a widget button.
/// > … It doesn't provide the app or widget with a custom shortcut's actions,
/// > parameters, or implementation details.
///
/// ## Why this back the single tile, and a grid
///
/// One widget configuration has one action slot, so this cannot fill nine tiles
/// from a catalogue — that is what ``LaunchStrategy/bounce`` and
/// ``LaunchStrategy/universalLink`` are for. Both of those carry a cost this one
/// doesn't: a hop, or a target that has to publish a universal link.
///
/// The honest arrangement is to let the user put their most-used app on the
/// widget through this route, and fill the rest of a folder the ordinary way.
/// That is why the fallback path exists as well: a first tap on an unconfigured
/// slot should offer to *configure* it, not silently do nothing.
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
