import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

/// The widget's rendered content: a grid of buttons, nothing else.
///
/// The only interactive element is `Button(intent: LaunchTileIntent(...))`. Each
/// button's job is to hand a URL to the system; see ``LaunchTileIntent`` for why
/// that reaches a third-party app at all. There is intentionally no `Link` here:
/// a `Link` in a widget can only open the containing app.
///
/// ## Appearance
///
/// There is no background drawn here, and that is the whole visual design. On
/// iOS 26 and later the system gives every widget a container — the Liquid Glass
/// plate — and what an app supplies through `containerBackground` is composited
/// *behind* it. Returning `Color.clear` asks for no fill of our own, which is
/// what lets the system's material be the widget's entire chrome: it picks up
/// the wallpaper's colour, blurs it, and matches whatever the user has chosen
/// for their Home Screen (default, tinted, or clear icons). Drawing a gradient
/// or a solid here would sit underneath that and turn the glass into a slightly
/// foggy window onto a rectangle.
///
/// On iOS 18–25 the same empty background means the widget shows the Home Screen
/// wallpaper, because that is what an unfilled widget region did before the
/// container existed. Neither behaviour is wrong, and neither is a colour we
/// chose — which is the point.
struct AppFolderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppFolderShared.widgetKind,
            intent: FolderSelectionIntent.self,
            provider: FolderTimelineProvider()
        ) { entry in
            FolderWidgetView(entry: entry)
                // No fill of our own, so the system's container is the chrome.
                //
                // iOS 26+: widgets are composited onto a Liquid Glass plate that
                // the system draws, and `containerBackground` renders *behind*
                // it. `Color.clear` therefore asks for nothing, and the plate is
                // the whole background — wallpaper-tinted, blurred, and matching
                // whatever the user picked for their Home Screen icons. Any fill
                // given here would sit under the glass and defeat it. Measured:
                // in dark appearance this region reads #19192A against a #2C2F4A
                // wallpaper, i.e. the wallpaper showing through a dark material,
                // while an app that ships its own opaque background (日历) stays
                // white in the same frame.
                //
                // iOS 18–25: an unfilled widget region shows the wallpaper,
                // which is what it did before the container existed.
                .containerBackground(for: .widget) { Color.clear }
        }
        // Lets the system drop our container entirely under the Home Screen's
        // 透明 icon appearance, so the folder melts into the wallpaper instead of
        // sitting on a plate. The app draws nothing that needs a backing — the
        // icons are opaque artwork, not text on a fill — so there is nothing to
        // lose by allowing it.
        .containerBackgroundRemovable(true)
        .configurationDisplayName("大文件夹")
        .description("在桌面上平铺显示一个文件夹里的 App，点一下直接打开。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct AppFolderWidgetBundle: WidgetBundle {
    var body: some Widget {
        AppFolderWidget()
    }
}
