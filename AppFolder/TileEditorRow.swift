import AppFolderKit
import SwiftUI
import UIKit

/// One tile in the editor: icon, name, URL, launch route.
///
/// The launch route is editable here and nowhere else, on purpose. A tile that
/// cannot open its app is indistinguishable from a broken app — the tap just
/// does nothing — so the place to find out is the editor, where the user is
/// already looking at the tile and can act on it.
///
/// "直接打开" is the route that makes this necessary. It needs the target app to
/// publish a universal link, which most apps do not, and the wrong choice
/// produces exactly the silent-nothing tap described above. So the option is
/// offered only when there is a link to use, and when it cannot be used the
/// editor says why and offers the fix — rather than letting the tile be saved in
/// a state where the widget renders it inert.
struct TileEditorRow: View {
    @Binding var tile: FolderTile
    @State private var isTesting = false
    @State private var result: TestResult?

    private enum TestResult {
        case opened
        case noHandler
        case finished
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TileIcon(tile: tile, side: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tile.title)
                    Text(tile.urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Menu {
                LaunchRouteMenu(tile: tile) { tile.strategy = $0 }
            } label: {
                HStack(spacing: 6) {
                    Text("打开方式")
                    Spacer()
                    Text(tile.strategy.localizedName)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
            }

            Text(tile.strategy.localizedExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let refusal = tile.universalLinkRefusal {
                refusalNotice(refusal)
            }

            HStack(spacing: 12) {
                Button("试一下") { test() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTesting)

                if let result {
                    switch result {
                    case .opened:
                        Label("已交给系统打开", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .noHandler:
                        Label("没有 App 能打开这个链接", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .finished:
                        Label("已发送，请确认目标 App 是否打开", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if case .noHandler = result {
                Text("这个链接在当前设备上打不开，可能是目标 App 没装，或者链接写错了。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: tile.strategy) { _, _ in
            // A stale verdict from a previous route reads as a verdict on this
            // one. Clear it rather than let the user draw the wrong conclusion.
            result = nil
        }
    }

    /// Explains an unusable "直接打开" and offers the one-tap way out.
    ///
    /// The repair is only offered when a repair exists: switching a tile that is
    /// already broken to the route that works. Anything else would be a button
    /// that changes a setting without fixing the tile.
    @ViewBuilder
    private func refusalNotice(_ refusal: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(refusal)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(.orange)

            if tile.canLaunch == false, tile.url != nil {
                Button("改用「经 AppFolder 中转」") {
                    tile.strategy = .bounce
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// Tries the URL for real.
    ///
    /// `canOpenURL` answers this directly when the scheme is declared in
    /// `LSApplicationQueriesSchemes`. The catalogue's schemes are, so this is a
    /// trustworthy answer for them; a scheme the user typed by hand is not
    /// declared, so `canOpenURL` returns false regardless and the honest thing
    /// to report is "sent, check for yourself" rather than a false negative.
    ///
    /// Note what this does *not* do: it does not verify that the widget's own
    /// route works. A `Button(intent:)` tap runs in the extension's process and
    /// tells nobody whether it succeeded, so the only real test of the widget is
    /// tapping the widget. This button answers the narrower, answerable question
    /// of whether the URL is reachable at all.
    private func test() {
        // The URL the tile will actually open, so "试一下" tests the route the
        // user configured rather than the one they didn't.
        guard let target = tile.launchURL else {
            result = .noHandler
            return
        }
        isTesting = true
        // Only a declared scheme (or one of Apple's, which need no declaration)
        // gets a trustworthy answer from `canOpenURL`. For anything else a `false`
        // would be the declaration rule talking, not the device, so the honest
        // report is "sent, go look".
        let isProbeable = AppCatalog.probeableSchemes.contains { scheme in
            target.scheme?.lowercased() == scheme.replacingOccurrences(of: "://", with: "").lowercased()
        }

        if isProbeable, !UIApplication.shared.canOpenURL(target) {
            result = .noHandler
            isTesting = false
            return
        }

        UIApplication.shared.open(target) { success in
            result = success ? .opened : .finished
            isTesting = false
        }
    }
}

// MARK: - Route picker

/// The `打开方式` menu, with the routes that cannot work removed.
///
/// A separate view because a `Picker` cannot disable one of its own rows:
/// `.disabled` applies to the whole control. The menu is built by hand instead,
/// which is also what allows each route to carry a reason.
struct LaunchRouteMenu: View {
    let tile: FolderTile
    let onPick: (LaunchStrategy) -> Void

    /// Routes offered for this tile, in the enum's own order.
    private var offered: [LaunchStrategy] {
        LaunchStrategy.allCases.filter { strategy in
            // Whatever is already selected stays listed, or the menu would
            // misreport the tile's state and the user could not switch away
            // from a route they picked before it became unusable.
            strategy == tile.strategy || Self.isAvailable(strategy, for: tile)
        }
    }

    private static func isAvailable(_ strategy: LaunchStrategy, for tile: FolderTile) -> Bool {
        switch strategy {
        case .universalLink: tile.universalLink != nil
        case .bounce: tile.url != nil
        case .systemShortcut: false
        }
    }

    var body: some View {
        ForEach(offered, id: \.self) { strategy in
            Button {
                onPick(strategy)
            } label: {
                if strategy == tile.strategy {
                    Label(strategy.localizedName, systemImage: "checkmark")
                } else {
                    Text(strategy.localizedName)
                }
            }
        }
    }
}

