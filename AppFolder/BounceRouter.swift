import AppFolderKit
import SwiftUI

/// Completes the widget's `.bounce` route, and hides the evidence.
///
/// A tile that can't reach its target directly opens AppFolder with the target
/// attached. That makes AppFolder a way-station the user never asked to visit,
/// so the job is to be gone again before they notice. Two things follow:
///
/// 1. **Open immediately.** Nothing here reads the library, resolves an icon, or
///    waits for the model to finish loading. The URL is parsed and handed to the
///    system in the same turn it arrives.
/// 2. **Draw nothing while it happens.** `RootView` swaps in a blank surface for
///    the duration, so the hand-off looks like a slow app launch rather than
///    AppFolder appearing and then vanishing. Without this the folder list
///    renders, scrolls into place, and is torn away again — which is both slower
///    to look at and obviously wrong.
///
/// The flag is deliberately awkward to clear, because each of the easy ways to
/// clear it is a bug:
///
/// * Clearing when `open` reports success would flash the UI, since success only
///   means the system accepted the request — the app is still frontmost for a
///   moment afterwards.
/// * Clearing on the next `.active` would flash too: the app passes through
///   `.active` on its way *out*, before it ever backgrounds.
///
/// So the blank surface comes down only once the app has actually been to the
/// background and come back. The timeout is the backstop: if the target app
/// never took over — a scheme with no handler, or a launch the system declined —
/// the user gets their launcher back rather than a blank screen forever.
///
/// ## Telling a failed hand-off from an unattributed timeout
///
/// `open(_:)`'s completion only reports whether the system *accepted* the request,
/// so a scheme with no handler — which Apple documents as "open the default
/// browser, or do nothing" — arrives as `true` and reads exactly like success.
/// That is the whole reason a guessed scheme fails invisibly today.
///
/// There is a second signal, though, and it is the good one: if the three-second
/// deadline elapses, the app is **still frontmost with a blank surface up**, which
/// means nothing took over. Whether `open` said `true` or `false`, that is a
/// failed hand-off — and it can say so *specifically*, because the tile's own
/// title came in on the link.
///
/// That is why the timeout reports rather than merely cleaning up. It is also why
/// the report is a banner and not an alert: the alert this used to raise was the
/// reason the app's most likely failure was the one it could not talk about — see
/// ``notice``.
@MainActor
@Observable
final class BounceRouter {
    /// True while a hand-off is in flight; `RootView` draws nothing while set.
    private(set) var isHandingOff = false

    /// A failed hand-off, for the user to dismiss.
    ///
    /// Was an `alert` trigger. A modal on the Home Screen is the wrong shape for
    /// this: the tap that produced it was a *launcher tap*, a gesture whose entire
    /// contract is "something opens, immediately", and blocking on a dialog with a
    /// 好 button is the app inserting itself into a gesture it exists to stay out
    /// of. So the notice is non-blocking and dismissible, and it names what failed
    /// instead of only that something did.
    var notice: HandoffNotice?
    /// The folder to show expanded, when the user tapped a grid's last cell.
    ///
    /// A separate channel from ``isHandingOff`` because the two are opposites:
    /// a hand-off hides the app and leaves immediately, this one *is* the app
    /// appearing. Routing both through one flag would make the folder view flash
    /// behind a blank surface and then be torn down by the deadline.
    var expandingFolderID: UUID?

    /// What to tell the user about a hand-off that went nowhere.
    struct HandoffNotice: Identifiable, Equatable {
        let id: UUID
        /// The tile's name, when the link carried one.
        let title: String?
        /// The URL that was handed to the system.
        let target: String

        /// The sentence to show, assembled from whichever parts are known.
        ///
        /// The URL is always shown, even when there is a title, because it is the
        /// thing that can be *acted on*: it is what the user would recognise as
        /// wrong, and what they would type into the tile editor to fix.
        public var message: String {
            if let title {
                String(localized: "打不开「\(title)」（\(target)）。这个 App 可能已经不在设备上了，或者图块里的链接不对。")
            } else {
                String(localized: "打不开这个图块的目标（\(target)）。这个 App 可能已经不在设备上了，或者图块里的链接不对。")
            }
        }
    }

    /// Whether the app has been to the background since the hand-off started.
    /// The only evidence that the target app actually took over.
    private var didLeaveApp = false
    private var timeout: Task<Void, Never>?
    /// What the deadline should say if it fires on a hand-off that never landed.
    private var pending: HandoffNotice?

    /// How long to stay blank before concluding the target never opened.
    ///
    /// Long enough to cover a cold launch of a heavyweight app on a slow device,
    /// short enough that a dead end doesn't feel like a hang.
    private static let deadline = Duration.seconds(3)

    /// Handles a URL that arrived from a widget tile.
    ///
    /// - Returns: whether the URL was recognised as a hand-off. `false` means
    ///   the caller should treat it as an ordinary deep link.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        // Checked before the bounce, because both are our scheme and one host is
        // a prefix of the other's shape — reading the wrong one would open a
        // folder whose id is another app's URL, or vice versa.
        if let folderID = LaunchLink.folderID(from: url) {
            expandingFolderID = folderID
            return true
        }

        guard let request = LaunchLink.request(from: url) else { return false }
        let target = request.target

        // A second tile tapped before the first resolved: the newest wins, and
        // the older deadline must not tear down the newer hand-off.
        timeout?.cancel()
        isHandingOff = true
        didLeaveApp = false
        // A notice about the previous tap has been superseded by this one, and
        // leaving it up would put a message about tile A over tile B's launch.
        notice = nil
        pending = HandoffNotice(id: UUID(), title: request.title, target: target.absoluteString)

        UIApplication.shared.open(target, options: [:]) { [weak self] opened in
            // Called on the main queue by contract, but `self` is main-actor
            // isolated, so hop explicitly rather than assume.
            Task { @MainActor [weak self] in
                guard let self else { return }
                // A `false` is conclusive and can report immediately. A `true`
                // says only that the system took the request — see the type's own
                // note — so it is left to the deadline, which is the signal that
                // actually distinguishes "an app took over" from "nothing did".
                guard !opened else { return }
                self.finish(reportingFailure: true)
            }
        }

        timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.deadline)
            guard !Task.isCancelled, let self else { return }
            // Still here after the deadline: nothing took over. Report it, naming
            // the tile — see the type's note on why the timeout is the signal.
            self.finish(reportingFailure: true)
        }
        return true
    }

    /// Feed the scene phase in; this decides when the launcher may be shown.
    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .background:
            // The hand-off worked. Whatever happens next, the user has left.
            didLeaveApp = true
            // And there is nothing to report: whatever we handed to is running.
            pending = nil
        case .active where didLeaveApp:
            // They came back to the launcher, so stop hiding it. No notice: the
            // hand-off landed, and coming back is the user's own doing.
            finish(reportingFailure: false)
        default:
            break
        }
    }

    /// Takes the blank surface down and stands the launcher back up.
    ///
    /// - Parameter reportingFailure: whether this teardown is evidence that the
    ///   hand-off went nowhere. True from the `false` completion and from the
    ///   deadline; false when the user simply came back, which is what a
    ///   *successful* hand-off looks like from here.
    private func finish(reportingFailure: Bool) {
        timeout?.cancel()
        timeout = nil
        didLeaveApp = false
        isHandingOff = false
        // The notice is assigned, never appended: the newest failure is the one
        // the user just caused, and a queue of stale ones would be worse to
        // dismiss than the notice itself.
        if reportingFailure { notice = pending }
        pending = nil
    }
}