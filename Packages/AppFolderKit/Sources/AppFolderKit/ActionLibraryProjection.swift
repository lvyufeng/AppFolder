import Foundation

/// Evidence of a name, not proof of installation or a current widget binding.
public enum ActionLibrarySource: String, Sendable, Hashable, CaseIterable {
    case library, observedWidget, savedGroup, customIcon, manualMapping
}

public struct ActionLibraryEntry: Sendable, Equatable, Identifiable {
    public let name: String
    public let record: ActionLibraryRecord?
    public let sources: Set<ActionLibrarySource>
    public var id: String { SavedGroupBinding.normalizedName(name) }
    public var tags: [String] { record?.tags ?? [] }
    public var isArchived: Bool { record?.isArchived ?? false }
    /// Observations accept longer names than saved groups. Keep those visible,
    /// but never shorten a binding name to make it fit a group.
    public var canAdd: Bool { ActionLibraryRecord.isValidName(name) }
}

public enum ActionLibraryProjection {
    /// Pure union. Reading candidates never creates metadata or rewrites names
    /// in saved groups. A durable spelling wins, then observed, group, icon and
    /// mapping spelling; only the existing binding-normalization key merges.
    public static func entries(
        records: [ActionLibraryRecord], savedGroups: [SavedGroup] = [],
        observedNames: [String] = [], customIconNames: [String] = [], mappingNames: [String] = []
    ) -> [ActionLibraryEntry] {
        struct Accumulator {
            var name: String
            var record: ActionLibraryRecord?
            var sources: Set<ActionLibrarySource>
        }
        var values: [String: Accumulator] = [:]
        func add(_ name: String, source: ActionLibrarySource, record: ActionLibraryRecord? = nil) {
            let key = SavedGroupBinding.normalizedName(name)
            guard !key.isEmpty else { return }
            if var existing = values[key] {
                existing.sources.insert(source)
                values[key] = existing
            } else {
                values[key] = .init(name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .precomposedStringWithCanonicalMapping, record: record, sources: [source])
            }
        }
        for record in records { add(record.name, source: .library, record: record) }
        for name in observedNames { add(name, source: .observedWidget) }
        for group in savedGroups { for name in group.allActionNames { add(name, source: .savedGroup) } }
        for name in customIconNames { add(name, source: .customIcon) }
        for name in mappingNames { add(name, source: .manualMapping) }
        return values.keys.sorted().compactMap { key in
            values[key].map { .init(name: $0.name, record: $0.record, sources: $0.sources) }
        }
    }
}
