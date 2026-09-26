import Foundation

/// Transient widget-display state, kept where both processes can see it.
///
/// Deliberately *not* part of ``FolderLibrary``: this changes on every tap and
/// must never end up in a user's backup, whereas the library changes rarely and
/// is exactly what should be exported.
///
/// Note what is *absent* here. There is no "did the last launch work" flag,
/// because there is no way to know: a direct launch runs out of process and the
/// system reports nothing back, so from inside the widget a successful tap and a
/// tap that did nothing look identical. Recording every attempt as suspicious
/// would flag working tiles as broken. Per-tile launch behaviour is therefore
/// configured and tested in the app, where the user can see what happened — see
/// `FolderEditorView`.
public enum WidgetState {
    /// `UserDefaults` is documented as thread-safe, so sharing one instance
    /// across the app and the widget's intent runner is sound; the compiler has
    /// no way to know that, because the class predates `Sendable`.
    private nonisolated(unsafe) static let defaults =
        UserDefaults(suiteName: AppFolderShared.appGroupIdentifier) ?? .standard

    private enum Key {
        static let expandedFolderID = "widget.expandedFolderID"
    }

    /// The folder currently expanded inside the widget, if any.
    public static var expandedFolderID: String? {
        get { defaults.string(forKey: Key.expandedFolderID) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.expandedFolderID)
            } else {
                defaults.removeObject(forKey: Key.expandedFolderID)
            }
        }
    }

    public static func collapse() {
        expandedFolderID = nil
    }
}
