import AppIntents
import Foundation
import WidgetKit

/// Expands or collapses a folder *inside* the widget.
///
/// A widget can't hold view state, so "which folder is open" lives in shared
/// defaults and the intent asks WidgetKit for a fresh timeline. The cost is a
/// visible beat between the tap and the redraw — the system decides when to grant
/// the reload, and grants it on a budget. Holding the previous frame during that
/// beat is what makes it read as a transition rather than a stall, which is why
/// the widget keeps drawing the folder header it was already showing.
public struct ToggleFolderIntent: AppIntent {
    public static let title: LocalizedStringResource = "展开/收起文件夹"

    /// The folder to expand, or `nil` to collapse whatever is open.
    @Parameter(title: "文件夹")
    public var folderID: String?

    public init() {}

    public init(folderID: String?) {
        self.folderID = folderID
    }

    public func perform() async throws -> some IntentResult {
        let current = WidgetState.expandedFolderID
        WidgetState.expandedFolderID = (current == folderID) ? nil : folderID
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
