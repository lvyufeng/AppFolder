import Foundation

/// The App Store territories offered by the local search-region picker.
/// This is an explicit storefront list, not every geographic region in Locale.
public enum AppStoreCountry {
    /// Apple's 175 App Store territories, represented by lowercase two-letter codes.
    /// Sources checked 2026-10-29:
    /// https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-store-pricing-and-availability-start-times-by-country-or-region/
    /// https://support.apple.com/en-us/118205
    /// The first table incorrectly labels NER as Nigeria and omits a separate
    /// Niger row. The second lists both App Stores: ne (Niger), ng (Nigeria).
    /// It also uses BO for Bolivia; bo is already the correct two-letter code.
    /// Kosovo uses Apple's xk storefront (https://apps.apple.com/xk/iphone/apps).
    /// Availability here does not guarantee that a particular app is sold there,
    /// or that Search API availability/indexing matches every web storefront.
    public static let supportedCodes: [String] = """
        ae af ag ai al am ao ar at au az ba bb be bf bg bh bj bm bn
        bo br bs bt bw by bz ca cd cg ch ci cl cm cn co cr cv cy cz
        de dk dm do dz ec ee eg es fi fj fm fr ga gb gd ge gh gm gr
        gt gw gy hk hn hr hu id ie il in iq is it jm jo jp ke kg kh
        kn kr kw ky kz la lb lc lk lr lt lu lv ly ma md me mg mk ml
        mm mn mo mr ms mt mu mv mw mx my mz na ne ng ni nl no np nr
        nz om pa pe pg ph pk pl pt pw py qa ro rs ru rw sa sb sc se
        sg si sk sl sn sr st sv sz tc td th tj tm tn to tr tt tw tz
        ua ug us uy uz vc ve vg vn vu xk ye za zm zw
        """.split(whereSeparator: \.isWhitespace).map(String.init)

    private static let supportedCodeSet = Set(supportedCodes)
    private static let englishLocale = Locale(identifier: "en_US")
    private static let searchLocale = Locale(identifier: "en_US_POSIX")

    /// Normalizes user input. Persistent records should additionally require
    /// equality with the original value when decoding canonical country codes.
    public static func normalized(_ input: String) -> String? {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedCodeSet.contains(code) ? code : nil
    }

    public static func isSupported(_ input: String) -> Bool {
        normalized(input) != nil
    }

    public static func displayName(for code: String, locale: Locale = .current) -> String {
        let identifier = code.uppercased()
        return locale.localizedString(forRegionCode: identifier)
            ?? englishLocale.localizedString(forRegionCode: identifier)
            ?? identifier
    }

    /// Searches only local region names, English names and two-letter codes.
    /// Results are sorted by the requested locale, with a stable code tie-break.
    public static func search(query: String, locale: Locale = .current) -> [String] {
        let terms = folded(query).split(whereSeparator: \.isWhitespace).map(String.init)
        return supportedCodes.compactMap { code -> (code: String, name: String)? in
            let name = displayName(for: code, locale: locale)
            let englishName = displayName(for: code, locale: englishLocale)
            let searchable = folded("\(code) \(name) \(englishName)")
            guard terms.allSatisfy(searchable.contains) else { return nil }
            return (code, name)
        }.sorted { lhs, rhs in
            let order = lhs.name.compare(rhs.name, options: [.caseInsensitive], locale: locale)
            return order == .orderedSame ? lhs.code < rhs.code : order == .orderedAscending
        }.map(\.code)
    }

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: searchLocale)
    }
}

/// A search preference on this device, separate from persisted per-app mappings.
/// Automatic preserves the existing US-then-China search order. It does not
/// inspect or change an Apple Account, device region or StoreKit storefront.
public struct AppStoreSearchRegion: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public static let automatic = Self(uncheckedRawValue: "automatic")

    public init?(rawValue: String) {
        guard rawValue == Self.automatic.rawValue
            || AppStoreCountry.normalized(rawValue) == rawValue else { return nil }
        self.rawValue = rawValue
    }

    public init?(countryCode: String) {
        guard let code = AppStoreCountry.normalized(countryCode) else { return nil }
        self.rawValue = code
    }

    public var countryCode: String? {
        self == .automatic ? nil : rawValue
    }

    public var queryCountries: [String] {
        countryCode.map { [$0] } ?? ["us", "cn"]
    }

    private init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }
}
