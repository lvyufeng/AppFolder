import Foundation

/// The App Store storefronts this app searches and resolves in.
///
/// ## Why this is a type at all
///
/// It used to be three separate arrays in three files — one in `FolderEditorView`
/// for the region picker, one in `AppStoreSearchClient` for the lookup fallback,
/// one in `IconStore` for artwork — and nothing made them agree. They drifted, and
/// the drift cost the region picker a row that could never work: `uk`, where the
/// App Store's code for the United Kingdom is **`gb`**.
///
/// That one is worth spelling out, because it is the failure mode this type
/// exists to make impossible — and because the failure is **not** the silent one
/// it was first written up as.
///
/// An unknown storefront code is rejected outright:
///
///     https://itunes.apple.com/lookup?id=414478124&country=uk
///     → HTTP 400 {"errorMessage":"Invalid value(s) for key(s): [country]"}
///     https://itunes.apple.com/lookup?id=414478124&country=gb
///     → HTTP 200 {"resultCount":1, ... }
///
/// Measured, same id, same moment, on both endpoints — `/search` refuses `uk` with
/// the same 400. The anchor is 微信 (`id=414478124`), which is sold in every
/// storefront listed here, so a zero could only ever have meant the code was
/// refused rather than that the app is absent.
///
/// ## What that means for the user, which is the part that has to be right
///
/// `AppStoreSearchClient.search(term:country:)` requires `statusCode == 200` and
/// returns `nil` **without consuming the body** — so the `errorMessage` that would
/// have explained everything is discarded before anyone could read it. `nil` is
/// the type's word for *"could not reach the App Store"*, and that is exactly what
/// the picker then drew: `storeSection` shows「连不上 App Store，检查一下网络」.
///
/// So picking 英国 did not produce a quiet "nothing found" the user could blame on
/// their query. It produced a confident, specific, **wrong** diagnosis — the
/// network — for a bug that was one letter in a hardcoded array. That is worse
/// than a silent failure, and it is why this list is now a tested type rather
/// than a `private static` a test could not reach.
///
/// ``AppStoreRegionsTests`` asserts the 200 and the non-empty result for every
/// code in ``storefronts``, so the next typo fails a test instead of shipping.
public enum AppStoreRegions {
    /// One storefront: the code the API takes, and the name to show a user.
    public struct Region: Sendable, Hashable, Identifiable {
        /// The storefront code, lowercased, as the `country` query item takes it.
        ///
        /// Not a display name and not an App Store URL slug — the three are
        /// different things and only this one works in a request.
        public let code: String
        /// What the picker shows. Chinese, matching the rest of the app's UI.
        public let label: String

        public var id: String { code }

        public init(code: String, label: String) {
            self.code = code
            self.label = label
        }
    }

    /// The storefronts beyond the device's own, in the order they are offered.
    ///
    /// Deliberately short, and this is the one place that argues for it: a
    /// storefront the user picks is one they *bought an app* from, and a mixed
    /// purchase history spans a handful of stores, not a hundred and seventy-five.
    /// A complete country list would be a worse picker for the real question —
    /// "where did this app come from" — and every row is another thing to read
    /// past on the way to the right answer.
    ///
    /// `us` and `cn` are the two this app's audience actually straddles. The rest
    /// are the neighbouring stores someone with an older purchase history is
    /// likely to hold.
    ///
    /// Every code here is measured, not looked up — see the type's own note for
    /// the table. `gb`, not `uk`.
    public static let storefronts: [Region] = [
        Region(code: "us", label: "美国"),
        Region(code: "cn", label: "中国大陆"),
        Region(code: "hk", label: "香港"),
        Region(code: "jp", label: "日本"),
        Region(code: "tw", label: "台湾"),
        Region(code: "gb", label: "英国"),
    ]

    /// Storefronts to try when a request named none, `nil` first.
    ///
    /// The `nil` is not a missing value — it is the request with **no `country`
    /// parameter at all**, which the endpoint resolves against the device's own
    /// storefront. That is the right first try for almost everyone, and it is a
    /// distinct request rather than a restatement of any code here, which is why
    /// it is a `String?` and why it leads.
    ///
    /// This is the artwork path's order: try the device's store, then the handful
    /// of others, first answer wins. The regions *after* `nil` exist for one
    /// concrete case — an app bought in another region stays installed after the
    /// account moves, and the device's own storefront then cannot see it, so its
    /// tile would go blank with no explanation.
    public static let lookupOrder: [String?] = [nil] + storefronts.map(\.code)

    /// The bare codes, for a caller that has its own reason to exclude `nil`.
    ///
    /// ``AppStoreSearchClient/lookup(trackID:region:)`` is the one: it takes the
    /// link's own region and the device's storefront as its first two attempts
    /// before falling back to this list, so repeating `nil` there would be a
    /// third request for an answer it already has. Keeping the two shapes as one
    /// list plus a derivation — rather than two literals — is the entire point.
    public static var codes: [String] { storefronts.map(\.code) }
}