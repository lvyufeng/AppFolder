import AppFolderKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct AppFolderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var openRequest: AppOpenRequest?
    @State private var queuedRequest: AppOpenRequest?
    @State private var dateIconRefreshToken = 0

    var body: some Scene {
        WindowGroup {
            TutorialView()
                .environment(\.dateIconRefreshToken, dateIconRefreshToken)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        dateIconRefreshToken &+= 1
                        Self.collapseExpandedWidgets()
                    }
                    if phase == .background {
                        // A presentation can be waiting for another sheet's
                        // transition. Revoke its shared permission even when
                        // ContactLaunchView has not appeared to observe this.
                        openRequest?.automaticContactLaunchPermission.revoke()
                        queuedRequest?.automaticContactLaunchPermission.revoke()
                        openRequest?.automaticWebsiteLaunchPermission.revoke()
                        queuedRequest?.automaticWebsiteLaunchPermission.revoke()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    refreshDateIcons()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    refreshDateIcons()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                    refreshDateIcons()
                }
                .onOpenURL(perform: receive)
                .background {
                    AppOpenRequestPresenter(request: openRequest) { id in
                        guard openRequest?.id == id else { return }
                        openRequest = nil
                        openQueuedRequest()
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
    }

    /// Asks every widget to drop any expansion when the app comes forward.
    ///
    /// A grid left expanded on the Home Screen is a transient view state, and
    /// opening the app is a strong signal the user has moved on from it. Left
    /// alone, the widget would still be showing that page the next time it is
    /// looked at.
    ///
    /// Observe the scene becoming active rather than a view task. The root view
    /// survives while the app is in the background, so its task does not run again
    /// when the user returns to an already-open app.
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
        SavedGroupNavigation.reset()
        WidgetState.requestCollapse()
        AppFolderWidgetRefresh.libraryChanged()
    }

    private func refreshDateIcons() {
        dateIconRefreshToken &+= 1
        AppFolderWidgetRefresh.libraryChanged()
    }

    private func receive(_ url: URL) {
        let destination: AppOpenRequest.Destination
        if let route = SavedGroupHelpRoute(url: url) {
            destination = .groupHelp(route)
        } else if let route = ContactLaunchRoute(url: url) {
            destination = .contact(route)
        } else if let route = WebsiteLaunchRoute(url: url) {
            destination = .website(route)
        } else if url.isFileURL, ["appfolderbackup", "json"].contains(url.pathExtension.lowercased()) {
            destination = .backup(url)
        } else {
            return
        }
        // Keep a visible import preview or help page intact. Repeated taps on
        // the same route refresh through scenePhase, without stacking a copy.
        if openRequest?.destination == destination, !destination.isBackup {
            return
        } else if openRequest == nil {
            openRequest = AppOpenRequest(destination: destination,
                                         allowsAutomaticWebsiteLaunch: scenePhase != .background)
        } else {
            // A delayed request is displayed for a fresh tap, never executed
            // automatically when an unrelated editor/import finally closes.
            queuedRequest = AppOpenRequest(destination: destination, allowsAutomaticContactLaunch: false,
                                           allowsAutomaticWebsiteLaunch: false)
        }
    }

    private func openQueuedRequest() {
        guard let request = queuedRequest else { return }
        queuedRequest = nil
        openRequest = request
    }
}

@MainActor
struct AppOpenRequest: Identifiable {
    enum Destination: Equatable {
        case backup(URL)
        case groupHelp(SavedGroupHelpRoute)
        case contact(ContactLaunchRoute)
        case website(WebsiteLaunchRoute)

        var isBackup: Bool {
            if case .backup = self { return true }
            return false
        }
    }
    let id = UUID()
    let destination: Destination
    let automaticContactLaunchPermission: AutomaticContactLaunchPermission
    let automaticWebsiteLaunchPermission: AutomaticWebsiteLaunchPermission
    let receivedAt = ContinuousClock().now

    init(destination: Destination, allowsAutomaticContactLaunch: Bool = true,
         allowsAutomaticWebsiteLaunch: Bool = true) {
        self.destination = destination
        self.automaticContactLaunchPermission = AutomaticContactLaunchPermission(isAllowed: allowsAutomaticContactLaunch)
        self.automaticWebsiteLaunchPermission = AutomaticWebsiteLaunchPermission(isAllowed: allowsAutomaticWebsiteLaunch)
    }
}

/// Shared by the pending request and its presented view. Revocation reaches a
/// view even if presentation or its first task is delayed across backgrounding.
@MainActor
final class AutomaticContactLaunchPermission {
    private(set) var isAllowed: Bool

    init(isAllowed: Bool) { self.isAllowed = isAllowed }
    func revoke() { isAllowed = false }
}

/// A website request keeps its own permission; revoking it cannot change a
/// contact request's lifecycle or communication policy.
@MainActor
final class AutomaticWebsiteLaunchPermission {
    private(set) var isAllowed: Bool

    init(isAllowed: Bool) { self.isAllowed = isAllowed }
    func revoke() { isAllowed = false }
}
