import AppFolderKit
import Foundation

/// Prints the `LSApplicationQueriesSchemes` array for `Config/AppFolder-Info.plist`.
///
/// The catalog in `AppCatalog+Data.swift` and the app's `Info.plist` have to
/// agree: a scheme missing from the plist makes `canOpenURL` answer `false` even
/// when the app is installed, which looks exactly like "the app isn't there".
/// Rather than keep two lists in sync by hand, run this and paste:
///
///     swift run --package-path Packages/AppFolderKit appfolder-schemes
///
/// Pass `--check` to exit non-zero when the plist is stale, which is what CI
/// should use.
///
/// Pass `--verify-ids` to check every `appStoreID` against the iTunes Search
/// API. That mode needs the network, so CI keeps it out of the default run.
@main
struct GenerateQueriedSchemes {
    static func main() {
        let schemes = AppCatalog.queriedSchemes
        let check = CommandLine.arguments.contains("--check")

        if CommandLine.arguments.contains("--verify-ids") {
            verifyAppStoreIDs()
            return
        }

        if check {
            guard let plist = try? String(contentsOf: plistURL, encoding: .utf8) else {
                FileHandle.standardError.write(Data("cannot read \(plistURL.path)\n".utf8))
                exit(1)
            }
            // The plist takes bare scheme names (`weixin`); the catalog stores
            // launchable URLs (`weixin://`). Compare on the bare form.
            let missing = schemes.filter { !plist.contains("<string>\(bare($0))</string>") }
            guard missing.isEmpty else {
                FileHandle.standardError.write(Data("""
                AppFolder-Info.plist is missing \(missing.count) scheme(s):
                \(missing.joined(separator: "\n"))

                Run: swift run --package-path Packages/AppFolderKit appfolder-schemes

                """.utf8))
                exit(1)
            }
            print("Info.plist is up to date (\(schemes.count) schemes).")
            return
        }

        for scheme in schemes {
            print("\t\t<string>\(bare(scheme))</string>")
        }
    }

    // MARK: - App Store id verification

    /// Confirms every `appStoreID` in the catalogue resolves to the app it claims
    /// to be.
    ///
    /// This exists because the ids cannot be derived from anything — they are
    /// transcription, and a transcription error is invisible until a tile shows
    /// the wrong app's icon. (A real instance: `腾讯会议` pointed at an id that
    /// resolved to a *music track*, so the tile would have drawn a record sleeve
    /// and opened a video-conferencing app.)
    ///
    /// Two severities, because they mean different things:
    ///
    /// * **error** — the id resolves to nothing, to a non-app, or to a different
    ///   id than the one asked for. Unambiguously broken.
    /// * **warning** — the id resolves to an app whose name doesn't resemble the
    ///   catalogue's. Sometimes that is a rebrand rather than a mistake
    ///   (`饿了么` is now sold by its store listing as `淘宝闪购`), so it needs a
    ///   human, not a non-zero exit.
    private static func verifyAppStoreIDs() {
        var errors: [String] = []
        var warnings: [String] = []
        var checked = 0

        for app in AppCatalog.all {
            guard let id = app.appStoreID else { continue }
            checked += 1

            // App names are ASCII for the international entries and CJK for the
            // Chinese ones, and the two live in different storefronts.
            let country = isASCII(app.name) ? "us" : "cn"
            let track: Track
            switch lookup(id: id, country: country, attempts: 3) {
            case .track(let found):
                track = found
            case .noResults:
                errors.append("\(app.name): id \(id) returned no results in \(country)")
                continue
            case .unreachable:
                errors.append("\(app.name): id \(id) could not be looked up — check the network")
                continue
            }
            guard track.trackId == id else {
                errors.append("\(app.name): asked for \(id), store returned \(track.trackId)")
                continue
            }
            guard track.kind == "software" else {
                errors.append("\(app.name): id \(id) is a '\(track.kind)', not an app — \(track.trackName)")
                continue
            }
            if !resembles(storeName: track.trackName, app: app) {
                warnings.append("\(app.name): id \(id) is '\(track.trackName)' — confirm this is the same app")
            }
            // Apple throttles the endpoint; a tight loop reads as an outage and
            // manufactures false failures.
            Thread.sleep(forTimeInterval: 1.2)
        }

        for warning in warnings {
            print("warning: \(warning)")
        }
        for error in errors {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        }
        print("\(checked) ids checked, \(warnings.count) warning(s), \(errors.count) error(s).")
        if !errors.isEmpty { exit(1) }
    }

    private enum Lookup {
        case track(Track)
        /// The endpoint answered, and the answer was "no such thing".
        case noResults
        /// The endpoint never answered — a different problem, and not the
        /// catalogue's fault.
        case unreachable
    }

    private struct Track {
        let trackId: Int
        let trackName: String
        let kind: String
    }

    /// One `lookup` response, retrying because an empty result is far more often
    /// throttling than a missing app.
    private static func lookup(id: Int, country: String, attempts: Int) -> Lookup {
        var sawResponse = false
        for attempt in 1...attempts {
            guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)&country=\(country)")
            else { return .unreachable }
            if let data = try? Data(contentsOf: url),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = root["results"] as? [[String: Any]] {
                sawResponse = true
                if let first = results.first {
                    return .track(Track(
                        trackId: first["trackId"] as? Int ?? -1,
                        trackName: first["trackName"] as? String ?? "",
                        kind: first["kind"] as? String ?? "unknown"
                    ))
                }
            }
            // `resultCount: 0`, or a failed request — pause and ask again before
            // believing it.
            if attempt < attempts { Thread.sleep(forTimeInterval: 2) }
        }
        return sawResponse ? .noResults : .unreachable
    }

    /// Whether the store's listing plausibly names the same app.
    ///
    /// Store names carry marketing suffixes (`淘宝-万能的淘宝！`), so this is a
    /// containment test on a normalised form rather than equality.
    private static func resembles(storeName: String, app: KnownApp) -> Bool {
        let store = normalise(storeName)
        for candidate in [app.name, app.englishName] {
            let ours = normalise(candidate)
            guard !ours.isEmpty else { continue }
            if store.contains(ours) || ours.contains(store) { return true }
        }
        return false
    }

    /// Lowercased, with punctuation and spacing removed so `X（前身为Twitter）`
    /// and `X` compare equal.
    private static func normalise(_ text: String) -> String {
        text.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func isASCII(_ text: String) -> Bool {
        text.allSatisfy(\.isASCII)
    }

    private static func bare(_ scheme: String) -> String {
        scheme.replacingOccurrences(of: "://", with: "")
    }

    /// The app's `Info.plist`, found by walking up from the working directory.
    ///
    /// Not a fixed `../../`: `swift run` from the package directory and from the
    /// repo root are both reasonable things to do, and only one of them used to
    /// work — the other reported the plist as missing, which reads as "the file
    /// is gone" rather than "you're standing in the wrong place".
    private static var plistURL: URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = directory.appending(path: "Config/AppFolder-Info.plist")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        // Nothing found: return the most likely path so the error message names
        // a real location rather than an empty string.
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "../../Config/AppFolder-Info.plist")
            .standardizedFileURL
    }
}
