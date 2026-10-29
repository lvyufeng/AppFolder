/// Bounds each retained tile image as a grid grows. Full-resolution sources
/// remain in the shared store; timeline entries retain only display thumbnails.
public enum WidgetArtworkResolution {
    public static func maximumPixelSize(cellCount: Int) -> Int {
        if cellCount > 40 { return 96 }
        if cellCount > 16 { return 160 }
        return 256
    }
}
