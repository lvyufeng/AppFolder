import AppIntents
import Foundation
import WidgetKit

/// Navigation changes only the widget's displayed folder/page. Actual app tiles
/// continue to use RunSystemShortcutIntent in the widget target.
public struct NavigateSavedGroupIntent: AppIntent {
    public static var isDiscoverable: Bool { false }
    public static let title: LocalizedStringResource = "浏览已保存分组"

    @Parameter(title: "分组")
    public var key: String

    @Parameter(title: "当前路径")
    public var expectedPath: String

    @Parameter(title: "当前页")
    public var expectedPage: Int

    @Parameter(title: "目标路径")
    public var targetPath: String

    @Parameter(title: "目标页")
    public var targetPage: Int

    public init() {}

    public init(key: String, expectedPath: String, expectedPage: Int, targetPath: String, targetPage: Int) {
        self.key = key
        self.expectedPath = expectedPath
        self.expectedPage = expectedPage
        self.targetPath = targetPath
        self.targetPage = targetPage
    }

    public func perform() async throws -> some IntentResult {
        if SavedGroupNavigation.navigate(
            key: key, expectedPath: expectedPath, expectedPage: expectedPage,
            targetPath: targetPath, targetPage: targetPage
        ) {
            WidgetCenter.shared.reloadTimelines(ofKind: AppFolderShared.directLaunchWidgetKind)
        }
        return .result()
    }
}
