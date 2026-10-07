import AppFolderKit
import UIKit

/// Reads pre-downloaded icon data. The widget does not do its own networking:
/// a timeline refresh has a tight budget and artwork is fetched at timeline time.
///
/// Reading is **synchronous**, which is unusual for a file read and deliberate.
/// The alternative — `Image(uiImage:)` arriving a frame late from a `.task` —
/// renders one frame of placeholder and is not obviously wrong until you look at
/// a screenshot. Widget rendering has a budget measured in milliseconds and by the
/// time a widget draws the bytes are already in the page cache, so this is a
/// `memcpy`.
///
/// The cache is a plain class with a lock rather than an actor: an actor's methods
/// are `async`, which is the thing being avoided.
///
/// ## What lives here now
///
/// This was carved out of the folder widget's view file when that widget was
/// removed. It is the part the direct-launch widget actually used — a slot knows
/// only an App Store id, and there is exactly one thing to read for that. The
/// `image(for:)` entry point that took a `FolderTile` went with the folder widget;
/// nothing calls it any more.
final class WidgetIconCache: @unchecked Sendable {
    static let shared = WidgetIconCache()

    private let lock = NSLock()
    private var cache: [String: UIImage] = [:]
    private let directory: URL?

    init() {
        directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier)?
            .appending(path: "Icons", directoryHint: .isDirectory)
    }

    /// Artwork for a direct-launch slot, which knows only the App Store id.
    ///
    /// A slot carries no `FolderTile` — the system holds the tile's identity and
    /// hands the widget nothing but a display name, see ``DirectLaunchIcons``. So
    /// this takes the one thing that names the file on disk.
    ///
    /// Keyed by the id rather than by any per-widget identity, so two widgets and
    /// the timeline provider all land on the same entry — and so a value the
    /// provider already read is a memory hit rather than a second file read when
    /// the view draws it in the same pass.
    func image(appStoreID: Int) -> UIImage? {
        guard let directory else { return nil }
        return load(key: "store:\(appStoreID)", file: directory.appending(path: "\(appStoreID).png"))
    }

    /// Reads one file, through the memory cache, or `nil` if it is not there.
    ///
    /// A miss is not cached. The file may appear between two draws — the timeline
    /// provider writes it — and remembering the absence would leave the slot blank
    /// until the process restarted.
    private func load(key: String, file: URL) -> UIImage? {
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: file), let image = UIImage(data: data) else {
            return nil
        }

        lock.lock()
        cache[key] = image
        lock.unlock()
        return image
    }
}