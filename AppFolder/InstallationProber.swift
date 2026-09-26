import AppFolderKit
import Foundation
import UIKit

/// Works out which apps from ``AppCatalog`` are actually on this device.
///
/// iOS has no API to list installed apps, so the only sanctioned discovery
/// route is asking, one scheme at a time, whether *something* handles it:
/// `canOpenURL(_:)`. Two rules make that work at all:
///
/// * Every scheme must be declared in `Info.plist` under
///   `LSApplicationQueriesSchemes`, or `canOpenURL` returns `false` even when
///   the app is installed. The list is generated from ``AppCatalog/queriedSchemes``.
/// * `canOpenURL` answers "is there a handler", not "is `weixin` installed" —
///   a different app could register the same scheme. In practice schemes are
///   unique enough that this does not matter, and the failure mode is benign:
///   we show an icon, tapping opens something plausible.
@Observable
@MainActor
public final class InstallationProber {
    /// Schemes confirmed reachable. Empty until the first probe finishes.
    public private(set) var installedSchemes: Set<String> = []
    public private(set) var isProbing = false
    public private(set) var lastProbeAt: Date?

    public init() {}

    /// Probes every known scheme. Cheap enough to run in full on launch — a few
    /// hundred `canOpenURL` calls take single-digit milliseconds — but yielding
    /// between batches keeps the UI responsive and lets results stream in.
    public func probe() async {
        guard !isProbing else { return }
        isProbing = true
        defer { isProbing = false }

        var found: Set<String> = []
        let schemes = AppCatalog.queriedSchemes
        for (index, scheme) in schemes.enumerated() {
            guard let url = URL(string: scheme) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                found.insert(scheme)
            }
            if index % 32 == 31 {
                installedSchemes = found
                await Task.yield()
            }
        }

        installedSchemes = found
        lastProbeAt = .now
    }

    /// Whether a catalog entry appears to be installed.
    public func isInstalled(_ app: KnownApp) -> Bool {
        installedSchemes.contains(app.scheme)
    }
}
