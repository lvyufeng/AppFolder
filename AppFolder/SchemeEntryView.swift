import AppFolderKit
import SwiftUI
import UIKit

/// Where a user-supplied URL scheme turns an App Store result into a working tile.
///
/// ## Why the user has to be involved
///
/// A tile launches by handing a URL to the system, so it needs the target app's
/// URL scheme. For an app in ``AppCatalog`` that scheme is already known and
/// verified, and this screen is skipped entirely. For any other app there is no
/// way to obtain it: the scheme is a string the developer registered in their own
/// `Info.plist`, and iOS exposes no API to read another app's registrations — the
/// same wall that makes listing installed apps impossible.
///
/// So the honest design is not to hide the concept but to make it cheap:
/// ``SchemeGuess`` proposes candidates, each one is one tap away from being
/// tried, and the device gives the verdict.
///
/// ## Why "试一下" is the primary control and not a debug affordance
///
/// `canOpenURL` cannot check a guess — it answers `false` for any scheme not
/// declared in `LSApplicationQueriesSchemes`, and the budget of 25 is already
/// spent. `open(_:)` is exempt from that rule, so actually opening is the only
/// check that works. It happens to be a *better* one: it reports what will really
/// happen on the Home Screen rather than a proxy for it.
///
/// That also means a wrong guess costs nothing but a tap, which is what makes
/// shipping a guesser that is often wrong reasonable.
struct SchemeEntryView: View {
    /// What the user picked in the App Store results.
    let lookup: AppStoreLookup
    /// The tile's name, already resolved — the lookup's name, or the catalogue's
    /// if the entry was found (which would have skipped this screen).
    let title: String
    let onDone: (FolderTile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scheme = ""
    @State private var outcome: Outcome = .untried

    /// What the last attempt did.
    private enum Outcome: Equatable {
        case untried
        /// Sent to the system, which means a handler was found and may now be
        /// opening. The system reports nothing back, so this is as much as can be
        /// known from inside the app.
        case sent
        /// No app on the device handles this scheme.
        case noHandler
    }

    private var candidates: [String] {
        SchemeGuess.candidates(bundleID: lookup.bundleID, name: title)
    }

    /// A scheme is worth offering only if it is syntactically a URL.
    private var trimmedScheme: String {
        scheme.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedScheme: String? {
        let text = trimmedScheme
        guard !text.isEmpty else { return nil }
        // Accept what the user types — `weixin`, `weixin://`, `weixin:` — and
        // store one canonical form. Rejecting `weixin` for want of punctuation
        // would be a form that punishes correct input.
        let bare = text
            .replacingOccurrences(of: "://", with: "")
            .replacingOccurrences(of: ":", with: "")
        guard !bare.isEmpty, URL(string: "\(bare)://") != nil else { return nil }
        return "\(bare)://"
    }

    var body: some View {
        NavigationStack {
            Form {
                header

                Section {
                    TextField("例如 weixin://", text: $scheme)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onChange(of: scheme) { _, _ in
                            // A verdict about the old value reads as a verdict
                            // about the new one. Clear it.
                            outcome = .untried
                        }
                } header: {
                    Text("打开的链接")
                } footer: {
                    Text("这是目标 App 注册的 URL scheme。AppFolder 没有别的办法知道它——iOS 不允许读别的 App 注册了什么。")
                }

                if !candidates.isEmpty {
                    Section {
                        ForEach(candidates, id: \.self) { candidate in
                            candidateRow(candidate)
                        }
                    } header: {
                        Text("猜的，不一定对")
                    } footer: {
                        Text("scheme 是开发者自己定的，跟 App 名字常常没有关系（抖音是 snssdk1128://）。逐个试一下，哪个能用就用哪个。")
                    }
                }

                testSection
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { add() }
                        .disabled(resolvedScheme == nil)
                }
            }
            .onAppear {
                // Prefill with the best candidate so the field is never blank.
                // The user confirms rather than composes.
                if scheme.isEmpty, let first = candidates.first {
                    scheme = first
                }
            }
        }
    }

    /// The app being added, drawn with its real artwork.
    ///
    /// Worth the space: the user reached this screen by searching a name, and the
    /// one thing that tells them they picked the right app is the icon. It also
    /// gives ``IconStore`` the chance to cache the artwork *before* the tile
    /// exists, so the tile appears with its icon rather than as a placeholder.
    private var header: some View {
        Section {
            HStack(spacing: 12) {
                AsyncTileIcon(appStoreID: lookup.trackID, symbolName: "app.dashed")
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lookup.name)
                    if let seller = lookup.sellerName {
                        Text(seller)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func candidateRow(_ candidate: String) -> some View {
        HStack {
            Button {
                scheme = candidate
                tryOpening(candidate)
            } label: {
                Text(candidate)
                    .font(.body.monospaced())
                    .foregroundStyle(scheme == candidate ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)

            Spacer()

            if scheme == candidate {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var testSection: some View {
        Section {
            Button("试一下") { tryOpening(resolvedScheme) }
                .disabled(resolvedScheme == nil)

            switch outcome {
            case .untried:
                EmptyView()
            case .sent:
                Label("已交给系统打开", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .noHandler:
                Label("没有 App 能打开这个链接", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            }
        } footer: {
            if outcome == .sent {
                Text("系统会切到那个 App。如果没切走，说明这个链接不是启动用的，换一个再试。")
            } else if outcome == .noHandler {
                Text("当前设备上没有 App 认这个链接，多半是拼错了，或者这个 App 没有对外公开 scheme。")
            } else {
                Text("会真的打开一次。只有真开一次才算数——`canOpenURL` 对没声明的 scheme 一律说不，问了也没用。")
            }
        }
    }

    /// Opens the scheme for real and reports what happened.
    ///
    /// The fallback to ``Outcome/sent`` when the completion handler reports
    /// failure deserves the explanation: `open(_:)`'s handler is documented to
    /// report whether the request was *handed to the system*, not whether an app
    /// then launched, and it is called on a different run loop turn. Reporting
    /// "no handler" on a `false` would show a red X for a scheme that just worked
    /// — so `false` is reported as "sent, go look", which is the truth.
    ///
    /// A `false` from the *synchronous* path is different: `canOpenURL` is not
    /// consulted at all here, on purpose, for the reason in the type's
    /// documentation.
    private func tryOpening(_ raw: String?) {
        guard let raw, let url = URL(string: raw) else { return }
        outcome = .untried
        UIApplication.shared.open(url, options: [:]) { _ in
            Task { @MainActor in
                outcome = .sent
            }
        }
    }

    private func add() {
        guard let resolvedScheme else { return }
        onDone(
            FolderTile(
                title: lookup.name,
                scheme: resolvedScheme,
                appStoreID: lookup.trackID,
                // Stored so ``SchemeGuess`` can be re-run on this tile later
                // without another network lookup — see ``FolderTile/bundleID``.
                bundleID: lookup.bundleID,
                // Whatever the user typed or picked here still counts as a guess.
                // This screen cannot tell a working link from a plausible one: it
                // hands the URL to the system and the system reports nothing back
                // (see ``Outcome``), so a tile made here is confirmed by the same
                // act as one made by the share extension — the first real open.
                // Marking it here is what makes the widget wait for that.
                needsSchemeConfirmation: true
            )
        )
        dismiss()
    }
}