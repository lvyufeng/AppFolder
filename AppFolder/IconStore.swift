import AppFolderKit
import Foundation
import SwiftUI

/// Fetches and caches real app icons.
///
/// The artwork is the *third-party app's own icon*, which we are allowed to
/// display: the App Store artwork is served from Apple's public iTunes Search
/// API and the app is describing apps the user already has. It is cached on disk
/// because a widget timeline can't afford a network round-trip per tile.
///
/// ## Where the cache lives, and why that matters more than it looks
///
/// The cache is the shared container, because that is the only place the widget
/// can read from — an extension cannot see the app's sandbox. On a build without
/// an App Group (a free Apple ID, say) this falls back to the app's temporary
/// directory, where the widget will never find it.
///
/// That failure is invisible in the worst way: the icons in the *app* are all
/// correct, because the app can read its own temporary directory. Everything
/// looks right until the widget is placed, and then the tiles come out as blank
/// squares with a symbol in them. ``cachedIconCount`` exists so the 排查 screen
/// can say which of the two worlds the icons actually ended up in.
actor IconStore {
    static let shared = IconStore()

    private var memory: [Int: Data] = [:]
    private var inFlight: [Int: Task<Data?, Never>] = [:]
    private let directory: URL

    /// Whether the cache is somewhere the widget can reach.
    private let isShared: Bool

    init() {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier)
        isShared = container != nil
        directory = (container ?? FileManager.default.temporaryDirectory)
            .appending(path: "Icons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// How many icons are on disk.
    ///
    /// Not `async` on purpose: it is read from a `View` body, and it is a
    /// directory listing that takes microseconds.
    nonisolated var cachedIconCount: Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.count
    }

    /// Whether the on-disk cache is in the shared container.
    ///
    /// The count above is only meaningful next to this: a healthy-looking number
    /// in a private temporary directory means a widget that draws nothing.
    nonisolated var isCacheSharedWithWidget: Bool { isShared }

    /// Cached icon bytes for an App Store id, fetching them if needed.
    func icon(forAppStoreID id: Int) async -> Data? {
        if let cached = memory[id] { return cached }

        if let inFlight = inFlight[id] { return await inFlight.value }

        let task = Task<Data?, Never> { [directory] in
            let file = directory.appending(path: "\(id).png")
            if let data = try? Data(contentsOf: file) { return data }
            guard let data = await Self.fetch(appStoreID: id) else { return nil }
            try? data.write(to: file, options: .atomic)
            return data
        }
        inFlight[id] = task
        let data = await task.value
        inFlight[id] = nil
        if let data { memory[id] = data }
        return data
    }

    /// Storefronts to try when resolving artwork, in order. `nil` is the request
    /// with no `country` parameter, which is what the device's own store resolves
    /// to — the right first try for almost everyone.
    private static let lookupCountries: [String?] = [nil, "us", "cn", "hk", "jp", "tw", "uk"]

    private static func fetch(appStoreID id: Int) async -> Data? {
        // The lookup endpoint is region-scoped, and not in a way that reports
        // itself: an app not sold in the storefront the request resolves to comes
        // back as `"results": []` with a 200, indistinguishable from a bad id.
        // Measured — `id=393765873` (爱奇艺) returns 0 results with no `country`
        // and 1 with `country=cn`, while `id=414478124` (微信) returns WeChat
        // without one and 微信 with `cn`.
        //
        // So a device signed into one store cannot fetch artwork for an app bought
        // in another, which is exactly what happens once an account changes
        // region: the app stays installed and its tile goes blank. Which
        // storefront holds a given id cannot be asked for directly, so several are
        // tried and the first answer wins.
        //
        // Concurrently, so the cost is one round trip rather than one per region,
        // and the winner is written to disk by the caller — a success is never
        // looked up again.
        await withTaskGroup(of: Data?.self) { group in
            for country in lookupCountries {
                group.addTask { await fetchArtwork(appStoreID: id, country: country) }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    /// One storefront's attempt at the artwork for `id`.
    private static func fetchArtwork(appStoreID id: Int, country: String?) async -> Data? {
        // `lookup` is the documented public endpoint; no key, no auth.
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [URLQueryItem(name: "id", value: String(id))]
        if let country {
            components?.queryItems?.append(URLQueryItem(name: "country", value: country))
        }
        guard let url = components?.url else { return nil }

        guard let (payload, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard
            let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let results = root["results"] as? [[String: Any]],
            let first = results.first,
            let artwork = first["artworkUrl512"] as? String ?? first["artworkUrl100"] as? String
        else { return nil }

        // The 100px variant is the only one guaranteed to exist; upscale the URL.
        let large = artwork
            .replacingOccurrences(of: "100x100bb", with: "512x512bb")
            .replacingOccurrences(of: "100x100", with: "512x512")
        guard let artworkURL = URL(string: large) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: artworkURL) else { return nil }
        return data
    }

    /// Resolves a tile's icon, preferring a user-chosen one.
    func image(for tile: FolderTile) async -> UIImage? {
        if let name = tile.customIconName,
           let data = try? Data(contentsOf: customIconURL(name)),
           let image = UIImage(data: data) {
            return image
        }
        if let id = tile.appStoreID, let data = await icon(forAppStoreID: id) {
            return UIImage(data: data)
        }
        return nil
    }

    nonisolated func customIconURL(_ name: String) -> URL {
        directory.appending(path: name)
    }

    /// Copies user-picked artwork into the shared container so the widget can
    /// read it too — the widget can't reach the app's own sandbox.
    func storeCustomIcon(_ image: UIImage, name: String) throws {
        guard let data = image.pngData() else { return }
        try data.write(to: customIconURL(name), options: .atomic)
    }
}
