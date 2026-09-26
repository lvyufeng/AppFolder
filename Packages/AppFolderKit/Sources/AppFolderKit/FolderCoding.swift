import Foundation

/// The one definition of how a ``FolderLibrary`` is encoded on disk.
///
/// Both the app and the widget go through ``FolderStore``, which goes through
/// here, so the format has exactly one home.
public enum FolderCoding {
    /// Encodes dates the way `JSONEncoder` does by default: seconds since the
    /// reference date.
    ///
    /// Kept as the default rather than switched to ISO-8601 on purpose. The
    /// written format is a contract with libraries already on disk, and the
    /// reader below accepts both, so there is nothing to gain from moving it.
    public static func makeEncoder() -> JSONEncoder {
        JSONEncoder()
    }

    /// Decodes dates in either of the two shapes that occur in the wild:
    /// a number (what we write) or an ISO-8601 string (what a human writes when
    /// editing the file by hand, and what any future export would carry).
    ///
    /// This leniency is load-bearing, not a nicety. ``FolderLibrary`` already
    /// tolerates *absent* keys so that adding a field can't discard a user's
    /// folders; tolerating a *presently malformed* one is the same bargain. The
    /// blast radius otherwise is out of all proportion to the mistake: dates are
    /// non-optional properties of `Folder` and `FolderTile`, so one unparseable
    /// date fails the decode of the whole library, and the whole library is then
    /// quarantined and replaced with nothing.
    ///
    /// That is not hypothetical — it happened while seeding a test folder by
    /// hand, and it cost all nine tiles of a folder that was otherwise perfect.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            // The shape we write.
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }

            // The shape everything else produces.
            let text = try container.decode(String.self)
            if let date = date(fromISO8601: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: """
                Expected seconds since 2001-01-01 or an ISO-8601 date \
                (for example 2026-09-26T16:48:00Z), got "\(text)".
                """
            )
        }
        return decoder
    }

    /// Two styles, because the fractional part is not optional: a style built
    /// for `...00Z` will not parse `...00.123Z`, and vice versa.
    ///
    /// `Date.ISO8601FormatStyle` rather than `ISO8601DateFormatter` — the class
    /// is not `Sendable`, and these are `static let`s read from whatever thread
    /// happens to be decoding.
    private static let plainStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    private static let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Parses an ISO-8601 timestamp, with or without fractional seconds.
    static func date(fromISO8601 text: String) -> Date? {
        if let date = try? plainStyle.parse(text) { return date }
        return try? fractionalStyle.parse(text)
    }
}