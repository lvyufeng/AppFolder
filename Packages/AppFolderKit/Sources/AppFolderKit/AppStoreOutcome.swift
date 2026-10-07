import Foundation

/// What came back from the App Store, kept apart into the three things it can be.
///
/// ## Why this exists
///
/// The search used to answer `[AppStoreLookup]?`, whose `nil` the type's own
/// documentation defined as *"could not reach the App Store"*. Every non-200 was
/// collapsed into that one answer — a 400 for a malformed request, a 429 for
/// being throttled, a 5xx because Apple was down, and a genuinely dead network.
/// The user then got one sentence about their Wi-Fi no matter which it was.
///
/// That is not a hypothetical. The `uk` storefront bug shipped behind exactly this
/// guard: the endpoint answered
///
/// ```json
/// {"errorMessage":"Invalid value(s) for key(s): [country]"}
/// ```
///
/// — a sentence that names the fault outright — and the response body was never
/// read, because `statusCode == 200` had already decided the outcome. The user was
/// told to check their connection.
///
/// ## What this is not
///
/// Not an error type to be thrown and caught. The caller's *next action* really is
/// the same for every refusal — say so, and offer the region picker — so this
/// deliberately does not fan out into a case per status. What was missing was the
/// **evidence**, not the branches: which of the three it was, the status code, and
/// the endpoint's own sentence. See ``AppStoreOutcome/refusalKind`` for the one
/// distinction that does change what is shown.
public enum AppStoreOutcome: Sendable, Equatable {
    /// The endpoint answered 200. The array may be empty, and an empty one is a
    /// real answer: the search worked and found nothing.
    case answered([AppStoreLookup])

    /// The endpoint answered, and the answer was not 200.
    case refused(status: Int, message: String?)

    /// No answer at all. This is the case that was previously being reported for
    /// all three, and the only one that is actually about the network.
    case unreachable

    /// Classifies a response. Pure, so the rule can be tested without a server.
    ///
    /// `status` is `nil` when no HTTP response was produced at all, which is the
    /// transport failure the caller already detected.
    public static func classify(status: Int?, body: Data?) -> AppStoreOutcome {
        guard let status else { return .unreachable }
        guard status != 200 else { return .answered(AppStoreLookup.parse(body ?? Data())) }
        return .refused(status: status, message: errorMessage(in: body))
    }

    /// The results, or an empty array for anything that was not a successful
    /// answer.
    ///
    /// For callers that only draw a list and have their own way of reporting the
    /// rest — the distinction they need is ``isUnreachable``, not this.
    public var results: [AppStoreLookup] {
        if case .answered(let results) = self { return results }
        return []
    }

    /// Whether the request never got an answer, which is the only case where the
    /// user's network is implicated.
    public var isUnreachable: Bool {
        if case .unreachable = self { return true }
        return false
    }

    /// What kind of refusal this was, or `nil` if it was not one.
    ///
    /// The split that matters for the message. A throttled request and a dead
    /// network want opposite advice: one says wait, the other says check your
    /// Wi-Fi, and this app used to give the second for both — which sends a user
    /// whose connection is fine off to check a connection that is fine.
    public var refusalKind: RefusalKind? {
        guard case .refused(let status, _) = self else { return nil }
        switch status {
        // 403 as well as 429: the iTunes API uses both for rate limiting. Grouping
        // only 429 as "throttled" and everything else as "your fault" would label
        // Apple throttling us as a bug in this app.
        case 403, 429: return .throttled
        case 400, 401, 404: return .malformedRequest
        case 500...599: return .server
        default: return .other
        }
    }

    /// A short parenthetical naming what the endpoint said, for showing beside the
/// explanation.
    ///
    /// Empty rather than absent when there is nothing to report, so callers can
    /// append it unconditionally instead of each deciding how to join. Includes the
    /// status code even when the endpoint explained itself: the code is what makes
    /// a user's report searchable, and the message is what makes it actionable.
    public var diagnosticSuffix: String {
        guard case .refused(let status, let message) = self else { return "" }
        guard let message else { return "（HTTP \(status)）" }
        return "（HTTP \(status)：\(message)）"
    }

    public enum RefusalKind: Sendable, Equatable {
        /// 403 / 429 — too many requests. Waiting helps; the network is fine.
        case throttled
        /// 400 / 401 / 404 — the request itself was wrong. This is a bug here, not
        /// a condition of the world, and it is the case the `uk` storefront fell
        /// into.
        case malformedRequest
        /// 5xx — the App Store is unwell. Nothing the user or this app can do.
        case server
        case other
    }

    /// The endpoint's own explanation, when it gave one.
    ///
    /// The API answers a refused request with `{"errorMessage": "…"}`, which is the
    /// most useful sentence available anywhere in this exchange — it is what would
    /// have made the `uk` bug a one-line fix. Read here rather than at the call
    /// site so that it is captured at the moment the body is still in hand.
    static func errorMessage(in body: Data?) -> String? {
        guard
            let body,
            let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let message = root["errorMessage"] as? String,
            !message.isEmpty
        else { return nil }
        return message
    }
}