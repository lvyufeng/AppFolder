#if canImport(SwiftUI)
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The same artwork in the editor, saved-icon list, and every widget grid.
/// Its parent owns the accessible action name; the artwork is decorative.
public struct CustomIconArtwork: View {
    public let icon: CustomIcon
    public let cornerRadius: CGFloat
    /// Widgets opt into appearance adaptation; the app's editor keeps original colors.
    public let usesWidgetRendering: Bool
    /// A miniature must remain bounded even if its source also serves a full tile.
    public let maxPixelSize: Int
    @Environment(\.widgetRenderingMode) private var renderingMode

    public init(icon: CustomIcon, cornerRadius: CGFloat = 12, usesWidgetRendering: Bool = false,
                maxPixelSize: Int = 256) {
        self.icon = icon
        self.cornerRadius = cornerRadius
        self.usesWidgetRendering = usesWidgetRendering
        self.maxPixelSize = min(max(1, maxPixelSize), CustomIcon.maximumPhotoSide)
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let tint = FolderTint(hex: icon.backgroundHex) ?? .defaultTint
            ZStack {
                Color(red: tint.red, green: tint.green, blue: tint.blue)
                    // Accented rendering tints both the background and glyph white.
                    // Preserve their contrast through alpha instead of source color.
                    .opacity(isAccented ? (icon.kind == .photo ? 0 : 0.18) : 1)
                switch icon.kind {
                case .symbol:
                    Image(systemName: icon.value)
                        .font(.system(size: side * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.monochrome)
                case .emoji:
                    Text(verbatim: icon.value)
                        .font(.system(size: side * (icon.value.count == 1 ? 0.62 : 0.42)))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                case .date:
                    DateIconGlyph(side: side)
                case .photo:
                    if let image = photo {
                        if usesWidgetRendering {
                            image.resizable()
                                .widgetAccentedRenderingMode(.fullColor)
                                .scaledToFill()
                        } else {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    private var isAccented: Bool { usesWidgetRendering && renderingMode == .accented }

    private var photo: Image? {
        guard let image = icon.decodedPhoto(maxSide: maxPixelSize) else { return nil }
        return Image(decorative: image, scale: 1)
    }
}
#endif
