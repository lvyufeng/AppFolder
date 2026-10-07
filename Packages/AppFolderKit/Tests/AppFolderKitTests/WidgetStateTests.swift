import Testing
@testable import AppFolderKit

/// The counter the app uses to ask the widget to drop an expansion.
///
/// ## Why this suite exists now
///
/// The request used to travel in `FolderLibrary`, as a field on the file the
/// folder widget read. The folder model and that widget are both gone, and the
/// request moved to ``WidgetState`` — which is the whole reason the model could
/// be deleted: this counter was the direct-launch widget's *only* remaining tie
/// to it. The field's own tests went with `FolderLibrary`; these replace them.
///
/// ## What was already right, and is not being re-litigated
///
/// The comparison itself — "collapse if the request is newer than the one I acted
/// on" — is ``WidgetState/applyCollapseRequest(_:)`` and is unchanged in
/// behaviour. What this suite adds is the *producer*: that ``requestCollapse()``
/// actually advances the counter, and that it is a counter rather than a flag,
/// which is what lets one request survive being read by two widgets and being
/// followed by another launch.
///
/// ## Why this suite is serialized, and why each test sets its own baseline
///
/// `WidgetState` is deliberately process-wide — one `UserDefaults`, shared by the
/// app and the widget — so there is nothing to inject and every test in here
/// mutates the same keys. Run in parallel (the default) they would read each
/// other's counters mid-flight and fail on a race rather than on the behaviour,
/// so the suite is serialized and each test writes the ``seenCollapseRequest``
/// cursor it needs instead of inheriting whatever the last test left.
@Suite("Widget collapse request", .serialized)
struct WidgetStateTests {
    /// The counter only goes up, and a second ask is a second request.
    ///
    /// A boolean would fail this: two asks collapse together, so a widget that
    /// missed the first reload would never learn of the second. The counter is
    /// what makes the request durable, so this is the property worth pinning.
    @Test("Asking twice advances the counter twice")
    func requestsAccumulate() {
        let before = WidgetState.collapseRequest
        WidgetState.requestCollapse()
        let once = WidgetState.collapseRequest
        WidgetState.requestCollapse()
        let twice = WidgetState.collapseRequest

        #expect(once > before)
        #expect(twice > once)
    }

    /// Asking also clears the state directly, so it takes effect in this process
    /// even when the widget is never reloaded.
    @Test("Asking collapses what this process can see")
    func requestAlsoCollapsesLocally() {
        WidgetState.directLaunchKey = "some-grid"
        WidgetState.expandedPage = 2

        WidgetState.requestCollapse()

        #expect(WidgetState.directLaunchKey == nil)
        #expect(WidgetState.expandedPage == 0)
    }

    /// The reader's half. A request is acted on once, and reading the same value
    /// again does nothing — otherwise a widget reloading for its own reasons
    /// would throw away an expansion the user is looking at.
    @Test("A request is applied once, not on every reload")
    func applyingIsIdempotent() {
        WidgetState.requestCollapse()
        let request = WidgetState.collapseRequest
        // Start from a cursor that has not seen it, so the first call really is
        // the first. Without this the test inherits whatever the previous one
        // left behind, which is a race rather than an assertion.
        WidgetState.seenCollapseRequest = request - 1

        #expect(WidgetState.applyCollapseRequest(request))
        #expect(!WidgetState.applyCollapseRequest(request))
    }

    /// And applying a *newer* request does the collapse, not just the
    /// bookkeeping.
    @Test("A newer request collapses the open grid")
    func newerRequestCollapses() {
        WidgetState.directLaunchKey = "some-grid"
        WidgetState.expandedPage = 3
        WidgetState.requestCollapse()
        // Pretend this process already consumed the previous request.
        WidgetState.seenCollapseRequest = WidgetState.collapseRequest - 1

        #expect(WidgetState.applyCollapseRequest(WidgetState.collapseRequest))
        #expect(WidgetState.directLaunchKey == nil)
        #expect(WidgetState.expandedPage == 0)
    }
}