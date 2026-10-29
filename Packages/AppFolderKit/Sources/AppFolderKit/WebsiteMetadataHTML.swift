import CoreFoundation
import Foundation

/// A bounded, non-rendering HTML head reader. It ignores comments and raw-text
/// elements; strings inside scripts cannot manufacture titles or icon requests.
enum WebsiteMetadataHTML {
    struct Parsed: Sendable {
        let title: String?
        let icons: [URL]
    }

    static func decode(_ data: Data, encodingName: String?) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let encodingName, let encoding = encoding(encodingName) {
            if encoding == .utf8 { return String(decoding: data, as: UTF8.self) }
            if let text = String(data: data, encoding: encoding) { return text }
        }
        let prefix = String(decoding: data.prefix(4_096), as: UTF8.self)
        if let name = declaredEncoding(prefix), let encoding = encoding(name) {
            if encoding == .utf8 { return String(decoding: data, as: UTF8.self) }
            if let text = String(data: data, encoding: encoding) { return text }
        }
        // Truncating a large HTML response may split its last UTF-8 character;
        // replacement affects only that tail, never the already closed head.
        return String(decoding: data, as: UTF8.self)
    }

    private static func encoding(_ name: String) -> String.Encoding? {
        let cf = CFStringConvertIANACharSetNameToEncoding(name.trimmingCharacters(in: .whitespacesAndNewlines) as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    private static func declaredEncoding(_ html: String) -> String? {
        let bytes = Array(html.utf8)
        var cursor = 0
        while cursor < bytes.count {
            guard let start = bytes[cursor...].firstIndex(of: 60) else { break }
            if matches(bytes, at: start, text: "<!--") {
                guard let end = find(bytes, text: "-->", from: start + 4) else { break }
                cursor = end + 3
                continue
            }
            guard let end = tagEnd(bytes, from: start + 1) else { break }
            cursor = end + 1
            let tag = attributes(Array(bytes[(start + 1)..<end]))
            if tag.name == "body" || tag.name == "/head" { break }
            if ["script", "style", "noscript", "template", "textarea"].contains(tag.name) {
                guard let closing = closingTag(bytes, name: tag.name, from: cursor) else { break }
                cursor = closing
                continue
            }
            guard tag.name == "meta" else { continue }
            if let charset = tag.values["charset"] { return charset }
            if tag.values["http-equiv"]?.lowercased() == "content-type", let content = tag.values["content"],
               let expression = try? NSRegularExpression(pattern: "(?i)charset\\s*=\\s*[\"']?([a-z0-9._-]+)"),
               let match = expression.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) { return String(content[range]) }
        }
        return nil
    }

    static func parse(_ html: String, baseURL: URL) -> Parsed {
        let bytes = Array(html.utf8)
        var cursor = 0
        var title: String?
        var socialTitle: String?
        var applicationName: String?
        var declaredBase: URL?
        var candidates: [(href: String, score: Int, order: Int)] = []
        var tags = 0
        while cursor < bytes.count && tags < 4_096 {
            guard let start = bytes[cursor...].firstIndex(of: 60) else { break }
            if matches(bytes, at: start, text: "<!--") {
                guard let end = find(bytes, text: "-->", from: start + 4) else { break }
                cursor = end + 3
                continue
            }
            guard let end = tagEnd(bytes, from: start + 1) else { break }
            cursor = end + 1
            tags += 1
            let tag = attributes(Array(bytes[(start + 1)..<end]))
            if tag.name == "body" || tag.name == "/head" { break }
            if ["script", "style", "noscript", "template", "textarea"].contains(tag.name) {
                guard let closing = closingTag(bytes, name: tag.name, from: cursor) else { break }
                cursor = closing
                continue
            }
            if tag.name == "title" {
                guard let closing = closingTag(bytes, name: "title", from: cursor) else { break }
                if title == nil, closing - cursor <= 16_384 {
                    title = normalizedTitle(String(decoding: bytes[cursor..<closing], as: UTF8.self))
                }
                cursor = closing
                continue
            }
            if tag.name == "base", declaredBase == nil, let href = tag.values["href"] {
                declaredBase = resolved(href, relativeTo: baseURL)
            }
            if tag.name == "meta", let content = tag.values["content"] {
                let key = (tag.values["property"] ?? tag.values["name"] ?? "").lowercased()
                if key == "og:title" && socialTitle == nil { socialTitle = normalizedTitle(content, inAttribute: true) }
                if ["application-name", "og:site_name"].contains(key) && applicationName == nil {
                    applicationName = normalizedTitle(content, inAttribute: true)
                }
            }
            if tag.name == "link", candidates.count < 24, let href = tag.values["href"],
               let rel = tag.values["rel"]?.lowercased().split(whereSeparator: \.isWhitespace),
               rel.contains("icon") || rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed") {
                let type = tag.values["type"]?.lowercased() ?? ""
                if type.contains("svg") || href.lowercased().split(separator: "?").first?.hasSuffix(".svg") == true { continue }
                let sizes = (tag.values["sizes"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
                let sides = sizes.compactMap { size -> Int? in
                    let pair = size.split(separator: "x")
                    guard pair.count == 2, let width = Int(pair[0]), let height = Int(pair[1]),
                          width > 0, height > 0, width <= 16_384, height <= 16_384 else { return nil }
                    return min(width, height)
                }
                let side = sides.max() ?? (rel.contains("apple-touch-icon") ? 180 : 32)
                let score = side >= 256 ? 1_000 - min(side - 256, 700) : side
                candidates.append((href, score, candidates.count))
            }
        }
        var seen = Set<String>()
        let icons = candidates.sorted { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }
            .compactMap { resolved($0.href, relativeTo: declaredBase ?? baseURL) }
            .filter { seen.insert($0.absoluteString).inserted }
        return Parsed(title: title ?? socialTitle ?? applicationName, icons: icons)
    }

    static func normalizedTitle(_ raw: String, inAttribute: Bool = false) -> String? {
        let decoded = entities(raw, inAttribute: inAttribute)
        // Normal HTML whitespace is folded. Other controls, bidi overrides and
        // invisible formatting are rejected instead of becoming a stored name.
        guard !decoded.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
        }) else { return nil }
        let collapsed = decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        var result = ""
        for character in collapsed.prefix(SavedGroup.maximumNameLength) {
            let next = String(character)
            guard result.utf8.count + next.utf8.count <= 512 else { break }
            result += next
        }
        return result.isEmpty ? nil : result
    }

    private static func resolved(_ raw: String, relativeTo base: URL) -> URL? {
        let value = entities(raw, inAttribute: true).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= WebsiteURL.maximumUTF8Bytes,
              let url = URL(string: value, relativeTo: base)?.absoluteURL else { return nil }
        return WebsiteURL.validated(url.absoluteString)
    }

    private static func tagEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var quote: UInt8?
        var index = start
        while index < bytes.count && index - start < 16_384 {
            let byte = bytes[index]
            if let current = quote { if byte == current { quote = nil } }
            else if byte == 34 || byte == 39 { quote = byte }
            else if byte == 62 { return index }
            index += 1
        }
        return nil
    }

    private static func attributes(_ bytes: [UInt8]) -> (name: String, values: [String: String]) {
        var cursor = 0
        func whitespace(_ byte: UInt8) -> Bool { [9, 10, 12, 13, 32].contains(byte) }
        while cursor < bytes.count && whitespace(bytes[cursor]) { cursor += 1 }
        let start = cursor
        while cursor < bytes.count && !whitespace(bytes[cursor]) { cursor += 1 }
        let name = String(decoding: bytes[start..<cursor], as: UTF8.self).lowercased()
        var values: [String: String] = [:]
        while cursor < bytes.count && values.count < 32 {
            while cursor < bytes.count && (whitespace(bytes[cursor]) || bytes[cursor] == 47) { cursor += 1 }
            let keyStart = cursor
            while cursor < bytes.count && !whitespace(bytes[cursor]) && bytes[cursor] != 61 { cursor += 1 }
            guard cursor > keyStart else { break }
            let key = String(decoding: bytes[keyStart..<cursor], as: UTF8.self).lowercased()
            while cursor < bytes.count && whitespace(bytes[cursor]) { cursor += 1 }
            guard cursor < bytes.count && bytes[cursor] == 61 else { continue }
            cursor += 1
            while cursor < bytes.count && whitespace(bytes[cursor]) { cursor += 1 }
            guard cursor < bytes.count else { break }
            let quote = bytes[cursor] == 34 || bytes[cursor] == 39 ? bytes[cursor] : nil
            if quote != nil { cursor += 1 }
            let valueStart = cursor
            while cursor < bytes.count {
                if let quote { if bytes[cursor] == quote { break } }
                else if whitespace(bytes[cursor]) { break }
                cursor += 1
            }
            if values[key] == nil { values[key] = String(decoding: bytes[valueStart..<cursor], as: UTF8.self) }
            if quote != nil && cursor < bytes.count { cursor += 1 }
        }
        return (name, values)
    }

    private static func matches(_ bytes: [UInt8], at index: Int, text: String) -> Bool {
        let target = Array(text.utf8)
        guard index + target.count <= bytes.count else { return false }
        return target.indices.allSatisfy { offset in
            let byte = bytes[index + offset]
            return (65...90).contains(byte) ? byte + 32 == target[offset] : byte == target[offset]
        }
    }

    private static func find(_ bytes: [UInt8], text: String, from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        for index in start..<bytes.count where bytes[index] == text.utf8.first {
            if matches(bytes, at: index, text: text) { return index }
        }
        return nil
    }

    private static func closingTag(_ bytes: [UInt8], name: String, from start: Int) -> Int? {
        let text = "</" + name
        var cursor = start
        while let found = find(bytes, text: text, from: cursor) {
            let end = found + text.utf8.count
            if end < bytes.count && [9, 10, 12, 13, 32, 47, 62].contains(bytes[end]) { return found }
            cursor = end
        }
        return nil
    }

    private static func entities(_ value: String, inAttribute: Bool) -> String {
        var result = ""
        // Character references are ASCII token syntax. Walk scalar boundaries
        // so a following combining mark cannot merge with the semicolon and
        // hide it inside one extended grapheme cluster.
        let scalars = value.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if scalars[index] == "&" {
                let start = scalars.index(after: index)
                // Keep numeric references' existing contract. The complete
                // named table below is matched once, never recursively decoded.
                if start < scalars.endIndex, scalars[start] == "#",
                   let end = scalars[start...].prefix(16).firstIndex(of: ";") {
                    let key = String(scalars[start..<end])
                    let hexadecimal = key.hasPrefix("#x") || key.hasPrefix("#X")
                    let digits = key.dropFirst(hexadecimal ? 2 : 1)
                    if let code = UInt32(digits, radix: hexadecimal ? 16 : 10), let scalar = UnicodeScalar(code) {
                        result.unicodeScalars.append(scalar)
                        index = scalars.index(after: end)
                        continue
                    }
                }
                var end = start
                var key = ""
                var match: (text: String, end: String.Index, hasSemicolon: Bool)?
                for _ in 0..<WebsiteMetadataHTMLEntities.maximumNameLength {
                    guard end < scalars.endIndex else { break }
                    let byte = scalars[end].value
                    guard
                          (65...90).contains(byte) || (97...122).contains(byte)
                            || (48...57).contains(byte) || byte == 59 else { break }
                    key.unicodeScalars.append(scalars[end])
                    end = scalars.index(after: end)
                    if let replacement = WebsiteMetadataHTMLEntities.values[key] {
                        match = (replacement, end, byte == 59)
                    }
                    if byte == 59 { break }
                }
                if let match, !(inAttribute && !match.hasSemicolon && ambiguousAttributeSuffix(value, at: match.end)) {
                    result += match.text
                    index = match.end
                    continue
                }
            }
            result.unicodeScalars.append(scalars[index])
            index = scalars.index(after: index)
        }
        return result
    }

    private static func ambiguousAttributeSuffix(_ value: String, at index: String.Index) -> Bool {
        guard index < value.unicodeScalars.endIndex else { return false }
        let byte = value.unicodeScalars[index].value
        return byte == 61 || (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
    }
}
