import AppFolderKit
import AppIntents
import Foundation

/// Separate type identity keeps existing Home Screen configurations unchanged.
struct LockScreenLaunchIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "锁屏启动"
    static let description: IntentDescription = "从已保存分组选择项目。网站按所选方式打开，联系人通过 AppFolder 处理；系统动作需在此配置。"

    @Parameter(title: "第一个项目") var firstItem: LockScreenLeafEntity?
    @Parameter(title: "第二个项目") var secondItem: LockScreenLeafEntity?
    @Parameter(title: "动作") var shortcuts: [SystemShortcut]?

    static var parameterSummary: some ParameterSummary {
        Switch(.widgetFamily) {
            Case(.accessoryCircular) {
                Summary { \.$firstItem; \.$shortcuts }
            }
            DefaultCase {
                Summary { \.$firstItem; \.$secondItem; \.$shortcuts }
            }
        }
    }
}

struct LockScreenLeafEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "分组项目")
    static let defaultQuery = LockScreenLeafQuery()

    let id: String
    let title: String
    let location: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(location)")
    }

    init(_ choice: LockScreenItemChoice) {
        id = choice.id.rawValue
        title = choice.title
        let path = ([choice.groupName] + choice.folderPath).joined(separator: " › ")
        // Two leaves can share a visible title in the same folder. Include the
        // actual destination so the person can identify the intended one.
        let destination: String
        if let target = choice.item.contactTarget {
            destination = target.operation.widgetLocalizedName + " · " + target.number
        } else {
            destination = choice.item.kind == .website ? choice.item.websiteURL ?? "" : choice.item.name
        }
        location = path + " · " + destination
    }

    init(unavailableID: String) {
        id = unavailableID
        title = String(localized: "项目不可用")
        location = String(localized: "重新选择已保存分组中的项目。")
    }
}

struct LockScreenLeafQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [LockScreenLeafEntity] {
        identifiers.map { rawValue in
            guard let id = LockScreenItemID(rawValue: rawValue),
                  let group = SavedGroupStore.group(id: id.groupID),
                  let choice = LockScreenItemChoice.resolve(id, in: group) else {
                // Retain the missing identity instead of allowing a default item
                // to replace it. A duplicate group may reuse node UUIDs.
                return LockScreenLeafEntity(unavailableID: rawValue)
            }
            return LockScreenLeafEntity(choice)
        }
    }

    func suggestedEntities() async throws -> [LockScreenLeafEntity] {
        LockScreenItemChoice.choices(in: SavedGroupStore.all).map(LockScreenLeafEntity.init)
    }

    func entities(matching string: String) async throws -> [LockScreenLeafEntity] {
        LockScreenItemChoice.choices(in: SavedGroupStore.all)
            .filter { choice in
                ([choice.title, choice.item.name, choice.groupName, choice.item.contactTarget?.number ?? ""] + choice.folderPath)
                    .contains { $0.localizedStandardContains(string) }
            }
            .map(LockScreenLeafEntity.init)
    }
}
