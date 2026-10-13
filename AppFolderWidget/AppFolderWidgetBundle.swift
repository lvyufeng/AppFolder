import SwiftUI
import WidgetKit

/// The widget extension: one widget, offered in every family.
///
/// ## What used to be here
///
/// A second widget — 大文件夹, `AppFolderWidget` — that tiled a folder's apps and
/// opened them through a URL scheme, bouncing through AppFolder for any app with
/// no universal link. It has been removed. Two reasons, and the second is the one
/// that decided it:
///
/// * Its geometry was the direct-launch widget's geometry. Both drew from
///   ``FolderGridMetrics``, so every change to the grid — the size ladder, the gap
///   floor, the door — had to be a change to both at once, and both had to be
///   re-verified on a device. One widget means one thing to check.
/// * It could not do the thing the app now exists to do. A tile in it reached its
///   target through a URL that the system might route anywhere, and the failure
///   mode was a tile that looked live and did nothing. ``DirectLaunchWidget``
///   reaches its target through the system's own shortcut mechanism, which cannot
///   fail that way. Keeping the weaker one beside the stronger one only left a
///   way for a user to pick the wrong one.
///
/// The folder *data* is untouched: the app still builds folders, still edits them,
/// still stores them. What is gone is the widget that drew one.
///
/// ## Which families are offered, and where that is decided
///
/// The supported set is stated on the configuration, in ``DirectLaunchWidget``,
/// because that is what the system reads and the only place it can be enforced.
/// This file records it so the next person reading the bundle does not have to
/// open the widget to learn it.
///
/// It is small, and on iOS 27 also extra-large portrait. The middle sizes were
/// offered twice and withdrawn twice: their margin and gap are shares of a
/// rectangle, where those shares only mean what they were chosen for on a square —
/// see ``DirectLaunchWidget`` for the measurements that took them out. If one is
/// ever offered again, the geometry is the place to look rather than this list.
@main
struct AppFolderWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 27.0, *) { DirectLaunchWidget() }
    }
}
