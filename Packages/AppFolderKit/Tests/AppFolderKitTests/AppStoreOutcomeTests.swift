import Foundation
import Testing

@testable import AppFolderKit

/// What the App Store answered, told apart.
///
/// The bug these exist for is a 400 being reported to the user as *"could not
/// reach the App Store"*, so most of them are about the cases that are **not** a
/// network problem.
@Suite("App Store outcome")
struct AppStoreOutcomeTests {
    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test("A 200 with results is an answer, not a refusal")
    func successfulAnswerIsNotARefusal() {
        let payload = body(#"{"results":[{"trackId":1,"trackName":"微信"}]}"#)
        let outcome = AppStoreOutcome.classify(status: 200, body: payload)

        #expect(outcome.results.count == 1)
        #expect(outcome.refusalKind == nil)
        #expect(!outcome.isUnreachable)
        #expect(outcome.diagnosticSuffix.isEmpty)
    }

    @Test("A 200 with no results is still an answer")
    func emptyAnswerIsAnAnswer() {
        let outcome = AppStoreOutcome.classify(status: 200, body: body(#"{"results":[]}"#))

        // The distinction the whole type exists for: "the search worked and found
        // nothing" must never be reported as "could not reach the App Store".
        #expect(outcome.results.isEmpty)
        #expect(outcome.refusalKind == nil)
        #expect(!outcome.isUnreachable)
    }

    @Test("No response at all is the only unreachable case")
    func missingResponseIsUnreachable() {
        let outcome = AppStoreOutcome.classify(status: nil, body: nil)

        #expect(outcome.isUnreachable)
        #expect(outcome.refusalKind == nil)
        #expect(outcome.results.isEmpty)
    }

    @Test("A 400 is a malformed request, not a network fault")
    func badRequestIsNotTheNetwork() {
        // The exact response the uk storefront produced — see the type's note.
        let payload = body(#"{"errorMessage":"Invalid value(s) for key(s): [country]"}"#)
        let outcome = AppStoreOutcome.classify(status: 400, body: payload)

        #expect(outcome.refusalKind == .malformedRequest)
        #expect(!outcome.isUnreachable)
    }

    @Test("Being throttled is reported as throttling, not as the user's connection")
    func throttlingIsItsOwnCase() {
        for status in [403, 429] {
            let outcome = AppStoreOutcome.classify(status: status, body: nil)
            #expect(outcome.refusalKind == .throttled)
            #expect(!outcome.isUnreachable)
        }
    }

    @Test("A 5xx is the App Store's problem")
    func serverErrorsAreTheirs() {
        for status in [500, 502, 503] {
            #expect(AppStoreOutcome.classify(status: status, body: nil).refusalKind == .server)
        }
    }

    @Test("The endpoint's own explanation is kept")
    func errorMessageIsCaptured() {
        let payload = body(#"{"errorMessage":"Invalid value(s) for key(s): [country]"}"#)
        let outcome = AppStoreOutcome.classify(status: 400, body: payload)

        // This sentence is what would have made the storefront bug a one-line fix,
        // and it was being read and thrown away.
        #expect(outcome.diagnosticSuffix.contains("Invalid value(s) for key(s)"))
        #expect(outcome.diagnosticSuffix.contains("400"))
    }

    @Test("A refusal with no explanation still reports the status code")
    func statusCodeSurvivesWithoutAMessage() {
        let outcome = AppStoreOutcome.classify(status: 503, body: body("not json"))

        // Malformed or missing bodies are the normal case for an error page, and
        // losing the code with them would leave nothing to report at all.
        #expect(outcome.diagnosticSuffix.contains("503"))
    }

    @Test("An unparseable 200 is an empty answer rather than a refusal")
    func garbageOnASuccessIsStillAnAnswer() {
        let outcome = AppStoreOutcome.classify(status: 200, body: body("<html>"))

        // The status is the endpoint's statement that it answered; a body this app
        // cannot read is a parsing problem, and calling it a refusal would send the
        // user to check their network over a decoder.
        #expect(!outcome.isUnreachable)
        #expect(outcome.refusalKind == nil)
        #expect(outcome.results.isEmpty)
    }

    @Test("An errorMessage of the wrong shape does not crash or leak through")
    func oddBodiesAreTolerated() {
        for payload in [#"{"errorMessage":123}"#, #"[]"#, #""""#, "null"] {
            let outcome = AppStoreOutcome.classify(status: 400, body: body(payload))
            #expect(outcome.refusalKind == .malformedRequest)
            #expect(outcome.diagnosticSuffix.contains("400"))
        }
    }
}