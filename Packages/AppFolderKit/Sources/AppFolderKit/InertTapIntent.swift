import AppIntents
import Foundation

/// A button that does nothing, used to swallow taps that should not do anything.
///
/// ## Why this has to exist
///
/// A widget's entire surface is tappable and opens the containing app. That is
/// the platform's behaviour and there is no switch for it: `widgetURL` *changes*
/// where a tap goes, it does not enable or disable the tap, and the SDK publishes
/// no hit-testing or tappable-region control at all. Apple's own widgets behave
/// the same way — tapping the blank half of a short Calendar widget opens
/// Calendar.
///
/// That default is wrong for this app. A folder holding four apps leaves a whole
/// row empty, and a tap on that row launching AppFolder reads as a bug: the user
/// aimed at nothing and got somewhere.
///
/// ## What it does instead
///
/// A `Button` is a tap target in its own right, and the system routes the tap to
/// it rather than to the widget's default action. So covering the uncovered cells
/// with buttons whose action does nothing takes those taps out of circulation,
/// and the only thing left that opens AppFolder is an actual tile.
///
/// ## Why not `openAppWhenRun`
///
/// Left `false`, and `perform()` returns an empty result rather than opening
/// anything. Opening the app would be the easy way to make the button "work", and
/// it is precisely the behaviour being removed.
///
/// One intent per cell rather than one shared instance: the cell is the only
/// thing that distinguishes them, and giving each its own value keeps the button
/// identity stable across timeline reloads, which is what stops SwiftUI reusing
/// one cell's button for another.
public struct InertTapIntent: AppIntent {
    /// Never shown. The intent is an implementation detail of the layout, so it
    /// deliberately has nothing a person could want to read.
    public static let title: LocalizedStringResource = "空白"

    /// Which empty cell this button covers. Not used by ``perform()`` — it exists
    /// so two cells are not the same intent.
    @Parameter(title: "位置")
    public var cell: Int

    /// Whether this cell is part of the layout at all. Kept so the parameter
    /// summary below has something honest to say, and so a future "what is this
    /// button" debug pass can tell a padded cell from a real gap.
    @Parameter(title: "已填充")
    public var isFiller: Bool

    public init() {}

    public init(cell: Int, isFiller: Bool = true) {
        self.cell = cell
        self.isFiller = isFiller
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("空白 \(\.$cell)")
    }

    /// Deliberately empty. Any result here — including opening the app — would
    /// put back the behaviour this type exists to remove.
    public func perform() async throws -> some IntentResult {
        .result()
    }
}