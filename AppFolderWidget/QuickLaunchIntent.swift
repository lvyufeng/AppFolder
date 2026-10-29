import AppFolderKit
import AppIntents
import Foundation
import SwiftUI

/// The iOS 27 route: let the *system* own the user's choice of app.
///
/// Everything else in this project works around a limitation — a widget cannot
/// name another app, so we either hand the system a URL and hope it routes there,
/// or make a visible hop through AppFolder. `RunSystemShortcutIntent` removes the
/// limitation instead of working around it. Apple's documentation:
///
/// > An app intent you use in widgets to open another app or perform an App
/// > Shortcut, custom shortcut, or system action.
/// >
/// > When a person configures the widget, they choose the button's action. It
/// > can: Open another installed app. Perform an App Shortcut. Perform a custom
/// > shortcut a person creates in Shortcuts. Perform a system action.
///
/// The price is that *the user* picks the app, not us. `SystemShortcut` is opaque
/// on purpose:
///
/// > An opaque reference to a user-configured action for use in a widget button.
/// > … It doesn't provide the app or widget with a custom shortcut's actions,
/// > parameters, or implementation details.
///
/// ## Why this type lives in the widget target and not in the shared package
///
/// Because a configuration intent that exists in **two** binaries breaks widget
/// taps. This type used to live in `AppFolderKit`, which both the app and the
/// widget link — so the app carried a second copy of it, and a button carrying a
/// `RunSystemShortcutIntent` did nothing when tapped: the tap was accepted, the
/// button highlighted, and no app opened.
///
/// The app never referenced this type — `nm` on the app binary showed 79
/// `QuickLaunchIntent` symbols against zero uses — so the second copy bought
/// nothing and cost the feature. It is compiled here, in the widget target alone,
/// which is the arrangement the one shipping app that does this also uses. Before
/// moving it back into the package for convenience, note that convenience is
/// exactly what broke it.
///
/// Changing the type's home also changes its **type identity**, and every existing
/// widget configuration is bound to the old one: after such a move the widget must
/// be removed and re-added, or its buttons highlight and do nothing. That is not a
/// hypothetical — it is what the move above cost.
#if os(iOS)
@available(iOS 27.0, *)
struct QuickLaunchIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "直接启动"
    static let description: IntentDescription = "选择系统动作或已保存分组，并设置这个小组件的外观。"

    /// The actions the user configured, one per grid slot.
    @Parameter(title: "动作")
    var shortcuts: [SystemShortcut]?

    /// Layout is ours; the actual launch actions remain owned by the system.
    @Parameter(title: "分组布局")
    var savedGroup: SavedGroupEntity?

    /// Opt in so existing widget configurations retain their own appearance.
    @Parameter(title: "使用分组外观", default: false)
    var useGroupAppearance: Bool

    // MARK: - Appearance
    //
    // The same five settings a folder offers, expressed as choices rather than as
    // a colour picker and a slider — see ``LaunchAppearance`` for why the two that
    // cannot be expressed exactly are expressed as a ladder instead, and why they
    // still read the same values the folder editor writes.

    @Parameter(title: "网格", default: .nine)
    var grid: LaunchGrid

    @Parameter(title: "布局密度", default: .standard)
    var density: LaunchDensity

    @Parameter(title: "显示图标名称", default: false)
    var showsTitles: Bool

    @Parameter(title: "底板", default: .automatic)
    var plate: LaunchPlate

    @Parameter(title: "颜色", default: .blue)
    var tint: LaunchTint

    @Parameter(title: "图标大小", default: .medium)
    var iconSize: LaunchIconSize

    /// Hide choices that cannot affect this widget. Action selection and the
    /// group selector remain available in every branch.
    static var parameterSummary: some ParameterSummary {
        When(\.$savedGroup, .hasAnyValue) {
            When(\.$useGroupAppearance, .equalTo, true) {
                Summary {
                    \.$savedGroup
                    \.$useGroupAppearance
                    \.$shortcuts
                }
            } otherwise: {
                Switch(.widgetFamily) {
                    Case(.systemSmall) {
                        When(\.$plate, .equalTo, LaunchPlate.automatic) {
                            Summary {
                                \.$savedGroup
                                \.$useGroupAppearance
                                \.$shortcuts
                                \.$grid
                                \.$showsTitles
                                \.$plate
                                \.$iconSize
                            }
                        } otherwise: {
                            Summary {
                                \.$savedGroup
                                \.$useGroupAppearance
                                \.$shortcuts
                                \.$grid
                                \.$showsTitles
                                \.$plate
                                \.$tint
                                \.$iconSize
                            }
                        }
                    }
                    DefaultCase {
                        When(\.$plate, .equalTo, LaunchPlate.automatic) {
                            Summary {
                                \.$savedGroup
                                \.$useGroupAppearance
                                \.$shortcuts
                                \.$density
                                \.$showsTitles
                                \.$plate
                                \.$iconSize
                            }
                        } otherwise: {
                            Summary {
                                \.$savedGroup
                                \.$useGroupAppearance
                                \.$shortcuts
                                \.$density
                                \.$showsTitles
                                \.$plate
                                \.$tint
                                \.$iconSize
                            }
                        }
                    }
                }
            }
        } otherwise: {
            Switch(.widgetFamily) {
                Case(.systemSmall) {
                    When(\.$plate, .equalTo, LaunchPlate.automatic) {
                        Summary {
                            \.$savedGroup
                            \.$shortcuts
                            \.$grid
                            \.$showsTitles
                            \.$plate
                            \.$iconSize
                        }
                    } otherwise: {
                        Summary {
                            \.$savedGroup
                            \.$shortcuts
                            \.$grid
                            \.$showsTitles
                            \.$plate
                            \.$tint
                            \.$iconSize
                        }
                    }
                }
                DefaultCase {
                    When(\.$plate, .equalTo, LaunchPlate.automatic) {
                        Summary {
                            \.$savedGroup
                            \.$shortcuts
                            \.$density
                            \.$showsTitles
                            \.$plate
                            \.$iconSize
                        }
                    } otherwise: {
                        Summary {
                            \.$savedGroup
                            \.$shortcuts
                            \.$density
                            \.$showsTitles
                            \.$plate
                            \.$tint
                            \.$iconSize
                        }
                    }
                }
            }
        }
    }

    /// Every configured action in the system's original order.
    ///
    /// Grid capacity limits a page, not the configuration. Saved groups can use
    /// any configured action, and binding must see the entire list to detect
    /// duplicate names. Truncating it would mark later actions as missing and
    /// could make an ambiguous name look unique. Preserve these indices alongside
    /// the provider's resolved slots; only artwork loading and rendering may be
    /// limited to what the current page displays.
    var slots: [SystemShortcut] {
        shortcuts ?? []
    }

    /// The folder style these choices add up to.
    ///
    /// Built here, once, so the widget draws from the same ``FolderStyle`` the
    /// folder widget draws from — the type that already decides what a plate looks
    /// like, what colour a name is on it, and how much of a cell the name takes.
    /// Reimplementing any of that for this widget is how the two would drift.
    var style: FolderStyle {
        FolderStyle(
            plate: plate.plate,
            tint: FolderTint(hex: tint.hex) ?? .defaultTint,
            showsTitles: showsTitles,
            iconScale: iconSize.scale,
            grid: grid.grid,
            density: density.density
        )
    }

    init() {}

    init(shortcuts: [SystemShortcut]?) {
        self.shortcuts = shortcuts
    }
}

@available(iOS 27.0, *)
struct SavedGroupEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "分组布局")
    static let defaultQuery = SavedGroupQuery()

    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

@available(iOS 27.0, *)
struct SavedGroupQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [SavedGroupEntity] {
        identifiers.map { id in
            // Keep a deleted selection explicit, so it cannot silently become
            // the ordinary grid and launch actions in an unexpected arrangement.
            SavedGroupEntity(id: id, name: SavedGroupStore.group(id: id)?.name ?? String(localized: "分组不可用"))
        }
    }

    func suggestedEntities() async throws -> [SavedGroupEntity] {
        SavedGroupStore.all.map { SavedGroupEntity(id: $0.id, name: $0.name) }
    }

    func entities(matching string: String) async throws -> [SavedGroupEntity] {
        SavedGroupStore.all.filter { $0.name.localizedStandardContains(string) }
            .map { SavedGroupEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Appearance choices

/// 四宫格 / 九宫格 — the same two arrangements a folder offers.
///
/// This choice applies to small widgets. Medium uses 5×2 and large uses 4×4.
@available(iOS 27.0, *)
enum LaunchGrid: String, AppEnum {
    case nine
    case four

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "网格")
    static let caseDisplayRepresentations: [LaunchGrid: DisplayRepresentation] = [
        .nine: "九宫格",
        .four: "四宫格",
    ]

    var grid: FolderGrid {
        switch self {
        case .nine: .nine
        case .four: .four
        }
    }
}

enum LaunchDensity: String, AppEnum {
    case standard, spacious, dense

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "布局密度")
    static let caseDisplayRepresentations: [LaunchDensity: DisplayRepresentation] = [
        .standard: "标准", .spacious: "大图标", .dense: "密集"
    ]

    var density: FolderDensity {
        switch self {
        case .standard: .standard
        case .spacious: .spacious
        case .dense: .dense
        }
    }
}

/// Automatic leaves the independently requested widget glass visible. Solid and
/// gradient keep their explicit content-layer fills above that background.
@available(iOS 27.0, *)
enum LaunchPlate: String, AppEnum {
    case automatic
    case solid
    case gradient

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "底板")
    static let caseDisplayRepresentations: [LaunchPlate: DisplayRepresentation] = [
        .automatic: "自动（玻璃）",
        .solid: "纯色",
        .gradient: "渐变",
    ]

    var plate: FolderPlate {
        switch self {
        case .automatic: .automatic
        case .solid: .solid
        case .gradient: .gradient
        }
    }
}

/// The colours a folder's picker offers, as a list.
///
/// A configuration parameter cannot be a colour — App Intents has no colour type —
/// so the choice is a fixed palette instead of an arbitrary pick. The values are the
/// same hex strings the folder editor writes, so a colour picked here and the same
/// colour picked in the app are the same colour.
@available(iOS 27.0, *)
enum LaunchTint: String, AppEnum {
    case blue, purple, pink, red, orange, yellow, green, teal, indigo, brown, gray

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "颜色")
    static let caseDisplayRepresentations: [LaunchTint: DisplayRepresentation] = [
        .blue: "蓝", .purple: "紫", .pink: "粉", .red: "红", .orange: "橙",
        .yellow: "黄", .green: "绿", .teal: "青", .indigo: "靛", .brown: "棕",
        .gray: "灰",
    ]

    var hex: String {
        switch self {
        case .blue: "#0A84FF"
        case .purple: "#BF5AF2"
        case .pink: "#FF375F"
        case .red: "#FF453A"
        case .orange: "#FF9F0A"
        case .yellow: "#FFD60A"
        case .green: "#30D158"
        case .teal: "#40C8E0"
        case .indigo: "#5E5CE6"
        case .brown: "#AC8E68"
        case .gray: "#8E8E93"
        }
    }
}

/// 小 / 中 / 大, standing in for the folder editor's continuous slider.
///
/// A slider is a `Double` and this *could* be one, but a configuration sheet has no
/// slider to offer and asking someone to type `0.75` into a number field is worse
/// than asking them to choose 大. The three stops are the same numbers
/// ``FolderGridMetrics/iconScale`` already means, so a folder at the slider's
/// midpoint and a slot at 中 draw identical grids.
@available(iOS 27.0, *)
enum LaunchIconSize: String, AppEnum {
    case small
    case medium
    case large

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "图标大小")
    static let caseDisplayRepresentations: [LaunchIconSize: DisplayRepresentation] = [
        .small: "小", .medium: "中", .large: "大",
    ]

    var scale: Double {
        switch self {
        case .small: 0.5
        case .medium: 0.75
        case .large: 1.0
        }
    }
}
#endif
