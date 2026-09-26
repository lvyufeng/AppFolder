import AppFolderKit
import SwiftUI
import UIKit

/// One tile in the editor: icon, name, URL, launch route.
///
/// The launch route is editable here and nowhere else, on purpose. A tile that
/// cannot open its app is indistinguishable from a broken app — the tap just
/// does nothing — so the place to find out is the editor, where the user is
/// already looking at the tile and can act on it.
struct TileEditorRow: View {
    @Binding var tile: FolderTile
    @State private var isTesting = false
    @State private var result: TestResult?

    private enum TestResult {
        case opened
        case noHandler
        case finished
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TileIcon(tile: tile, side: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tile.title)
                    Text(tile.urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Picker("打开方式", selection: $tile.strategy) {
                ForEach(LaunchStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.localizedName).tag(strategy)
                }
            }
            .pickerStyle(.menu)
            .font(.subheadline)

            Text(tile.strategy.localizedExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)

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
        guard let target = tile.url else {
            result = .noHandler
            return
        }
        isTesting = true
        let isDeclared = AppCatalog.queriedSchemes.contains { scheme in
            target.scheme?.lowercased() == scheme.replacingOccurrences(of: "://", with: "").lowercased()
        }

        if isDeclared, !UIApplication.shared.canOpenURL(target) {
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
