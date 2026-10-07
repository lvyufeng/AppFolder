import AppIntents
import Foundation
import WidgetKit

/// Opens or closes a direct-launch grid, in the widget's own process.
///
/// A widget can't hold view state, so "which grid is open" lives in shared
/// defaults (``WidgetState``) and the intent asks WidgetKit for a fresh timeline.
/// The cost is a visible beat between the tap and the redraw — the system decides
/// when to grant the reload, and grants it on a budget. Holding the previous frame
/// during that beat is what makes it read as a transition rather than a stall,
/// which is why the expand tap changes only the last cell.
///
/// ## Why this does not open the app
///
/// `openAppWhenRun` stays at its default of `false`, and that is the whole point:
/// the user asked to see the rest of the grid without leaving the Home Screen. An
/// intent that launched AppFolder would be the behaviour this type exists to
/// replace.
///
/// ## Where it runs
///
/// In the widget extension's process. That is what lets the write here and the
/// read in the next render agree even when the App Group is unreachable — see
/// ``WidgetState/isAvailable``.
///
/// ## Why the key is computed, not stored
///
/// This used to be the twin of a `ToggleFolderIntent` that carried a folder's id;
/// both that intent and the folder widget it served have been removed, so the
/// comparison is now to nothing. What survives is the reason a folder's id could
/// not simply be replaced by something similar: the system will not let us read,
/// compare or store the shortcuts, so there is no id here to carry. What both the
/// tap and the render *can* see is the slots' display names — the same names, in
/// the same order, from the same `displayRepresentation` — so both sides compute
/// the key from them and agree without either having to write it down. See
/// ``WidgetState/directLaunchExpansionKey(slotNames:)``.
///
/// That is also why the key is passed in rather than derived here: this intent
/// lives in the app-binary-safe part of the package and cannot import
/// `SystemShortcut`, which is why ``DirectLaunchWidget``'s own intent is the only
/// place the shortcuts themselves exist.
public struct ToggleDirectLaunchIntent: AppIntent {
    public static let title: LocalizedStringResource = "展开/收起直开分组"

    /// The grid to open, or the same value again to close it.
    ///
    /// The door and the back cell pass the *same* key, so one intent serves both
    /// and the widget does not have to carry two — the trick a folder's toggle used
    /// to use, with a digest standing in for the id a grid does not have.
    @Parameter(title: "分组")
    public var key: String

    public init() {}

    public init(key: String) {
        self.key = key
    }

    public func perform() async throws -> some IntentResult {
        if WidgetState.directLaunchKey == key {
            WidgetState.collapse()
        } else {
            WidgetState.directLaunchKey = key
            // Always page one, for the same reason a folder's toggle did: a fresh
            // look at the group, not whatever page it was left on.
            WidgetState.expandedPage = 0
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Turns to the next page of an expanded direct-launch grid.
///
/// Carries the drawn page it was tapped on, for two reasons that have not changed:
///
/// 1. The widget renders from a stored page it clamps to the group's real length,
///    so the button the user tapped may have been drawn on a lower page than the
///    stored value. Advancing from the drawn page is what makes the tap mean what
///    it looked like it meant.
/// 2. A `Button` in a widget whose intent value never changes can be reused for
///    another cell across a timeline reload — the hazard ``InertTapIntent``
///    documents. Carrying the page makes the value change when the page does, so a
///    stale button cannot replay onto a different page.
///
/// It bounds nothing. The intent has no widget family, so it cannot know how many
/// pages there are; the reader clamps instead. See
/// ``FolderExpansionLayout/clampedPage(_:)``.
public struct AdvanceDirectLaunchPageIntent: AppIntent {
    public static let title: LocalizedStringResource = "直开分组翻页"

    @Parameter(title: "分组")
    public var key: String

    /// The page the button was drawn on, so the advance starts from what the user
    /// actually saw rather than from whatever is stored.
    @Parameter(title: "当前页")
    public var page: Int

    public init() {}

    public init(key: String, page: Int) {
        self.key = key
        self.page = page
    }

    public func perform() async throws -> some IntentResult {
        // Ignored unless that grid is the one open — a tap arriving after the
        // widget collapsed, or after the other widget's grid opened, must not
        // move a page belonging to it.
        guard WidgetState.directLaunchKey == key else { return .result() }
        WidgetState.expandedPage = page + 1
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}