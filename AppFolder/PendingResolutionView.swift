import AppFolderKit
import SwiftUI

/// One row in the editor's 待确认的分享 list.
///
/// Resolves the app's name and icon on the way in, because the record deliberately
/// carries neither — see ``PendingResolution``. Until the lookup answers, the row
/// shows the id, which is honest rather than blank: an unresolved share that
/// happens to be offline should look like a share whose name has not loaded, not
/// like a broken row.
struct PendingResolutionRow: View {
    @Environment(LibraryModel.self) private var model
    let pending: PendingResolution

    @State private var lookup: AppStoreLookup?

    /// The folder this share will land in, when it still exists.
    ///
    /// `nil` after the folder was deleted, which the row says outright — the
    /// confirmation falls back to the first folder, and the user should know that
    /// before they confirm rather than after.
    private var targetFolderName: String? {
        model.folder(withID: pending.folderID)?.name
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncTileIcon(appStoreID: pending.trackID, symbolName: "questionmark.app.dashed")
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(lookup?.name ?? "id\(pending.trackID)")
                    .foregroundStyle(lookup == nil ? .secondary : .primary)
                Text(targetFolderName.map { "确认后放进「\($0)」" } ?? "原文件夹已删除，会放进第一个文件夹")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange)
        }
        .task(id: pending.trackID) {
            lookup = await AppStoreSearchClient.shared.lookup(
                trackID: pending.trackID,
                region: pending.region
            )
        }
    }
}

/// Confirming one unresolved share: try candidate schemes, pick the one that works.
///
/// ## Why this is the same screen the manual path uses
///
/// ``SchemeEntryView`` already does exactly this job — proposes candidates, tries
/// each one against the real device, and hands back a tile. Duplicating it would
/// create a second place where "how do we decide a scheme works" is answered, and
/// the two would drift.
///
/// What this screen adds is the two things a *share* has that a manual entry does
/// not: a folder the user already chose, and a queue record that has to leave the
/// queue however the visit ends. Both are handled here rather than in
/// ``SchemeEntryView``, which should not know that a queue exists.
///
/// ## Why discarding is offered as plainly as confirming
///
/// The app may genuinely not be installed any more, or the shared link may point
/// at something the user no longer wants. A queue with no way out is a badge that
/// never goes down, and there is nothing on the Home Screen that would explain
/// why. So 不用了 is a first-class action, not a hidden swipe.
struct PendingResolutionView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pending: PendingResolution

    @State private var lookup: AppStoreLookup?
    @State private var didFailLookup = false
    @State private var isResolving = true

    var body: some View {
        Group {
            if isResolving {
                ProgressView("正在从 App Store 取这个 App…")
            } else if let lookup {
                SchemeEntryView(lookup: lookup, title: lookup.name) { tile in
                    model.resolve(pending, into: tile)
                    dismiss()
                }
            } else {
                // The lookup is the only way to get a name for the tile, and it
                // needs the network. Rather than dead-end, the manual path stays
                // open — the user can still type a name and a scheme, which is
                // strictly more than they had.
                let manual = AppStoreLookup.manual(name: "新图块")
                SchemeEntryView(lookup: manual, title: manual.name) { tile in
                    model.resolve(pending, into: tile)
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(role: .destructive) {
                model.discard(pending)
                dismiss()
            } label: {
                Text("不用了，从待确认里去掉")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding()
            .background(.bar)
        }
        .task(id: pending.trackID) {
            lookup = await AppStoreSearchClient.shared.lookup(
                trackID: pending.trackID,
                region: pending.region
            )
            didFailLookup = lookup == nil
            isResolving = false
        }
    }
}