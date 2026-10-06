import Foundation
import Testing

@testable import AppFolderKit

/// The scheme guesser, and the one property that actually matters about it: it
/// never claims to be right.
///
/// A guess is a starting point for an editable field, so a *wrong* candidate is
/// not a failure — an invalid one is. These tests care much more about the
/// candidates being well-formed URLs than about them being correct, because
/// correctness is decided by `open(_:)` on the user's device and by nothing else.
@Suite("Scheme guess")
struct SchemeGuessTests {
    @Test("The product component leads, the company follows")
    func productComponentLeads() {
        #expect(
            SchemeGuess.candidates(bundleID: "com.burbn.instagram", name: "Instagram")
                == ["instagram://", "burbn://"]
        )
    }

    /// The ordering is a coin toss and this test exists so nobody reads the one
    /// above and concludes the first candidate is *the* answer.
    ///
    /// Keep's real scheme is `gotokeep://` — the company component, second in the
    /// list. A bundle id does not encode which shape its developer chose, so both
    /// are offered and the user decides with one tap.
    @Test("The company component is offered even when the product leads")
    func companyComponentIsAlsoOffered() {
        let candidates = SchemeGuess.candidates(bundleID: "com.gotokeep.keep", name: "Keep")
        #expect(candidates.contains("gotokeep://"))
        #expect(candidates.contains("keep://"))
        #expect(candidates.count == 2)
    }

    /// The reverse-DNS prefix is not a scheme, and neither is the country code
    /// that usually follows it. Offering `com://` would waste the one row the
    /// user actually reads.
    @Test("Reverse-DNS prefixes never become candidates")
    func prefixesAreExcluded() {
        for bundle in ["com.spotify.client", "cn.damai.app", "org.example.thing", "io.github.thing"] {
            let candidates = SchemeGuess.candidates(bundleID: bundle, name: "N")
            #expect(!candidates.contains("com://"), "\(bundle) offered com://")
            #expect(!candidates.contains("cn://"), "\(bundle) offered cn://")
            #expect(!candidates.contains("org://"), "\(bundle) offered org://")
            #expect(!candidates.contains("io://"), "\(bundle) offered io://")
        }
    }

    /// The rule that exists because of a real tile.
    ///
    /// 大麦's bundle is `cn.damai.iphone`, and read straight it offers
    /// `iphone://` — which is what the tile was saved as, and nothing on the
    /// device answers to it. A component naming the device rather than the app
    /// is still offered, but behind the one that names the company.
    @Test("A device component does not lead")
    func deviceComponentIsDemoted() {
        let candidates = SchemeGuess.candidates(bundleID: "cn.damai.iphone", name: "大麦")
        #expect(candidates.first == "damai://")
        #expect(candidates.contains("iphone://"))
    }

    /// Demoted, never dropped: a bundle whose only usable component is a device
    /// word still has to offer something, because the alternative is an empty
    /// field the user has to compose from nothing.
    @Test("A device component is still offered when it is all there is")
    func deviceComponentSurvivesAlone() {
        #expect(SchemeGuess.candidates(bundleID: "com.acme.iphone", name: "Acme") == ["acme://", "iphone://"])
    }

    /// Two components after the prefix is the minimum for a company *and* a
    /// product, so a company guess is only offered when there is one.
    @Test("One remaining component yields only a product guess")
    func oneComponentYieldsOneGuess() {
        let candidates = SchemeGuess.candidates(bundleID: "com.keep", name: "Keep")
        #expect(candidates == ["keep://"])
    }

    /// The name is the signal of last resort, and it still has to produce
    /// something a user can tap.
    @Test("The name is used when the bundle id says nothing")
    func nameIsTheFallback() {
        #expect(SchemeGuess.candidates(bundleID: nil, name: "Spotify") == ["spotify://"])
    }

    /// A scheme is `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`. Anything outside
    /// that is dropped rather than transliterated — a scheme containing CJK could
    /// not exist, so offering one would be an invalid candidate rather than a
    /// merely wrong one.
    @Test("Characters a scheme cannot contain are dropped")
    func normalizesToTheSchemeAlphabet() {
        #expect(SchemeGuess.normalize("QQ 音乐") == "qq")
        #expect(SchemeGuess.normalize("High-Low") == "high-low")
        #expect(SchemeGuess.normalize("A.B+C") == "a.b+c")
        #expect(SchemeGuess.normalize("抖音") == "")
    }

    /// A scheme must start with a letter, so a leading digit is dropped instead
    /// of being emitted in a candidate that could never resolve.
    @Test("A leading digit is dropped")
    func leadingDigitIsDropped() {
        #expect(SchemeGuess.normalize("1Password") == "password")
        #expect(SchemeGuess.candidates(bundleID: nil, name: "1Password") == ["password://"])
    }

    /// Deduplication is worth a test of its own because the sources overlap
    /// constantly — `com.keep.keep` and the name `Keep` all produce `keep`, and a
    /// list showing the same candidate three times would look broken.
    @Test("Overlapping sources collapse to one candidate")
    func duplicatesCollapse() {
        let candidates = SchemeGuess.candidates(bundleID: "com.keep.keep", name: "Keep")
        #expect(candidates == ["keep://"])
    }

    /// The property that keeps a bad guess from being a *broken* one: whatever
    /// comes out has to be a URL scheme that could theoretically work. An empty
    /// or malformed candidate is the only genuinely unacceptable output, because
    /// the user may tap it without reading.
    @Test("Every candidate is a well-formed scheme", arguments: [
        "com.gotokeep.keep", "snssdk.1128", "a", "", "com.", "..", "com.ss.iphone.ugc.Aweme",
    ])
    func candidatesAreAlwaysWellFormed(bundleID: String) {
        for candidate in SchemeGuess.candidates(bundleID: bundleID, name: "Test 123") {
            #expect(candidate.hasSuffix("://"))
            let bare = String(candidate.dropLast(3))
            #expect(!bare.isEmpty)
            let first = bare.unicodeScalars.first
            #expect(first.map { $0.value >= 97 && $0.value <= 122 } == true)
            guard let url = URL(string: candidate) else {
                Issue.record("\(candidate) is not a URL")
                continue
            }
            #expect(url.scheme == bare)
        }
    }

    /// A bundle id with nothing usable and a name that normalises away leaves
    /// nothing to offer. The caller must handle an empty list by showing an empty
    /// field — not by inventing a candidate.
    @Test("An unusable bundle and a non-latin name yield no candidates")
    func nothingUsableYieldsNothing() {
        #expect(SchemeGuess.candidates(bundleID: "com.", name: "抖音").isEmpty)
    }

    /// 抖音 is the honest example of a scheme no heuristic could reach, and it is
    /// recorded here so nobody later "improves" the guesser by trusting it: the
    /// right answer is the one the user types, and the guess exists only to have
    /// something in the box.
    @Test("A scheme with no relation to the app is not guessable")
    func unguessableSchemesStayUnguessable() {
        let candidates = SchemeGuess.candidates(bundleID: "com.ss.iphone.ugc.Aweme", name: "抖音")
        #expect(!candidates.contains("snssdk1128://"))
    }
}