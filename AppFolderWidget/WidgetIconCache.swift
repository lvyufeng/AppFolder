import AppFolderKit
import UIKit

/// UIKit presentation of the bounded pixel cache shared with the package tests.
/// No networking or disk writes occur while a widget view renders.
final class WidgetIconCache: @unchecked Sendable {
    static let shared = WidgetIconCache()

    private let artwork: WidgetArtworkCache

    init() {
        let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier)?
            .appending(path: "Icons", directoryHint: .isDirectory)
        artwork = WidgetArtworkCache(directory: directory)
    }

    func image(appStoreID: Int, country: String? = nil, maxPixelSize: Int = 256) -> UIImage? {
        guard let pixels = artwork.image(appStoreID: appStoreID, country: country, maxPixelSize: maxPixelSize) else { return nil }
        return UIImage(cgImage: pixels)
    }
}
