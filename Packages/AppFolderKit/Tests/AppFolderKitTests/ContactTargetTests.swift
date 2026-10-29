import Foundation
import Testing
@testable import AppFolderKit

@Suite("Contact target validation")
struct ContactTargetTests {
    @Test("Visual separators and decimal scripts normalize without changing a country's numbering", arguments: [
        ("+1 (202) 555-0100", "+12025550100"),
        ("００８６（０１０）１２３４－５６７８", "008601012345678"),
        ("＋٤٤\u{00A0}٢٠\u{2009}٧١٢٣—٤٥٦٧", "+442071234567"),
        (" 000.123–456 ", "000123456"), ("1", "1"), ("000", "000")
    ])
    func normalization(input: String, expected: String) throws {
        #expect(ContactTarget.normalizedNumber(input) == expected)
        let value = try #require(ContactTarget(operation: .phone, number: input))
        #expect(value.number == expected)
        #expect(try JSONDecoder().decode(ContactTarget.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test("Extensions, control and format characters, multiple-number delimiters and URL injection are rejected", arguments: [
        "", " + ", "( )", "1+2", "++12", "12++", "123x45", "123 ext 45", "123#45", "*123",
        "123,45", "123;45", "123/456", "123 & 456", "tel:123", "123?body=hi", "123%23", "123@host",
        "123\n456", "123\r456", "123\t456", "123\0", "123\u{2028}456", "123\u{2029}456",
        "123\u{202E}456", "123\u{200B}456", "123\u{200D}456", "123\u{FEFF}456", "12²", "Ⅻ", "½"
    ])
    func invalid(input: String) {
        #expect(ContactTarget.normalizedNumber(input) == nil)
        #expect(ContactTarget(operation: .message, number: input) == nil)
    }

    @Test("Resource bounds apply to both raw bytes and canonical digits without imposing country lengths")
    func limits() {
        let digits = String(repeating: "0", count: 64)
        #expect(ContactTarget.normalizedNumber("+" + digits) == "+" + digits)
        #expect(ContactTarget.normalizedNumber(digits + "0") == nil)
        let raw = String(repeating: " ", count: 511) + "1"
        #expect(raw.utf8.count == ContactTarget.maximumInputUTF8Bytes)
        #expect(ContactTarget.normalizedNumber(raw) == "1")
        #expect(ContactTarget.normalizedNumber(" " + raw) == nil)
        let unicodeSpaces = String(repeating: "\u{3000}", count: 170) + "12"
        #expect(unicodeSpaces.utf8.count == 512)
        #expect(ContactTarget.normalizedNumber(unicodeSpaces) == "12")
        #expect(ContactTarget.normalizedNumber(unicodeSpaces + "3") == nil)
    }

    @Test("Persisted endpoints require canonical numbers, a known operation and exactly the declared fields")
    func strictDecode() throws {
        for number in ["+1 (202) 555-0100", "１２３", " 123", "123 ", "123\n", "+", ""] {
            let data = try JSONSerialization.data(withJSONObject: ["operation": "phone", "number": number])
            #expect(throws: (any Error).self) { try JSONDecoder().decode(ContactTarget.self, from: data) }
        }
        for object: [String: Any] in [
            ["operation": "email", "number": "123"], ["operation": "phone", "number": NSNull()],
            ["operation": "phone"], ["number": "123"],
            ["operation": "phone", "number": "123", "extension": "456"]
        ] {
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(ContactTarget.self, from: data) }
        }
    }

    @Test("Each operation creates only its fixed URL and a supported local symbol", arguments: ContactTarget.Operation.allCases)
    func operationURL(operation: ContactTarget.Operation) throws {
        let target = try #require(ContactTarget(operation: operation, number: "+12025550100"))
        let schemes: [ContactTarget.Operation: String] = [.phone: "tel", .message: "sms", .faceTimeAudio: "facetime-audio", .faceTimeVideo: "facetime"]
        #expect(target.url.absoluteString == schemes[operation]! + ":+12025550100")
        #expect(target.url.host == nil && target.url.user == nil && target.url.query == nil && target.url.fragment == nil)
        #expect(CustomIcon.symbol(operation.systemImage) != nil)
        #expect(WebsiteURL.validated(target.url.absoluteString) == nil)
    }
}
