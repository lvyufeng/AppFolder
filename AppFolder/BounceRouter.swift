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
@MainActor
@Observable
final class BounceRouter {
    /// True while a hand-off is in flight; `RootView` draws nothing while set.
    private(set) var isHandingOff = false
    /// Set when a hand-off could not be completed, for the user to see.
    var failure: String?

    /// Whether the app has been to the background since the hand-off started.
    /// The only evidence that the target app actually took over.
    private var didLeaveApp = false
    private var timeout: Task<Void, Never>?

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
        guard let target = LaunchLink.targetURL(from: url) else { return false }

        // A second tile tapped before the first resolved: the newest wins, and
        // the older deadline must not tear down the newer hand-off.
        timeout?.cancel()
        isHandingOff = true
        didLeaveApp = false

        UIApplication.shared.open(target, options: [:]) { [weak self] opened in
            // Called on the main queue by contract, but `self` is main-actor
            // isolated, so hop explicitly rather than assume.
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !opened else { return }  // see `scenePhaseChanged`
                self.finish(message: String(
                    localized: "打不开这个图块的目标，也许它已经不在设备上了。"
                ))
            }
        }

        timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.deadline)
            guard !Task.isCancelled, let self else { return }
            self.finish(message: nil)
        }
        return true
    }

    /// Feed the scene phase in; this decides when the launcher may be shown.
    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .background:
            // The hand-off worked. Whatever happens next, the user has left.
            didLeaveApp = true
        case .active where didLeaveApp:
            // They came back to the launcher, so stop hiding it.
            finish(message: nil)
        default:
            break
        }
    }

    /// Takes the blank surface down and stands the launcher back up.
    private func finish(message: String?) {
        timeout?.cancel()
        timeout = nil
        didLeaveApp = false
        isHandingOff = false
        failure = message
    }
}