import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved website browser choices")
struct SavedGroupWebsiteBrowserTests {
    @Test("Legacy websites keep their JSON and revisions; changing only the browser participates in persistence and undo")
    func legacyAndHistory() throws {
        let legacy = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","items":[{"children":[],"id":"00000000-0000-0000-0000-000000000002","kind":"website","name":"Example","websiteURL":"https://example.org/path?q=A%2BB#fragment"}],"name":"Links","updatedAt":0}
        """.utf8)
        let decoder = JSONDecoder()
        let original = try decoder.decode(SavedGroup.self, from: legacy)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        #expect(try encoder.encode(original) == legacy)
        #expect(original.items[0].websiteBrowser == nil && original.items[0].effectiveWebsiteBrowser == .systemDefault)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WebsiteBrowser-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SavedGroupRepository(directory: directory)
        #expect(repository.save(original))
        let oldRevision = original.revision
        var changed = original
        changed.items[0].websiteBrowser = .chrome
        #expect(changed.revision != oldRevision)
        #expect(repository.save(changed) && repository.group(id: changed.id) == changed)
        var history = SavedGroupEditHistory()
        let recorded = history.record(before: original, after: changed)
        #expect(recorded)
        #expect(history.undo(current: changed) == original)
        #expect(history.redo(current: original) == changed)
        changed.items[0].websiteBrowser = nil
        #expect(changed.revision == oldRevision && changed == original)
        #expect(try encoder.encode(changed) == legacy)
    }

    @Test("Only websites may carry browser fields, including explicit null; unknown modes fail decoding")
    func strictSchema() throws {
        let target = try #require(ContactTarget(operation: .message, number: "+12025550100"))
        let nonWebsites: [GroupItem] = [.action(name: "Camera"), .folder(name: "Tools"), .spacer(), .contact(name: "Person", target: target)]
        for original in nonWebsites {
            var invalid = original
            invalid.websiteBrowser = .chrome
            #expect(!SavedGroup(name: "Invalid", items: [invalid]).isValid)
            let base = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            for field: Any in ["chrome", "systemDefault", "appDefault", NSNull()] {
                var json = base
                json["websiteBrowser"] = field
                #expect(throws: (any Error).self) {
                    try JSONDecoder().decode(GroupItem.self, from: JSONSerialization.data(withJSONObject: json))
                }
            }
        }
        let website = GroupItem.website(name: "Site", url: "https://example.org")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(website)) as? [String: Any])
        json["websiteBrowser"] = "unsupportedBrowser"
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(GroupItem.self, from: JSONSerialization.data(withJSONObject: json))
        }
        for browser in WebsiteBrowser.allCases {
            let item = GroupItem.website(name: "Site", url: "https://example.org", browser: browser)
            #expect(SavedGroup(name: "Valid", items: [item]).isValid)
            #expect(try JSONDecoder().decode(GroupItem.self, from: JSONEncoder().encode(item)) == item)
        }
    }
}

@Suite("Website browser backup compatibility")
struct LibraryBackupWebsiteBrowserTests {
    @Test("Full and group exports preserve browser choices and raw URLs through independent imported copies")
    func importCopies() throws {
        let source = try BackupTestStorage.coverFixture()
        let id = try #require(source.groups.keys.first)
        let icon = try #require(source.groups[id]?.items.first?.folderCover)
        let sites = WebsiteBrowser.allCases.map {
            GroupItem.website(name: $0.displayName, url: "https://example.org/a%2Fb?q=A%2BB&x=1&x=2#part", icon: icon, browser: $0)
        } + [.website(name: "Legacy", url: "https://example.org")]
        source.groups[id]?.items.append(.folder(name: "Sites", children: sites))
        let original = try #require(source.groups[id])
        let engine = LibraryBackupEngine(storage: source)
        for data in [try engine.exportData(), try engine.exportData(groupID: id)] {
            let header = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(header["version"] as? Int == 16)
            let document = try LibraryBackup.decode(data)
            #expect(document.groups == [original])
            let destination = BackupTestStorage()
            let importer = LibraryBackupEngine(storage: destination)
            let result = importer.apply(importer.prepareImport(document))
            #expect(result.status == .completed)
            let imported = try #require(result.groups.first)
            let copies = try #require(imported.items.last?.children)
            #expect(copies.count == sites.count && imported.id != id)
            for (copy, site) in zip(copies, sites) {
                #expect(copy.id != site.id && copy.websiteBrowser == site.websiteBrowser)
                #expect(copy.websiteURL == site.websiteURL && copy.websiteIcon == site.websiteIcon)
            }
            #expect(source.groups[id] == original)
        }
    }

    @Test("Versions one through twelve remain readable and cannot smuggle any browser field presence")
    func legacyEnvelopes() throws {
        for version in 1...12 {
            let source = try BackupTestStorage.fixture()
            let id = try #require(source.groups.keys.first)
            let leaf = version >= 6 ? GroupItem.website(name: "Site", url: "https://example.org") : .action(name: "Camera")
            source.groups[id]?.items = [.folder(name: "Outer", children: [leaf])]
            if version >= 9 {
                let target = try #require(ContactTarget(operation: .message, number: "+12025550100"))
                source.groups[id]?.items.append(.contact(name: "Person", target: target))
            }
            var envelope = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
            envelope["version"] = version
            envelope.removeValue(forKey: "appearancePresets")
            if version < 12 { envelope.removeValue(forKey: "actionLibrary") }
            if version < 5 { envelope.removeValue(forKey: "coverAssets") }
            #expect(try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)).groups == Array(source.groups.values))
            for depth in [0, 1] {
                for field: Any in ["chrome", "systemDefault", "appDefault", NSNull()] {
                    var changed = envelope
                    var groups = try #require(changed["groups"] as? [[String: Any]])
                    var items = try #require(groups[0]["items"] as? [[String: Any]])
                    if depth == 0 { items[0]["websiteBrowser"] = field }
                    else {
                        var children = try #require(items[0]["children"] as? [[String: Any]])
                        children[0]["websiteBrowser"] = field
                        items[0]["children"] = children
                    }
                    groups[0]["items"] = items
                    changed["groups"] = groups
                    #expect(throws: LibraryBackupError.invalidContents) {
                        try LibraryBackup.decode(JSONSerialization.data(withJSONObject: changed))
                    }
                }
            }
        }
    }

    @Test("Version thirteen accepts only its original concrete choices or nil and rejects follow-app at every tree boundary")
    func versionThirteenBoundary() throws {
        for depth in [0, SavedGroup.maximumDepth] {
            let source = BackupTestStorage()
            let website = GroupItem.website(name: "Site", url: "https://example.org/a%2Fb?q=A%2BB#part")
            var node = website
            for level in 0..<depth { node = .folder(name: "Folder \(level)", children: [node]) }
            let group = SavedGroup(name: "Version thirteen", items: [node])
            source.groups[group.id] = group
            var envelope = try #require(JSONSerialization.jsonObject(with: LibraryBackupEngine(storage: source).exportData()) as? [String: Any])
            envelope["version"] = 13
            envelope.removeValue(forKey: "appearancePresets")

            func payload(browser: Any?) throws -> Data {
                var changed = envelope
                var groups = try #require(changed["groups"] as? [[String: Any]])
                func inserting(_ nodes: [[String: Any]], remaining: Int) throws -> [[String: Any]] {
                    var result = nodes
                    if remaining == 0 { result[0]["websiteBrowser"] = browser }
                    else {
                        let children = try #require(result[0]["children"] as? [[String: Any]])
                        result[0]["children"] = try inserting(children, remaining: remaining - 1)
                    }
                    return result
                }
                groups[0]["items"] = try inserting(try #require(groups[0]["items"] as? [[String: Any]]), remaining: depth)
                changed["groups"] = groups
                return try JSONSerialization.data(withJSONObject: changed)
            }

            for browser in WebsiteBrowser.concreteCases {
                let document = try LibraryBackup.decode(payload(browser: browser.rawValue))
                let restored = try #require(document.groups.first)
                let item = try #require(WebsiteLaunchRoute(groupID: group.id, itemID: website.id).resolve(in: restored))
                #expect(item.websiteBrowser == browser && item.websiteURL == website.websiteURL)
            }
            for value: Any? in [nil, NSNull()] {
                let document = try LibraryBackup.decode(payload(browser: value))
                let restored = try #require(document.groups.first)
                let item = try #require(WebsiteLaunchRoute(groupID: group.id, itemID: website.id).resolve(in: restored))
                #expect(item.websiteBrowser == nil && item.effectiveWebsiteBrowser == .systemDefault)
            }
            for invalid: Any in ["appDefault", "futureBrowser", 3, ["chrome"]] {
                #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(payload(browser: invalid)) }
            }
        }
    }

    @Test("A follow-app choice travels in a backup and resolves against the importing device's untouched local preference")
    func portableFollowChoice() throws {
        let firstSuite = "WebsiteBrowserBackup.source.\(UUID())"
        let secondSuite = "WebsiteBrowserBackup.destination.\(UUID())"
        let sourceDefaults = try #require(UserDefaults(suiteName: firstSuite))
        let destinationDefaults = try #require(UserDefaults(suiteName: secondSuite))
        defer {
            sourceDefaults.removePersistentDomain(forName: firstSuite)
            destinationDefaults.removePersistentDomain(forName: secondSuite)
        }
        #expect(WebsiteBrowserSettings.setBrowser(.chrome, in: sourceDefaults))
        #expect(WebsiteBrowserSettings.setBrowser(.firefox, in: destinationDefaults))
        let sourcePreference = sourceDefaults.persistentDomain(forName: firstSuite) ?? [:]
        let destinationPreference = destinationDefaults.persistentDomain(forName: secondSuite) ?? [:]
        let original = SavedGroup(name: "Portable", items: [.website(name: "Site", url: "https://example.org/", browser: .appDefault)])
        #expect(original.items[0].effectiveWebsiteBrowser.resolved(using: WebsiteBrowserSettings.selectedBrowser(in: sourceDefaults)) == .chrome)
        let source = BackupTestStorage()
        source.groups[original.id] = original
        let data = try LibraryBackupEngine(storage: source).exportData()
        let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(envelope.keys) == ["format", "version", "createdAt", "groups", "icons", "mappings", "coverAssets", "actionLibrary", "appearancePresets"])
        #expect(!String(decoding: data, as: UTF8.self).contains(WebsiteBrowserSettings.defaultsKey))
        let destination = BackupTestStorage()
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(try LibraryBackup.decode(data)))
        #expect(result.status == .completed)
        let imported = try #require(result.groups.first?.items.first)
        #expect(imported.id != original.items[0].id && imported.websiteBrowser == .appDefault)
        #expect(imported.effectiveWebsiteBrowser.resolved(using: WebsiteBrowserSettings.selectedBrowser(in: destinationDefaults)) == .firefox)
        #expect(NSDictionary(dictionary: sourcePreference).isEqual(to: sourceDefaults.persistentDomain(forName: firstSuite) ?? [:]))
        #expect(NSDictionary(dictionary: destinationPreference).isEqual(to: destinationDefaults.persistentDomain(forName: secondSuite) ?? [:]))
    }
}
