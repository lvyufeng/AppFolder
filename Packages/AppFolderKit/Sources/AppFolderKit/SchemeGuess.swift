import Foundation

/// Guesses the URL scheme an app might answer to.
///
/// ## What this is not
///
/// **A guess is not an answer.** A URL scheme is a string the app's developer
/// chose and registered in their `Info.plist`; nothing derives it, and nothing
/// on the device can read it back. The published scheme often has no relationship
/// to the app at all — 抖音's is `snssdk1128://`, WeChat's is `weixin://`, 高德's
/// is `iosamap://` — and no amount of bundle-id parsing recovers those.
///
/// So this type does not exist to be right. It exists so the entry field is not
/// blank: a user who has to type a scheme from scratch will not, and a user shown
/// a wrong candidate can see it is wrong at a glance and correct it. The candidate
/// list is a starting point that costs one tap when it is right and one edit when
/// it is not.
///
/// ## Why the caller must still verify
///
/// The obvious way to check a guess is `canOpenURL`, and it does not work here:
/// it answers `false` for any scheme that is not declared in
/// `LSApplicationQueriesSchemes`, whether or not an app handles it — and the
/// declaration budget is 25, already spent (see ``AppCatalog/queryBudget``). A
/// freshly guessed scheme is by definition not declared, so `canOpenURL` would
/// report every guess as dead.
///
/// `open(_:)` has no such constraint: Apple documents it as *not* gated by the
/// declaration list, and the system launches a handler when one exists. So the
/// check that works is to actually try to open, which is what the entry screen
/// offers. That is also why guessing is safe to ship — the device, not this type,
/// has the final say.
public enum SchemeGuess {
    /// Candidate schemes for an app, best first, without duplicates.
    ///
    /// - Parameters:
    ///   - bundleID: the app's bundle identifier, if the lookup returned one.
    ///   - name: the app's display name, used as the fallback signal.
    ///
    /// All of the following are offered, in this order:
    ///
    /// 1. The last bundle-id component — `com.burbn.instagram` → `instagram`,
    ///    `com.google.ios.youtube` → `youtube`. Product-first because a bundle
    ///    usually ends in the product and the product is what the scheme is
    ///    named after.
    /// 2. The first component after the reverse-DNS prefix — the same bundles
    ///    yield `burbn` and `ios`. Frequently nothing, sometimes the answer:
    ///    `com.spotify.client` → `spotify` is right, and `client` is not.
    /// 3. The name, lowercased and stripped of anything a scheme cannot contain
    ///    — `Keep` → `keep`, `QQ 音乐` → `qq`.
    ///
    /// **The order is a coin toss and should not be trusted.** `com.gotokeep.keep`
    /// resolves to `gotokeep://` — the *company* component — while
    /// `com.burbn.instagram` resolves to `instagram://`, the product. Both shapes
    /// are common and nothing in the bundle distinguishes them. What makes that
    /// acceptable is that neither candidate is hidden: the user sees the list and
    /// taps 试一下, and one tap is a cheap way to be wrong.
    ///
    /// Reverse-DNS prefixes (`com`, `cn`, `org`, `net`) are excluded: nobody
    /// registers `com://`. So are a few large-company names whose schemes are
    /// branded differently from the company — `tencent` and `bytedance` are the
    /// reason 微信 is `weixin://` and 抖音 is `snssdk1128://`, and offering
    /// `tencent://` would spend a row on a candidate that is never the answer.
    public static func candidates(bundleID: String?, name: String) -> [String] {
        var ordered: [String] = []

        if let bundleID {
            let parts = bundleID
                .split(separator: ".")
                .map(String.init)
                .filter { !$0.isEmpty }
            // Drop the reverse-DNS prefix so the *first* remaining component is
            // the company or product rather than `com`.
            let meaningful = parts.drop { Self.prefixes.contains($0.lowercased()) }
            let tail = Array(meaningful)

            if tail.count >= 1 { ordered.append(tail[tail.count - 1]) }  // product
            if tail.count >= 2 { ordered.append(tail[0]) }               // company
        }

        ordered.append(name)

        var seen: Set<String> = []
        return ordered
            .map(normalize)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map { "\($0)://" }
    }

    /// Reverse-DNS prefixes and corporate identifiers that never appear as a
    /// scheme. Kept small deliberately: excluding a name that *was* the scheme is
    /// worse than offering one extra irrelevant candidate, because the list is
    /// scanned by eye rather than trusted.
    private static let prefixes: Set<String> = [
        "com", "cn", "org", "net", "io", "me", "co",
        "apple", "google", "tencent", "alibaba", "bytedance",
        "iphone", "ipad", "ios", "app", "mobile",
    ]

    /// Reduces a string to the character set a URL scheme may contain.
    ///
    /// A scheme is `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )` and must start
    /// with a letter, so `QQ 音乐` becomes `qq` — the CJK is dropped rather than
    /// transliterated, because a scheme containing it could not exist. Lowercased
    /// because scheme matching is case-insensitive and every real one is written
    /// lower.
    ///
    /// A leading digit is dropped too: `1Password` has no scheme starting with
    /// `1`, so offering `1password://` would be a candidate that is invalid rather
    /// than merely wrong.
    static func normalize(_ raw: String) -> String {
        var scalars = raw.lowercased().unicodeScalars.filter { scalar in
            let isASCIILowercase = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            let isAllowedPunctuation = scalar == "+" || scalar == "-" || scalar == "."
            return isASCIILowercase || isDigit || isAllowedPunctuation
        }
        while let first = scalars.first, !(first.value >= 97 && first.value <= 122) {
            scalars.removeFirst()
        }
        return String(String.UnicodeScalarView(scalars))
    }
}