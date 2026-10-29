#if canImport(SwiftUI)
import SwiftUI

/// A website owns its artwork by node, independently of its title or URL.
/// Rendering never fetches the site; callers supply bounded local artwork.
public struct WebsiteArtwork: View {
    public let variants: CustomIconVariants?
    public var cornerRadius: CGFloat
    public var usesWidgetRendering: Bool
    public var maxPixelSize: Int
    @Environment(\.colorScheme) private var colorScheme

    public init(variants: CustomIconVariants? = nil, cornerRadius: CGFloat = 12,
                usesWidgetRendering: Bool = false, maxPixelSize: Int = 256) {
        self.variants = variants
        self.cornerRadius = cornerRadius
        self.usesWidgetRendering = usesWidgetRendering
        self.maxPixelSize = maxPixelSize
    }

    public var body: some View {
        let selected = variants?.resolved(isDark: colorScheme == .dark)
        CustomIconArtwork(icon: selected ?? Self.defaultIcon,
                          cornerRadius: cornerRadius, usesWidgetRendering: usesWidgetRendering,
                          maxPixelSize: maxPixelSize)
            .overlay(alignment: .bottomTrailing) {
                if selected != nil {
                    GeometryReader { proxy in
                        let side = min(proxy.size.width, proxy.size.height)
                        if side >= 24 {
                            Image(systemName: "link")
                                .font(.system(size: max(6, side * 0.15), weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: max(11, side * 0.3), height: max(11, side * 0.3))
                                .background(.black.opacity(0.7), in: .circle)
                                .padding(side * 0.03)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
    }

    private static let defaultIcon = CustomIcon.symbol("globe", backgroundHex: "#007C91")!
}
#endif
