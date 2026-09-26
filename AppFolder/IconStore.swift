import AppFolderKit
import Foundation
import SwiftUI

/// Fetches and caches real app icons.
///
/// The artwork is the *third-party app's own icon*, which we are allowed to
/// display: the App Store artwork is served from Apple's public iTunes Search
/// API and the app is describing apps the user already has. It is cached on disk
/// because a widget timeline can't afford a network round-trip per tile.
actor IconStore {
    static let shared = IconStore()

    private var memory: [Int: Data] = [:]
    private var inFlight: [Int: Task<Data?, Never>] = [:]
    private let directory: URL

    init() {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier)
            ?? FileManager.default.temporaryDirectory
        directory = base.appending(path: "Icons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

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

    private static func fetch(appStoreID id: Int) async -> Data? {
        // `lookup` is the documented public endpoint; no key, no auth.
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)") else { return nil }
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
