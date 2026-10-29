#if canImport(SwiftUI)
import SwiftUI

/// Local node artwork. The operation badge stays visible when a custom image
/// replaces the default, so calling and messaging tiles remain distinguishable.
public struct ContactArtwork: View {
    public let target: ContactTarget
    public let variants: CustomIconVariants?
    public var cornerRadius: CGFloat
    public var usesWidgetRendering: Bool
    public var maxPixelSize: Int
    @Environment(\.colorScheme) private var colorScheme

    public init(target: ContactTarget, variants: CustomIconVariants? = nil, cornerRadius: CGFloat = 8,
                usesWidgetRendering: Bool = false, maxPixelSize: Int = 256) {
        self.target = target
        self.variants = variants
        self.cornerRadius = cornerRadius
        self.usesWidgetRendering = usesWidgetRendering
        self.maxPixelSize = maxPixelSize
    }

    public var body: some View {
        let selected = variants?.resolved(isDark: colorScheme == .dark)
        let isFaceTime = target.operation == .faceTimeAudio || target.operation == .faceTimeVideo
        let background = isFaceTime ? "#5856D6" : (target.operation == .message ? "#007C91" : "#00854A")
        let fallback = CustomIcon.symbol(target.operation.systemImage, backgroundHex: background)
            ?? CustomIcon.symbol("phone.fill", backgroundHex: background)!
        CustomIconArtwork(icon: selected ?? fallback, cornerRadius: cornerRadius,
                          usesWidgetRendering: usesWidgetRendering, maxPixelSize: maxPixelSize)
            .overlay(alignment: .bottomTrailing) {
                if selected != nil || isFaceTime {
                    GeometryReader { proxy in
                        let side = min(proxy.size.width, proxy.size.height)
                        if side >= 24 {
                            Group {
                                if isFaceTime { Text(verbatim: "FT") }
                                else { Image(systemName: target.operation.systemImage) }
                            }
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
            .privacySensitive()
            .accessibilityHidden(true)
    }
}
#endif
