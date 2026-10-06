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
    /// ## What the bundle id is read for now
    ///
    /// The string's *shape* is evidence, and it turns out to be better evidence
    /// than the names of its parts. A bundle id is a domain the developer has
    /// held since before the app existed, so the address bar is the test:
    ///
    /// 1. **A domain-shaped tail.** `com.ipiaoniu.pner` — the last two non-noise
    ///    components — is the registrable domain `ipiaoniu.pner`. Reachable at
    ///    `ipiaoniu.pner` ⇒ `pner://`. This is the one rule that would have saved
    ///    票牛, where the plain "last component" answer, `ipiaoniu`, is the
    ///    company and the answer was `pner`.
    /// 2. **A product-ish tail**, left-to-right: `com.zhang333.dd` → `zhang333`
    ///    then `dd`, `com.burbn.instagram` → `burbn` then `instagram`. Both
    ///    shapes are common — Keep is `com.gotokeep.keep` → `gotokeep://`, the
    ///    company — so neither order can be right on its own, and the only cure
    ///    is to offer both and let the device decide.
    /// 3. **The name**, lowercased and stripped of anything a scheme cannot
    ///    contain — `Keep` → `keep`, `QQ 音乐` → `qq`.
    ///
    /// **The order is a coin toss and should not be trusted.** What makes that
    /// acceptable is that no candidate is hidden: the user sees the list and taps
    /// 试一下, and one tap is a cheap way to be wrong.
    ///
    /// ## The component a scheme is never named after
    ///
    /// `iphone`, for one, and this is measured rather than assumed. 大麦's bundle
    /// is `cn.damai.iphone`; the old rule kept only the last component that was
    /// not noise, `iphone` had not been listed as noise, so the tile was saved
    /// pointing at `iphone://` — a scheme nothing on earth handles. The company
    /// name in that bundle, `damai`, is quite possibly the real answer, and it is
    /// offered now. The direction of the mistake is what matters: a candidate that
    /// is merely wrong costs one tap, and one that is *dropped* silently removes
    /// the only thing that might have worked.
    ///
    /// So the noise list is short and stays short. `com`, `cn`, `org`, `net` earn
    /// their place because nobody registers `com://`; `tencent` and `bytedance`
    /// earn theirs because 微信 is `weixin://` and 抖音 is `snssdk1128://`, and
    /// these are understood to be bets on the *order*, not filters on the list.
    public static func candidates(bundleID: String?, name: String) -> [String] {
        var ordered: [String] = []

        if let bundleID {
            let parts = bundleID
                .split(separator: ".")
                .map(String.init)
                .filter { !$0.isEmpty }
            // Drop the reverse-DNS prefix so the *first* remaining component is
            // the company or product rather than `com`.
            let tail = Array(parts.drop { Self.prefixes.contains($0.lowercased()) })

            // Product first, then the company. Both are usually present and only
            // the developer knows which one they named the scheme after.
            //
            // The one adjustment: a component that names a *device* or a build
            // variant rather than a product goes last. 大麦's bundle is
            // `cn.damai.iphone`, and read straight it offers `iphone://` ahead of
            // `damai://` — which is exactly the tile that prompted this rule: it
            // was saved as `iphone://`, and nothing on the device answers to it.
            // These tokens are not removed from the list, only demoted; a wrong
            // candidate costs one tap, and one that never gets offered can cost
            // the whole tile.
            let promoted = tail.filter { !Self.genericTokens.contains($0.lowercased()) }
            let demoted = tail.filter { Self.genericTokens.contains($0.lowercased()) }
            ordered.append(contentsOf: promoted.reversed())
            ordered.append(contentsOf: demoted.reversed())
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
    ///
    /// Only the leading run is dropped — see ``candidates(bundleID:name:)`` — so
    /// `cn.damai.iphone` loses `cn` and keeps `damai`. `iphone` is no longer here:
    /// it used to be, and because it sat at the *end* of 大麦's bundle it was not
    /// dropped but promoted, producing `iphone://`.
    private static let prefixes: Set<String> = [
        "com", "cn", "org", "net", "io", "me", "co",
        "apple", "google", "tencent", "alibaba", "bytedance",
    ]

    /// Bundle components that name the target device or a build variant rather
    /// than the app, so they are offered last.
    ///
    /// Demoted rather than dropped, and that is the whole design. `iphone` is the
    /// component that put `iphone://` on a real tile and had the user staring at
    /// 打不开这个图块的目标, so it clearly cannot lead — but a bundle that ended in
    /// one of these *and had nothing else* would otherwise offer no bundle-derived
    /// candidate at all, which is worse than offering a bad one.
    ///
    /// `ios`, `ipad` and `mobile` were in the old exclusion list. The difference
    /// is that excluding them only ever affected the *leading* component, since
    /// the old rule read a fixed pair and never scanned the middle; here every
    /// component is considered, so the same words have to be handled by rank.
    private static let genericTokens: Set<String> = ["iphone", "ipad", "ios", "mobile", "app"]

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