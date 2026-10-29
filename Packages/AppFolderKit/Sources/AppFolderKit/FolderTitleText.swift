import SwiftUI
import WidgetKit

/// One title implementation shared by saved-group widgets and their editor.
/// The no-customization branch intentionally retains the original Text chain.
public struct FolderTitleText: View {
    public let text: String
    public let fontSize: CGFloat
    public let width: CGFloat
    public let style: FolderStyle
    public let minimumScaleFactor: CGFloat
    public let weight: Font.Weight
    public let usesWidgetRendering: Bool
    public let availableHeight: CGFloat?
    @Environment(\.self) private var environment
    @Environment(\.displayScale) private var displayScale

    public init(text: String, fontSize: CGFloat, width: CGFloat, style: FolderStyle,
                minimumScaleFactor: CGFloat = 0.7, weight: Font.Weight = .regular,
                usesWidgetRendering: Bool = false, availableHeight: CGFloat? = nil) {
        self.text = text
        self.fontSize = fontSize
        self.width = width
        self.style = style
        self.minimumScaleFactor = minimumScaleFactor
        self.weight = weight
        self.usesWidgetRendering = usesWidgetRendering
        self.availableHeight = availableHeight
    }

    @ViewBuilder
    public var body: some View {
        if style.titleTint == nil && style.titleOutlineTint == nil {
            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .lineLimit(1).minimumScaleFactor(minimumScaleFactor)
                .foregroundStyle(style.titleStyle).frame(width: width)
        } else {
            // Let native Text continue to determine the cell's layout. The
            // bitmap occupies only its overlay, never the grid's geometry.
            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .lineLimit(1).minimumScaleFactor(minimumScaleFactor)
                .foregroundStyle(style.labelStyle).frame(width: width)
                .hidden()
                .overlay { customTitle }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: text))
        }
    }

    @ViewBuilder
    private var customTitle: some View {
        if let raster {
            let image = Image(decorative: raster.image, scale: 1).resizable()
            if usesWidgetRendering {
                image.widgetAccentedRenderingMode(.fullColor)
                    .frame(width: raster.size.width, height: raster.size.height)
            } else {
                image.frame(width: raster.size.width, height: raster.size.height)
            }
        } else {
            // Impossible dimensions or unsupported input must not lose a name.
            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .lineLimit(1).minimumScaleFactor(minimumScaleFactor)
                .foregroundStyle(style.labelStyle).frame(width: width)
        }
    }

    private var raster: FolderTitleRaster? {
        let fill = style.labelColor.resolve(in: environment)
        let outline = style.titleOutlineTint?.color.resolve(in: environment)
        let request = FolderTitleRenderRequest(
            text: text, fontSize: fontSize, width: width, availableHeight: availableHeight,
            minimumScaleFactor: minimumScaleFactor, weight: coreTextWeight,
            displayScale: displayScale,
            foreground: rgba(fill), outline: outline.map(rgba),
            outlineWidth: style.titleOutlineTint == nil ? 0 : style.titleOutlineWidth.points
        )
        return FolderTitleRasterCache.shared.raster(for: request)
    }

    private func rgba(_ color: Color.Resolved) -> FolderTitleRGBA {
        // Resolved semantic colors use extended sRGB; even ordinary dark-mode
        // white can resolve to 1.0000001. Convert into our 8-bit SDR gamut here,
        // without relaxing the rasterizer's validation of malformed requests.
        func sdr(_ value: Float) -> Double {
            let component = Double(value)
            return component.isFinite ? min(1, max(0, component)) : component
        }
        return FolderTitleRGBA(red: sdr(color.red), green: sdr(color.green), blue: sdr(color.blue),
                               alpha: sdr(color.opacity))
    }

    private var coreTextWeight: CGFloat {
        switch weight {
        case .ultraLight: -0.8
        case .thin: -0.6
        case .light: -0.4
        case .medium: 0.23
        case .semibold: 0.3
        case .bold: 0.4
        case .heavy: 0.56
        case .black: 0.62
        default: 0
        }
    }
}
