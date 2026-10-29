import Foundation
import Testing
@testable import AppFolderKit

@Suite("Custom icon symbol catalog")
struct CustomIconSymbolCatalogTests {
    typealias Catalog = CustomIconSymbolCatalog

    @Test("The original seventy symbols remain the ordered prefix of one complete unique allowlist")
    func catalogIntegrity() {
        #expect(Array(Catalog.entries.prefix(70).map(\.id)) == Self.legacySymbols)
        #expect(CustomIcon.symbols == Catalog.entries.map(\.id))
        #expect((140...170).contains(Catalog.entries.count))
        #expect(Set(Catalog.entries.map(\.id)).count == Catalog.entries.count)
        #expect(Catalog.Category.allCases.count == 10)
        for category in Catalog.Category.allCases {
            #expect(!category.titleKey.isEmpty && category.id == category.rawValue)
            #expect(Catalog.entries.contains { $0.category == category })
        }
        for entry in Catalog.entries {
            #expect(!entry.titleKey.isEmpty && entry.titleKey == entry.titleKey.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect(entry.keywords.contains { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } })
            #expect(entry.keywords.contains { $0.unicodeScalars.contains { (0x61...0x7A).contains($0.value) } })
            #expect(entry.keywords.allSatisfy { !$0.isEmpty && !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } })
            #expect(Catalog.entry(id: entry.id) == entry)
        }
    }

    @Test("Every offered symbol round-trips through the existing icon schema with its exact name and color")
    func persistenceCompatibility() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for entry in Catalog.entries {
            let icon = try #require(CustomIcon.symbol(entry.id, backgroundHex: "#123456"))
            let encoded = try encoder.encode(icon)
            #expect(try JSONDecoder().decode(CustomIcon.self, from: encoded) == icon)
            let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(Set(object.keys) == ["kind", "value", "backgroundHex"])
            #expect(object["value"] as? String == entry.id && object["backgroundHex"] as? String == "#123456")
        }
        let oldBytes = Data(##"{"backgroundHex":"#123456","kind":"symbol","value":"star.fill"}"##.utf8)
        let old = try JSONDecoder().decode(CustomIcon.self, from: oldBytes)
        #expect(try encoder.encode(old) == oldBytes)
        for unknown in ["not.a.symbol", "STAR.FILL", "star.fill ", "", "../../phone.fill"] {
            #expect(Catalog.entry(id: unknown) == nil && CustomIcon.symbol(unknown) == nil)
            let data = try JSONSerialization.data(withJSONObject: ["kind": "symbol", "value": unknown, "backgroundHex": "#123456"])
            #expect(throws: (any Error).self) { try JSONDecoder().decode(CustomIcon.self, from: data) }
        }
    }

    @Test("Empty and Unicode whitespace searches preserve catalog or selected-category order")
    func emptyAndCategory() {
        for query in ["", " \n\t", "\u{3000}\u{00A0}\u{2009}"] {
            #expect(Catalog.search(query: query) == Catalog.entries)
            for category in Catalog.Category.allCases {
                #expect(Catalog.search(query: query, category: category) == Catalog.entries.filter { $0.category == category })
            }
        }
        #expect(Catalog.search(query: "phone", category: .nature).isEmpty)
        #expect(Catalog.search(query: "phone", category: .communication).allSatisfy { $0.category == .communication })
    }

    @Test("Search combines Chinese and English synonyms, exact SF names and AND terms without reordering")
    func textSearch() {
        #expect(Catalog.search(query: "拨出 电话").map(\.id) == ["phone.arrow.up.right"])
        #expect(Catalog.search(query: "phone outgoing").map(\.id) == ["phone.arrow.up.right"])
        #expect(Catalog.search(query: "camera photo").map(\.id) == ["camera.fill"])
        #expect(Catalog.search(query: "photo camera") == Catalog.search(query: "camera photo"))
        #expect(Catalog.search(query: "camera no-such-term").isEmpty)
        #expect(Catalog.search(query: "cup.and.saucer.fill").map(\.id) == ["cup.and.saucer.fill"])
        #expect(Catalog.search(query: "收件盘").map(\.id) == ["tray.fill"])
        #expect(Catalog.search(query: "备忘录").contains { $0.id == "note.text" })
        for (title, id) in [("指南针", "safari.fill"), ("两个人", "person.2.fill"), ("调色板", "paintpalette.fill")] {
            #expect(Catalog.entry(id: id)?.titleKey == title)
            #expect(Catalog.search(query: title).map(\.id) == [id])
        }
        let results = Catalog.search(query: "photo")
        #expect(results == Catalog.entries.filter { Set(results.map(\.id)).contains($0.id) })
        #expect(Set(results.map(\.id)).count == results.count)
        #expect(results == Catalog.search(query: "photo photo"))
    }

    @Test("Case, accents and full-width text fold consistently without altering stored IDs")
    func unicodeSearch() {
        let baseline = Catalog.search(query: "camera photo")
        for query in ["CAMERA PHOTO", "cámera phóto", "ＣＡＭＥＲＡ　ＰＨＯＴＯ", "ca\u{0301}mera\tphoto"] {
            #expect(Catalog.search(query: query) == baseline)
        }
        #expect(Catalog.search(query: "ＰＨＯＮＥ．ＡＲＲＯＷ．ＵＰ．ＲＩＧＨＴ").map(\.id) == ["phone.arrow.up.right"])
        #expect(Catalog.entry(id: "ＣＡＭＥＲＡ．ＦＩＬＬ") == nil)
    }

    @Test("Localized entry and category titles participate; the resolver receives only declared source keys")
    func localizedSearch() throws {
        let camera = try #require(Catalog.entry(id: "camera.fill"))
        let coffee = try #require(Catalog.entry(id: "cup.and.saucer.fill"))
        let translations = [camera.titleKey: "Appareil photo", coffee.titleKey: "Café",
                            Catalog.Category.technology.titleKey: "Équipement"]
        var requested = Set<String>()
        let localize: (String) -> String = { key in
            requested.insert(key)
            return translations[key] ?? key
        }
        #expect(Catalog.search(query: "APPAREIL photo", localizedText: localize).map(\.id) == [camera.id])
        #expect(Catalog.search(query: "cafe coffee", localizedText: localize).map(\.id) == [coffee.id])
        #expect(Catalog.search(query: "ＥＱＵＩＰＥＭＥＮＴ", localizedText: localize)
                == Catalog.entries.filter { $0.category == .technology })
        #expect(Catalog.search(query: "appareil", category: .nature, localizedText: localize).isEmpty)
        let allowed = Set(Catalog.entries.map(\.titleKey) + Catalog.Category.allCases.map(\.titleKey))
        #expect(!requested.isEmpty && requested.isSubset(of: allowed))
        #expect(!requested.contains("APPAREIL photo"))
    }

    private static let legacySymbols = [
        "star.fill", "heart.fill", "bolt.fill", "moon.fill", "sun.max.fill",
        "house.fill", "briefcase.fill", "book.fill", "bookmark.fill", "graduationcap.fill",
        "paperplane.fill", "envelope.fill", "bubble.left.and.bubble.right.fill", "phone.fill", "person.fill",
        "person.2.fill", "camera.fill", "photo.fill", "video.fill", "music.note",
        "headphones", "play.fill", "gamecontroller.fill", "film.fill", "paintpalette.fill",
        "pencil", "note.text", "checklist", "calendar", "clock.fill",
        "timer", "bell.fill", "gearshape.fill", "wrench.and.screwdriver.fill", "lock.fill",
        "key.fill", "shield.fill", "qrcode", "barcode", "doc.fill",
        "folder.fill", "tray.fill", "archivebox.fill", "externaldrive.fill", "network",
        "globe", "safari.fill", "map.fill", "location.fill", "car.fill",
        "bicycle", "airplane", "tram.fill", "figure.walk", "figure.run",
        "cart.fill", "bag.fill", "creditcard.fill", "gift.fill", "cup.and.saucer.fill",
        "fork.knife", "leaf.fill", "flame.fill", "drop.fill", "pawprint.fill",
        "cross.case.fill", "pills.fill", "dumbbell.fill", "lightbulb.fill", "wifi",
    ]
}
