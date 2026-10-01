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
        ZStack {
            // A wallpaper stand-in. Everything in this file is about what a
            // surface does to what is *behind* it, so the backdrop has to have
            // structure in it.
            LinearGradient(
                colors: [
                    Color(red: 0.58, green: 0.47, blue: 0.36),
                    Color(red: 0.29, green: 0.21, blue: 0.15),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                plate(title: "A 玻璃 + 不画背景", detail: "glassEffect 画在一块透明板上") {
                    glassPlate { Rectangle().fill(Color.clear) }
                }
                plate(title: "B 玻璃 + Color.clear", detail: "把 .widget 交给系统，内容上再叠玻璃") {
                    glassPlate {
                        Rectangle().fill(Color.clear)
                            .containerBackground(for: .widget) { Color.clear }
                    }
                }
                plate(title: "C 只有玻璃，没有 containerBackground", detail: "看少了那一层会不会出事") {
                    glassPlate { Rectangle().fill(Color.clear) }
                }
            }
            .padding(20)
        }
    }

    /// `glassEffect` is iOS 26+; the widget target deploys lower, so the call
    /// has to be behind an availability check or the whole target fails to
    /// compile. Below 26 there is no glass to draw, so the plate is just the
    /// view the caller handed in.
    @ViewBuilder
    private func glassPlate<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            content().glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            content()
        }
    }

    private func plate<Fill: View>(
        title: String,
        detail: String,
        @ViewBuilder fill: () -> Fill
    ) -> some View {
        fill()
            .frame(height: 130)
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
