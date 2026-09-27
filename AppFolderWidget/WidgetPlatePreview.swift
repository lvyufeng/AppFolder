import SwiftUI

/// The widget's own rendering, with no dependency on `AppFolderKit`.
///
/// This file exists so the widget's appearance can be iterated in **Xcode
/// Previews**, which do not need a device, a signing identity, or a running
/// simulator session. `FolderWidgetView` needs a `FolderEntry` full of tiles
/// and an App Group to read icons from, so it cannot be previewed from a bare
/// file the way this can.
///
/// ## What it is really for
///
/// The question this renders is whether an app can make a widget's *own* region
/// translucent. Everything measured so far says no: a widget's content is drawn
/// onto an opaque plate and mounted as a unit, and Apple's own widgets agree
/// (Maps and Calendar both measure flat `#FFFFFF` inside, on the same screen
/// where an iOS folder transmits its wallpaper). See `AppFolderWidget.swift`
/// for the full table.
///
/// The unanswered half is what the system puts under a widget on a **real
/// device** at the default 图标外观. The simulator draws a flat white plate there
/// while its own dock, search pill and folders transmit the wallpaper, and there
/// is no way to reach the customization menu from here to check another
/// appearance — the setting lives in the Home Screen poster store and an
/// unchanged value is never written down. That part needs a device.
///
/// Previews are where that gets checked next: `#Preview` runs the real view
/// builder, and Xcode renders it against a wallpaper instead of a white sheet,
/// which is the part the screenshots could not show.
struct WidgetPlatePreview: View {
    var body: some View {
        VStack(spacing: 16) {
            plate(
                title: "现在的写法",
                detail: ".containerBackground { Color.clear }"
            ) {
                Color.clear
            }
            plate(
                title: "上次试过的写法",
                detail: "45% 黑 —— 渲染成 #969696，说明底下是白板"
            ) {
                Color.black.opacity(0.45)
            }
            plate(
                title: "对照：真玻璃应该长这样",
                detail: "同一张壁纸上透出下面的颜色"
            ) {
                Rectangle().fill(.regularMaterial)
            }
        }
        .padding(20)
        // A wallpaper-like backdrop: without gradients behind it there is
        // nothing for a translucent surface to be translucent *to*.
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.58, green: 0.47, blue: 0.36),
                    Color(red: 0.29, green: 0.21, blue: 0.15),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func plate<Fill: View>(
        title: String,
        detail: String,
        @ViewBuilder fill: () -> Fill
    ) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.clear)
            .overlay { fill() }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .frame(height: 110)
            .overlay {
                VStack(spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
    }
}

#Preview("Widget 底板") {
    WidgetPlatePreview()
}
