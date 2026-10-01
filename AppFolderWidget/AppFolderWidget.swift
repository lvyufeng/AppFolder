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
/// The folder decides what this plate is — see ``FolderPlate``. There are three
/// settings and no fourth: 透明 paints nothing and lets the system draw the
/// plate, which is also the only arrangement that reacts to the user's 图标外观
/// (默认 / 浅色 / 深色 / 透明). 纯色 and 渐变 paint a colour the user picked, and
/// are honest about what that costs: a plate we draw is a plate the system's
/// appearance setting no longer reaches.
///
/// 透明 is not a second, weaker glass setting — it *is* the glass setting, and it
/// is the default. The distinction is the one that survived measurement: an app
/// chooses between *the system's plate* and *one it paints*, and it has no lever
/// on the material itself. A plate of our own cannot be made to show the
/// wallpaper through — measured seven ways, four inside the content and three in
/// `containerBackground`, and the full table is on the `containerBackground` call
/// below — because the widget is composited onto the system's plate before it
/// ever meets a wallpaper. A screenshot of one Home Screen makes the same point
/// from the other side: Apple's own Maps and Calendar widgets measure the same
/// flat `#FFFFFF` ours does, while the iOS folders and the Dock beside them
/// transmit the wallpaper.
struct AppFolderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppFolderShared.widgetKind,
            intent: FolderSelectionIntent.self,
            provider: FolderTimelineProvider()
        ) { entry in
            FolderWidgetView(entry: entry)
                // The plate the folder asked for, drawn **in the content layer**,
                // which is not where the plan put it and is where measurement put
                // it. The same `#3478F6`, drawn through `containerBackground`,
                // renders as `#4583F7` — the system composites its own glass over
                // that layer, and the glass has a vertical alpha ramp: +12% white
                // at the widget's top edge fading to +5% at the bottom. A user who
                // picks a colour should get that colour, so the fill goes where
                // nothing is layered on top of it.
                //
                // Measured, one column clear of the icons, same widget, same
                // wallpaper, only the drawing layer changed:
                //
                // | y (px) | `containerBackground` | content layer | excess |
                // |---|---|---|---|
                // | 1500 | #4D88F7 | #4D88F7 | 0 — inside the corner radius |
                // | 1600 | #4A86F7 | #3478F6 | +11% white |
                // | 1730 | #4583F7 | #3478F6 | +8% |
                // | 1930 | #3E7FF7 | #3E7FF7 | 0 — the ramp has run out |
                //
                // Two things fall out of this beyond the colour fidelity. The
                // system clips content to the widget's shape, so an edge-to-edge
                // fill needs no corner radius of its own — the corner insets
                // measured off both paths are identical (96 px at the top row,
                // 1 px by 80 px down, which fits a radius of 83 px = 27.7 pt). And
                // the content layer being *above* the glass is why ``FolderPlate``
                // can promise 纯色 at all: the fill is not fighting the plate, it
                // is covering it.
                //
                // What `containerBackground` keeps is the case where the app
                // should not paint: `Color.clear` leaves the plate to the system,
                // which is ``FolderPlate/automatic`` — 透明 in the picker — and the
                // only setting that reacts to the user's 图标外观. A widget with no
                // container background at all is not drawn correctly, so this call
                // stays.
                .background {
                    if let fill = entry.style.plateFill {
                        // No `ignoresSafeArea` here, because it does not escape
                        // what is actually in the way. A widget's content is laid
                        // out inside the system's content margins — measured at a
                        // uniform 18 pt on all four sides of a medium widget — and
                        // a `.background` is inset by them. `contentMarginsDisabled`
                        // below removes them, and ``FolderWidgetView`` then applies
                        // its own padding, so the fill reaches the widget's edge and
                        // the icons still sit where the measurements put them.
                        Rectangle().fill(fill)
                    }
                }
                .containerBackground(for: .widget) { Color.clear }
        }
        // Lets the system drop the plate in contexts that prefer no background —
        // the user's 透明 icon appearance is one. Apple's own words for this
        // modifier: mark the background removable "to allow people to place the
        // widget in as many contexts as possible", and "the system always displays
        // the background container" if you do not; they also warn the container
        // "may render differently; for example, it can appear faded or
        // desaturated" when it is not removable. So the plate is the system's
        // either way, and this switch only tells it we have not built our layout
        // around one — a prerequisite for the system's own treatment to show, not
        // the cause of any glass.
        //
        // Note where this modifier lives: on `WidgetConfiguration`, not on the
        // view inside it. It is therefore one setting for the whole widget and
        // cannot be made to follow ``FolderPlate`` — a folder that painted a
        // colour would still be droppable in a context that prefers no
        // background. That is a real edge, and it is the reason 透明 is the
        // default rather than something a user has to find: the plate the system
        // draws is the one this switch was written for.
        //
        // No effect before iOS 17, and the app targets 18, so there is no
        // conditional needed here.
        .containerBackgroundRemovable(true)
        // Turns off the 18 pt margin the system leaves inside a widget.
        //
        // It has to be off for exactly one reason: a folder that paints its own
        // plate needs the fill to reach the widget's edge, and content margins
        // apply to `.background` as much as to anything else — measured, a solid
        // #3478F6 came out 313.7 pt wide inside a 349.7 pt widget, with exactly
        // 18 pt of the system's white plate left showing on every side.
        //
        // The cost is that the grid is now responsible for its own inset, which
        // is where ``FolderGridMetrics`` already was: it divides up whatever
        // container it is handed, so ``FolderWidgetView`` passes it one 18 pt
        // smaller on each side and the icons land precisely where they did before.
        // Keeping the two is not pedantry — the measurement above means the widget
        // and the editor's preview were 18 pt apart on the two settings that paint,
        // and the preview exists to make that impossible.
        //
        // Not needed on iOS 18–25, where there are no content margins to disable,
        // but the modifier is a no-op there rather than an error.
        .contentMarginsDisabled()
        // Asks the host for the system's Liquid Glass plate. This is a
        // configuration-level preference, not a view one: it is what makes the
        // widget take the same plate the Home Screen gives its own folders.
        //
        // It compiles only because `Scripts/widgetkit-overlay.sh` runs before
        // this target's Swift compile and drops a WidgetKit module into
        // TARGET_TEMP_DIR that declares the entry point. iOS exports it and
        // WidgetKit.tbd lists it, but no SDK swiftinterface publishes it, so an
        // ordinary build cannot see it. That script is also why the call cannot
        // be replaced by a Swift extension of the same name — see its header.
        //
        // 透明 is where this shows. A folder that paints its own colour fills
        // the content layer, which sits above the plate and hides it, so those
        // settings keep the colour they promised and lose the glass.
        .preferredBackgroundStyle(.blur)
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
