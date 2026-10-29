import Foundation
import Testing
@testable import AppFolderKit

@Suite("Fine appearance backup version sixteen")
struct LibraryBackupFineAppearanceTests {
    private static let fineKeys: Set<String> = ["spacing", "margin", "titleColorHex", "titleOutlineHex", "titleOutlineWidth"]

    private enum Location: CaseIterable {
        case root, firstFolder, deepestFolder, preset
    }

    @Test("Full backups preserve preset settings and shares preserve only embedded root and child settings")
    func fullAndScopedRoundTrip() throws {
        let rootStyle = fineAppearance(spacing: 0, margin: 40, width: .thin)
        let childStyle = fineAppearance(spacing: 24, margin: 0, width: .medium)
        let presetStyle = fineAppearance(spacing: 8, margin: 12, width: .thick)
        let record = AppearancePreset(name: "Detailed", appearance: presetStyle)
        let source = BackupTestStorage()
        let original = makeGroup(root: rootStyle, child: childStyle)
        source.groups[original.id] = original
        source.strictExport = { .init(groups: [original], appearancePresets: [record]) }
        let exporter = LibraryBackupEngine(storage: source)
        let fullData = try exporter.exportData()
        let fullJSON = try object(fullData)
        #expect(fullJSON["version"] as? Int == 16)
        #expect(Set(fullJSON.keys) == ["format", "version", "createdAt", "groups", "icons", "mappings", "coverAssets", "actionLibrary", "appearancePresets"])
        let full = try LibraryBackup.decode(fullData)
        #expect(full.groups == [original] && full.appearancePresets == [record])
        #expect(full.counts.appearancePresets == 1 && full.counts.groups == 1)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fine-backup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fullDestination = PresetBackupStorage(directory: root)
        let fullImporter = LibraryBackupEngine(storage: fullDestination)
        let fullResult = fullImporter.apply(fullImporter.prepareImport(full))
        #expect(fullResult.status == .completed && fullResult.imported.appearancePresets == 1)
        #expect(try fullDestination.repository.exportRecords() == [record])
        #expect(fullResult.groups.first?.appearance == rootStyle)
        #expect(deepestFolder(in: try #require(fullResult.groups.first)).folderAppearance == childStyle)

        // A broken unrelated library still cannot block a single-group share.
        source.strictExport = { throw LibraryBackupError.exportFailed }
        let shared = try LibraryBackup.decode(exporter.exportData(groupID: original.id))
        #expect(shared.groups == [original] && shared.appearancePresets.isEmpty)
        let destination = BackupTestStorage()
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(shared))
        #expect(result.status == .completed && result.imported.appearancePresets == 0)
        let copy = try #require(result.groups.first)
        #expect(copy.id != original.id && copy.appearance == rootStyle)
        #expect(deepestFolder(in: copy).folderAppearance == childStyle)
        #expect(deepestFolder(in: copy).id != deepestFolder(in: original).id)
        #expect(source.groups[original.id] == original)
    }

    @Test("Versions one through fifteen read old values without adding fine-appearance fields", arguments: Array(1...15))
    func legacyRoundTrip(version: Int) throws {
        let original = try baseEnvelope(version: version)
        let document = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: original))
        let reencoded = try object(LibraryBackup.encode(document))
        #expect(reencoded["version"] as? Int == 16)
        let oldGroups = try #require(original["groups"] as? [[String: Any]])
        let newGroups = try #require(reencoded["groups"] as? [[String: Any]])
        #expect(try canonical(oldGroups) == canonical(newGroups))
        if version >= 15 {
            #expect(try canonical(try #require(original["appearancePresets"])) == canonical(try #require(reencoded["appearancePresets"])))
        } else {
            #expect(document.appearancePresets.isEmpty)
        }
        for group in document.groups {
            let decodedAgain = try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group))
            #expect(decodedAgain.revision == group.revision)
        }
        for location in Location.allCases where location != .preset || version >= 15 {
            if let appearance = try appearanceObject(in: reencoded, at: location) {
                #expect(Self.fineKeys.isDisjoint(with: appearance.keys))
            }
        }
    }

    @Test("Every pre-v16 envelope rejects each fine field at root, both child depths and preset, including null and defaults", arguments: Array(1...15))
    func rejectsDowngrade(version: Int) throws {
        let baseline = try baseEnvelope(version: version)
        _ = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: baseline))
        let values: [String: [Any]] = [
            "spacing": [0, 24, NSNull(), "invalid"],
            "margin": [0, 40, NSNull(), "invalid"],
            "titleColorHex": ["#123456", "#000000", NSNull(), 12],
            "titleOutlineHex": ["#ABCDEF", "#000000", NSNull(), 12],
            "titleOutlineWidth": ["thin", "thick", NSNull(), 12]
        ]
        for location in Location.allCases {
            for (key, candidates) in values {
                for value in candidates {
                    let mutated = try injecting([key: value], into: baseline, at: location)
                    #expect(throws: LibraryBackupError.invalidContents) {
                        try LibraryBackup.decode(JSONSerialization.data(withJSONObject: mutated))
                    }
                }
            }
        }
    }

    @Test("Version sixteen validates each new field consistently at all appearance locations")
    func invalidCurrentValues() throws {
        let baseline = try baseEnvelope(version: 16)
        let invalid: [String: [Any]] = [
            "spacing": [-1, 25, 1.5, "2", true],
            "margin": [-1, 41, 1.5, "2", true],
            "titleColorHex": ["", "#GGGGGG", "transparent", 12, true],
            "titleOutlineHex": ["", "#GGGGGG", "transparent", 12, true],
            "titleOutlineWidth": [NSNull(), "", "THIN", 1, true]
        ]
        for location in Location.allCases {
            for (key, candidates) in invalid {
                for value in candidates {
                    let mutated = try injecting([key: value], into: baseline, at: location)
                    #expect(throws: LibraryBackupError.invalidContents) {
                        try LibraryBackup.decode(JSONSerialization.data(withJSONObject: mutated))
                    }
                }
            }
        }
    }

    @Test("Current optional nulls and explicit thin remain absent when reencoded")
    func currentNullAndDefaultSemantics() throws {
        let fields: [String: Any] = ["spacing": NSNull(), "margin": NSNull(), "titleColorHex": NSNull(),
                                     "titleOutlineHex": NSNull(), "titleOutlineWidth": "thin"]
        for location in Location.allCases {
            let json = try injecting(fields, into: baseEnvelope(version: 16), at: location)
            let document = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json))
            let encoded = try object(LibraryBackup.encode(document))
            let appearance = try #require(try appearanceObject(in: encoded, at: location))
            #expect(Self.fineKeys.isDisjoint(with: appearance.keys))
        }
    }

    @Test("Explicit zero and boundary spacing survive, colors normalize, and outline thickness is preserved")
    func currentBoundariesAndNormalization() throws {
        for location in Location.allCases {
            for (spacing, margin, width) in [(0, 0, "thin"), (24, 40, "medium"), (8, 12, "thick")] {
                let fields: [String: Any] = ["spacing": spacing, "margin": margin, "titleColorHex": "#a1b2c3",
                                             "titleOutlineHex": "#d4e5f6", "titleOutlineWidth": width]
                let json = try injecting(fields, into: baseEnvelope(version: 16), at: location)
                let document = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json))
                let encoded = try object(LibraryBackup.encode(document))
                let appearance = try #require(try appearanceObject(in: encoded, at: location))
                #expect(appearance["spacing"] as? Int == spacing && appearance["margin"] as? Int == margin)
                #expect(appearance["titleColorHex"] as? String == "#A1B2C3")
                #expect(appearance["titleOutlineHex"] as? String == "#D4E5F6")
                if width == "thin" { #expect(appearance["titleOutlineWidth"] == nil) }
                else { #expect(appearance["titleOutlineWidth"] as? String == width) }
            }
        }
    }

    @Test("Older density, back button, folder presentation and browser boundaries remain strict")
    func earlierBoundariesRemainStrict() throws {
        for version in 1...6 {
            let json = try injecting(["density": NSNull()], into: baseEnvelope(version: version), at: .root)
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json)) }
        }
        for version in 1...7 {
            let json = try injecting(["backButtonStyle": "chevronUp"], into: baseEnvelope(version: version), at: .root)
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json)) }
            let child = try injecting([:], into: baseEnvelope(version: version), at: .firstFolder)
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: child)) }
        }
        var browser = try baseEnvelope(version: 13)
        var groups = try #require(browser["groups"] as? [[String: Any]])
        groups[0]["items"] = [["id": UUID().uuidString, "kind": "website", "name": "Web", "children": [],
                                "websiteURL": "https://example.org", "websiteBrowser": "appDefault"]]
        browser["groups"] = groups
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: browser)) }
    }

    private func fineAppearance(spacing: Int, margin: Int, width: SavedGroupTitleOutlineWidth) -> SavedGroupAppearance {
        var value = SavedGroupAppearance(grid: .four, showsTitles: true, plate: .automatic, tintHex: "#778899")
        value.spacing = spacing
        value.margin = margin
        value.titleColorHex = "#123456"
        value.titleOutlineHex = "#FEDCBA"
        value.titleOutlineWidth = width
        return value
    }

    private func makeGroup(root: SavedGroupAppearance?, child: SavedGroupAppearance?) -> SavedGroup {
        var node = GroupItem.folder(name: "Deep", children: [.action(name: "Action")], folderAppearance: child)
        for level in 1..<SavedGroup.maximumDepth { node = .folder(name: "Folder \(level)", children: [node]) }
        return .init(name: "Appearance", items: [node], updatedAt: Date(timeIntervalSince1970: 1_234), appearance: root)
    }

    private func deepestFolder(in group: SavedGroup) -> GroupItem {
        var node = group.items[0]
        while node.children.first?.kind == .folder { node = node.children[0] }
        return node
    }

    private func baseEnvelope(version: Int) throws -> [String: Any] {
        let group = makeGroup(root: version >= 3 ? .default : nil, child: version >= 8 ? .default : nil)
        let presets: [AppearancePreset] = version >= 15 ? [.init(name: "Legacy", appearance: .default)] : []
        let document = LibraryBackup.Document(createdAt: Date(timeIntervalSince1970: 1_234), groups: [group],
                                              icons: [], mappings: [], appearancePresets: presets)
        var json = try object(LibraryBackup.encode(document))
        json["version"] = version
        if version < 15 { json.removeValue(forKey: "appearancePresets") }
        if version < 12 { json.removeValue(forKey: "actionLibrary") }
        if version < 5 { json.removeValue(forKey: "coverAssets") }
        return json
    }

    private func injecting(_ fields: [String: Any], into original: [String: Any], at location: Location) throws -> [String: Any] {
        var result = original
        let fallback = try object(JSONEncoder().encode(SavedGroupAppearance.default))
        func replacing(_ current: Any?) -> [String: Any] {
            var appearance = current as? [String: Any] ?? fallback
            appearance.merge(fields) { _, incoming in incoming }
            return appearance
        }
        if location == .preset {
            var presets = result["appearancePresets"] as? [[String: Any]] ?? [["name": "Injected", "appearance": fallback]]
            presets[0]["appearance"] = replacing(presets[0]["appearance"])
            result["appearancePresets"] = presets
            return result
        }
        var groups = try #require(result["groups"] as? [[String: Any]])
        if location == .root { groups[0]["appearance"] = replacing(groups[0]["appearance"]) }
        else {
            func nested(_ nodes: [[String: Any]], remaining: Int) throws -> [[String: Any]] {
                var nodes = nodes
                if remaining == 1 { nodes[0]["folderAppearance"] = replacing(nodes[0]["folderAppearance"]) }
                else {
                    let children = try #require(nodes[0]["children"] as? [[String: Any]])
                    nodes[0]["children"] = try nested(children, remaining: remaining - 1)
                }
                return nodes
            }
            let items = try #require(groups[0]["items"] as? [[String: Any]])
            groups[0]["items"] = try nested(items, remaining: location == .firstFolder ? 1 : SavedGroup.maximumDepth)
        }
        result["groups"] = groups
        return result
    }

    private func appearanceObject(in json: [String: Any], at location: Location) throws -> [String: Any]? {
        if location == .preset {
            return (json["appearancePresets"] as? [[String: Any]])?.first?["appearance"] as? [String: Any]
        }
        let groups = try #require(json["groups"] as? [[String: Any]])
        if location == .root { return groups[0]["appearance"] as? [String: Any] }
        var nodes = try #require(groups[0]["items"] as? [[String: Any]])
        let depth = location == .firstFolder ? 1 : SavedGroup.maximumDepth
        for _ in 1..<depth { nodes = try #require(nodes[0]["children"] as? [[String: Any]]) }
        return nodes[0]["folderAppearance"] as? [String: Any]
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func canonical(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
