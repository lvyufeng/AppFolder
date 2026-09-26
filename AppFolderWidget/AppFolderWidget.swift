import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

/// The folder widget: a grid of tiles, each one a button.
///
/// Two structural facts about WidgetKit shape everything here:
///
/// * A widget view is a static snapshot. It cannot hold `@State`, so the grid is
///   drawn entirely from the timeline entry, and any interaction has to go
///   through an `AppIntent` that the *system* runs.
/// * A `Button(intent:)` renders as a tappable region but the system decides
///   when the widget redraws afterwards. Anything that looks like an animation
///   is really "hold the old frame, then swap".
struct AppFolderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppFolderShared.widgetKind,
            intent: FolderSelectionIntent.self,
            provider: FolderTimelineProvider()
        ) { entry in
            FolderWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(entry: entry)
                }
        }
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
