import Foundation
import Testing
@testable import AppFolderKit

@Suite("App Store artwork mapping")
struct AppStoreMappingTests {
    typealias Mapping = DirectLaunchOverrides.Mapping

    @Test("User input normalizes a supported country, while an absent country preserves legacy lookup")
    func construction() throws {
        let jp = try #require(Mapping(appStoreID: 123, country: " JP \n"))
        #expect(jp.country == "jp" && jp.appStoreID == 123)
        let legacy = try #require(Mapping(appStoreID: 123))
        #expect(legacy.country == nil && legacy != jp)
        #expect(Mapping(appStoreID: 0) == nil && Mapping(appStoreID: -1, country: "jp") == nil)
        for country in ["", "zz", "jpn", "jp&country=us", "j\0p", "../jp"] {
            #expect(Mapping(appStoreID: 123, country: country) == nil)
        }
    }

    @Test("Persisted countries must already be canonical and do not silently repair corrupted source data")
    func strictDecoder() throws {
        let typo = Data(#"{"appStoreID":123,"countryCode":"jp"}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Mapping.self, from: typo) }
        for country: Any in ["JP", " jp ", "zz", "", true, 123] {
            let data = try JSONSerialization.data(withJSONObject: ["appStoreID": 123, "country": country])
            #expect(throws: (any Error).self) { try JSONDecoder().decode(Mapping.self, from: data) }
        }
        for id: Any in [true, -1, 0, 1.5, "123"] {
            let data = try JSONSerialization.data(withJSONObject: ["appStoreID": id, "country": "jp"])
            #expect(throws: (any Error).self) { try JSONDecoder().decode(Mapping.self, from: data) }
        }
        for country in [nil, "jp", "us"] as [String?] {
            let original = try #require(Mapping(appStoreID: 123, country: country))
            let data = try JSONEncoder().encode(original)
            #expect(try JSONDecoder().decode(Mapping.self, from: data) == original)
            if country == nil { #expect(!String(decoding: data, as: UTF8.self).contains("country")) }
        }
    }

    @Test("Strict backup reads accept mixed numeric and complete mapping records but reject any malformed record")
    func rawStorageValidation() throws {
        let legacy = try #require(Mapping(appStoreID: 123))
        let jp = try #require(Mapping(appStoreID: 456, country: "jp"))
        let values: [String: Any] = ["old": 123, "new": ["appStoreID": 456, "country": "jp"]]
        #expect(try DirectLaunchOverrides.validatedBackupMappings(values) == ["old": legacy, "new": jp])
        let invalid: [Any] = [true, 0, -1, 1.5, "123", ["country": "jp"],
                              ["appStoreID": true], ["appStoreID": 123, "country": "JP"],
                              ["appStoreID": 123, "country": "zz"], ["appStoreID": 123, "country": NSNull()],
                              ["appStoreID": 123, "country": "jp", "unknown": 1]]
        for malformed in invalid {
            var mixed = values; mixed["broken"] = malformed
            #expect(throws: LibraryBackupError.exportFailed) { try DirectLaunchOverrides.validatedBackupMappings(mixed) }
        }
    }
}
