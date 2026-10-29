import Foundation

/// Constants shared by the app, widget and share extensions, and intents.
///
/// Everything here is a string that must match something outside this package —
/// an entitlement, an Info.plist key, or a widget kind registered by the
/// extension. Keeping them in one place is the difference between "the widget
/// renders blank" and "the widget renders blank, and we know why".
///
/// Saved groups, artwork, pending shared websites, and widget navigation state
/// use the same App Group container. Their stores own their file and key names.
public enum AppFolderShared {
    /// App Group container for saved groups, downloaded and custom artwork,
    /// pending shared websites, and shared widget navigation state.
    ///
    /// Requires the App Groups capability on the app and both extensions.
    /// If the container is unavailable, these shared data features are
    /// unavailable; stores report that state instead of using local fallbacks.
    public static let appGroupIdentifier = "group.com.lvyufeng.appfolder"

    /// The kind of the direct-launch widget, whose slots open apps with no hop.
    ///
    /// Kept in step with the `kind` passed to `WidgetConfiguration` in
    /// ``DirectLaunchWidget``. The *folder* widget's kind used to sit beside this
    /// one; it is gone with the widget. That widget could not simply be repurposed
    /// into this one: this one's configuration intent carries `SystemShortcut`
    /// values, which exist only in a widget's own configuration and cannot be
    /// stored beside a folder.
    public static let directLaunchWidgetKind = "AppFolderDirectLaunch"

    /// The independent Lock Screen launcher, with one or two selected leaf items.
    public static let lockScreenWidgetKind = "AppFolderLockScreenLaunch"
}
