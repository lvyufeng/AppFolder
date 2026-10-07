import Foundation
import Testing

@testable import AppFolderKit

/// The storefront list, checked against the endpoint that has to accept it.
///
/// ## Why these tests talk to the network
///
/// Every other suite in this package is a pure function of its inputs, and this
/// one is not, which needs justifying because the exception is the point.
///
/// The bug being guarded against — 英国 listed as `uk` — is **not** expressible as
/// an assertion about a string. `uk` is a perfectly well-formed storefront code.
/// It is simply not one Apple has, and the only thing that knows the difference
/// is Apple's server. Locally the wrong code and the right one are
/// indistinguishable, which is exactly why it survived: the list was a `private
/// static` array on a view, so no test could reach it, and a typo that *looked*
/// like a country abbreviation stayed plausible for as long as nobody measured.
///
/// The server's answer is a `400`, not an empty list: `uk` is refused with
/// `Invalid value(s) for key(s): [country]`. So the assertion is a measurement —
/// ask about an app every one of these storefronts sells, and require a `200` with
/// an answer in it. The anchor is 微信 (`id=414478124`), chosen because it is the
/// one app that is simultaneously available in `cn` under its Chinese name and
/// everywhere else under its English one — so a zero result can only mean the
/// *code* was refused, and can never be dismissed as "that app isn't sold there".
///
/// The negative case is verified rather than assumed: putting `uk` back into
/// ``AppStoreRegions/storefronts`` fails this suite, on the status code and on the
/// empty result alike.
///
/// ## Why this is off by default
///
/// A test that needs the network fails when the network is down, and CI is
/// exactly where that happens. The rest of the suite has to stay green in a
/// locked room, so this one opts in:
///
///     APPFOLDER_NETWORK_TESTS=1 swift test --package-path Packages/AppFolderKit
///
/// Off, the cases report as skipped rather than passed — a silently-passing
/// network test is worse than no test, because it reads as coverage.
///
/// The generator's `--verify-ids` mode (`appfolder-schemes --verify-ids`) is
/// deliberately a sibling of this rather than the same thing: it checks that the
/// catalogue's App Store *ids* resolve, which is a different transcription and a
/// different failure. Both need the network; neither replaces the other.
/// Whether the network cases should run.
///
/// Read from the environment rather than hardcoded so one command line turns them
/// on without a source edit. At file scope rather than as a `static` on the suite
/// because the `.enabled(if:)` trait is evaluated where the suite is declared, so
/// `Self` is not in scope there yet.
private let networkTestsEnabled =
    ProcessInfo.processInfo.environment["APPFOLDER_NETWORK_TESTS"] == "1"

@Suite("App Store regions", .enabled(if: networkTestsEnabled))
struct AppStoreRegionsTests {
    /// Sold in every storefront this app offers. See the suite's note for why
    /// this specific app is the right anchor.
    private static let anchor = 414478124

    /// The list is non-empty, has no duplicate codes, and holds no obvious
    /// mistake. The purity check — it does not touch the network, and it is what
    /// runs in CI.
    @Test("The storefront list is well formed")
    func listIsWellFormed() {
        let regions = AppStoreRegions.storefronts

        #expect(!regions.isEmpty)
        // A duplicate is not cosmetic: `ForEach` keys on `code`, so two rows with
        // the same one make a picker that highlights the wrong entry.
        #expect(Set(regions.map(\.code)).count == regions.count)
        #expect(regions.allSatisfy { $0.code == $0.code.lowercased() && $0.code.count == 2 })
        #expect(regions.allSatisfy { !$0.label.isEmpty })
    }

    /// ``lookupOrder`` and ``codes`` have to stay in step, because the first is
    /// built from the second and a caller relies on both describing one list.
    @Test("The two derived shapes agree with the list")
    func derivedShapesAgree() throws {
        #expect(AppStoreRegions.codes == AppStoreRegions.storefronts.map(\.code))
        // `nil` leads, and it means "no `country` parameter" — the device's own
        // storefront — which is a request, not a missing value.
        //
        // Read through `#require` rather than `lookupOrder.first == nil`: the
        // array's element type is already optional, so `.first` is a `String??`
        // and comparing it to `nil` asks whether the *array* is empty, which it
        // never is. The outer level has to be unwrapped before the comparison
        // means what it reads as.
        let head = try #require(AppStoreRegions.lookupOrder.first)
        #expect(head == nil)
        #expect(Array(AppStoreRegions.lookupOrder.dropFirst()) == AppStoreRegions.codes)
    }

    /// The bug, as a test. Every code must resolve an app that is sold in all of
    /// them; `uk` returns `resultCount: 0` and fails here.
    @Test("Every storefront code resolves an app it is supposed to sell",
          arguments: AppStoreRegions.storefronts)
    func everyCodeResolvesSomething(_ region: AppStoreRegions.Region) async throws {
        let url = try #require(AppStoreLookup.lookupURL(ids: [Self.anchor], country: region.code))
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)

        let results = AppStoreLookup.parse(data)
        // The failure message has to name the code, because the whole problem
        // with this bug was that nothing on screen ever did.
        #expect(
            !results.isEmpty,
            "storefront \(region.code) (\(region.label)) returned nothing for id \(Self.anchor) — is \(region.code) a real App Store storefront?"
        )
        #expect(results.first?.trackID == Self.anchor)
    }
}