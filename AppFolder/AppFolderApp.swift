import AppFolderKit
import SwiftUI
import WidgetKit

@main
struct AppFolderApp: App {
    var body: some Scene {
        WindowGroup {
            TutorialView()
                .task { Self.collapseExpandedWidgets() }
        }
    }

    /// Asks every widget to drop any expansion when the app comes forward.
    ///
    /// A grid left expanded on the Home Screen is a transient view state, and
    /// opening the app is a strong signal the user has moved on from it. Left
    /// alone, the widget would still be showing that page the next time it is
    /// looked at.
    ///
    /// ## Why this is the app's only remaining behaviour
    ///
    /// It is the last thing the app and the widget still share. Everything else
    /// the app used to own — the folder library, the share queue, the icon cache
    /// — has been deleted, because the direct-launch widget does not read any of
    /// it: its slots live in the system's widget configuration and its icons are
    /// fetched by the extension itself. This counter is the one piece of state
    /// that has to cross the process boundary, so it is the one thing the app
    /// still does.
    ///
    /// The request is unconditional: ``WidgetState/requestCollapse()`` bumps a
    /// counter and the widget compares it against the value it last acted on, so
    /// nothing here has to know whether anything was actually open. That is what
    /// makes it survive being read by two widgets, being missed because WidgetKit
    /// declined a reload, or being followed by another launch — none of which a
    /// flag would.
    ///
    /// The reload is requested because the counter lives in shared defaults the
    /// widget only reads when it builds a timeline; without the nudge the change
    /// would sit there until the system decided to refresh it on its own.
    private static func collapseExpandedWidgets() {
        WidgetState.requestCollapse()
        WidgetCenter.shared.reloadAllTimelines()
    }
}