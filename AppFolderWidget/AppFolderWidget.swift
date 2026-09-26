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
                // Measured on iOS 27, against a brown #B59989 wallpaper, in light
                // appearance. Four separate attempts to get something translucent
                // into a widget, and what each actually rendered:
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
                // result is #969696, which is black blended against *white*. So a
                // widget's snapshot has an opaque white backdrop and no access to
                // the wallpaper, and **an app cannot make a widget translucent by
                // drawing**. Materials and `glassEffect` degrade to flat fills for
                // the same reason.
                //
                // Where the plate comes from is the user's 图标外观 setting (long
                // press the Home Screen → 编辑 → 自定), whose 透明 option is what
                // makes widgets glass. Apps do not participate in that; the widget
                // drawn here is the same content either way. That is also why this
                // reader is a `Color.clear` rather than a look-alike: anything we
                // drew would sit under that plate and fight it.
                //
                // Either way the plate is not ours to draw. Apple's own widgets are
                // flat opaque white inside (the Maps and Calendar widgets both
                // measure #FFFFFF with a hard edge against the wallpaper), so a
                // widget surface is white-on-white by design; the glass, if any,
                // is added around all of them at mount time, by the system, under
                // the user's 图标外观 setting.
                .containerBackground(for: .widget) { Color.clear }
        }
        // Lets the system drop the plate entirely under 透明. This is exactly the
        // hook the measurement above is about: the plate is the system's, drawn
        // when it mounts the widget, so asking for no fill is the only way to get
        // out of its way. Not verifiable here — not because the simulator lacks a
        // glass pipeline (it has one: the dock's luminance tracks the wallpaper
        // behind it at r = +0.997, with a lit rim along its edge) but because
        // nothing can open 编辑 → 自定 on this machine to switch the appearance.
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
