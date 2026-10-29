#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import AppFolderKit

/// Headless SwiftUI composition checks. These do not stand in for WidgetKit's
/// archived rendering or an actual VoiceOver interaction on the Home Screen.
@MainActor
@Suite("Folder title SwiftUI composition", .serialized)
struct FolderTitleTextTests {
    private func render(_ content: some View, scheme: ColorScheme = .light) throws -> CGImage {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, scheme)
            .environment(\.displayScale, 3))
        renderer.scale = 3
        return try #require(renderer.cgImage, "The host could not render SwiftUI offscreen")
    }

    private func oldTitle(_ title: String, width: CGFloat, style: FolderStyle,
                          weight: Font.Weight = .regular) -> some View {
        Text(title).font(weight == .regular ? .system(size: 14) : .system(size: 14, weight: weight))
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(style.titleStyle).frame(width: width)
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let address = try #require(context.data)
        return Array(UnsafeBufferPointer(start: address.assumingMemoryBound(to: UInt8.self),
                                         count: image.width * image.height * 4))
    }

    private func visiblePixels(_ image: CGImage) throws -> Int {
        let data = try pixels(image)
        return stride(from: 3, to: data.count, by: 4).filter { data[$0] > 0 }.count
    }

    private func bluePixels(_ image: CGImage) throws -> Int {
        let data = try pixels(image)
        var count = 0
        for index in stride(from: 0, to: data.count, by: 4) {
            let red = Int(data[index]), green = Int(data[index + 1]), blue = Int(data[index + 2])
            if data[index + 3] > 20 && blue > red + 20 && blue > green + 20 { count += 1 }
        }
        return count
    }

    private func sameSize(_ lhs: CGImage, _ rhs: CGImage) {
        #expect(lhs.width == rhs.width)
        #expect(lhs.height == rhs.height)
    }

    @Test("The nil-style branch exactly matches the prior Text layout and pixels")
    func defaultIsUnchanged() throws {
        let styles = [FolderStyle(), FolderStyle(plate: .solid, tint: FolderTint(red: 1, green: 0.8, blue: 0.1))]
        for style in styles {
            for scheme in [ColorScheme.light, .dark] {
                for (text, width) in [("工作 Folder", CGFloat(100)), ("很长的标题 Long shared documents", CGFloat(42))] {
                    for weight in [Font.Weight.regular, .medium] {
                        let old = try render(oldTitle(text, width: width, style: style, weight: weight), scheme: scheme)
                        let new = try render(FolderTitleText(text: text, fontSize: 14, width: width,
                                                             style: style, weight: weight), scheme: scheme)
                        sameSize(old, new)
                        #expect(try pixels(old) == pixels(new))
                        #expect(try visiblePixels(new) > 0)
                    }
                }
            }
        }
        let style = FolderStyle()
        try emit(try render(oldTitle("工作 Folder", width: 100, style: style)), name: "default-original")
        try emit(try render(FolderTitleText(text: "工作 Folder", fontSize: 14, width: 100, style: style)), name: "default-shared")
    }

    @Test("Custom fill and outline overlays are visible without increasing native layout bounds")
    func overlayIsVisible() throws {
        let name = "Folder 工作"
        let plain = try render(oldTitle(name, width: 100, style: FolderStyle()))
        let red = FolderTint(red: 1, green: 0, blue: 0)
        let white = FolderTint(red: 1, green: 1, blue: 1)
        let blue = FolderTint(red: 0, green: 0, blue: 1)
        let colored = try render(FolderTitleText(text: name, fontSize: 14, width: 100,
                                               style: FolderStyle(titleTint: red)))
        let outlined = try render(FolderTitleText(text: name, fontSize: 14, width: 100,
                                                 style: FolderStyle(titleTint: white, titleOutlineTint: blue,
                                                                    titleOutlineWidth: .thick)))
        sameSize(plain, colored)
        sameSize(plain, outlined)
        #expect(try visiblePixels(colored) > 20)
        #expect(try visiblePixels(outlined) > 20)
        let data = try pixels(colored)
        var redPixels = 0
        for index in stride(from: 0, to: data.count, by: 4) {
            let red = Int(data[index]), green = Int(data[index + 1]), blue = Int(data[index + 2])
            if data[index + 3] > 100 && red > green + 30 && red > blue + 30 { redPixels += 1 }
        }
        #expect(redPixels > 20)
        #expect(try pixels(colored) != pixels(outlined))
        try emit(colored, name: "custom-red")
        try emit(outlined, name: "outlined")
    }

    @Test("A tiny height falls back visibly and a truncated title preserves the old cell size")
    func fallbackAndTruncationStayVisible() throws {
        let text = "工作资料 Research and shared documents"
        let style = FolderStyle(titleTint: FolderTint(red: 1, green: 1, blue: 1),
                                titleOutlineTint: FolderTint(red: 0, green: 0, blue: 1))
        let old = try render(oldTitle(text, width: 42, style: style))
        let tiny = try render(FolderTitleText(text: text, fontSize: 14, width: 42,
                                             style: style, availableHeight: 0.5))
        let truncated = try render(FolderTitleText(text: text, fontSize: 14, width: 42,
                                                  style: style, availableHeight: 16))
        sameSize(old, tiny)
        sameSize(old, truncated)
        #expect(try visiblePixels(tiny) > 20)
        #expect(try visiblePixels(truncated) > 20)
        try emit(tiny, name: "small-height-fallback")
        try emit(truncated, name: "truncated")
    }

    @Test("Light to dark to light resolves new fill colors and does not reuse stale cached pixels")
    func schemeChangesInvalidatePixels() throws {
        let style = FolderStyle(titleOutlineTint: FolderTint(red: 0, green: 0, blue: 1))
        let title = FolderTitleText(text: "Theme 工作", fontSize: 14, width: 100, style: style)
        let light = try render(title, scheme: .light)
        let dark = try render(title, scheme: .dark)
        let lightAgain = try render(title, scheme: .light)
        sameSize(light, dark)
        #expect(try visiblePixels(light) > 0)
        #expect(try visiblePixels(dark) > 0)
        #expect(try bluePixels(light) > 20)
        #expect(try bluePixels(dark) > 20)
        #expect(try pixels(light) != pixels(dark))
        #expect(try pixels(light) == pixels(lightAgain))
        try emit(light, name: "light")
        try emit(dark, name: "dark")
        try emit(lightAgain, name: "light-revisited")
    }

    private func emit(_ image: CGImage, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["APPFOLDER_TITLE_VALIDATION_DIRECTORY"] else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("swiftui-" + name + ".png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
#endif
