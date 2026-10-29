import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppFolderKit

@Suite("Local dark artwork generation")
struct DarkIconGeneratorTests {
    @Test("Semantic symbols, text and dates retain their content and only darken the background")
    func semantic() throws {
        let candidates = [CustomIcon.symbol("calendar", backgroundHex: "#FFFFFF"),
                          CustomIcon.emoji("AB", backgroundHex: "#FF8800"),
                          CustomIcon.emoji("🙂", backgroundHex: "#00FF00"),
                          CustomIcon.date(backgroundHex: "#0A84FF")]
        for candidate in candidates {
            let source = try #require(candidate)
            let result = try DarkIconGenerator.generate(from: .custom(source))
            #expect(result.source == source)
            #expect(result.treatment == .semantic)
            #expect(result.icon.kind == source.kind && result.icon.value == source.value)
            #expect(result.icon.pngData == nil && result.icon.isValid)
            let tint = try #require(FolderTint(hex: result.icon.backgroundHex))
            #expect(max(tint.red, tint.green, tint.blue) < 0.8)
        }
        let source = try #require(CustomIcon.date(backgroundHex: "#001122"))
        let result = try DarkIconGenerator.generate(from: .custom(source))
        #expect(result.icon == source)
        #expect(CustomIconVariants(dark: result.icon).containsDate)
        #expect(result.icon.thumbnail(maxSide: 32) == result.icon)
    }

    @Test("A white canvas becomes dark while a black mark becomes readable")
    func blackOnWhite() throws {
        let data = try png(side: 64) { x, y in
            (20..<44).contains(x) && (20..<44).contains(y) ? [0, 0, 0, 255] : [255, 255, 255, 255]
        }
        let source = try #require(CustomIcon.photo(pngData: data))
        let result = try DarkIconGenerator.generate(from: .custom(source))
        let pixels = try decoded(result.icon)
        #expect(result.treatment == .graphic)
        #expect(result.source.pngData == data)
        #expect(pixel(pixels, side: 64, x: 0, y: 0)[0] < 70)
        #expect(pixel(pixels, side: 64, x: 32, y: 32)[0] > 220)
        #expect(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
        #expect(result.icon.backgroundHex == "#1C1C1E")
        try capture("black-white", source: source, result: result.icon)
    }

    @Test("Flat red, green and blue marks stay in their original color family")
    func colorMarks() throws {
        let data = try png(side: 96) { x, y in
            guard (24..<72).contains(y) else { return [255, 255, 255, 255] }
            if (12..<36).contains(x) { return [230, 0, 0, 255] }
            if (36..<60).contains(x) { return [0, 180, 0, 255] }
            if (60..<84).contains(x) { return [0, 0, 220, 255] }
            return [255, 255, 255, 255]
        }
        let source = try #require(CustomIcon.photo(pngData: data))
        let result = try DarkIconGenerator.generate(from: .custom(source))
        let pixels = try decoded(result.icon)
        #expect(result.treatment == .graphic)
        let red = pixel(pixels, side: 96, x: 24, y: 48)
        let green = pixel(pixels, side: 96, x: 48, y: 48)
        let blue = pixel(pixels, side: 96, x: 72, y: 48)
        #expect(Int(red[0]) > Int(red[1]) + 25 && red[1] == red[2])
        #expect(Int(green[1]) > Int(green[0]) + 25 && green[0] == green[2])
        #expect(Int(blue[2]) > Int(blue[0]) + 25 && blue[0] == blue[1])
        try capture("color-logo", source: source, result: result.icon)
    }

    @Test("Bright yellow, cyan and magenta marks retain contrast against the generated dark neutral canvas")
    func brightColorContrast() throws {
        let data = try png(side: 96) { x, y in
            guard (24..<72).contains(y) else { return [255, 255, 255, 255] }
            if (12..<36).contains(x) { return [255, 255, 0, 255] }
            if (36..<60).contains(x) { return [0, 255, 255, 255] }
            if (60..<84).contains(x) { return [255, 0, 255, 255] }
            return [255, 255, 255, 255]
        }
        let source = try #require(CustomIcon.photo(pngData: data))
        let result = try DarkIconGenerator.generate(from: .custom(source))
        let pixels = try decoded(result.icon)
        #expect(result.treatment == .graphic)
        let canvas = relativeLuminance(pixel(pixels, side: 96, x: 0, y: 0))
        let yellow = pixel(pixels, side: 96, x: 24, y: 48)
        let cyan = pixel(pixels, side: 96, x: 48, y: 48)
        let magenta = pixel(pixels, side: 96, x: 72, y: 48)
        for mark in [yellow, cyan, magenta] {
            #expect((relativeLuminance(mark) + 0.05) / (canvas + 0.05) >= 3)
        }
        #expect(yellow[0] == yellow[1] && Int(yellow[0]) > Int(yellow[2]) + 40)
        #expect(cyan[1] == cyan[2] && Int(cyan[1]) > Int(cyan[0]) + 40)
        #expect(magenta[0] == magenta[2] && Int(magenta[0]) > Int(magenta[1]) + 40)
        try capture("bright-color-logo", source: source, result: result.icon)
    }

    @Test("A strongly colored bright canvas keeps conservative tonal contrast instead of reversing its black mark")
    func coloredCanvas() throws {
        let data = try png(side: 64) { x, y in
            (20..<44).contains(x) && (20..<44).contains(y) ? [0, 0, 0, 255] : [255, 255, 0, 255]
        }
        let source = try #require(CustomIcon.photo(pngData: data))
        let result = try DarkIconGenerator.generate(from: .custom(source))
        let pixels = try decoded(result.icon)
        #expect(result.treatment == .photograph)
        let canvas = relativeLuminance(pixel(pixels, side: 64, x: 0, y: 0))
        let mark = relativeLuminance(pixel(pixels, side: 64, x: 32, y: 32))
        #expect((canvas + 0.05) / (mark + 0.05) >= 3)
        try capture("colored-canvas", source: source, result: result.icon)
    }

    @Test("A photographic gradient keeps tonal order and midtones instead of becoming a negative")
    func photographTones() throws {
        let data = try png(side: 256) { x, _ in [UInt8(x), UInt8(x), UInt8(x), 255] }
        let source = try #require(CustomIcon.photo(pngData: data))
        let result = try DarkIconGenerator.generate(from: .custom(source))
        let pixels = try decoded(result.icon)
        let row = (0..<256).map { pixel(pixels, side: 256, x: $0, y: 128)[0] }
        #expect(result.treatment == .photograph)
        #expect(zip(row, row.dropFirst()).allSatisfy { $0 <= $1 })
        #expect((10...60).contains(row[0]))
        #expect((120...140).contains(row[128]))
        #expect((200..<255).contains(row[255]))
        #expect(row[200] < 200)
        try capture("photo-tones", source: source, result: result.icon)
    }

    @Test("Complex color content remains a bounded reproducible photo treatment")
    func complexPhoto() throws {
        let data = try png(side: 256) { x, y in
            [UInt8((x * 17 + y * 31) & 255), UInt8((x * 51 + y * 7) & 255), UInt8((x * y * 3) & 255), 255]
        }
        let source = try #require(CustomIcon.photo(pngData: data))
        let result = try DarkIconGenerator.generate(from: .custom(source))
        #expect(result.treatment == .photograph)
        #expect(result.icon.isValid)
        #expect(try #require(result.icon.pngData).count <= CustomIcon.maximumPhotoBytes)
        #expect(result.icon.decodedPhoto()?.width == 256)
        #expect(try DarkIconGenerator.generate(from: .custom(source)).icon == result.icon)
        try capture("complex-photo", source: source, result: result.icon)
    }

    @Test("Transparent and semitransparent dark marks retain every alpha byte and become visible")
    func transparency() throws {
        let alphas: [UInt8] = [0, 1, 32, 64, 128, 192, 255, 0]
        let data = try png(side: 64) { x, _ in [0, 0, 0, alphas[x / 8]] }
        let source = try #require(CustomIcon.photo(pngData: data))
        let original = try decoded(source)
        let result = try DarkIconGenerator.generate(from: .custom(source))
        let pixels = try decoded(result.icon)
        #expect(result.treatment == .graphic)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[offset + 3]
            #expect(alpha == original[offset + 3])
            #expect(pixels[offset] <= alpha && pixels[offset + 1] <= alpha && pixels[offset + 2] <= alpha)
            if alpha == 0 { #expect(pixels[offset] == 0 && pixels[offset + 1] == 0 && pixels[offset + 2] == 0) }
            if alpha >= 32 { #expect(Double(pixels[offset]) / Double(alpha) > 0.70) }
        }
        try capture("transparent-mark", source: source, result: result.icon)
    }

    @Test("Bright transparent frames and U-shaped marks touching the edges stay bright on the dark plate")
    func brightTransparentMarks() throws {
        let colors: [[UInt8]] = [[255, 255, 255, 255], [255, 255, 0, 255], [0, 255, 255, 255]]
        for (index, color) in colors.enumerated() {
            let data = try png(side: 64) { x, y in
                let visible = x < 8 || x >= 56 || y >= 56 || (index == 0 && y < 8)
                return visible ? color : [0, 0, 0, 0]
            }
            let source = try #require(CustomIcon.photo(pngData: data))
            let result = try DarkIconGenerator.generate(from: .custom(source))
            let pixels = try decoded(result.icon), original = try decoded(source)
            #expect(result.treatment == .graphic)
            #expect(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == original[$0] })
            let foreground = pixel(pixels, side: 64, x: 2, y: 32)
            #expect(relativeLuminance(foreground) >= 0.60)
            #expect((relativeLuminance(foreground) + 0.05) / (relativeLuminance([28, 28, 30, 255]) + 0.05) >= 3)
            #expect(pixel(pixels, side: 64, x: 32, y: 32)[3] == 0)
            try capture("transparent-bright-mark-\(index)", source: source, result: result.icon)
        }
    }

    @Test("Transparent rounded corners do not turn a white panel and its black mark into white-on-white")
    func transparentCanvas() throws {
        for inset in [false, true] {
            let data = try png(side: 64) { x, y in
                let outside: Bool
                if inset { outside = x < 8 || x >= 56 || y < 8 || y >= 56 }
                else { outside = (x < 8 || x >= 56) && (y < 8 || y >= 56) }
                if outside { return [0, 0, 0, 0] }
                return (22..<42).contains(x) && (22..<42).contains(y) ? [0, 0, 0, 255] : [255, 255, 255, 255]
            }
            let source = try #require(CustomIcon.photo(pngData: data))
            let result = try DarkIconGenerator.generate(from: .custom(source))
            let original = try decoded(source), pixels = try decoded(result.icon)
            #expect(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == original[$0] })
            let panel = Int(pixel(pixels, side: 64, x: 12, y: 12)[0])
            let mark = Int(pixel(pixels, side: 64, x: 32, y: 32)[0])
            #expect(abs(panel - mark) > 150)
            #expect(result.treatment == (inset ? .photograph : .graphic))
            try capture(inset ? "transparent-inset-panel" : "transparent-rounded-logo", source: source, result: result.icon)
        }
    }

    @Test("Source PNG bytes remain intact while generated and cached previews omit source metadata")
    func metadataAndCacheSource() throws {
        let marker = "fixture-author-private-marker"
        let original = try png(side: 64) { x, _ in x < 32 ? [0, 0, 0, 255] : [255, 255, 255, 255] }
        let annotated = addingText(marker, to: original)
        let source = try #require(CustomIcon.photo(pngData: annotated))
        #expect(annotated.range(of: Data(marker.utf8)) != nil)
        let result = try DarkIconGenerator.generate(from: .custom(source))
        #expect(result.source == source && result.source.pngData == annotated)
        #expect(result.icon.pngData?.range(of: Data(marker.utf8)) == nil)
        let cached = try DarkIconGenerator.generate(from: .cachedArtwork(annotated))
        #expect(cached.source.kind == .photo && cached.source.isValid)
        #expect(cached.source.pngData?.range(of: Data(marker.utf8)) == nil)
        #expect(cached.icon.pngData?.range(of: Data(marker.utf8)) == nil)
        #expect(try decoded(cached.source) == decoded(source))
    }

    @Test("Empty, corrupt, truncated, nonsquare, invisible and over-budget sources fail without recovery")
    func invalidAndLimits() throws {
        let normal = try png(side: 64) { _, _ in [255, 255, 255, 255] }
        let rectangle = try png(width: 64, height: 32) { _, _ in [255, 0, 0, 255] }
        let nearSquare = try png(width: 512, height: 511) { _, _ in [255, 0, 0, 255] }
        let tooWide = try png(width: 8_193, height: 1) { _, _ in [255, 0, 0, 255] }
        for data in [Data(), Data("not an image".utf8), Data(normal.dropLast()), rectangle, nearSquare, tooWide,
                     Data(repeating: 0, count: DirectLaunchIcons.artworkByteLimit + 1)] {
            #expect(throws: DarkIconGenerationError.invalidImage) { try DarkIconGenerator.generate(from: .cachedArtwork(data)) }
        }
        let emptyData = try png(side: 32) { _, _ in [0, 0, 0, 0] }
        let empty = try #require(CustomIcon.photo(pngData: emptyData))
        #expect(throws: DarkIconGenerationError.invalidImage) { try DarkIconGenerator.generate(from: .custom(empty)) }
        #expect(throws: DarkIconGenerationError.invalidImage) { try DarkIconGenerator.generate(from: .cachedArtwork(emptyData)) }
        let larger = try png(side: 512) { x, y in ((x / 64 + y / 64) % 2 == 0) ? [0, 0, 0, 255] : [255, 255, 255, 255] }
        let bounded = try DarkIconGenerator.generate(from: .cachedArtwork(larger))
        #expect(bounded.source.decodedPhoto()?.width == 256)
        #expect(bounded.icon.decodedPhoto()?.width == 256)
        #expect(try #require(bounded.source.pngData).count <= CustomIcon.maximumPhotoBytes)
    }

    @Test("Cancellation remains CancellationError rather than an image failure")
    func cancellation() async throws {
        let source = try #require(CustomIcon.date())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DarkIconGenerator.generate(from: .custom(source))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Generated date and photo variants retain source data, asset identity and current backup restore behavior")
    func backupRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DarkIcon-Backup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = DiskIconBackupStorage(root: root.appendingPathComponent("source"))
        let data = try png(side: 64) { x, y in (16..<48).contains(x) && (16..<48).contains(y) ? [0, 0, 0, 255] : [255, 255, 255, 255] }
        let original = try #require(CustomIcon.photo(pngData: data))
        let dark = try DarkIconGenerator.generate(from: .custom(original)).icon
        let date = try #require(CustomIcon.date(backgroundHex: "#FF8800"))
        let darkDate = try DarkIconGenerator.generate(from: .custom(date)).icon
        let logoSaved = source.setIcon(CustomIconVariants(standard: original, dark: dark), name: "Logo")
        let dateSaved = source.setIcon(CustomIconVariants(standard: date, dark: darkDate), name: "Calendar")
        #expect(logoSaved && dateSaved)
        let assetID = try #require(FolderCoverAssetRepository.id(for: dark))
        #expect(source.saveCoverAsset(dark, id: assetID))
        let group = SavedGroup(name: "Generated", items: [.folder(name: "Tools", children: [
            .action(name: "Logo"), .action(name: "Calendar"),
            .website(name: "Site", url: "https://example.com", icon: .init(dark: assetID))
        ], folderCover: .init(dark: assetID))])
        #expect(source.saveGroup(group))
        let exporter = LibraryBackupEngine(storage: source)
        for (index, encoded) in [try exporter.exportData(), try exporter.exportData(groupID: group.id)].enumerated() {
            let header = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(header["version"] as? Int == 16)
            let document = try LibraryBackup.decode(encoded)
            let target = DiskIconBackupStorage(root: root.appendingPathComponent("target-\(index)"))
            let importer = LibraryBackupEngine(storage: target)
            let restored = importer.apply(importer.prepareImport(document))
            #expect(restored.status == .completed)
            #expect(target.icon(name: "Logo") == .init(standard: original, dark: dark))
            #expect(target.icon(name: "Logo")?.standard?.pngData == data)
            #expect(target.icon(name: "Calendar")?.containsDate == true)
            #expect(target.icon(name: "Calendar")?.dark?.kind == .date)
            #expect(target.coverAsset(id: assetID) == dark)
            #expect(restored.groups.first?.coverAssetIDs == [assetID])
        }
    }

    private func png(side: Int, pixel: (Int, Int) -> [UInt8]) throws -> Data { try png(width: side, height: side, pixel: pixel) }
    private func png(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let value = pixel(x, y), offset = (y * width + x) * 4
            for channel in 0..<3 { bytes[offset + channel] = UInt8((Int(value[channel]) * Int(value[3]) + 127) / 255) }
            bytes[offset + 3] = value[3]
        } }
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: width * 4, space: space,
                                        bitmapInfo: .init(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return try encoded(image)
    }
    private func encoded(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
    private func decoded(_ icon: CustomIcon) throws -> [UInt8] {
        let image = try #require(icon.decodedPhoto())
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    private func pixel(_ bytes: [UInt8], side: Int, x: Int, y: Int) -> [UInt8] { Array(bytes[((y * side + x) * 4)..<((y * side + x) * 4 + 4)]) }

    private func relativeLuminance(_ rgba: [UInt8]) -> Double {
        let channels = rgba.prefix(3).map { Double($0) / 255 }.map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private func addingText(_ text: String, to png: Data) -> Data {
        let payload = Data("Comment\0\(text)".utf8)
        let type = Data("tEXt".utf8)
        var crc = UInt32.max
        for byte in type + payload {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
        }
        func word(_ value: UInt32) -> Data { Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]) }
        return Data(png.dropLast(12)) + word(UInt32(payload.count)) + type + payload + word(crc ^ UInt32.max) + png.suffix(12)
    }

    /// Opt-in synthetic review artifacts; no personal photographs or network data.
    private func capture(_ name: String, source: CustomIcon, result: CustomIcon) throws {
        guard let path = ProcessInfo.processInfo.environment["APPFOLDER_DARK_FIXTURES_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.pngData?.write(to: directory.appendingPathComponent(name + "-source.png"))
        try result.pngData?.write(to: directory.appendingPathComponent(name + "-result.png"))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 528, height: 256, bitsPerComponent: 8, bytesPerRow: 528 * 4,
                                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.95, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        context.setFillColor(CGColor(gray: 0.4, alpha: 1)); context.fill(CGRect(x: 256, y: 0, width: 16, height: 256))
        context.setFillColor(CGColor(gray: 0.11, alpha: 1)); context.fill(CGRect(x: 272, y: 0, width: 256, height: 256))
        context.interpolationQuality = .none
        context.draw(try #require(source.decodedPhoto()), in: CGRect(x: 0, y: 0, width: 256, height: 256))
        context.draw(try #require(result.decodedPhoto()), in: CGRect(x: 272, y: 0, width: 256, height: 256))
        try encoded(#require(context.makeImage())).write(to: directory.appendingPathComponent(name + "-comparison.png"))
    }
}
