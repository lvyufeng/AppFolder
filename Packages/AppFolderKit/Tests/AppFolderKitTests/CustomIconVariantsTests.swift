import Foundation
import Testing
@testable import AppFolderKit

@Suite("Custom icon appearance variants")
struct CustomIconVariantsTests {
    @Test("Missing variants preserve automatic artwork and dark inherits standard")
    func fallback() throws {
        let standard = try #require(CustomIcon.symbol("sun.max.fill"))
        let dark = try #require(CustomIcon.symbol("moon.fill", backgroundHex: "#000000"))
        let both = CustomIconVariants(standard: standard, dark: dark)
        #expect(both.isValid && !both.containsPhoto)
        #expect(both.resolved(isDark: false) == standard)
        #expect(both.resolved(isDark: true) == dark)
        let standardOnly = CustomIconVariants(standard: standard)
        #expect(standardOnly.resolved(isDark: true) == standard)
        #expect(standardOnly.dark == nil)
        let darkOnly = CustomIconVariants(dark: dark)
        #expect(darkOnly.isValid)
        #expect(darkOnly.resolved(isDark: false) == nil)
        #expect(darkOnly.resolved(isDark: true) == dark)
        #expect(!CustomIconVariants().isValid)
        #expect(CustomIconVariants().thumbnail() == nil)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CustomIconVariants.self, from: Data("{}".utf8))
        }
        #expect(try JSONDecoder().decode(CustomIconVariants.self, from: JSONEncoder().encode(both)) == both)
    }

    @Test("Legacy records read without migration and dark-only records remain discoverable")
    func legacyAndCandidates() throws {
        try withRepository { repository, directory in
            let standard = try #require(CustomIcon.emoji("AB"))
            #expect(repository.set(standard, name: "Legacy"))
            let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            let oldData = try Data(contentsOf: file)
            let oldJSON = try #require(JSONSerialization.jsonObject(with: oldData) as? [String: Any])
            #expect(Set(oldJSON.keys) == ["name", "icon"])
            let reopened = CustomIconRepository(directory: directory)
            #expect(reopened.variants(name: "LEGACY") == CustomIconVariants(standard: standard))
            #expect(try Data(contentsOf: file) == oldData)

            let moon = try #require(CustomIcon.symbol("moon.fill"))
            let darkOnly = CustomIconVariants(dark: moon)
            #expect(repository.setVariants(darkOnly, name: "  Night Action  "))
            #expect(reopened.icon(name: "night action") == nil)
            #expect(reopened.containsRecord(name: "night action"))
            #expect(reopened.all["night action"] == darkOnly)
            #expect(reopened.displayNames["night action"] == "Night Action")
            #expect(try reopened.backupRecords().first { $0.name == "Night Action" }?.icon == darkOnly)
        }
    }

    @Test("Clearing one side keeps the other; clearing the whole record removes it")
    func independentUpdates() throws {
        try withRepository { repository, _ in
            let standard = try #require(CustomIcon.symbol("sun.max.fill"))
            let dark = try #require(CustomIcon.symbol("moon.fill"))
            let pair = CustomIconVariants(standard: standard, dark: dark)
            #expect(repository.setVariants(pair, name: "Action"))
            let revision = repository.revision
            #expect(repository.setVariants(pair, name: "Action"))
            #expect(repository.revision == revision)
            #expect(repository.setVariants(CustomIconVariants(standard: standard), name: "Action"))
            #expect(repository.variants(name: "Action") == CustomIconVariants(standard: standard))
            #expect(repository.revision != revision)
            // Selecting an App Store standard image leaves the independent dark image.
            #expect(repository.setVariants(CustomIconVariants(dark: dark), name: "Action"))
            #expect(repository.variants(name: "Action")?.dark == dark)
            #expect(repository.icon(name: "Action") == nil)
            #expect(repository.setVariants(nil, name: "Action"))
            #expect(repository.setVariants(nil, name: "Action"))
            #expect(!repository.containsRecord(name: "Action"))
            #expect(repository.all.isEmpty && repository.displayNames.isEmpty)
        }
    }

    @Test("Invalid pairs and failed atomic writes leave both saved appearances intact")
    func failedUpdates() throws {
        try withRepository { repository, directory in
            let a = try #require(CustomIcon.symbol("sun.max.fill"))
            let b = try #require(CustomIcon.symbol("moon.fill"))
            let original = CustomIconVariants(standard: a, dark: b)
            #expect(repository.setVariants(original, name: "Action"))
            let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            let bytes = try Data(contentsOf: file)
            #expect(!repository.setVariants(CustomIconVariants(), name: "Action"))
            #expect(repository.variants(name: "Action") == original)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
            #expect(!repository.setVariants(CustomIconVariants(standard: b, dark: a), name: "Action"))
            #expect(try Data(contentsOf: file) == bytes)
            #expect(repository.variants(name: "Action") == original)
        }
    }

    @Test("Legacy replacement explicitly clears dark while malformed dark data cannot bypass validation")
    func compatibilityAndValidation() throws {
        try withRepository { repository, directory in
            let standard = try #require(CustomIcon.symbol("sun.max.fill"))
            let dark = try #require(CustomIcon.symbol("moon.fill"))
            #expect(repository.setVariants(CustomIconVariants(standard: standard, dark: dark), name: "Action"))
            #expect(repository.set(standard, name: "Action"))
            #expect(repository.variants(name: "Action") == CustomIconVariants(standard: standard))
            let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            let bytes = try Data(contentsOf: file)
            var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            json["darkIcon"] = ["kind": "photo", "value": "", "backgroundHex": "#000000", "pngData": "bm90IHBob3Rv"]
            let corrupt = try JSONSerialization.data(withJSONObject: json)
            try corrupt.write(to: file)
            #expect(repository.variants(name: "Action") == nil)
            #expect(repository.containsRecord(name: "Action"))
            #expect(throws: LibraryBackupError.exportFailed) { try repository.backupRecords() }
            #expect(try Data(contentsOf: file) == corrupt)
        }
    }

    private func withRepository(_ body: (CustomIconRepository, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IconVariants-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(CustomIconRepository(directory: directory), directory)
    }
}
