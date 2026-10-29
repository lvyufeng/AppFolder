import Darwin
import Foundation

/// The same URL contract is used by the editor, decoded layouts and widget taps.
/// It validates syntax locally; it never resolves DNS or fetches a website.
public enum WebsiteURL {
    public static let maximumUTF8Bytes = 2_048

    /// Converts a person's input into an absolute website URL. Unknown schemes
    /// are rejected rather than silently becoming an HTTPS hostname.
    public static func normalized(_ input: String) -> String? {
        guard input.utf8.count <= maximumUTF8Bytes, !hasControls(input),
              !input.contains("\\"), validPercentEscapes(input) else { return nil }
        let value = input.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        let candidate: String
        if value.hasPrefix("//") {
            candidate = "https:" + value
        } else if let colon = schemeSeparator(in: value) {
            let prefix = String(value[..<colon])
            if ["http", "https"].contains(prefix.lowercased()) {
                guard value[colon...].hasPrefix("://") else { return nil }
                candidate = value
            } else {
                // A dotted host or localhost followed by a numeric port is an
                // unambiguous host:port input. For other single-label hosts,
                // require an explicit https:// so javascript:123 stays invalid.
                let afterColon = value[value.index(after: colon)...]
                let port = afterColon.prefix { !"/?#".contains($0) }
                guard (prefix.contains(".") || prefix.lowercased() == "localhost"),
                      validPort(port) else { return nil }
                candidate = "https://" + value
            }
        } else {
            candidate = "https://" + value
        }
        // Foundation performs IDNA and percent-encodes literal path characters.
        // Malformed percent sequences were rejected above, before it can repair
        // them into a different address. The stored result must pass strict use.
        guard let encoded = URL(string: candidate)?.absoluteString,
              validated(encoded) != nil else { return nil }
        return encoded
    }

    /// Validates a stored absolute HTTP(S) address without trimming it or adding
    /// a scheme. Unicode domains and paths are encoded by Foundation; existing
    /// path/query case, escaped delimiters, query order and fragments survive.
    public static func validated(_ stored: String) -> URL? {
        guard !stored.isEmpty, stored.utf8.count <= maximumUTF8Bytes,
              !hasControls(stored), !stored.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              !stored.contains("\\"), validPercentEscapes(stored),
              // These ASCII characters require escaping in a stored URI. Unlike
              // the input normalizer, this path must not silently repair them.
              !stored.contains(where: { "\"<>^`{|}".contains($0) }),
              let separator = stored.range(of: "://"),
              ["http", "https"].contains(stored[..<separator.lowerBound].lowercased()) else { return nil }
        let authority = stored[separator.upperBound...].prefix { !"/?#".contains($0) }
        guard !authority.isEmpty, !authority.contains("@"),
              let url = URL(string: stored), url.absoluteString.utf8.count <= maximumUTF8Bytes,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil else { return nil }

        if authority.first == "[" {
            guard let end = authority.firstIndex(of: "]") else { return nil }
            let literal = authority[authority.index(after: authority.startIndex)..<end]
            let remainder = authority[authority.index(after: end)...]
            guard validIPv6(literal), validPortSuffix(remainder) else { return nil }
        } else {
            let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), !parts[0].isEmpty,
                  !parts[0].contains("%"), !parts[0].contains("["), !parts[0].contains("]"),
                  parts.count == 1 || validPort(parts[1]),
                  let host = url.host(percentEncoded: false), validHost(host) else { return nil }
        }
        return url
    }

    private static func hasControls(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validPercentEscapes(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        var index = 0
        func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: byte - 48
            case 65...70: byte - 65 + 10
            case 97...102: byte - 97 + 10
            default: nil
            }
        }
        while index < bytes.count {
            if bytes[index] == 37 {
                guard index + 2 < bytes.count,
                      let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) else { return false }
                let decoded = high * 16 + low
                guard decoded >= 32, decoded != 127 else { return false }
                index += 3
            } else { index += 1 }
        }
        // Also reject percent-encoded Unicode controls when decoding succeeds;
        // arbitrary non-UTF8 escaped bytes remain valid URI data.
        return value.removingPercentEncoding.map { !hasControls($0) } ?? true
    }

    private static func schemeSeparator(in value: String) -> String.Index? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let prefix = value[..<colon].utf8
        guard let first = prefix.first, (65...90).contains(first) || (97...122).contains(first),
              prefix.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || [43, 45, 46].contains($0) }) else { return nil }
        return colon
    }

    private static func validPort(_ value: Substring) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
            && Int(value).map { (1...65_535).contains($0) } == true
    }

    private static func validPortSuffix(_ value: Substring) -> Bool {
        value.isEmpty || (value.first == ":" && validPort(value.dropFirst()))
    }

    private static func validIPv6(_ value: Substring) -> Bool {
        var address = String(value)
        if let marker = address.range(of: "%25") {
            let zone = address[marker.upperBound...]
            guard !zone.isEmpty, zone.utf8.count <= 63,
                  zone.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                      || (48...57).contains($0) || [45, 46, 95, 126].contains($0) }) else { return false }
            address = String(address[..<marker.lowerBound])
        }
        var destination = in6_addr()
        return address.withCString { inet_pton(AF_INET6, $0, &destination) == 1 }
    }

    private static func validHost(_ host: String) -> Bool {
        let value = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard !value.isEmpty, value.utf8.count <= 253 else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        let last = labels.last ?? ""
        let endsInDecimal = !last.isEmpty && last.utf8.allSatisfy { (48...57).contains($0) }
        let hexadecimal = last.lowercased()
        let endsInHexadecimal = hexadecimal.hasPrefix("0x") && hexadecimal.count > 2
            && hexadecimal.dropFirst(2).utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        if endsInDecimal || endsInHexadecimal {
            // Browsers treat numeric-ending hosts as IPv4 candidates, including
            // shorthand, octal and hexadecimal forms. Require four decimal
            // octets so the displayed address cannot route to a different IP.
            return labels.count == 4 && labels.allSatisfy {
                !$0.isEmpty && ($0.count == 1 || $0.first != "0")
                    && $0.utf8.allSatisfy { (48...57).contains($0) }
                    && Int($0).map { (0...255).contains($0) } == true
            }
        }
        return labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0)
                    || (48...57).contains($0) || $0 == 45 }
        }
    }
}
