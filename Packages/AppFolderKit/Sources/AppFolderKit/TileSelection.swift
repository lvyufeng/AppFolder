import Foundation

/// What the tile picker is holding: the folder's contents, in the folder's order,
/// with each entry knowing whether it is a catalogue reference or a tile the user
/// built.
///
/// ## Why the entries are ordered rather than two collections
///
/// The obvious shape is two halves — a set of catalogue ids and an array of
/// hand-built tiles — and that is what this was. It loses the interleaving, and
/// the loss is visible on the Home Screen: resolving put the hand-built tiles
/// first and the catalogue entries after them, so a folder holding 微信, then a
/// hand-added 机器人, then QQ came back as 机器人, 微信, QQ. Opening the picker and
/// tapping 完成 without touching anything rearranged the folder, because the
/// widget's grid is positional and the order *is* the layout.
///
/// ## Why an entry is one of two shapes rather than one
///
/// A catalogue entry is fully described by its id. ``AppCatalog`` has the name,
/// the scheme, the artwork id and the symbol, and it is the project's own
/// continuing work to keep those right — so a ticked entry is stored as one
/// string and the tile is rebuilt from the catalogue on the way out. That is what
/// lets a catalogue correction reach a folder assembled months ago, which is
/// ``LibraryRepair``'s job stated from the other side.
///
/// A tile the user built has no such backing. Its scheme was worked out by hand or
/// guessed and then confirmed with 试一下, and that fact exists nowhere else in the
/// world. It cannot be reduced to an id and it cannot be re-derived, so it is
/// carried **whole**.
///
/// Keeping both in one ordered list is what lets each entry be rebuilt the way it
/// has to be, without either half losing its position.
///
/// ## Why this is a type and not state on a view
///
/// It was two `@State`s and a computed property inside ``TilePickerView``, which
/// is why nothing tested it and why it was wrong: `extraTiles` had exactly one
/// writer, the seeding pass, and no code path ever added to it. Every route that
/// produced a non-catalogue tile called the view's `onDone` directly instead, so
/// adding one app by hand **replaced the folder** — silently deleting everything
/// else in it. The bug was invisible from the view, because the sheet closes and
/// the result is handed over in the same turn, so the list the user was looking at
/// never re-rendered with the loss in it.
///
/// That is the shape of mistake a test catches and a screenshot does not, so the
/// merge lives here, in the package, where a test can reach it.
public struct TileSelection: Sendable, Equatable {
    /// One thing in the folder.
    public enum Entry: Sendable, Equatable {
        /// ``KnownApp/id``. Resolved against the catalogue at the end, so the
        /// tile always carries the catalogue's current answer.
        case catalog(String)
        /// A tile with no catalogue backing, carried whole.
        case tile(FolderTile)
    }

    /// The folder's contents, in the folder's order.
    ///
    /// Public to read and mutate only through the methods below, so the two
    /// halves cannot drift apart the way they did when they were separate
    /// storage.
    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public init(catalogIDs: Set<String> = [], extraTiles: [FolderTile] = []) {
        self.entries = catalogIDs.map { Entry.catalog($0) } + extraTiles.map { Entry.tile($0) }
    }

    /// The folder's current contents, in order, split by ``FolderTile/catalogID``
    /// and nothing else.
    ///
    /// Identity by id, never by name: a user may hand-build a tile called 地图 with
    /// their own scheme, and it is not the catalogue's 地图. ``LibraryRepair``
    /// follows the same rule for the same reason, and the tests that rejected an
    /// earlier attempt to widen it are the argument for keeping it.
    public static func seeded(from tiles: [FolderTile]) -> TileSelection {
        TileSelection(entries: tiles.map { tile in
            if let catalogID = tile.catalogID { .catalog(catalogID) } else { .tile(tile) }
        })
    }

    /// The catalogue entries that are ticked.
    ///
    /// Derived, for rendering a list of catalogue rows as either picked or not.
    public var catalogIDs: Set<String> {
        Set(entries.compactMap { if case .catalog(let id) = $0 { id } else { nil } })
    }

    /// The non-catalogue tiles, in order, for the section that lists them.
    public var extraTiles: [FolderTile] {
        entries.compactMap { if case .tile(let tile) = $0 { tile } else { nil } }
    }

    /// Whether anything is picked at all.
    ///
    /// Lets a screen tell "you removed everything" from "this folder was already
    /// empty", which are different sentences to show.
    public var isEmpty: Bool { entries.isEmpty }

    /// Ticks or unticks a catalogue entry.
    ///
    /// Ticking appends, so the entry lands where the user can see it go — at the
    /// end of the folder — rather than at a position decided by the catalogue's
    /// own ordering. That ordering is curated and sensible as a *list* to pick
    /// from; using it as a layout would move a newly added app somewhere the user
    /// did not put it.
    public mutating func setCatalog(_ id: String, isSelected: Bool) {
        if isSelected {
            if !catalogIDs.contains(id) { entries.append(.catalog(id)) }
        } else {
            entries.removeAll { $0 == .catalog(id) }
        }
    }

    /// Drops a hand-built tile by the tile's own id.
    public mutating func removeTile(id: UUID) {
        entries.removeAll { entry in
            if case .tile(let tile) = entry { tile.id == id } else { false }
        }
    }

    /// Adds a finished tile without disturbing anything already selected.
    ///
    /// The method this type exists for. It is what the scheme screen and the
    /// manual entry call, and it is why they no longer take the picker down with
    /// them — see the type's own note for the bug that caused.
    public mutating func add(_ tile: FolderTile) {
        if let catalogID = tile.catalogID {
            // A tile that *is* a catalogue entry becomes a reference like any
            // other, so the two shapes can never hold the same app twice.
            setCatalog(catalogID, isSelected: true)
        } else {
            entries.append(.tile(tile))
        }
    }

    /// The folder's contents after the user is done.
    ///
    /// Catalogue references are rebuilt from the catalogue here, so a correction
    /// that landed since the folder was assembled reaches it. A tile stored as its
    /// own copy of the scheme would keep the old, wrong answer forever — 票牛's
    /// `pner://` is the worked example.
    ///
    /// A reference the catalogue no longer holds is dropped rather than drawn as a
    /// nameless blank. The alternative would be a tile with no name and no scheme
    /// that the user can see and cannot explain.
    public var resolved: [FolderTile] {
        entries.compactMap { entry in
            switch entry {
            case .catalog(let id):
                AppCatalog.all.first { $0.id == id }.map { FolderTile(app: $0) }
            case .tile(let tile):
                tile
            }
        }
    }
}