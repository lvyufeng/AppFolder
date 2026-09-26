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
/// The widget draws no background of its own, and that is the whole design. What
/// sits behind the content is the plate the system puts under every widget, and
/// whether that plate is glass is the user's choice — Home Screen → 编辑 → 自定 →
/// 图标外观 — not ours. See the measured table on the `containerBackground` call
/// below for what an app can and cannot do here.
///
/// On iOS 18–25 there is no such plate and an unfilled widget region shows the
/// Home Screen wallpaper, which is what it did before the container existed.
/// Neither behaviour is a colour we chose, which is the point.
struct AppFolderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppFolderShared.widgetKind,
            intent: FolderSelectionIntent.self,
            provider: FolderTimelineProvider()
        ) { entry in
            FolderWidgetView(entry: entry)
                // No fill of our own: the plate under a widget is the system's to
                // draw, and this is the lever that asks it not to.
                //
                // Four separate attempts to get something translucent into a widget,
                // and what each actually rendered against a brown #B59989 wallpaper:
                //
                // | `containerBackground` | rendered | reads wallpaper? |
                // |---|---|---|
                // | pure red | #FF4A4D | n/a — the fill lands, so this *is* the hook |
                // | `Color.black.opacity(0.45)` | #969696 | **no** — perfectly neutral R=G=B |
                // | `.ultraThinMaterial` | #F4F4F5 | no — flat |
                // | `.glassEffect(.regular, in:)` | #FCFCFC | no — flat |
                //
                // The second row is the one that settles it. A 45% black over that
                // wallpaper would be #64544B if the two were ever composited; the
                // result is #969696, which is black blended against *white*, and the
                // plate measures a literal #FFFFFF even where the wallpaper behind it
                // is dark. So a widget's snapshot has an opaque plate under it and no
                // access to the wallpaper, and **an app cannot make a widget
                // translucent by drawing**. Materials and `glassEffect` degrade to
                // flat fills for the same reason.
                //
                // Apple's own widgets are the control: on one screen, Maps and
                // Calendar both measure perfectly flat #FFFFFF inside, while the iOS
                // folder a few rows below them — two apps dragged together —
                // transmits the wallpaper behind it (#967060, #9D7762, following what
                // is underneath). The glass renderer is demonstrably running; it is
                // simply not offered to a widget's own content.
                //
                // So where the plate comes from is the user's 图标外观 setting (long
                // press the Home Screen → 编辑 → 自定), and the system draws it around
                // the content either way. That is why this reader is a `Color.clear`
                // rather than a look-alike: anything we drew would sit under that
                // plate and fight it.
                .containerBackground(for: .widget) { Color.clear }
        }
        // Lets the system drop the plate in contexts that prefer no background —
        // the user's 透明 icon appearance is one, and it is the one being asked
        // for. Apple's own words for this modifier: mark the background removable
        // "to allow people to place the widget in as many contexts as possible",
        // and "the system always displays the background container" if you do not;
        // they also warn the container "may render differently; for example, it can
        // appear faded or desaturated" when it is not removable. So the plate is
        // the system's, and this is the switch that tells it we have not built our
        // layout around one — the prerequisite for 透明, not the cause of it.
        //
        // No effect before iOS 17, and the app targets 18, so there is no
        // conditional needed here.
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
