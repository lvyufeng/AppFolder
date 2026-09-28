import AppFolderKit
import SwiftUI

/// A folder's plate, drawn as the widget would draw it.
///
/// The counterpart to ``FolderPreviewGrid``: that one answers "where do the icons
/// go", this one answers "what are they sitting on". They are separate because
/// the answers differ in kind — the grid is always the same drawing, whereas the
/// plate has a case (``FolderPlate/automatic``) where the honest thing to draw is
/// *nothing at all*, and a view that draws nothing needs somewhere to say so.
///
/// ## What the 透明 case shows, and why it is a dashed outline
///
/// An app cannot draw the system's plate. It is composited around a snapshot the
/// extension already handed over, on the far side of a process boundary, so a
/// preview claiming to show it would be inventing a colour — and the invented
/// colour would be wrong in the one case that matters, because the whole point of
/// this case is that the plate depends on the user's 图标外观 setting and their
/// wallpaper, neither of which the app can read.
///
/// So it draws the absence instead: an empty outline at the exact size the plate
/// will be, plus the sentence the user actually needs — that the system draws
/// this one, and that it follows 图标外观 and the wallpaper. A preview that
/// invented a plausible glass would be promising a colour the app does not
/// control; naming who does control it is the honest version of the same
/// reassurance.
struct FolderPlateView: View {
    let style: FolderStyle
    /// What sits on the plate.
    let content: AnyView
    /// The plate's shape, as a ratio. Defaults to the medium widget's.
    var aspectRatio: CGFloat = FolderPlateView.widgetAspectRatio

    /// The shape of a medium widget on the Home Screen.
    ///
    /// Measured off a simulator screenshot rather than taken from memory: the
    /// widget's plate on the Home Screen is 349.7 × 164.3 pt on this device, and
    /// a preview at the wrong ratio would size the icons differently from the
    /// widget — which is the drift ``FolderGridMetrics`` exists to prevent.
    ///
    /// The default family in the gallery is Medium, so that is the one to match.
    /// Small is square and Large is taller; neither is a better default. Sizes do
    /// vary by device, and this is one device's.
    static let widgetAspectRatio: CGFloat = 349.7 / 164.3

    /// Apple's own inset between a widget's edge and its content.
    ///
    /// Measured, not remembered: a plate that painted its fill with the system's
    /// content margins still applied came out 313.7 pt wide inside a 349.7 pt
    /// widget — 18 pt a side, the same on all four. The widget turns those
    /// margins off so a painted plate can reach the edge, and re-applies exactly
    /// this much around the grid.
    static let contentInset: CGFloat = 18

    var body: some View {
        content
            .padding(Self.contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { plate }
            .aspectRatio(aspectRatio, contentMode: .fit)
    }

    @ViewBuilder
    private var plate: some View {
        if let fill = style.plateFill {
            // What the user chose, drawn exactly as the widget draws it: the same
            // `plateFill`, through the same shape.
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(fill)
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                )
        }
    }
}

/// The plate's explanation, shown under the picker rather than inside the preview.
///
/// Kept as a view rather than folded into ``FolderPlateView`` because the two are
/// answering different questions: the preview shows what will be drawn, and this
/// says what the user has to do to get the thing the preview cannot draw.
struct FolderPlateFootnote: View {
    let plate: FolderPlate

    var body: some View {
        Text(plate.localizedExplanation)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview("三档底板") {
    VStack(spacing: 16) {
        plate("透明", FolderStyle(plate: .automatic))
        plate("纯色", FolderStyle(plate: .solid, tint: FolderTint(hex: "#3478F6")!))
        plate("渐变", FolderStyle(plate: .gradient, tint: FolderTint(hex: "#F2A03D")!))
    }
    .padding()
}

@ViewBuilder
@MainActor
private func plate(_ title: String, _ style: FolderStyle) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.subheadline.weight(.medium))
        FolderPlateView(style: style, content: AnyView(placeholderGrid))
    }
}

@MainActor
private var placeholderGrid: some View {
    FolderPreviewGrid(tiles: FolderEntryPlaceholder.tiles)
}

/// Tiles for previews, mirroring the widget's own gallery placeholder.
enum FolderEntryPlaceholder {
    static let tiles: [FolderTile] = (0..<6).map { index in
        FolderTile(
            title: "App \(index + 1)",
            urlString: "appfolder://placeholder/\(index)",
            symbolName: ["message", "calendar", "camera", "music.note", "map", "envelope"][index]
        )
    }
}
