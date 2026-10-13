import Foundation
import Testing
@testable import AppFolderKit

/// The render-path network budget.
///
/// ## The failure this pins
///
/// Timeouts were set per *request* and nothing bounded the *build*. A timeline
/// provider resolves its slots one at a time, and each could reach the network —
/// an uncached catalogue entry, an Apple app with no bundled store id, or a plain
/// store search. A grid of twenty such slots, each allowed its own 5 s request
/// timeout, is a build that can be held open for well over a minute; WidgetKit
/// allows a fraction of that, discards the result, and the widget keeps stale
/// content. The work was not merely slow, it was thrown away.
///
/// ``DirectLaunchIcons/Budget`` bounds a build by a deadline *and* a request count.
/// Both matter, and the count was already wrong once in a way worth recording: the
/// first version allowed **one** request per build, and an app the catalogue does
/// not know needs **two** — search for its id, then fetch its artwork — so the
/// second was always refused and no icon from the search path could ever be cached.
/// The tests below therefore assert a *count* that admits the two-step, not the
/// single request that looked sufficient.
@Suite("Render path budget")
struct DirectLaunchDeadlineTests {
    /// A build may make more than one request — specifically, enough for the
    /// two-step that finding an unknown app takes.
    ///
    /// This is the regression pin for the one-request version: with a ceiling of 1,
    /// search then fetch-artwork could never complete, and every such slot redrew a
    /// placeholder forever.
    @Test func aBuildAffordsTheTwoStepLookup() {
        let budget = DirectLaunchIcons.Budget(requests: 2, allowance: 3_600)
        #expect(budget.claim(), "the search for the id must be allowed")
        #expect(budget.claim(), "and so must the artwork fetch that follows it")
        #expect(!budget.claim(), "but the third is over the count")
    }

    /// The shipping count is comfortably above one, or the search path can never
    /// finish. Cheap guard, and the number that was actually wrong.
    @Test func theDefaultCountAdmitsTheSearchPath() {
        #expect(DirectLaunchIcons.Budget.defaultRequests >= 2)
    }

    /// A build that has run out of time cannot start a request, whatever its count.
    ///
    /// A zero allowance is a deadline already in the past; a negative one is the
    /// same and is what a clock that moved backwards would produce, so both are
    /// asserted rather than only the tidy case.
    @Test func anExpiredBudgetRefuses() {
        #expect(!DirectLaunchIcons.Budget(requests: 8, allowance: 0).claim())
        #expect(!DirectLaunchIcons.Budget(requests: 8, allowance: -1).claim())
    }

    /// The shipping allowance is inside the per-request timeout.
    ///
    /// If the deadline were the longer of the two it would never be the thing a
    /// slow build meets first — the transport would be — and the whole point is
    /// that the *build* gives up before the render budget does. The request timeout
    /// is 5 s (``DirectLaunchIcons/session``); this keeps the two in the right order
    /// if either is tuned.
    @Test func theAllowanceBeatsTheRequestTimeout() {
        #expect(DirectLaunchIcons.Budget.defaultAllowance <= 5)
        #expect(DirectLaunchIcons.Budget.defaultAllowance > 0)
    }

    /// The gate is genuinely per task: a build's budget is visible inside it and
    /// gone outside, and a nested build gets its own rather than inheriting one.
    ///
    /// This is the property that replaced a process-wide static, and the reason for
    /// replacing it — two builds run at once in this process (the gallery's
    /// `snapshot` beside a real `timeline`, or two widget instances), and a shared
    /// slot let one build's tidy-up unbounded the other's remaining requests.
    @Test func theBudgetIsScopedToOneTask() async {
        #expect(DirectLaunchIcons.Budget.current == nil, "no build is open at rest")

        await DirectLaunchIcons.withBudget {
            #expect(DirectLaunchIcons.Budget.current != nil, "open inside the build")

            // A nested build must not see the outer one's budget, and finishing it
            // must not clear the outer one's.
            await DirectLaunchIcons.withBudget {
                #expect(DirectLaunchIcons.Budget.current != nil)
            }
            #expect(
                DirectLaunchIcons.Budget.current != nil,
                "the inner build's end must not close the outer build"
            )
        }

        #expect(DirectLaunchIcons.Budget.current == nil, "and it is restored on the way out")
    }
}
