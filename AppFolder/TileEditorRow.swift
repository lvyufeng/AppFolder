import AppFolderKit
import SwiftUI
import UIKit

/// One tile in the editor: icon, name, and a way to try it.
///
/// ## Why there is no launch-route picker
///
/// There used to be one — 直接打开 / 经 AppFolder 中转 — and it was a mistake,
/// for a reason worth recording. The two options are not preferences; they are a
/// fact about the target app. "直接打开" needs the target to publish a universal
/// link and most apps do not (of the catalogue's 73 entries, exactly two do), so
/// picking it for anything else produced a tile that drew normally and did
/// nothing when tapped. The picker looked like a setting and was really asking
/// the user a question the app can answer itself.
///
/// The route is now derived from the tile — ``FolderTile/launchRoute`` — and the
/// widget reads it from there. What is left here is the only thing the user can
/// actually act on: whether the link works. "试一下" opens it for real, which is
/// the one check that settles the question, and for a hand-added tile the link
/// itself is editable above it.
struct TileEditorRow: View {
    @Binding var tile: FolderTile
    @State private var isTesting = false
    @State private var result: TestResult?

    private enum TestResult {
        case opened
        case noHandler
        case finished
    }

    /// Whether this tile came from the catalogue.
    ///
    /// The catalogue's entries have an id, which is what ``LibraryRepair`` uses to
    /// find them again; a hand-added tile has none. The distinction decides
    /// whether this row shows an edit affordance: a catalogue entry's name and
    /// scheme are facts about a real app, and letting them be edited would only
    /// create a tile the repair pass no longer recognises.
    private var isUserAdded: Bool { tile.catalogID == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TileIcon(tile: tile, side: 36)
                VStack(alignment: .leading, spacing: 1) {
                    // Editable only for a hand-added tile. The name came from an
                    // App Store search that may have returned a same-named app,
                    // and the scheme is a guess the device may have rejected —
                    // without this the only remedy would be deleting the tile and
                    // starting over.
                    if isUserAdded {
                        TextField("名称", text: $tile.title)
                    } else {
                        Text(tile.title)
                    }

                    if isUserAdded {
                        TextField("链接", text: $tile.urlString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Text(tile.urlString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
            }

            if isUserAdded {
                Text("这个 App 不在目录里，链接是你自己试出来的。打不开就在这里改。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("试一下") { test() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTesting)

                if let result {
                    switch result {
                    case .opened:
                        Label("已交给系统打开", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .noHandler:
                        Label("没有 App 能打开这个链接", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .finished:
                        Label("已发送，请确认目标 App 是否打开", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if case .noHandler = result {
                Text("这个链接在当前设备上打不开，可能是目标 App 没装，或者链接写错了。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: tile.urlString) { _, _ in
            // A stale verdict from a previous link reads as a verdict on the new
            // one. Clear it rather than let the user draw the wrong conclusion.
            result = nil
        }
    }

    /// Tries the URL for real.
    ///
    /// `canOpenURL` answers this directly when the scheme is declared in
    /// `LSApplicationQueriesSchemes`. The catalogue's schemes are, so this is a
    /// trustworthy answer for them; a scheme the user typed by hand is not
    /// declared, so `canOpenURL` returns false regardless and the honest thing
    /// to report is "sent, check for yourself" rather than a false negative.
    ///
    /// Note what this does *not* do: it does not verify that the widget's own
    /// route works. A `Button(intent:)` tap runs in the extension's process and
    /// tells nobody whether it succeeded, so the only real test of the widget is
    /// tapping the widget. This button answers the narrower, answerable question
    /// of whether the URL is reachable at all.
    private func test() {
        // The URL the tile will actually open, so "试一下" tests the route the
        // user configured rather than the one they didn't.
        guard let target = tile.launchURL else {
            result = .noHandler
            return
        }
        isTesting = true
        // Only a declared scheme (or one of Apple's, which need no declaration)
        // gets a trustworthy answer from `canOpenURL`. For anything else a `false`
        // would be the declaration rule talking, not the device, so the honest
        // report is "sent, go look".
        let isProbeable = AppCatalog.probeableSchemes.contains { scheme in
            target.scheme?.lowercased() == scheme.replacingOccurrences(of: "://", with: "").lowercased()
        }

        if isProbeable, !UIApplication.shared.canOpenURL(target) {
            result = .noHandler
            isTesting = false
            return
        }

        UIApplication.shared.open(target) { success in
            result = success ? .opened : .finished
            isTesting = false
        }
    }
}
