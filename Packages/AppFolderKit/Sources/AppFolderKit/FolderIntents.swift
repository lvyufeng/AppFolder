import AppIntents
import Foundation
import WidgetKit

/// Expands or collapses a folder *inside* the widget.
///
/// A widget can't hold view state, so "which folder is open" lives in shared
/// defaults (``WidgetState``) and the intent asks WidgetKit for a fresh timeline.
/// The cost is a visible beat between the tap and the redraw — the system decides
/// when to grant the reload, and grants it on a budget. Holding the previous
/// frame during that beat is what makes it read as a transition rather than a
/// stall, which is why the widget keeps drawing the folder's plate it was already
/// showing, and why the expand tap changes only the last cell.
///
/// ## Why this does not open the app
///
/// `openAppWhenRun` stays at its default of `false`, and that is the whole point:
/// the user asked to see the folder without leaving the Home Screen. An intent
/// that launched AppFolder would be the behaviour this type exists to replace.
///
/// ## Where it runs
///
/// In the widget extension's process. That is what lets the write here and the
/// read in the next render agree even when the App Group is unreachable — see
/// ``WidgetState/isAvailable``.
public struct ToggleFolderIntent: AppIntent {
    public static let title: LocalizedStringResource = "展开/收起文件夹"

    /// The folder to expand, or `nil` to collapse whatever is open.
    ///
    /// The back cell passes the *same* id as the door that opened it, so a tap on
    /// either toggles correctly without the widget having to carry two intents.
    @Parameter(title: "文件夹")
    public var folderID: String?

    public init() {}

    public init(folderID: String?) {
        self.folderID = folderID
    }

    public func perform() async throws -> some IntentResult {
        let current = WidgetState.expandedFolderID
        if current == folderID {
            WidgetState.collapse()
        } else {
            WidgetState.expandedFolderID = folderID
            // Always page one. Expanding is a fresh look at the folder, and
            // opening on whatever page the user last left would be a state they
            // never asked to keep — they collapsed it on purpose.
            WidgetState.expandedPage = 0
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Turns to the next page of an expanded folder.
///
/// Separate from ``ToggleFolderIntent`` because it is a different action on a
/// different cell, not a second mode of the first: folding it in would mean the
/// back cell and the next cell carry the same intent with different parameters,
/// and SwiftUI would be free to reuse one button for the other.
///
/// ## Why it carries the page it was drawn on
///
/// The intent does not advance "whatever page is stored" — it advances *from the
/// page this button was drawn on*. Two reasons, and the second is the important
/// one:
///
/// 1. The widget renders from a stored page it clamps to the folder's real
///    length, so the button the user tapped may have been drawn on a lower page
///    than the stored value. Advancing from the drawn page is what makes the tap
///    mean what it looked like it meant.
/// 2. A `Button` in a widget whose intent value never changes can be reused for
///    another cell across a timeline reload — the same hazard ``InertTapIntent``
///    documents. Carrying the page makes the value change when the page does, so
///    a stale button cannot replay onto a different page.
///
/// It bounds nothing. The intent has no widget family, so it cannot know how many
/// pages there are; the reader clamps instead. See
/// ``FolderExpansionLayout/clampedPage(_:)``.
public struct AdvanceFolderPageIntent: AppIntent {
    public static let title: LocalizedStringResource = "文件夹翻页"

    @Parameter(title: "文件夹")
    public var folderID: String

    /// The page the button was drawn on, so the advance starts from what the user
    /// actually saw rather than from whatever is stored.
    @Parameter(title: "当前页")
    public var page: Int

    public init() {}

    public init(folderID: String, page: Int) {
        self.folderID = folderID
        self.page = page
    }

    public func perform() async throws -> some IntentResult {
        // Ignored unless that folder is the one open. A tap that arrives after
        // the widget collapsed — or after another folder was opened — must not
        // resurrect the old folder or move a page belonging to it.
        guard WidgetState.expandedFolderID == folderID else { return .result() }
        WidgetState.expandedPage = page + 1
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}