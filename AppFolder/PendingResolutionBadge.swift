import AppFolderKit
import Foundation
import UserNotifications

/// Keeps the app icon's badge equal to the number of unresolved shares.
///
/// ## Why a badge, and why it is the whole notification story
///
/// A share the app cannot resolve becomes **no tile at all** — no placeholder, no
/// dimmed cell. That is deliberate: a tile that cannot open is worse than no tile,
/// because the user only discovers the difference by tapping. But it leaves the
/// person who just shared an app looking at a Home Screen with nothing new on it,
/// and no way to tell whether the share worked.
///
/// The badge answers exactly that, and nothing else. It is the smallest possible
/// signal — it changes a numeral on one icon, puts nothing on the Home Screen, and
/// sends no banner. An app that is a launcher should not be interrupting anyone; it
/// should be telling them there is something to finish when they next open it.
///
/// ## Why it needs authorization, and why that is asked for narrowly
///
/// `UNAuthorizationOptionBadge` is a separate bit from alert and sound, and
/// `UNNotificationSettings` exposes `badgeSetting` separately from `alertSetting`
/// and `soundSetting` for the same reason — so an app can request the numeral
/// *without* ever being able to show a banner or play a sound. That is the only
/// permission this app asks for anywhere, and it is asked for at the one moment it
/// is meaningful: when there is something to count.
///
/// It is still a permission, and the user can refuse it. When they do, the badge
/// simply does not appear — there is no error, no fallback, and nothing on screen
/// that would explain the silence. So ``availability()`` is exposed for the 排查
/// screen: an unexplained missing badge is exactly the kind of failure this project
/// has had to stop guessing at.
///
/// ## Measured: `setBadgeCount` succeeds even when no badge is possible
///
/// On a fresh install, with authorization still `notDetermined` and `badgeSetting`
/// reporting `.notSupported`, `setBadgeCount(1)` **returns without throwing** — and
/// the Home Screen icon shows no numeral. Verified on the iOS simulator after a
/// reboot and a clean install, so the absence is not a stale icon cache.
///
/// This is the reason the 排查 screen reads `notificationSettings` instead of
/// trusting a call to have worked, and the reason ``apply(_:)`` checks `granted`
/// rather than relying on the throw. A `try?` around `setBadgeCount` would swallow
/// nothing, because there is nothing to swallow: the failure is silent by design.
///
/// If the user refuses, nothing else breaks. The queue is still there, the editor
/// still lists it, and confirming still works. The badge is a convenience on top of
/// a flow that does not depend on it.
@MainActor
enum PendingResolutionBadge {
    /// Whether a numeral can appear on the app icon at all.
    ///
    /// Three answers rather than a `Bool`, because the two ways of *not* having a
    /// badge are different situations with different remedies and only one of them
    /// is the user's doing. The same reasoning as ``InstallationProber/InstallStatus``:
    /// collapsing "we asked and were refused" into "we never asked" is how a
    /// screen starts reporting a decision the user never made.
    enum Availability: Sendable, Equatable {
        /// Never asked. The normal state before the first share, and not a fault.
        case notRequested
        /// Asked and granted: a numeral will appear.
        case available
        /// Asked and refused — the user's own decision, reported as such.
        case refused
        /// Authorization exists but the badge specifically is unsupported. Seen on
        /// the simulator with authorization `notDetermined`, where `badgeSetting`
        /// is `.notSupported` rather than `.disabled`.
        case unsupported
    }

    /// Asks for the badge permission, once, at the moment the queue stops being
    /// empty.
    ///
    /// Deliberately narrow: ``UNAuthorizationOptions/badge`` and nothing else, so
    /// the system prompt says the app wants to show a number, not that it wants to
    /// send notifications. The two are the same request object but not the same
    /// thing to the person reading the prompt.
    private static var hasRequested = false

    /// Sets the badge to the current queue depth, asking for permission first if
    /// this is the first time there has been anything to show.
    static func refresh() {
        let count = PendingResolutionStore().count()
        Task { await apply(count) }
    }

    /// What the 排查 screen should say about the badge.
    ///
    /// Read from `notificationSettings` rather than remembered from the request,
    /// because the answer can change in Settings while the app is backgrounded —
    /// and because, per the note above, the request's own return value does not
    /// report whether a numeral will actually be drawn.
    static func availability() async -> Availability {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus != .notDetermined else { return .notRequested }
        switch settings.badgeSetting {
        case .enabled: return .available
        case .disabled: return .refused
        default: return .unsupported
        }
    }

    private static func apply(_ count: Int) async {
        let centre = UNUserNotificationCenter.current()

        if count > 0, !hasRequested {
            hasRequested = true
            // Requested lazily and only when it will be used. An app that asks for
            // a permission on first launch, before it has anything to show, is
            // asking the user to decide something they have no context for.
            let granted = (try? await centre.requestAuthorization(options: [.badge])) ?? false
            guard granted else {
                // Refused: there is nothing to do and nothing to report here. The
                // count is still tracked, the editor still lists it.
                return
            }
        }

        // Zero clears the numel as surely as any number sets it — this is the
        // documented way to remove a badge (`applicationIconBadgeNumber` is
        // deprecated as of iOS 17 in favour of exactly this call).
        try? await centre.setBadgeCount(count)
    }
}