import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppFolderKit

@Suite("Library backup folder presentation version")
struct LibraryBackupFolderPresentationTests {
    @Test("Full and single-group current backups preserve overrides and miniatures with independent imported IDs")
    func roundTrip() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        let nested = GroupItem.folder(name: "Nested", children: [.action(name: "Camera", displayName: "Shot"),
                                                                 .website(name: "Site", url: "https://example.com")],
                                      folderAppearance: .init(grid: .four, iconSize: .large, plate: .gradient,
                                                              tintHex: "#123456", density: .spacious, backButtonStyle: .folder),
                                      folderPreviewGrid: .nine)
        source.groups[id]?.items = [.folder(name: "Inherited", children: [nested])]
        source.groups[id]?.appearance = .init(density: .dense, backButtonStyle: .turnUpLeft)
        let original = try #require(source.groups[id])
        let exporter = LibraryBackupEngine(storage: source)
        for data in [try exporter.exportData(), try exporter.exportData(groupID: id)] {
            let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(envelope["version"] as? Int == 16)
            let document = try LibraryBackup.decode(data)
            #expect(document.groups == [original])
            let destination = BackupTestStorage()
            let importer = LibraryBackupEngine(storage: destination)
            #expect(importer.apply(importer.prepareImport(document)).status == .completed)
            let imported = try #require(destination.groups.values.first)
            let copiedNested = try #require(imported.items.first?.children.first)
            #expect(imported.id != original.id && imported.items[0].id != original.items[0].id)
            #expect(copiedNested.id != nested.id && copiedNested.children[0].id != nested.children[0].id)
            #expect(imported.appearance == original.appearance)
            #expect(copiedNested.folderAppearance == nested.folderAppearance && copiedNested.folderPreviewGrid == .nine)
            #expect(copiedNested.children[0].displayName == "Shot" && copiedNested.children[1].websiteURL == "https://example.com")
            #expect(imported.allActionNames == original.allActionNames && source.groups[id] == original)
        }
    }

    @Test("All older versions remain readable when new fields are absent", arguments: Array(1...7))
    func legacy(version: Int) throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.items = [.folder(name: "Legacy", children: [.action(name: "Camera")])]
        if version >= 3 { source.groups[id]?.appearance = .default }
        if version == 7 { source.groups[id]?.appearance?.density = .dense }
        let original = try #require(source.groups[id])
        var envelope = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        envelope["version"] = version
        envelope.removeValue(forKey: "appearancePresets")
        envelope.removeValue(forKey: "actionLibrary")
        if version < 5 { envelope.removeValue(forKey: "coverAssets") }
        let document = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope))
        #expect(document.groups.first == original)
        #expect(document.groups.first?.resolvedAppearance.backButtonStyle == .chevronUp)
        #expect(document.groups.first?.items.first?.folderPreviewGrid == nil)
        if version == 7 { #expect(document.groups.first?.resolvedAppearance.density == .dense) }
    }

    @Test("Pre-v8 envelopes reject explicit folder fields at every depth, even default or null", arguments: Array(1...7))
    func rejectsDowngrade(version: Int) throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.appearance = .default
        source.groups[id]?.items = [.folder(name: "Outer", children: [.folder(name: "Inner")])]
        var original = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        original["version"] = version
        original.removeValue(forKey: "appearancePresets")
        original.removeValue(forKey: "actionLibrary")
        if version < 5 { original.removeValue(forKey: "coverAssets") }
        let appearance = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGroupAppearance()))
        for key in ["folderAppearance", "folderPreviewGrid"] {
            let values: [Any] = key == "folderAppearance" ? [appearance, NSNull()] : ["four", "nine", NSNull()]
            for depth in [0, 1] {
                for value in values {
                    var envelope = original
                    var groups = try #require(envelope["groups"] as? [[String: Any]])
                    var items = try #require(groups[0]["items"] as? [[String: Any]])
                    if depth == 0 { items[0][key] = value }
                    else {
                        var children = try #require(items[0]["children"] as? [[String: Any]])
                        children[0][key] = value
                        items[0]["children"] = children
                    }
                    groups[0]["items"] = items
                    envelope["groups"] = groups
                    let data = try JSONSerialization.data(withJSONObject: envelope)
                    #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(data) }
                }
            }
        }
        let invalidBackFields: [Any] = ["chevronUp", "folder", NSNull()]
        for value in invalidBackFields {
            var envelope = original
            var groups = try #require(envelope["groups"] as? [[String: Any]])
            var rootAppearance = try #require(groups[0]["appearance"] as? [String: Any])
            rootAppearance["backButtonStyle"] = value
            groups[0]["appearance"] = rootAppearance
            envelope["groups"] = groups
            let data = try JSONSerialization.data(withJSONObject: envelope)
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(data) }
        }
    }

    @Test("Version eight rejects malformed new enum values and non-folder presentation fields")
    func malformed() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.items = [.folder(name: "Folder", folderAppearance: .default)]
        let original = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        for key in ["folderPreviewGrid", "backButtonStyle"] {
            let values: [Any] = key == "folderPreviewGrid" ? ["six", 9] : ["unknown", NSNull(), 2]
            for value in values {
                var envelope = original
                var groups = try #require(envelope["groups"] as? [[String: Any]])
                var items = try #require(groups[0]["items"] as? [[String: Any]])
                if key == "folderPreviewGrid" { items[0][key] = value }
                else {
                    var appearance = try #require(items[0]["folderAppearance"] as? [String: Any])
                    appearance[key] = value
                    items[0]["folderAppearance"] = appearance
                }
                groups[0]["items"] = items
                envelope["groups"] = groups
                let data = try JSONSerialization.data(withJSONObject: envelope)
                #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(data) }
            }
        }
        var envelope = original
        var groups = try #require(envelope["groups"] as? [[String: Any]])
        var items = try #require(groups[0]["items"] as? [[String: Any]])
        items[0]["kind"] = "action"
        groups[0]["items"] = items
        envelope["groups"] = groups
        #expect(throws: LibraryBackupError.invalidContents) {
            try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope))
        }
    }
}

@Suite("Library backup density version")
struct LibraryBackupDensityTests {
    @Test("Current exports and independent imported copies retain every density", arguments: FolderDensity.allCases)
    func roundTrip(density: FolderDensity) throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.appearance = .init(grid: .four, showsTitles: false, iconSize: .large,
                                              plate: .gradient, tintHex: "#AA00FF", density: density)
        let original = try #require(source.groups[id])
        let engine = LibraryBackupEngine(storage: source)
        for data in [try engine.exportData(), try engine.exportData(groupID: id)] {
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["version"] as? Int == 16)
            let document = try LibraryBackup.decode(data)
            #expect(document.groups.first?.appearance == original.appearance)
            let destination = BackupTestStorage()
            let importer = LibraryBackupEngine(storage: destination)
            #expect(importer.apply(importer.prepareImport(document)).status == .completed)
            let copy = try #require(destination.groups.values.first)
            #expect(copy.id != original.id && copy.items[0].id != original.items[0].id)
            #expect(copy.appearance?.density == density && copy.appearance == original.appearance)
            #expect(copy.allActionNames == original.allActionNames)
        }
    }

    @Test("Versions one through six without density stay readable at standard density", arguments: [1, 2, 3, 4, 5, 6])
    func legacyReader(version: Int) throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        if version >= 3 { source.groups[id]?.appearance = .default }
        if version == 6 { source.groups[id]?.items.append(.website(name: "Website", url: "https://example.com")) }
        var object = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        object["version"] = version
        object.removeValue(forKey: "appearancePresets")
        object.removeValue(forKey: "actionLibrary")
        if version < 5 { object.removeValue(forKey: "coverAssets") }
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(!String(decoding: data, as: UTF8.self).contains("density"))
        let document = try LibraryBackup.decode(data)
        #expect(document.groups.first?.resolvedAppearance.density == .standard)
        if version == 6 { #expect(document.groups.first?.items.last?.kind == .website) }
    }

    @Test("A pre-v7 envelope cannot smuggle even an explicit standard density field", arguments: [1, 2, 3, 4, 5, 6])
    func rejectsDowngrade(version: Int) throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.appearance = .default
        let original = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        for density in FolderDensity.allCases {
            var object = original
            object["version"] = version
            object.removeValue(forKey: "appearancePresets")
            object.removeValue(forKey: "actionLibrary")
            if version < 5 { object.removeValue(forKey: "coverAssets") }
            var groups = try #require(object["groups"] as? [[String: Any]])
            var appearance = try #require(groups[0]["appearance"] as? [String: Any])
            appearance["density"] = density.rawValue
            groups[0]["appearance"] = appearance
            object["groups"] = groups
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(data) }
        }
    }

    @Test("Version seven still rejects unknown or null density rather than substituting standard")
    func invalidDensity() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.appearance = .default
        let original = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        let invalidValues: [Any] = ["future", "Dense", 1, NSNull()]
        for value in invalidValues {
            var object = original
            var groups = try #require(object["groups"] as? [[String: Any]])
            var appearance = try #require(groups[0]["appearance"] as? [String: Any])
            appearance["density"] = value
            groups[0]["appearance"] = appearance
            object["groups"] = groups
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(data) }
        }
    }
}

@Suite("Library backup format")
struct LibraryBackupFormatTests {
    @Test("Legacy versions one through four retain standard artwork without inventing a dark override", arguments: [1, 2, 3, 4])
    func legacyIconVersions(version: Int) throws {
        let source = try BackupTestStorage.fixture(photo: true)
        let exported = try LibraryBackupEngine(storage: source).exportData()
        let data = try changed(exported) { $0["version"] = version; $0.removeValue(forKey: "appearancePresets"); $0.removeValue(forKey: "actionLibrary"); $0.removeValue(forKey: "coverAssets") }
        #expect(!String(decoding: data, as: UTF8.self).contains("darkIcon"))
        let document = try LibraryBackup.decode(data)
        #expect(document.icons.first?.icon == source.icons["camera"])
        #expect(document.icons.first?.icon.dark == nil)
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        #expect(engine.apply(engine.prepareImport(document)).status == .completed)
        #expect(destination.icons == source.icons)
    }

    @Test("Versions four through eight preserve dark-only and paired artwork while counting photo records once", arguments: [4, 5, 6, 7, 8])
    func appearanceRoundTrip(version: Int) throws {
        let source = try BackupTestStorage.fixture(photo: true)
        let photo = try #require(source.icons["camera"]?.standard)
        let moon = try #require(CustomIcon.symbol("moon.fill"))
        source.icons["camera"] = CustomIconVariants(standard: photo, dark: moon)
        source.icons["dark only"] = CustomIconVariants(dark: photo)
        source.icons["both photos"] = CustomIconVariants(standard: photo, dark: photo)
        let exported = try LibraryBackupEngine(storage: source).exportData()
        let data = try changed(exported) {
            $0["version"] = version; $0.removeValue(forKey: "appearancePresets"); $0.removeValue(forKey: "actionLibrary")
            if version < 5 { $0.removeValue(forKey: "coverAssets") }
        }
        let document = try LibraryBackup.decode(data)
        #expect(document.counts == .init(groups: 1, icons: 3, photos: 3, mappings: 1))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == version)
        let records = try #require(json["icons"] as? [[String: Any]])
        let darkOnly = try #require(records.first { $0["name"] as? String == "dark only" })
        #expect(darkOnly["icon"] == nil && darkOnly["darkIcon"] != nil)
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        #expect(engine.apply(engine.prepareImport(document)).status == .completed)
        #expect(destination.icons == source.icons)
        #expect(try LibraryBackup.decode(engine.exportData()).icons == document.icons)
        for invalid in [false, true] {
            let malformed = try changed(data) { json in
                var icons = json["icons"] as! [[String: Any]]
                icons[0].removeValue(forKey: "icon")
                if invalid { icons[0]["darkIcon"] = ["kind": "unknown"] }
                else { icons[0].removeValue(forKey: "darkIcon") }
                json["icons"] = icons
            }
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(malformed) }
        }
    }

    @Test("One file preserves groups, custom photos and manual mappings without transient state")
    func roundTrip() throws {
        let storage = try BackupTestStorage.fixture(photo: true)
        let engine = LibraryBackupEngine(storage: storage)
        let data = try engine.exportData()
        let document = try LibraryBackup.decode(data)
        #expect(document.counts == .init(groups: 1, icons: 1, photos: 1, mappings: 1))
        #expect(document.groups == Array(storage.groups.values))
        #expect(document.icons.first?.icon.standard?.pngData == storage.icons["camera"]?.standard?.pngData)
        #expect(document.mappings == [.init(name: "camera", appStoreID: 123456)])
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["format", "version", "createdAt", "groups", "icons", "mappings", "coverAssets", "actionLibrary", "appearancePresets"])
        #expect(json["version"] as? Int == 16)
        #expect(storage.writes == 0)
    }

    @Test("Version-one backups without aliases still decode and import; exports use the current version")
    func legacyVersion() throws {
        let source = try BackupTestStorage.fixture()
        let exported = try LibraryBackupEngine(storage: source).exportData()
        let legacy = try changed(exported) { $0["version"] = 1; $0.removeValue(forKey: "appearancePresets"); $0.removeValue(forKey: "actionLibrary"); $0.removeValue(forKey: "coverAssets") }
        #expect(!String(decoding: legacy, as: UTF8.self).contains("displayName"))
        let document = try LibraryBackup.decode(legacy)
        #expect(document.groups == Array(source.groups.values))
        #expect(document.groups.first?.items.first?.children.first?.displayName == nil)
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        #expect(engine.apply(engine.prepareImport(document)).status == .completed)
        #expect(destination.groups.values.first?.items.first?.children.first?.displayTitle == "Camera")
        let reexported = try engine.exportData()
        let json = try #require(JSONSerialization.jsonObject(with: reexported) as? [String: Any])
        #expect(json["version"] as? Int == 16)
        let future = try changed(exported) { $0["version"] = 17 }
        #expect(throws: LibraryBackupError.unsupportedVersion(17)) { try LibraryBackup.decode(future) }
    }

    @Test("Version-two backups retain aliases without inventing a stored appearance")
    func versionTwoAliases() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.items[0].children[0].displayName = "Trip photo"
        let exported = try LibraryBackupEngine(storage: source).exportData()
        let v2 = try changed(exported) { $0["version"] = 2; $0.removeValue(forKey: "appearancePresets"); $0.removeValue(forKey: "actionLibrary"); $0.removeValue(forKey: "coverAssets") }
        #expect(!String(decoding: v2, as: UTF8.self).contains("appearance"))
        let document = try LibraryBackup.decode(v2)
        #expect(document.groups.first?.appearance == nil)
        #expect(document.groups.first?.items[0].children[0].displayTitle == "Trip photo")
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document)
        #expect(engine.apply(plan).status == .completed)
        #expect(destination.groups.values.first?.appearance == nil)
        #expect(destination.groups.values.first?.items[0].children[0].displayTitle == "Trip photo")
    }

    @Test("Invalid appearance cannot be exported or accepted from a backup")
    func invalidAppearance() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.appearance = .default
        let exported = try LibraryBackupEngine(storage: source).exportData()
        for (key, value) in [("tintHex", "+12345"), ("grid", "five"), ("iconSize", "huge"), ("plate", "unknown")] {
            let malformed = try changed(exported) { json in
                var groups = json["groups"] as! [[String: Any]]
                var appearance = groups[0]["appearance"] as! [String: Any]
                appearance[key] = value
                groups[0]["appearance"] = appearance
                json["groups"] = groups
            }
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(malformed) }
        }
        source.groups[id]?.appearance?.tintHex = "+12345"
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackupEngine(storage: source).exportData() }
        #expect(source.writes == 0)
    }

    @Test("Invalid nested aliases reject the entire backup")
    func invalidAliasContents() throws {
        let data = try LibraryBackupEngine(storage: BackupTestStorage.fixture()).exportData()
        for alias: Any in ["", "bad\nalias", String(repeating: "a", count: 81), 42] {
            let invalid = try changed(data) { json in
                var groups = json["groups"] as! [[String: Any]]
                var items = groups[0]["items"] as! [[String: Any]]
                var children = items[0]["children"] as! [[String: Any]]
                children[0]["displayName"] = alias
                items[0]["children"] = children
                groups[0]["items"] = items
                json["groups"] = groups
            }
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(invalid) }
        }
    }

    @Test("Wrong format, future versions and unknown envelope fields are rejected")
    func envelopeValidation() throws {
        let data = try LibraryBackupEngine(storage: BackupTestStorage()).exportData()
        #expect(throws: LibraryBackupError.invalidFormat) { try LibraryBackup.decode(Data("not JSON".utf8)) }
        let wrongFormat = try changed(data) { $0["format"] = "some.other.backup" }
        #expect(throws: LibraryBackupError.invalidFormat) { try LibraryBackup.decode(wrongFormat) }
        let future = try changed(data) { $0["version"] = 999; $0["groups"] = "not even the old shape" }
        #expect(throws: LibraryBackupError.unsupportedVersion(999)) { try LibraryBackup.decode(future) }
        let unknown = try changed(data) { $0["systemShortcuts"] = ["opaque token"] }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(unknown) }
        let missing = try changed(data) { $0.removeValue(forKey: "icons") }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(missing) }
    }

    @Test("Size limits apply before parsing and before reading a large file")
    func boundedInput() throws {
        let oversized = Data(repeating: 0, count: LibraryBackup.maximumFileBytes + 1)
        #expect(throws: LibraryBackupError.fileTooLarge) { try LibraryBackup.decode(oversized) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Backup-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let largeURL = directory.appendingPathComponent("large.appfolderbackup")
        FileManager.default.createFile(atPath: largeURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: largeURL)
        try handle.truncate(atOffset: UInt64(LibraryBackup.maximumFileBytes + 1))
        try handle.close()
        #expect(throws: LibraryBackupError.fileTooLarge) { try LibraryBackup.read(from: largeURL) }
        let validURL = directory.appendingPathComponent("valid.appfolderbackup")
        try LibraryBackupEngine(storage: BackupTestStorage.fixture()).exportData().write(to: validURL)
        #expect(try LibraryBackup.read(from: validURL).counts.groups == 1)
        #expect(throws: LibraryBackupError.readFailed) { try LibraryBackup.read(from: directory) }
    }

    @Test("Duplicate identities and normalized names invalidate the complete document")
    func duplicateRecords() throws {
        let data = try LibraryBackupEngine(storage: BackupTestStorage.fixture()).exportData()
        let duplicateGroup = try changed(data) { json in
            let groups = json["groups"] as! [[String: Any]]
            json["groups"] = groups + groups
        }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(duplicateGroup) }
        for key in ["icons", "mappings"] {
            let duplicate = try changed(data) { json in
                let records = json[key] as! [[String: Any]]
                var second = records[0]
                second["name"] = " CAMERA "
                json[key] = records + [second]
            }
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(duplicate) }
        }
    }

    @Test("Invalid names, IDs, trees and photo bytes reject the entire backup")
    func contentValidation() throws {
        let data = try LibraryBackupEngine(storage: BackupTestStorage.fixture(photo: true)).exportData()
        for name in [" ", "Line\nbreak", String(repeating: "a", count: 1_025)] {
            let bad = try changed(data) { json in
                var records = json["icons"] as! [[String: Any]]
                records[0]["name"] = name
                json["icons"] = records
            }
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(bad) }
        }
        for id in [0, -1] {
            let bad = try changed(data) { json in
                var records = json["mappings"] as! [[String: Any]]
                records[0]["appStoreID"] = id
                json["mappings"] = records
            }
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(bad) }
        }
        let tree = try changed(data) { json in
            var groups = json["groups"] as! [[String: Any]]
            let items = groups[0]["items"] as! [[String: Any]]
            groups[0]["items"] = items + items
            json["groups"] = groups
        }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(tree) }
        let photo = try changed(data) { json in
            var icons = json["icons"] as! [[String: Any]]
            var icon = icons[0]["icon"] as! [String: Any]
            icon["pngData"] = Data("broken PNG".utf8).base64EncodedString()
            icons[0]["icon"] = icon
            json["icons"] = icons
        }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(photo) }
    }

    @Test("Record limits reject rather than silently truncate")
    func recordLimits() throws {
        let data = try LibraryBackupEngine(storage: BackupTestStorage.fixture()).exportData()
        let overLimit = try changed(data) { json in
            let first = (json["groups"] as! [[String: Any]])[0]
            json["groups"] = Array(repeating: first, count: LibraryBackup.maximumGroups + 1)
        }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(overLimit) }
        let storage = BackupTestStorage()
        storage.mappings = ["bad": 0]
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackupEngine(storage: storage).exportData() }
    }

    @Test("Corrupt or unreadable on-disk records fail export instead of disappearing", arguments: [true, false])
    func strictDiskSnapshot(groupRecord: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Backup-strict-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let groups = SavedGroupRepository(directory: root.appendingPathComponent("groups"))
        let icons = CustomIconRepository(directory: root.appendingPathComponent("icons"))
        let group = SavedGroup(name: "Keep me", items: [.action(name: "Camera")])
        let icon = try #require(CustomIcon.symbol("camera.fill"))
        #expect(groups.save(group))
        #expect(icons.set(icon, name: "Camera"))
        let storage = BackupTestStorage()
        storage.strictExport = {
            .init(groups: try groups.backupRecords(), icons: try icons.backupRecords(), mappings: [])
        }
        let engine = LibraryBackupEngine(storage: storage)
        #expect(try LibraryBackup.decode(engine.exportData()).counts == .init(groups: 1, icons: 1))
        let directory = try #require(groupRecord ? groups.directory : icons.directory)
        let record = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: record)
        try Data("broken JSON".utf8).write(to: record)
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData() }
        try original.write(to: record)
        #expect(try LibraryBackup.decode(engine.exportData()).counts == .init(groups: 1, icons: 1))
        try FileManager.default.removeItem(at: record)
        try FileManager.default.createDirectory(at: record, withIntermediateDirectories: false)
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData() }
    }

    @Test("An absent library is empty, but an unreadable store location is an export failure")
    func strictStoreLocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Backup-location-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = SavedGroupRepository(directory: root)
        #expect(try repository.backupRecords().isEmpty)
        try Data("not a directory".utf8).write(to: root)
        #expect(throws: LibraryBackupError.exportFailed) { try repository.backupRecords() }
    }

    @Test("Malformed manual mapping values cannot silently disappear from export")
    func strictManualMappings() throws {
        #expect(try DirectLaunchOverrides.validatedBackupMappings(nil).isEmpty)
        #expect(try DirectLaunchOverrides.validatedBackupMappings(["camera": NSNumber(value: 123456)])["camera"]?.appStoreID == 123456)
        for bad: Any in ["not a dictionary", ["camera": "123"], ["camera": true],
                         ["camera": 1.5], ["camera": -1], [" ": 1]] {
            #expect(throws: LibraryBackupError.exportFailed) { try DirectLaunchOverrides.validatedBackupMappings(bad) }
        }
    }

    private func changed(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

@Suite("Library backup import")
struct LibraryBackupImportTests {
    @Test("An existing dark-only record protects the whole name during import")
    func darkOnlyConflict() throws {
        let document = try fixtureDocument(photo: true)
        let destination = BackupTestStorage()
        let moon = try #require(CustomIcon.symbol("moon.fill"))
        let existing = CustomIconVariants(dark: moon)
        destination.icons["camera"] = existing
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document)
        #expect(plan.counts == .init(groups: 1))
        #expect(plan.keptExisting == .init(icons: 1, photos: 1, mappings: 1))
        #expect(engine.apply(plan).status == .completed)
        #expect(destination.icons["camera"] == existing)
        #expect(destination.mappings.isEmpty)
    }

    @Test("Variant import rolls back the complete pair but preserves a changed dark image", arguments: [false, true])
    func variantRollback(changesDark: Bool) throws {
        let source = try BackupTestStorage.fixture(photo: true)
        let standard = try #require(source.icons["camera"]?.standard)
        let dark = try #require(CustomIcon.symbol("moon.fill"))
        source.icons["camera"] = CustomIconVariants(standard: standard, dark: dark)
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        destination.failWrite = 2
        let replacement = try #require(CustomIcon.emoji("ZZ"))
        let changed = CustomIconVariants(standard: standard, dark: replacement)
        if changesDark { destination.onFailure = { destination.icons["camera"] = changed } }
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(document))
        if changesDark {
            #expect(result.status == .partial)
            #expect(result.imported == .init(icons: 1, photos: 1))
            #expect(destination.icons["camera"] == changed)
        } else {
            #expect(result.status == .rolledBack)
            #expect(destination.icons.isEmpty)
        }
        #expect(destination.mappings.isEmpty && destination.groups.isEmpty)
    }

    @Test("Version-three copies preserve appearance and every alias with independent identities")
    func aliasCopies() throws {
        var branch = GroupItem.action(name: "Deep action", displayName: "Deep alias")
        for depth in (1...SavedGroup.maximumDepth).reversed() {
            branch = .folder(name: "Level \(depth)", children: [
                .action(name: "Action \(depth)", displayName: "Alias \(depth)"), .spacer(), branch,
            ])
        }
        let original = SavedGroup(name: "Aliases", items: [
            .action(name: "Camera", displayName: "Trip photo"), branch, .action(name: "Unchanged"),
        ], appearance: .init(grid: .four, showsTitles: false, iconSize: .large,
                            plate: .gradient, tintHex: "#AABBCC"))
        #expect(original.isValid)
        let source = try BackupTestStorage.fixture(photo: true)
        source.groups = [original.id: original]
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        #expect(document.groups == [original])
        let destination = BackupTestStorage()
        destination.groups = source.groups
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document)
        let copy = try #require(plan.groups.first)
        func flattened(_ items: [GroupItem]) -> [GroupItem] {
            items.flatMap { [$0] + flattened($0.children) }
        }
        let oldItems = flattened(original.items)
        let newItems = flattened(copy.items)
        #expect(copy.id != original.id)
        #expect(copy.appearance == original.appearance)
        #expect(Set(newItems.map(\.id)).isDisjoint(with: oldItems.map(\.id)))
        #expect(Set(newItems.map(\.id)).count == oldItems.count)
        #expect(newItems.map(\.kind) == oldItems.map(\.kind))
        #expect(newItems.map(\.name) == oldItems.map(\.name))
        #expect(newItems.map(\.displayName) == oldItems.map(\.displayName))
        #expect(newItems.map { $0.children.count } == oldItems.map { $0.children.count })
        #expect(copy.allActionNames == original.allActionNames)
        #expect(engine.apply(plan).status == .completed)
        #expect(destination.groups[original.id] == original)
        #expect(destination.groups[copy.id] == copy)
        #expect(destination.icons["camera"] == source.icons["camera"])
        #expect(destination.icons["trip photo"] == nil)
        #expect(destination.mappings == source.mappings)
        let reexported = try LibraryBackup.decode(engine.exportData())
        #expect(reexported.groups.first(where: { $0.id == copy.id }) == copy)
    }

    @Test("Preview has no writes and creates explicit copies with fresh tree identities")
    func previewAndImport() throws {
        let source = try BackupTestStorage.fixture(photo: true)
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        destination.groups = source.groups
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document, copyNameSuffix: "Copy")
        let copy = try #require(plan.groups.first)
        let original = try #require(document.groups.first)
        #expect(destination.writes == 0)
        #expect(copy.id != original.id)
        #expect(copy.name == original.name + " Copy")
        #expect(Set(ids(copy.items)).isDisjoint(with: ids(original.items)))
        #expect(copy.allActionNames == original.allActionNames)
        let result = engine.apply(plan)
        #expect(result.status == .completed)
        #expect(result.imported == document.counts)
        #expect(destination.groups[original.id] == original)
        #expect(destination.groups[copy.id] == copy)
        #expect(destination.icons == source.icons)
        #expect(destination.mappings == source.mappings)
    }

    @Test("Existing custom icons or mappings protect both settings for that name")
    func conflictsPreserveChoices() throws {
        let source = try BackupTestStorage.fixture()
        let symbol = try #require(CustomIcon.symbol("star.fill"))
        source.icons["mail"] = CustomIconVariants(standard: symbol)
        source.icons["maps"] = CustomIconVariants(standard: symbol)
        source.mappings["mail"] = 11
        source.mappings["maps"] = 22
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        let existing = try #require(CustomIcon.emoji("AB"))
        destination.icons["mail"] = CustomIconVariants(standard: existing)
        destination.mappings["maps"] = 999
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document)
        #expect(plan.counts == .init(groups: 1, icons: 1, mappings: 1))
        #expect(plan.keptExisting == .init(icons: 2, mappings: 2))
        #expect(engine.apply(plan).status == .completed)
        #expect(destination.icons["mail"] == CustomIconVariants(standard: existing))
        #expect(destination.mappings["maps"] == 999)
        #expect(destination.mappings["mail"] == nil)
        #expect(destination.icons["maps"] == nil)
    }

    @Test("A name added after preview is preserved when applying the plan")
    func stalePreview() throws {
        let document = try fixtureDocument()
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document)
        destination.mappings["camera"] = 999
        let result = engine.apply(plan)
        #expect(result.status == .completed)
        #expect(result.imported == .init(groups: 1))
        #expect(result.keptExisting == .init(icons: 1, mappings: 1))
        #expect(destination.mappings["camera"] == 999)
        #expect(destination.icons.isEmpty)
    }

    @Test("Failed writes roll back both confirmed and partially written new records", arguments: [false, true])
    func rollback(persistBeforeFailure: Bool) throws {
        let destination = BackupTestStorage()
        destination.failWrite = 2
        destination.persistBeforeFailure = persistBeforeFailure
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(try fixtureDocument()))
        #expect(result.status == .rolledBack)
        #expect(result.imported == .init())
        #expect(!result.failedRecords.isEmpty)
        #expect(destination.groups.isEmpty && destination.icons.isEmpty && destination.mappings.isEmpty)
    }

    @Test("Failed rollback reports remaining records instead of claiming atomic failure")
    func partialRollback() throws {
        let destination = BackupTestStorage()
        destination.failWrite = 3
        destination.failedRemovals = ["icon:camera"]
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(try fixtureDocument(photo: true)))
        #expect(result.status == .partial)
        #expect(result.imported == .init(icons: 1, photos: 1))
        #expect(destination.icons.count == 1)
        #expect(destination.mappings.isEmpty && destination.groups.isEmpty)
        #expect(result.failedRecords.contains("Icon: camera"))
    }

    @Test("Rollback outcome is verified even when a deletion returns false")
    func failedReturnButRemoved() throws {
        let destination = BackupTestStorage()
        destination.failWrite = 2
        destination.reportFailedRemoval = true
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(try fixtureDocument()))
        #expect(result.status == .rolledBack)
        #expect(destination.icons.isEmpty)
    }

    @Test("A store acknowledging an unwritten record fails read-back verification")
    func missingWrite() throws {
        let destination = BackupTestStorage()
        destination.acknowledgeWithoutWrite = 1
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(try fixtureDocument()))
        #expect(result.status == .rolledBack)
        #expect(result.imported == .init())
    }

    @Test("Unreadable bytes left by a failed group write remain visible as a partial import")
    func unreadablePartialRecord() throws {
        let destination = BackupTestStorage()
        destination.corruptGroupWrite = true
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(try fixtureDocument())
        let group = try #require(plan.groups.first)
        destination.failedRemovals = ["group:\(group.id)"]
        let result = engine.apply(plan)
        #expect(result.status == .partial)
        #expect(result.imported == .init(groups: 1))
        #expect(result.groups.isEmpty, "an unreadable group is not presented as a usable copy")
        #expect(destination.unreadableGroups == [group.id])
        #expect(destination.icons.isEmpty && destination.mappings.isEmpty)
    }

    @Test("Rollback does not delete a record changed by another writer")
    func preserveConcurrentChange() throws {
        let destination = BackupTestStorage()
        destination.failWrite = 2
        let replacement = try #require(CustomIcon.emoji("ZZ"))
        destination.onFailure = { destination.icons["camera"] = CustomIconVariants(standard: replacement) }
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(try fixtureDocument()))
        #expect(result.status == .partial)
        #expect(destination.icons["camera"] == CustomIconVariants(standard: replacement))
    }

    @Test("Replaying a plan cannot overwrite an existing imported group")
    func replay() throws {
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(try fixtureDocument())
        #expect(engine.apply(plan).status == .completed)
        let original = destination.groups
        let result = engine.apply(plan)
        #expect(result.status == .rolledBack)
        #expect(result.imported == .init())
        #expect(destination.groups == original)
    }

    @Test("Unavailable storage does not claim export or import success")
    func unavailable() throws {
        let destination = BackupTestStorage()
        destination.isAvailable = false
        let engine = LibraryBackupEngine(storage: destination)
        #expect(throws: LibraryBackupError.storageUnavailable) { try engine.exportData() }
        let plan = engine.prepareImport(try fixtureDocument())
        #expect(!plan.isAvailable)
        #expect(engine.apply(plan).status == .unavailable)
        #expect(destination.writes == 0)
    }

    @Test("Long copy names stay valid and every original node remains in the preview")
    func longCopyName() throws {
        let source = BackupTestStorage()
        let group = SavedGroup(name: String(repeating: "a", count: 80), items: (0..<200).map { .action(name: "App \($0)") })
        source.groups[group.id] = group
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let plan = LibraryBackupEngine(storage: BackupTestStorage()).prepareImport(document)
        let copy = try #require(plan.groups.first)
        #expect(copy.isValid)
        #expect(copy.name.hasSuffix(" (Copy)"))
        #expect(copy.name.count == 80)
        #expect(copy.items.count == 200)
    }

    private func fixtureDocument(photo: Bool = false) throws -> LibraryBackup.Document {
        try LibraryBackup.decode(LibraryBackupEngine(storage: BackupTestStorage.fixture(photo: photo)).exportData())
    }

    private func ids(_ items: [GroupItem]) -> [UUID] { items.flatMap { [$0.id] + ids($0.children) } }
}

@Suite("Library backup folder covers")
struct LibraryBackupCoverTests {
    @Test("Shared covers round-trip once, preserve both appearances, and get new group and node IDs")
    func coverRoundTrip() throws {
        let source = try BackupTestStorage.coverFixture()
        let unused = try #require(CustomIcon.symbol("heart.fill"))
        source.coverAssets[try #require(FolderCoverAssetRepository.id(for: unused))] = unused
        let data = try LibraryBackupEngine(storage: source).exportData()
        let document = try LibraryBackup.decode(data)
        #expect(document.counts == .init(groups: 1, icons: 1, mappings: 1, folderCovers: 2, folderCoverPhotos: 1))
        let original = try #require(document.groups.first)
        #expect(original.coverAssetIDs == Set(document.coverAssets.map(\.id)))
        #expect(document.coverAssets.count == 2)
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document)
        let copy = try #require(plan.groups.first)
        #expect(copy.id != original.id)
        #expect(nodeIDs(copy.items).isDisjoint(with: nodeIDs(original.items)))
        #expect(copy.coverAssetIDs == original.coverAssetIDs)
        #expect(copy.items[0].folderCover == original.items[0].folderCover)
        #expect(copy.items[0].children[2].folderCover == original.items[0].children[2].folderCover)
        #expect(copy.items[0].children[0].displayName == "Take photo")
        #expect(engine.apply(plan).imported == document.counts)
        #expect(destination.coverAssets.count == 2)
        #expect(try LibraryBackup.decode(engine.exportData()).coverAssets == document.coverAssets)
    }

    @Test("Missing, duplicate, orphaned, mismatched and invalid cover payloads reject the complete file")
    func invalidCoverTables() throws {
        let data = try LibraryBackupEngine(storage: BackupTestStorage.coverFixture()).exportData()
        for mutation in 0..<8 {
            let bad = try changed(data) { json in
                var assets = json["coverAssets"] as! [[String: Any]]
                switch mutation {
                case 0: assets.removeLast()
                case 1: assets[1] = assets[0]
                case 2: assets.append(assets[0])
                case 3: assets[0]["id"] = String(repeating: "0", count: 64)
                case 4: assets[0]["id"] = (assets[0]["id"] as! String).uppercased()
                case 5: assets[0]["icon"] = assets[1]["icon"]
                case 6:
                    var icon = (assets.first { ($0["icon"] as? [String: Any])?["kind"] as? String == "photo" }!["icon"] as! [String: Any])
                    icon["pngData"] = Data(repeating: 0, count: CustomIcon.maximumPhotoBytes + 1).base64EncodedString()
                    assets[0]["icon"] = icon
                default: json.removeValue(forKey: "coverAssets"); return
                }
                json["coverAssets"] = assets
            }
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(bad) }
        }
        // A legacy version cannot claim references without its asset payload.
        let stripped = try changed(data) { $0["version"] = 4; $0.removeValue(forKey: "appearancePresets"); $0.removeValue(forKey: "actionLibrary"); $0.removeValue(forKey: "coverAssets") }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(stripped) }
    }

    @Test("Real missing or corrupt referenced assets fail export instead of silently losing covers")
    func strictAssetExport() throws {
        let source = try BackupTestStorage.coverFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Backup-cover-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("FolderCoverAssets")
        let repository = FolderCoverAssetRepository(directory: directory, groupDirectory: root.appendingPathComponent("SavedGroups"))
        for (id, icon) in source.coverAssets { #expect(repository.save(icon, id: id)) }
        source.assetReader = { repository.icon(id: $0) }
        let engine = LibraryBackupEngine(storage: source)
        #expect(try LibraryBackup.decode(engine.exportData()).counts.folderCovers == 2)
        let id = try #require(source.coverAssets.keys.first)
        let file = directory.appendingPathComponent(id.rawValue + ".json")
        let original = try Data(contentsOf: file)
        try Data("broken asset".utf8).write(to: file)
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData() }
        try original.write(to: file)
        #expect(try LibraryBackup.decode(engine.exportData()).counts.folderCovers == 2)
        try FileManager.default.removeItem(at: file)
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData() }
    }

    @Test("Existing immutable assets are reused and missing preview assets are recreated at apply")
    func reuseAndRecheck() throws {
        let document = try coverDocument()
        let destination = BackupTestStorage()
        let existing = try #require(document.coverAssets.first { $0.icon.kind == .photo })
        destination.coverAssets[existing.id] = existing.icon
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document)
        #expect(plan.counts.folderCovers == 1 && plan.counts.folderCoverPhotos == 0)
        #expect(plan.keptExisting.folderCovers == 1 && plan.keptExisting.folderCoverPhotos == 1)
        // A preview owns its payload, so GC before confirmation loses no artwork.
        destination.coverAssets.removeValue(forKey: existing.id)
        let result = engine.apply(plan)
        #expect(result.status == .completed)
        #expect(result.imported.folderCovers == 2 && result.imported.folderCoverPhotos == 1)
        #expect(result.keptExisting.folderCovers == 0)
        #expect(destination.groups.values.first?.coverAssetIDs == Set(destination.coverAssets.keys))
    }

    @Test("A corrupt or conflicting existing asset blocks import without overwriting any library record", arguments: [false, true])
    func existingAssetConflict(unreadable: Bool) throws {
        let document = try coverDocument()
        let destination = BackupTestStorage()
        let asset = try #require(document.coverAssets.first)
        let reusable = try #require(document.coverAssets.last)
        destination.coverAssets[reusable.id] = reusable.icon
        if unreadable { destination.unreadableCoverAssets.insert(asset.id) }
        else {
            let replacement = try #require(CustomIcon.symbol("heart.fill"))
            destination.coverAssets[asset.id] = replacement
        }
        let original = destination.coverAssets
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(document))
        #expect(result.status == .rolledBack && result.imported == .init())
        #expect(result.keptExisting == .init(folderCovers: 1, folderCoverPhotos: reusable.icon.kind == .photo ? 1 : 0))
        #expect(destination.writes == 0)
        #expect(destination.coverAssets == original && destination.containsCoverAsset(id: asset.id))
        #expect(destination.groups.isEmpty && destination.icons.isEmpty && destination.mappings.isEmpty)
    }

    @Test("Failures at every asset, icon, mapping and group write roll back only this import", arguments: [false, true])
    func coverWriteFailures(persistBeforeFailure: Bool) throws {
        let document = try coverDocument()
        let original = try #require(CustomIcon.symbol("heart.fill"))
        let originalID = try #require(FolderCoverAssetRepository.id(for: original))
        for failure in 1...5 {
            let destination = BackupTestStorage()
            destination.coverAssets[originalID] = original
            destination.failWrite = failure
            destination.persistBeforeFailure = persistBeforeFailure
            let engine = LibraryBackupEngine(storage: destination)
            let result = engine.apply(engine.prepareImport(document))
            #expect(result.status == .rolledBack && result.imported == .init())
            #expect(destination.coverAssets == [originalID: original])
            #expect(destination.groups.isEmpty && destination.icons.isEmpty && destination.mappings.isEmpty)
        }
    }

    @Test("A group that cannot be rolled back keeps all of its cover assets")
    func failedGroupRemovalKeepsAssets() throws {
        let source = try BackupTestStorage.coverFixture()
        let first = try #require(source.groups.values.first)
        let second = SavedGroup(name: "Second", items: first.items)
        source.groups[second.id] = second
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document)
        let retained = try #require(plan.groups.first)
        destination.failWrite = 6
        destination.failedRemovals.insert("group:\(retained.id)")
        let result = engine.apply(plan)
        #expect(result.status == .partial)
        #expect(result.imported == .init(groups: 1, folderCovers: 2, folderCoverPhotos: 1))
        #expect(destination.groups[retained.id] == retained)
        #expect(retained.coverAssetIDs.isSubset(of: Set(destination.coverAssets.keys)))
        #expect(destination.icons.isEmpty && destination.mappings.isEmpty)
    }

    @Test("Unreadable remaining groups make asset rollback fail closed")
    func unreadableGroupKeepsAssets() throws {
        let destination = BackupTestStorage()
        destination.corruptGroupWrite = true
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(try coverDocument())
        let group = try #require(plan.groups.first)
        destination.failedRemovals.insert("group:\(group.id)")
        let result = engine.apply(plan)
        #expect(result.status == .partial)
        #expect(result.imported == .init(groups: 1, folderCovers: 2, folderCoverPhotos: 1))
        #expect(result.groups.isEmpty && destination.unreadableGroups == [group.id])
        #expect(destination.coverAssets.count == 2)
    }

    @Test("Active editors and other persistent groups protect assets during rollback", arguments: [false, true])
    func externalReferencesKeepAssets(editorLease: Bool) throws {
        let document = try coverDocument()
        let asset = try #require(document.coverAssets.first { $0.icon.kind == .photo })
        let destination = BackupTestStorage()
        destination.failWrite = 3
        destination.onFailure = {
            if editorLease { destination.activeCoverAssetIDs.insert(asset.id) }
            else {
                var folder = GroupItem.folder(name: "Existing reference", children: [])
                folder.folderCover = FolderCover(standard: asset.id)
                let group = SavedGroup(name: "Other writer", items: [folder])
                destination.groups[group.id] = group
            }
        }
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(document))
        #expect(result.status == .partial)
        #expect(result.imported == .init(folderCovers: 1, folderCoverPhotos: 1))
        #expect(destination.coverAssets == [asset.id: asset.icon])
        #expect(destination.icons.isEmpty && destination.mappings.isEmpty)
    }

    @Test("Reused assets remain after later failures and newly retained assets are counted accurately")
    func reusedAndFailedAssetRemoval() throws {
        let document = try coverDocument()
        let existing = try #require(document.coverAssets.first { $0.icon.kind != .photo })
        let added = try #require(document.coverAssets.first { $0.icon.kind == .photo })
        let destination = BackupTestStorage()
        destination.coverAssets[existing.id] = existing.icon
        destination.failWrite = 4
        destination.failedRemovals.insert("cover:\(added.id.rawValue)")
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(document))
        #expect(result.status == .partial)
        #expect(result.imported == .init(folderCovers: 1, folderCoverPhotos: 1))
        #expect(result.keptExisting == .init(folderCovers: 1))
        #expect(destination.coverAssets.count == 2 && destination.groups.isEmpty)
    }

    private func coverDocument() throws -> LibraryBackup.Document {
        try LibraryBackup.decode(LibraryBackupEngine(storage: BackupTestStorage.coverFixture()).exportData())
    }

    private func nodeIDs(_ items: [GroupItem]) -> Set<UUID> {
        Set(items.map(\.id)).union(items.reduce(into: Set<UUID>()) { $0.formUnion(nodeIDs($1.children)) })
    }

    private func changed(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

@Suite("Library backup websites")
struct LibraryBackupWebsiteTests {
    @Test("Website-only group sharing preserves node artwork and excludes same-title action icons and mappings")
    func websiteOnlyRoundTrip() throws {
        let source = try BackupTestStorage.coverFixture()
        let groupID = try #require(source.groups.keys.first)
        let photoID = try #require(source.coverAssets.first { $0.value.kind == .photo }?.key)
        let address = "https://example.com/Path?Query=Case#Section"
        source.groups[groupID]?.items[0].children[0] = .website(name: "Camera", url: address, icon: .init(dark: photoID))
        source.groups[groupID]?.appearance = .default
        let original = try #require(source.groups[groupID])
        #expect(original.allActionNames.isEmpty)
        let data = try LibraryBackupEngine(storage: source).exportData(groupID: groupID)
        let document = try LibraryBackup.decode(data)
        #expect(document.groups == [original])
        #expect(document.counts == .init(groups: 1, folderCovers: 2, folderCoverPhotos: 1))
        #expect(document.icons.isEmpty && document.mappings.isEmpty)
        #expect(Set(document.coverAssets.map(\.id)) == original.coverAssetIDs)
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(document))
        #expect(result.status == .completed)
        let copy = try #require(result.groups.first)
        let website = try #require(copy.items.first?.children.first)
        #expect(copy.id != original.id && website.id != original.items[0].children[0].id)
        #expect(copy.appearance == original.appearance)
        #expect(website.kind == .website && website.websiteURL == address)
        #expect(website.websiteIcon == original.items[0].children[0].websiteIcon)
        #expect(website.folderCover == nil && website.displayName == nil)
        #expect(destination.icons.isEmpty && destination.mappings.isEmpty)
        #expect(destination.coverAssets == source.coverAssets)

        // A real action with the same title is a separate, explicit dependency.
        source.groups[groupID]?.items.append(.action(name: "Camera"))
        let mixed = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData(groupID: groupID))
        #expect(mixed.counts.icons == 1 && mixed.counts.mappings == 1)
        #expect(mixed.icons.first?.icon == source.icons["camera"])
        #expect(mixed.coverAssets == document.coverAssets)
    }

    @Test("Version five cover backups remain readable; website records require version six")
    func versionCompatibility() throws {
        let source = try BackupTestStorage.coverFixture()
        let current = try LibraryBackupEngine(storage: source).exportData()
        let legacy = try changed(current) { $0["version"] = 5; $0.removeValue(forKey: "appearancePresets"); $0.removeValue(forKey: "actionLibrary") }
        let old = try LibraryBackup.decode(legacy)
        #expect(old.coverAssets.count == 2)
        #expect(old.groups == Array(source.groups.values))
        let groupID = try #require(source.groups.keys.first)
        source.groups[groupID]?.items.append(.website(name: "Site", url: "https://example.com/"))
        let data = try LibraryBackupEngine(storage: source).exportData()
        let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(envelope["version"] as? Int == 16)
        #expect(try LibraryBackup.decode(data).groups == Array(source.groups.values))
        let downgraded = try changed(data) { $0["version"] = 5; $0.removeValue(forKey: "appearancePresets"); $0.removeValue(forKey: "actionLibrary") }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(downgraded) }
        let badURL = try changed(data) { object in
            var groups = object["groups"] as! [[String: Any]]
            var items = groups[0]["items"] as! [[String: Any]]
            items[items.count - 1]["websiteURL"] = "example.com"
            groups[0]["items"] = items
            object["groups"] = groups
        }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(badURL) }
    }

    @Test("Website artwork participates in the strict asset closure instead of silently reverting to a globe")
    func websiteAssetClosure() throws {
        let source = try websiteFixture()
        let groupID = try #require(source.groups.keys.first)
        let engine = LibraryBackupEngine(storage: source)
        let data = try engine.exportData(groupID: groupID)
        let missingTable = try changed(data) { $0["coverAssets"] = [] }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(missingTable) }
        let duplicate = try changed(data) {
            let assets = $0["coverAssets"] as! [[String: Any]]
            $0["coverAssets"] = assets + assets
        }
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(duplicate) }
        source.coverAssets.removeAll()
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData() }
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData(groupID: groupID) }
    }

    @Test("A website group left after failed rollback keeps its imported artwork alive")
    func websiteRollback() throws {
        let source = try websiteFixture()
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        let engine = LibraryBackupEngine(storage: destination)
        let plan = engine.prepareImport(document)
        let copy = try #require(plan.groups.first)
        destination.failWrite = 2
        destination.persistBeforeFailure = true
        destination.failedRemovals.insert("group:\(copy.id)")
        let result = engine.apply(plan)
        #expect(result.status == .partial)
        #expect(result.imported == .init(groups: 1, folderCovers: 1))
        #expect(destination.groups[copy.id] == copy)
        #expect(copy.coverAssetIDs.allSatisfy { destination.coverAsset(id: $0) != nil })
        #expect(destination.icons.isEmpty && destination.mappings.isEmpty)
    }

    private func websiteFixture() throws -> BackupTestStorage {
        let source = BackupTestStorage()
        let icon = try #require(CustomIcon.symbol("globe"))
        let id = try #require(FolderCoverAssetRepository.id(for: icon))
        source.coverAssets[id] = icon
        let group = SavedGroup(name: "Website", items: [.website(name: "Example", url: "https://example.com/", icon: .init(standard: id))])
        source.groups[group.id] = group
        return source
    }

    private func changed(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

@Suite("Single saved group export")
struct LibraryBackupSingleGroupTests {
    @Test("Only the saved tree's real action names and referenced covers enter the file")
    func scopedContents() throws {
        let source = try BackupTestStorage.coverFixture()
        let id = try #require(source.groups.keys.first)
        let photo = try #require(source.coverAssets.values.first { $0.kind == .photo })
        source.icons["maps"] = .init(dark: photo)
        source.mappings["maps"] = 654321
        source.groups[id]?.items[0].children.append(.action(name: "Maps", displayName: "Unrelated"))
        source.groups[id]?.items[0].children.append(.action(name: "CAMERA", displayName: "Other alias"))
        source.groups[id]?.items[0].children.append(.action(name: "Automatic"))
        let unrelated = try #require(CustomIcon.emoji("X"))
        source.icons["unrelated"] = .init(standard: unrelated)
        source.icons["tools"] = .init(standard: unrelated)
        source.icons["take photo"] = .init(standard: unrelated)
        source.mappings["unrelated"] = 999
        let unrelatedAsset = try #require(FolderCoverAssetRepository.id(for: unrelated))
        source.coverAssets[unrelatedAsset] = unrelated
        let other = SavedGroup(name: "Unrelated group", items: [
            .folder(name: "Other", children: [.action(name: "Unrelated")], folderCover: .init(standard: unrelatedAsset))
        ])
        source.groups[other.id] = other
        source.unreadableIcons.insert("broken unrelated")
        source.strictExport = { throw LibraryBackupError.exportFailed }

        // Read after changing the stored group: the API accepts no stale/draft tree.
        let saved = try #require(source.groups[id])
        let data = try LibraryBackupEngine(storage: source).exportData(groupID: id)
        let document = try LibraryBackup.decode(data)
        #expect(document.groups == [saved])
        #expect(document.counts == .init(groups: 1, icons: 2, photos: 1, mappings: 2, folderCovers: 2, folderCoverPhotos: 1))
        #expect(Set(document.icons.map { LibraryBackup.normalizedName($0.name) }) == ["camera", "maps"])
        #expect(document.icons.first { $0.name == "Maps" }?.icon == source.icons["maps"])
        #expect(Set(document.mappings.map { LibraryBackup.normalizedName($0.name) }) == ["camera", "maps"])
        #expect(Set(document.coverAssets.map(\.id)) == saved.coverAssetIDs)
        let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(envelope["version"] as? Int == 16)
        #expect(Set(envelope.keys) == ["format", "version", "createdAt", "groups", "icons", "mappings", "coverAssets", "actionLibrary", "appearancePresets"])
        #expect(source.writes == 0)
    }

    @Test("Missing or unreadable groups and unavailable storage cannot produce an empty backup")
    func missingGroup() throws {
        let source = BackupTestStorage()
        let id = UUID()
        let engine = LibraryBackupEngine(storage: source)
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData(groupID: id) }
        source.unreadableGroups.insert(id)
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData(groupID: id) }
        source.isAvailable = false
        #expect(throws: LibraryBackupError.storageUnavailable) { try engine.exportData(groupID: id) }
        #expect(source.writes == 0)
    }

    @Test("A missing selected icon is automatic, but a present unreadable one aborts export")
    func unreadableSelectedIcon() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        let engine = LibraryBackupEngine(storage: source)
        source.icons.removeValue(forKey: "camera")
        #expect(try LibraryBackup.decode(engine.exportData(groupID: id)).counts.icons == 0)
        source.unreadableIcons.insert("camera")
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData(groupID: id) }
        #expect(source.writes == 0)
    }

    @Test("A missing or hash-mismatched referenced cover aborts single-group export")
    func missingCover() throws {
        let source = try BackupTestStorage.coverFixture()
        let id = try #require(source.groups.keys.first)
        let assetID = try #require(source.groups[id]?.coverAssetIDs.first)
        let engine = LibraryBackupEngine(storage: source)
        source.coverAssets.removeValue(forKey: assetID)
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData(groupID: id) }
        let mismatched = try #require(CustomIcon.symbol("star.fill"))
        source.coverAssets[assetID] = mismatched
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData(groupID: id) }
        #expect(source.writes == 0)
    }

    @Test("The ordinary import path creates an independent copy with aliases, appearance and covers intact")
    func importCompatibility() throws {
        let source = try BackupTestStorage.coverFixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.appearance = .init(grid: .four, showsTitles: false, iconSize: .large, plate: .gradient, tintHex: "#AF52DE")
        let photo = try #require(source.coverAssets.values.first { $0.kind == .photo })
        let standard = try #require(source.icons["camera"]?.standard)
        source.icons["camera"] = .init(standard: standard, dark: photo)
        let original = try #require(source.groups[id])
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData(groupID: id))
        let destination = BackupTestStorage()
        destination.groups[id] = original
        let engine = LibraryBackupEngine(storage: destination)
        let result = engine.apply(engine.prepareImport(document, copyNameSuffix: " (Copy)"))
        #expect(result.status == .completed)
        let copy = try #require(result.groups.first)
        #expect(copy.id != original.id)
        #expect(nodeIDs(copy.items).isDisjoint(with: nodeIDs(original.items)))
        #expect(copy.allActionNames == original.allActionNames)
        #expect(copy.items[0].children[0].displayName == original.items[0].children[0].displayName)
        #expect(copy.appearance == original.appearance && copy.coverAssetIDs == original.coverAssetIDs)
        #expect(destination.groups[id] == original)
        #expect(destination.icons == source.icons && destination.mappings == source.mappings)
        #expect(destination.coverAssets == source.coverAssets)
        #expect(source.writes == 0)
    }

    @Test("A single group exceeding the same 32 MiB envelope limit is rejected without truncation")
    func outputLimit() throws {
        let source = BackupTestStorage()
        let photo = try largePhoto()
        let pair = CustomIconVariants(standard: photo, dark: photo)
        let group = SavedGroup(name: "Many photos", items: (0..<100).map { .action(name: "Photo \($0)") })
        source.groups[group.id] = group
        for name in group.allActionNames { source.icons[LibraryBackup.normalizedName(name)] = pair }
        #expect(throws: LibraryBackupError.fileTooLarge) {
            try LibraryBackupEngine(storage: source).exportData(groupID: group.id)
        }
        #expect(source.writes == 0 && source.icons.count == 100)
    }

    private func nodeIDs(_ items: [GroupItem]) -> Set<UUID> {
        Set(items.map(\.id)).union(items.reduce(into: Set<UUID>()) { $0.formUnion(nodeIDs($1.children)) })
    }

    private func largePhoto() throws -> CustomIcon {
        let context = try #require(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1_024,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var noise: UInt32 = 0x12345678
        for offset in stride(from: 0, to: 256 * 1_024, by: 4) {
            for channel in 0..<3 {
                noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5
                pixels[offset + channel] = UInt8(truncatingIfNeeded: noise)
            }
            pixels[offset + 3] = 255
        }
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        let finalized = CGImageDestinationFinalize(destination)
        #expect(finalized)
        #expect(data.length > 180_000)
        return try #require(CustomIcon.photo(pngData: data as Data))
    }
}

@Suite("Library backup contacts version")
struct LibraryBackupContactTests {
    @Test("Current full and single-group exports preserve chosen endpoints, independent copied IDs and shared artwork")
    func roundTrip() throws {
        let source = try contactFixture()
        let original = try #require(source.groups.values.first)
        let other = SavedGroup(name: "Other", items: [.action(name: "Other action")])
        source.groups[other.id] = other
        let unrelated = try #require(CustomIcon.symbol("heart.fill"))
        source.icons["person"] = .init(standard: unrelated)
        source.mappings["person"] = 999
        let exporter = LibraryBackupEngine(storage: source)
        for single in [false, true] {
            let data = try single ? exporter.exportData(groupID: original.id) : exporter.exportData()
            let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(envelope["version"] as? Int == 16)
            let document = try LibraryBackup.decode(data)
            #expect(document.counts.contactItems == 2 && document.counts.folderCovers == 2)
            #expect(document.counts.folderCoverPhotos == 1)
            #expect(document.groups.contains(original))
            if single {
                #expect(document.groups == [original])
                #expect(document.icons.isEmpty && document.mappings.isEmpty)
                #expect(!String(decoding: data, as: UTF8.self).contains("Other action"))
            }
            let destination = BackupTestStorage()
            destination.groups[original.id] = original
            destination.coverAssets = source.coverAssets
            let importer = LibraryBackupEngine(storage: destination)
            let plan = importer.prepareImport(document)
            #expect(plan.counts.contactItems == 2 && plan.counts.folderCovers == 0)
            #expect(plan.keptExisting.folderCovers == 2 && plan.keptExisting.folderCoverPhotos == 1)
            let copy = try #require(plan.groups.first { $0.contactItemCount == 2 })
            #expect(copy.id != original.id && copy.items[0].id != original.items[0].id)
            let oldNodes = original.items[0].children
            let newNodes = copy.items[0].children
            #expect(Set(newNodes.map(\.id)).isDisjoint(with: oldNodes.map(\.id)))
            #expect(newNodes.map(\.contactTarget) == oldNodes.map(\.contactTarget))
            #expect(newNodes.map(\.contactIcon) == oldNodes.map(\.contactIcon))
            #expect(copy.coverAssetIDs == original.coverAssetIDs && copy.allActionNames.isEmpty)
            let result = importer.apply(plan)
            #expect(result.status == .completed && result.imported.contactItems == 2)
            #expect(destination.groups[original.id] == original && destination.groups[copy.id] == copy)
        }
    }

    @Test("Older envelopes cannot carry contact kinds or fields, even null at a nested node", arguments: Array(1...8))
    func rejectsDowngrade(version: Int) throws {
        let source = try BackupTestStorage.fixture()
        let data = try LibraryBackupEngine(storage: source).exportData()
        var original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        original["version"] = version
        original.removeValue(forKey: "appearancePresets")
        original.removeValue(forKey: "actionLibrary")
        if version < 5 { original.removeValue(forKey: "coverAssets") }
        #expect(try LibraryBackup.decode(JSONSerialization.data(withJSONObject: original)).counts.contactItems == 0)
        let target: [String: Any] = ["operation": "phone", "number": "12025550100"]
        for depth in [0, 1] {
            for field in ["contactTarget", "contactIcon", "kind"] {
                for asNull in [false, true] {
                    var envelope = original
                    var groups = try #require(envelope["groups"] as? [[String: Any]])
                    var items = try #require(groups[0]["items"] as? [[String: Any]])
                    let value: Any = asNull ? NSNull() : (field == "kind" ? "contact" : target)
                    if depth == 0 { items[0][field] = value }
                    else {
                        var children = try #require(items[0]["children"] as? [[String: Any]])
                        children[0][field] = value
                        items[0]["children"] = children
                    }
                    groups[0]["items"] = items
                    envelope["groups"] = groups
                    #expect(throws: LibraryBackupError.invalidContents) {
                        try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope))
                    }
                }
            }
        }
    }

    @Test("Explicit v8 folder presentation still reads without altering its old revision")
    func legacyEight() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.groups[id]?.appearance = .init(density: .dense, backButtonStyle: .folder)
        source.groups[id]?.items[0].folderAppearance = .init(grid: .four, backButtonStyle: .turnUpLeft)
        source.groups[id]?.items[0].folderPreviewGrid = .nine
        let original = try #require(source.groups[id])
        var envelope = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        envelope["version"] = 8
        envelope.removeValue(forKey: "appearancePresets")
        envelope.removeValue(forKey: "actionLibrary")
        let document = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope))
        #expect(document.groups == [original] && document.groups[0].revision == original.revision)
        #expect(document.counts.contactItems == 0)
    }

    @Test("Current backups reject missing or noncanonical endpoints and missing contact artwork as one invalid document")
    func invalidContents() throws {
        let source = try contactFixture()
        let original = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        for target: Any in [NSNull(), ["operation": "email", "number": "123"], ["operation": "phone", "number": "+1 (202) 555-0100"], ["operation": "phone", "number": "123;456"]] {
            var envelope = original
            var groups = try #require(envelope["groups"] as? [[String: Any]])
            var items = try #require(groups[0]["items"] as? [[String: Any]])
            var children = try #require(items[0]["children"] as? [[String: Any]])
            children[0]["contactTarget"] = target
            items[0]["children"] = children
            groups[0]["items"] = items
            envelope["groups"] = groups
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)) }
        }
        var noAssets = original; noAssets["coverAssets"] = []
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: noAssets)) }
        let id = try #require(source.groups.keys.first)
        source.coverAssets = [:]
        let exporter = LibraryBackupEngine(storage: source)
        #expect(throws: LibraryBackupError.exportFailed) { try exporter.exportData() }
        #expect(throws: LibraryBackupError.exportFailed) { try exporter.exportData(groupID: id) }
    }

    @Test("Failed writes roll back contact counts, but a retained group keeps its endpoints and artwork", arguments: [false, true])
    func rollback(retainsGroup: Bool) throws {
        let source = try contactFixture()
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document)
        let group = try #require(plan.groups.first)
        destination.failWrite = 5 // two assets, one action icon, one mapping, then group
        destination.persistBeforeFailure = true
        if retainsGroup { destination.failedRemovals.insert("group:\(group.id)") }
        let result = importer.apply(plan)
        if retainsGroup {
            #expect(result.status == .partial && result.imported.contactItems == 2)
            #expect(result.imported.groups == 1 && result.imported.folderCovers == 2)
            #expect(destination.groups[group.id] == group && group.coverAssetIDs == Set(destination.coverAssets.keys))
        } else {
            #expect(result.status == .rolledBack && result.imported.contactItems == 0)
            #expect(result.imported == .init() && destination.groups.isEmpty && destination.coverAssets.isEmpty)
        }
    }

    @Test("Unreadable partial group writes still disclose the attempted contact data and retain its assets")
    func unreadablePartial() throws {
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: contactFixture()).exportData())
        let destination = BackupTestStorage()
        destination.corruptGroupWrite = true
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document)
        let group = try #require(plan.groups.first)
        destination.failedRemovals.insert("group:\(group.id)")
        let result = importer.apply(plan)
        #expect(result.status == .partial && result.groups.isEmpty)
        #expect(result.imported.groups == 1 && result.imported.contactItems == 2)
        #expect(result.imported.folderCovers == 2 && result.imported.folderCoverPhotos == 1)
        #expect(destination.unreadableGroups == [group.id] && destination.coverAssets.count == 2)
    }

    private func contactFixture() throws -> BackupTestStorage {
        let source = try BackupTestStorage.coverFixture()
        let id = try #require(source.groups.keys.first)
        let cover = try #require(source.groups[id]?.items[0].folderCover)
        let phone = try #require(ContactTarget(operation: .phone, number: "+12025550100"))
        let message = try #require(ContactTarget(operation: .message, number: "+12025550100"))
        source.groups[id]?.items = [.folder(name: "People", children: [
            .contact(name: "Person", target: phone, icon: cover),
            .contact(name: "Person", target: message, icon: .init(dark: cover.dark))
        ])]
        return source
    }
}

@Suite("Library backup App Store countries")
struct LibraryBackupCountryTests {
    @Test("Current full and single-group files preserve selected countries and legacy mappings through import")
    func roundTrip() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        source.mappingCountries["camera"] = "jp"
        source.groups[id]?.items.append(.action(name: "Legacy"))
        source.mappings["legacy"] = 222
        let exporter = LibraryBackupEngine(storage: source)
        for data in [try exporter.exportData(), try exporter.exportData(groupID: id)] {
            let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(envelope["version"] as? Int == 16)
            let records = try #require(envelope["mappings"] as? [[String: Any]])
            #expect(records.first { $0["name"] as? String == "camera" }?["country"] as? String == "jp")
            #expect(records.first { $0["name"] as? String == "Legacy" || $0["name"] as? String == "legacy" }?["country"] == nil)
            let document = try LibraryBackup.decode(data)
            let destination = BackupTestStorage()
            let importer = LibraryBackupEngine(storage: destination)
            let plan = importer.prepareImport(document)
            #expect(plan.counts.mappings == 2)
            #expect(importer.apply(plan).status == .completed)
            #expect(destination.mapping(name: "camera")?.country == "jp")
            #expect(destination.mapping(name: "legacy")?.country == nil)
            #expect(destination.mappings == source.mappings)
            let again = try LibraryBackup.decode(importer.exportData())
            #expect(again.mappings.first { $0.name == "camera" }?.country == "jp")
        }
    }

    @Test("Versions one through nine keep source-less mappings and reject any explicit country field", arguments: Array(1...9))
    func legacyReader(version: Int) throws {
        let source = try BackupTestStorage.fixture()
        var envelope = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        envelope["version"] = version
        envelope.removeValue(forKey: "appearancePresets")
        envelope.removeValue(forKey: "actionLibrary")
        if version < 5 { envelope.removeValue(forKey: "coverAssets") }
        let legacy = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope))
        #expect(legacy.mappings.first?.appStoreID == 123456 && legacy.mappings.first?.country == nil)
        for country: Any in ["jp", "us", NSNull()] {
            var changed = envelope
            var records = try #require(changed["mappings"] as? [[String: Any]])
            records[0]["country"] = country
            changed["mappings"] = records
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
    }

    @Test("A v9 contact backup stays readable after the country schema upgrade")
    func legacyContacts() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        let target = try #require(ContactTarget(operation: .message, number: "+12025550100"))
        source.groups[id]?.items.append(.contact(name: "Person", target: target))
        var envelope = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        envelope["version"] = 9
        envelope.removeValue(forKey: "appearancePresets")
        envelope.removeValue(forKey: "actionLibrary")
        let document = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope))
        #expect(document.groups == Array(source.groups.values) && document.counts.contactItems == 1)
        #expect(document.mappings.first?.country == nil)
    }

    @Test("Invalid or noncanonical countries and unknown record fields fail the whole current document")
    func invalidCountries() throws {
        let data = try LibraryBackupEngine(storage: BackupTestStorage.fixture()).exportData()
        let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for country: Any in ["JP", " jp", "", "zz", "jpn", "jp&country=us", true, 123] {
            var envelope = original
            var records = try #require(envelope["mappings"] as? [[String: Any]])
            records[0]["country"] = country
            envelope["mappings"] = records
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)) }
        }
        var envelope = original
        var records = try #require(envelope["mappings"] as? [[String: Any]])
        records[0]["countryCode"] = "jp"
        envelope["mappings"] = records
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)) }
    }

    @Test("Existing source choices and unreadable mappings retain their complete name protection", arguments: [false, true])
    func existingMapping(unreadable: Bool) throws {
        let source = try BackupTestStorage.fixture()
        source.mappingCountries["camera"] = "jp"
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        if unreadable { destination.unreadableMappings.insert("camera") }
        else {
            destination.mappings["camera"] = 123456
            destination.mappingCountries["camera"] = "us"
        }
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document)
        #expect(plan.keptExisting.mappings == 1 && plan.keptExisting.icons == 1)
        #expect(plan.counts.mappings == 0 && plan.counts.icons == 0)
        #expect(importer.apply(plan).status == .completed)
        if unreadable { #expect(destination.unreadableMappings == ["camera"] && destination.mappings.isEmpty) }
        else { #expect(destination.mapping(name: "camera")?.country == "us") }
    }

    @Test("Rollback compares ID and country, removing its own pair but preserving a later country-only edit", arguments: [false, true])
    func countryAwareRollback(changed: Bool) throws {
        let source = try BackupTestStorage.fixture()
        source.mappingCountries["camera"] = "jp"
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        destination.failWrite = 3
        if changed { destination.onFailure = { destination.mappingCountries["camera"] = "us" } }
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document))
        if changed {
            #expect(result.status == .partial && result.imported == .init(mappings: 1))
            #expect(destination.mapping(name: "camera")?.appStoreID == 123456)
            #expect(destination.mapping(name: "camera")?.country == "us")
        } else {
            #expect(result.status == .rolledBack && result.imported == .init())
            #expect(destination.mappings.isEmpty && destination.mappingCountries.isEmpty)
        }
        #expect(destination.groups.isEmpty && destination.icons.isEmpty)
    }

    @Test("An unreadable country written after import is retained and reported as partial")
    func unreadableCountryRollback() throws {
        let source = try BackupTestStorage.fixture()
        source.mappingCountries["camera"] = "jp"
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        destination.failWrite = 3
        destination.onFailure = { destination.mappingCountries["camera"] = "zz" }
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document))
        #expect(result.status == .partial && result.imported == .init(mappings: 1))
        #expect(destination.mapping(name: "camera") == nil && destination.containsMapping(name: "camera"))
        #expect(destination.mappings["camera"] == 123456 && destination.mappingCountries["camera"] == "zz")
        #expect(destination.groups.isEmpty && destination.icons.isEmpty)
    }
}

@Suite("Library backup date artwork")
struct LibraryBackupDateTests {
    @Test("Current full and single-group backups restore date variants and shared assets without losing photos or targets")
    func roundTrip() throws {
        let source = try dateFixture()
        let original = try #require(source.groups.values.first)
        let exporter = LibraryBackupEngine(storage: source)
        for data in [try exporter.exportData(), try exporter.exportData(groupID: original.id)] {
            let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(envelope["version"] as? Int == 16)
            let document = try LibraryBackup.decode(data)
            #expect(document.groups == [original])
            #expect(document.counts == .init(groups: 1, icons: 2, photos: 1, mappings: 1,
                                            folderCovers: 2, folderCoverPhotos: 1, contactItems: 1))
            #expect(document.icons.allSatisfy { $0.icon.containsDate })
            #expect(document.coverAssets.filter { $0.icon.kind == .date }.count == 1)
            let destination = BackupTestStorage()
            let importer = LibraryBackupEngine(storage: destination)
            let plan = importer.prepareImport(document)
            let copy = try #require(plan.groups.first)
            #expect(copy.id != original.id && copy.items[0].id != original.items[0].id)
            #expect(copy.coverAssetIDs == original.coverAssetIDs)
            #expect(copy.items[0].children.map(\.id).allSatisfy { id in !original.items[0].children.contains { $0.id == id } })
            #expect(copy.items[0].children.map(\.websiteURL) == original.items[0].children.map(\.websiteURL))
            #expect(copy.items[0].children.map(\.contactTarget) == original.items[0].children.map(\.contactTarget))
            #expect(copy.allActionNames == original.allActionNames)
            let result = importer.apply(plan)
            #expect(result.status == .completed && result.imported == document.counts)
            #expect(destination.icons == source.icons)
            #expect(copy.coverAssetIDs.allSatisfy { destination.coverAssets[$0] == source.coverAssets[$0] })
            let reexported = try LibraryBackup.decode(importer.exportData())
            #expect(reexported.counts == document.counts)
            #expect(reexported.icons.map(\.icon) == document.icons.map(\.icon))
            #expect(reexported.icons.map { LibraryBackup.normalizedName($0.name) }
                    == document.icons.map { LibraryBackup.normalizedName($0.name) })
            #expect(source.groups[original.id] == original)
        }
    }

    @Test("Versions one through ten reject dates in either action appearance", arguments: Array(1...10))
    func oldActionVersions(version: Int) throws {
        let date = try #require(CustomIcon.date())
        for dark in [false, true] {
            let source = try BackupTestStorage.fixture()
            source.icons["camera"] = dark ? .init(dark: date) : .init(standard: date)
            var envelope = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
            envelope["version"] = version
            envelope.removeValue(forKey: "appearancePresets")
            envelope.removeValue(forKey: "actionLibrary")
            if version < 5 { envelope.removeValue(forKey: "coverAssets") }
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)) }
        }
    }

    @Test("Versions one through ten cannot smuggle a date through a shared node asset", arguments: Array(1...10))
    func oldAssetVersions(version: Int) throws {
        let source = try BackupTestStorage.fixture()
        let groupID = try #require(source.groups.keys.first)
        let date = try #require(CustomIcon.date())
        let id = try #require(FolderCoverAssetRepository.id(for: date))
        source.groups[groupID]?.items[0].folderCover = .init(dark: id)
        source.coverAssets = [id: date]
        var envelope = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        envelope["version"] = version
        envelope.removeValue(forKey: "appearancePresets")
        envelope.removeValue(forKey: "actionLibrary")
        // Before v5, even the asset-table field itself is outside the schema.
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)) }
    }

    @Test("Older non-date artwork stays readable, including v10 countries", arguments: Array(1...10))
    func legacyReader(version: Int) throws {
        let source = try BackupTestStorage.fixture()
        if version == 10 { source.mappingCountries["camera"] = "jp" }
        var envelope = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        envelope["version"] = version
        envelope.removeValue(forKey: "appearancePresets")
        envelope.removeValue(forKey: "actionLibrary")
        if version < 5 { envelope.removeValue(forKey: "coverAssets") }
        let document = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope))
        #expect(document.icons.first?.icon.containsDate == false)
        #expect(document.icons.first?.icon.standard?.kind == .symbol)
        #expect(document.groups == Array(source.groups.values))
        #expect(document.mappings.first?.country == (version == 10 ? "jp" : nil))
    }

    @Test("A date cannot carry frozen date text or PNG bytes in a current backup")
    func malformedDate() throws {
        let source = try BackupTestStorage.fixture()
        let date = try #require(CustomIcon.date())
        source.icons["camera"] = .init(standard: date)
        let original = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
        for field in ["value", "pngData"] {
            var envelope = original
            var icons = try #require(envelope["icons"] as? [[String: Any]])
            var icon = try #require(icons[0]["icon"] as? [String: Any])
            icon[field] = field == "value" ? "29" : Data().base64EncodedString()
            icons[0]["icon"] = icon
            envelope["icons"] = icons
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)) }
        }
    }

    @Test("Date import conflicts preserve existing artwork and failed writes roll back its new configuration")
    func conflictsAndRollback() throws {
        let source = try dateFixture()
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        let old = try #require(CustomIcon.symbol("calendar"))
        destination.icons["camera"] = .init(standard: old)
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document)
        #expect(plan.keptExisting.icons == 1 && plan.keptExisting.photos == 1)
        #expect(importer.apply(plan).status == .completed)
        #expect(destination.icons["camera"]?.standard == old)
        #expect(destination.icons["dark date"]?.dark?.kind == .date)
        let failed = BackupTestStorage()
        failed.failWrite = 6 // two assets, two action icon records, mapping, then group
        let failingImporter = LibraryBackupEngine(storage: failed)
        let result = failingImporter.apply(failingImporter.prepareImport(document))
        #expect(result.status == .rolledBack && result.imported == .init())
        #expect(failed.groups.isEmpty && failed.icons.isEmpty && failed.coverAssets.isEmpty && failed.mappings.isEmpty)
    }

    private func dateFixture() throws -> BackupTestStorage {
        let source = try BackupTestStorage.coverFixture()
        let groupID = try #require(source.groups.keys.first)
        let photo = try #require(source.coverAssets.values.first { $0.kind == .photo })
        let photoID = try #require(FolderCoverAssetRepository.id(for: photo))
        let date = try #require(CustomIcon.date(backgroundHex: "#AA00FF"))
        let dateID = try #require(FolderCoverAssetRepository.id(for: date))
        let dark = try #require(CustomIcon.date(backgroundHex: "#000000"))
        source.icons = ["camera": .init(standard: date, dark: photo), "dark date": .init(dark: dark)]
        source.coverAssets = [photoID: photo, dateID: date]
        let cover = FolderCover(standard: dateID, dark: photoID)
        let target = try #require(ContactTarget(operation: .message, number: "+12025550100"))
        source.groups[groupID]?.items = [.folder(name: "Dates", children: [
            .action(name: "Camera", displayName: "Agenda"), .action(name: "Dark date"),
            .website(name: "Web", url: "https://example.com", icon: .init(dark: dateID)),
            .contact(name: "Person", target: target, icon: .init(standard: dateID))
        ], folderCover: cover)]
        return source
    }
}

final class BackupTestStorage: LibraryBackupStorage {
    var isAvailable = true
    var actionLibrary: [String: ActionLibraryRecord] = [:]
    var unreadableActionLibrary = false
    var actionLibraryReads = 0
    var actionLibraryInsertCalls = 0
    var actionLibraryRollbackCalls = 0
    var groups: [UUID: SavedGroup] = [:]
    var icons: [String: CustomIconVariants] = [:]
    var mappings: [String: Int] = [:]
    var mappingCountries: [String: String] = [:]
    var unreadableMappings = Set<String>()
    var coverAssets: [FolderCoverAssetID: CustomIcon] = [:]
    var unreadableCoverAssets = Set<FolderCoverAssetID>()
    var activeCoverAssetIDs = Set<FolderCoverAssetID>()
    var assetReader: ((FolderCoverAssetID) -> CustomIcon?)?
    var unreadableGroups = Set<UUID>()
    var unreadableIcons = Set<String>()
    var writes = 0
    var failWrite: Int?
    var persistBeforeFailure = false
    var acknowledgeWithoutWrite: Int?
    var corruptGroupWrite = false
    var failedRemovals = Set<String>()
    var reportFailedRemoval = false
    var onFailure: (() -> Void)?
    var strictExport: (() throws -> LibraryBackupSnapshot)?

    var snapshot: LibraryBackupSnapshot {
        .init(groups: Array(groups.values), icons: icons.map { .init(name: $0.key, icon: $0.value) },
              mappings: mappings.map { .init(name: $0.key, appStoreID: $0.value, country: mappingCountries[$0.key]) })
    }
    func exportSnapshot() throws -> LibraryBackupSnapshot {
        if let strictExport { return try strictExport() }
        var value = snapshot
        value.actionLibrary = try actionLibraryRecords()
        return value
    }
    func actionLibraryRecords() throws -> [ActionLibraryRecord] {
        actionLibraryReads += 1
        guard !unreadableActionLibrary else { throw LibraryBackupError.exportFailed }
        return Array(actionLibrary.values)
    }
    func insertActionLibraryRecords(_ records: [ActionLibraryRecord]) -> ActionLibraryInsertResult {
        actionLibraryInsertCalls += 1
        guard !unreadableActionLibrary else {
            return .init(didCommit: false, attemptedRecords: [], keptExistingRecords: [], error: nil)
        }
        let attempted = records.filter { actionLibrary[$0.id] == nil }
        let kept = records.compactMap { actionLibrary[$0.id] }
        let committed = attempted.isEmpty || write {
            for record in attempted { actionLibrary[record.id] = record }
        }
        return .init(didCommit: committed, attemptedRecords: attempted, keptExistingRecords: kept, error: nil)
    }
    func rollbackActionLibraryRecords(_ records: [ActionLibraryRecord]) throws -> ActionLibraryRollbackResult {
        actionLibraryRollbackCalls += 1
        guard !unreadableActionLibrary else { throw LibraryBackupError.exportFailed }
        for record in records where actionLibrary[record.id] == record && !failedRemovals.contains("library:\(record.id)") {
            actionLibrary.removeValue(forKey: record.id)
        }
        return .init(remainingNames: Set(records.filter { actionLibrary[$0.id] != nil }.map(\.id)))
    }
    func group(id: UUID) -> SavedGroup? { groups[id] }
    func icon(name: String) -> CustomIconVariants? { icons[LibraryBackup.normalizedName(name)] }
    func mapping(name: String) -> DirectLaunchOverrides.Mapping? {
        let key = LibraryBackup.normalizedName(name)
        guard let id = mappings[key] else { return nil }
        return .init(appStoreID: id, country: mappingCountries[key])
    }
    func coverAsset(id: FolderCoverAssetID) -> CustomIcon? {
        if let assetReader { return assetReader(id) }
        guard let icon = coverAssets[id], FolderCoverAssetRepository.id(for: icon) == id else { return nil }
        return icon
    }
    func containsGroup(id: UUID) -> Bool { groups[id] != nil || unreadableGroups.contains(id) }
    func containsIcon(name: String) -> Bool { icon(name: name) != nil || unreadableIcons.contains(LibraryBackup.normalizedName(name)) }
    func containsMapping(name: String) -> Bool {
        mappings[LibraryBackup.normalizedName(name)] != nil || unreadableMappings.contains(LibraryBackup.normalizedName(name))
    }
    func containsCoverAsset(id: FolderCoverAssetID) -> Bool {
        coverAssets[id] != nil || unreadableCoverAssets.contains(id)
    }

    func saveCoverAsset(_ icon: CustomIcon, id: FolderCoverAssetID) -> Bool {
        guard FolderCoverAssetRepository.id(for: icon) == id else { return false }
        if containsCoverAsset(id: id) { return coverAsset(id: id) == icon }
        return write { coverAssets[id] = icon }
    }
    func removeCoverAsset(id: FolderCoverAssetID) -> Bool {
        guard !failedRemovals.contains("cover:\(id.rawValue)") else { return false }
        coverAssets.removeValue(forKey: id)
        unreadableCoverAssets.remove(id)
        return !reportFailedRemoval
    }
    func protectedCoverAssetIDs() throws -> Set<FolderCoverAssetID> {
        guard unreadableGroups.isEmpty else { throw LibraryBackupError.exportFailed }
        return groups.values.reduce(into: activeCoverAssetIDs) { $0.formUnion($1.coverAssetIDs) }
    }

    func saveGroup(_ group: SavedGroup) -> Bool {
        if corruptGroupWrite { unreadableGroups.insert(group.id); return false }
        return write { groups[group.id] = group }
    }
    func removeGroup(id: UUID) -> Bool {
        guard !failedRemovals.contains("group:\(id)") else { return false }
        groups.removeValue(forKey: id)
        unreadableGroups.remove(id)
        return !reportFailedRemoval
    }
    func setIcon(_ icon: CustomIconVariants?, name: String) -> Bool {
        let name = LibraryBackup.normalizedName(name)
        if let icon { return write { icons[name] = icon } }
        guard !failedRemovals.contains("icon:\(name)") else { return false }
        icons.removeValue(forKey: name)
        return !reportFailedRemoval
    }
    func setMapping(_ mapping: DirectLaunchOverrides.Mapping?, name: String) -> Bool {
        let name = LibraryBackup.normalizedName(name)
        if let mapping { return write {
            mappings[name] = mapping.appStoreID
            mappingCountries[name] = mapping.country
        } }
        guard !failedRemovals.contains("mapping:\(name)") else { return false }
        mappings.removeValue(forKey: name)
        mappingCountries.removeValue(forKey: name)
        unreadableMappings.remove(name)
        return !reportFailedRemoval
    }
    private func write(_ mutation: () -> Void) -> Bool {
        writes += 1
        if writes == failWrite {
            if persistBeforeFailure { mutation() }
            onFailure?()
            return false
        }
        if writes == acknowledgeWithoutWrite { return true }
        mutation()
        return true
    }

    static func fixture(photo: Bool = false) throws -> BackupTestStorage {
        let storage = BackupTestStorage()
        let group = SavedGroup(name: "Everyday", items: [.folder(name: "Tools", children: [.action(name: "Camera"), .spacer()])])
        storage.groups[group.id] = group
        storage.icons["camera"] = CustomIconVariants(standard: try photo ? photoIcon() : #require(CustomIcon.symbol("camera.fill")))
        storage.mappings["camera"] = 123456
        return storage
    }

    static func coverFixture() throws -> BackupTestStorage {
        let storage = try fixture()
        let photo = try photoIcon()
        let symbol = try #require(CustomIcon.symbol("moon.fill", backgroundHex: "#1C1C1E"))
        let photoID = try #require(FolderCoverAssetRepository.id(for: photo))
        let symbolID = try #require(FolderCoverAssetRepository.id(for: symbol))
        storage.coverAssets = [photoID: photo, symbolID: symbol]
        let id = try #require(storage.groups.keys.first)
        storage.groups[id]?.items[0].folderCover = FolderCover(standard: photoID, dark: symbolID)
        storage.groups[id]?.items[0].children[0].displayName = "Take photo"
        var nested = GroupItem.folder(name: "Shared dark photo", children: [])
        nested.folderCover = FolderCover(dark: photoID)
        storage.groups[id]?.items[0].children.append(nested)
        return storage
    }

    private static func photoIcon() throws -> CustomIcon {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                                             bytesPerRow: 128, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        let finalized = CGImageDestinationFinalize(destination)
        #expect(finalized)
        return try #require(CustomIcon.photo(pngData: data as Data))
    }
}
