import AppFolderKit
import SwiftUI
import UIKit

/// A folder's whole contents, opened from the grid's last cell.
///
/// ## Why this exists
///
/// A widget shows a fixed number of cells, and a folder is not required to fit
/// in them. The alternative to this screen is not "no screen" — it is a folder
/// whose tenth app is invisible on the Home Screen, which the user has no way to
/// distinguish from an app they never added. So the last cell stops being an app
/// and becomes a door, and this is what is behind it.
///
/// ## What it is not
///
/// Not the editor. The editor is reachable from the folder list and is for
/// changing things; a screen that appears when someone taps an icon on their Home
/// Screen is for *launching*, and every extra control in it is a step between the
/// tap and the app. So this draws icons and launches them, and nothing else.
///
/// ## The two-hop problem
///
/// A tap here still may not be able to reach the target app. ``LaunchStrategy``
/// is a property of the tile, and for most apps it is ``bounce``: a custom scheme
/// the widget could not hand to the system, which AppFolder opens on its behalf.
/// Here there is no need for the widget's trick — this *is* the app — so a tap
/// calls `open(_:)` directly, which is the same second hop the bounce route makes
/// without the blank-screen dance.
///
/// A tile that cannot launch at all — a `systemShortcut`, which has no URL of its
/// own, or a malformed link — is drawn but inert, the same choice the widget
/// makes. See ``TileLauncher``.
struct FolderExpandView: View {
    let folder: Folder

    @Environment(\.dismiss) private var dismiss

    private var columns: Int {
        // Derived from the count rather than from the folder's grid setting: the
        // setting exists to decide how many apps fit in a *widget*, and a sheet
        // that showed four at a time with a scroll would be applying a widget's
        // constraint to a screen that has no such constraint. Four across is
        // where a phone stops looking like a folder and starts looking like a
        // table, which is the same call ``FolderGridMetrics/columns(forTileCount:)``
        // already makes for counts above nine.
        FolderGridMetrics.columns(forTileCount: folder.tiles.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns),
                    spacing: 20
                ) {
                    ForEach(folder.tiles) { tile in
                        TileLauncher(tile: tile, titleStyle: FolderStyle(folder).titleStyle)
                    }
                }
                .padding()
            }
            .navigationTitle(folder.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

/// One app in the expanded folder: icon, name, and a tap that opens it.
///
/// The launching lives here rather than in the view body so that the three
/// outcomes — launched, could not launch, and never could — are decided in one
/// place, the same way ``TileButton`` decides them for the widget.
///
/// The route is deliberately *not* ``FolderTile/launchURL``, which is the widget's
/// answer. That property returns `nil` for a universal-link tile with no link so
/// the widget will not draw a live-looking button; here the target is a scheme
/// the app itself can open, and refusing it because the *widget's* route would
/// not have worked would make the expanded folder less capable than the widget.
/// What this screen needs is ``FolderTile/url``.
private struct TileLauncher: View {
    let tile: FolderTile
    let titleStyle: AnyShapeStyle

    /// A real Home Screen icon is about 60 pt on this class of device, and these
    /// should look like the same apps. Larger would make a grid of four on a
    /// phone look like a different folder from the one the widget drew.
    private static let iconSide: CGFloat = 64

    var body: some View {
        VStack(spacing: 6) {
            TileIcon(tile: tile, side: Self.iconSide)

            Text(tile.title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(titleStyle)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .opacity(canOpen ? 1 : 0.45)
        .onTapGesture(perform: open)
        // Named as a link so VoiceOver announces the ones that do something, and
        // left unnamed when nothing happens — an element that offers an action it
        // will not perform is worse than one that offers none.
        .accessibilityAddTraits(canOpen ? .isButton : [])
    }

    /// Whether this tile has a URL the app can hand to the system.
    private var canOpen: Bool { tile.url != nil }

    private func open() {
        guard let url = tile.url else { return }
        UIApplication.shared.open(url)
    }
}