import Foundation

/// A single, explicitly chosen phone endpoint. It is a local snapshot, not a
/// Contacts identifier or permission to read/update the address book.
public struct ContactTarget: Codable, Sendable, Equatable {
    public enum Operation: String, Codable, Sendable, CaseIterable {
        case phone, message, faceTimeAudio, faceTimeVideo

        public var systemImage: String {
            switch self {
            case .phone: "phone.fill"
            case .message: "bubble.left.and.bubble.right.fill"
            case .faceTimeAudio: "phone.fill"
            case .faceTimeVideo: "video.fill"
            }
        }

        fileprivate var scheme: String {
            switch self {
            case .phone: "tel"
            case .message: "sms"
            case .faceTimeAudio: "facetime-audio"
            case .faceTimeVideo: "facetime"
            }
        }
    }

    public static let maximumInputUTF8Bytes = 512
    /// A resource bound, not a country's telephone-number validation rule.
    public static let maximumDigits = 64
    public let operation: Operation
    public let number: String

    public init?(operation: Operation, number: String) {
        guard let number = Self.normalizedNumber(number) else { return nil }
        self.operation = operation
        self.number = number
    }

    /// Accept decimal digits, one leading plus, and visual phone separators.
    /// Never infer a country code, discard a trunk zero, or cut off an extension.
    /// Pause/wait syntax, multiple numbers and URL syntax fail as a whole.
    public static func normalizedNumber(_ input: String) -> String? {
        guard !input.isEmpty, input.utf8.count <= maximumInputUTF8Bytes else { return nil }
        var output = ""
        var digits = 0
        for scalar in input.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                return nil
            case .spaceSeparator:
                continue
            case .decimalNumber:
                guard let value = scalar.properties.numericValue, value >= 0, value <= 9 else { return nil }
                digits += 1
                guard digits <= maximumDigits else { return nil }
                output.append(String(Int(value)))
            default:
                switch scalar.value {
                case 0x2B, 0xFF0B: // ASCII/full-width plus.
                    guard output.isEmpty else { return nil }
                    output.append("+")
                case 0x28, 0x29, 0x2D, 0x2E, // Parentheses, hyphen and period.
                     0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2212,
                     0xFF08, 0xFF09, 0xFF0D, 0xFF0E:
                    continue
                default:
                    return nil
                }
            }
        }
        return digits > 0 ? output : nil
    }

    /// The scheme is fixed by the operation; canonical numbers contain only
    /// ASCII digits and an optional leading plus, so URL construction cannot fail.
    /// Constructing the URL never opens it or performs a communication action.
    public var url: URL { URL(string: operation.scheme + ":" + number)! }

    private enum CodingKeys: String, CodingKey, CaseIterable { case operation, number }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: any Decoder) throws {
        let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
        guard keys == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid contact target fields"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let operation = try values.decode(Operation.self, forKey: .operation)
        let number = try values.decode(String.self, forKey: .number)
        guard Self.normalizedNumber(number) == number, let target = Self(operation: operation, number: number) else {
            throw DecodingError.dataCorruptedError(forKey: .number, in: values, debugDescription: "Contact number must be canonical")
        }
        self = target
    }
}
