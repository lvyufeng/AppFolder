import AppFolderKit
import Foundation
import UIKit

/// Works out which apps from ``AppCatalog`` are actually on this device.
///
/// iOS has no API to list installed apps, so the only sanctioned discovery route
/// is asking, one scheme at a time, whether *something* handles it:
/// `canOpenURL(_:)`. Three rules bound what that can do:
///
/// * Every scheme must be declared in `Info.plist` under
///   `LSApplicationQueriesSchemes`, or `canOpenURL` returns `false` even when the
///   app is installed. That list is generated from ``AppCatalog/queriedSchemes``.
/// * The declaration list is capped — 25 entries for apps linked against iOS 27.
///   So this probes a *budgeted* subset, and the result distinguishes "we asked
///   and the answer was no" from "we never asked". Only the first is a reason to
///   hide a tile; the second is ignorance, and hiding a working tile on the
///   strength of it would be a bug.
/// * `canOpenURL` answers "is there a handler", not "is `weixin` installed" — a
///   different app could register the same scheme. In practice schemes are unique
///   enough that this doesn't matter, and the failure mode is benign.
///
/// `canOpenURL` is deprecated as of iOS 27 ("prefer attempting to open URLs and
/// handling any failures"), which is fair for launching and useless for
/// discovery — there is no way to attempt an open quietly. Discovery is the one
/// thing it is still good for, so this is the one place it is used.
@Observable
@MainActor
public final class InstallationProber {
    /// The result of one full sweep.
    public struct Result: Sendable {
        /// Schemes the system said yes to.
        public var installed: Set<String>
        /// Every scheme we asked about, so "no" can be told apart from "unknown".
        public var probed: Set<String>
    }

    public private(set) var installedSchemes: Set<String> = []
    public private(set) var probedSchemes: Set<String> = []
    public private(set) var isProbing = false

    public init() {}

    /// Probes the declared schemes. Cheap enough to run on every launch — a
    /// couple of dozen `canOpenURL` calls take single-digit milliseconds — but it
    /// yields between batches so the UI can show partial results rather than
    /// stalling.
    public func probe() async -> Result {
        guard !isProbing else {
            return Result(installed: installedSchemes, probed: probedSchemes)
        }
        isProbing = true
        defer { isProbing = false }

        var found: Set<String> = []
        var asked: Set<String> = []
        let schemes = AppCatalog.queriedSchemes

        for (index, scheme) in schemes.enumerated() {
            // The catalogue stores launchable URLs (`weixin://`); `canOpenURL`
            // and `URL.scheme` both want the bare form.
            let name = scheme.replacingOccurrences(of: "://", with: "")
            guard let url = URL(string: scheme) else { continue }
            asked.insert(name)
            if UIApplication.shared.canOpenURL(url) {
                found.insert(name)
            }
            if index % 8 == 7 {
                installedSchemes = found
                probedSchemes = asked
                await Task.yield()
            }
        }

        installedSchemes = found
        probedSchemes = asked
        return Result(installed: found, probed: asked)
    }

    /// Whether a catalog entry appears to be installed.
    public func isInstalled(_ app: KnownApp) -> Bool {
        installedSchemes.contains(app.schemeName.lowercased())
    }
}
