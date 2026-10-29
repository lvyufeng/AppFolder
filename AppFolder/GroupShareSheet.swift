import Foundation
import LinkPresentation
import SwiftUI
import UIKit

/// The file stays alive while either SwiftUI or an activity still owns it.
/// Completion removes its directory explicitly; deinit also cleans abandoned work.
final class PreparedGroupShare: Identifiable, Sendable {
    let id: UUID
    let name: String
    let fileURL: URL
    private let directory: URL

    init(data: Data, name: String) throws {
        id = UUID()
        self.name = name
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppFolderGroupShare-" + id.uuidString, isDirectory: true)
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        var filename = name.components(separatedBy: invalid).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while filename.utf8.count > 100 { filename.removeLast() }
        if filename.isEmpty { filename = "Group" }
        fileURL = directory.appendingPathComponent("AppFolder-" + filename + ".appfolderbackup")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Call only after the activity has finished or its presentation was cancelled.
    func removeTemporaryFile() { try? FileManager.default.removeItem(at: directory) }

    deinit { removeTemporaryFile() }
}

/// An invisible anchor presents UIKit's activity controller directly. The
/// activity controller is never embedded in a SwiftUI sheet or custom layout.
struct GroupSharePresenter: UIViewControllerRepresentable {
    let file: PreparedGroupShare?
    let onCompletion: @MainActor (Bool) -> Void

    func makeUIViewController(context: Context) -> GroupSharePresentationController {
        GroupSharePresentationController()
    }

    func updateUIViewController(_ controller: GroupSharePresentationController, context: Context) {
        controller.update(file: file, onCompletion: onCompletion)
    }
}

@MainActor
final class GroupSharePresentationController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private var pendingFile: PreparedGroupShare?
    private var activity: UIActivityViewController?
    private var activeID: UUID?
    private var completedID: UUID?
    private var isFinishing = false
    private var onCompletion: (@MainActor (Bool) -> Void)?

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        schedulePresentation()
    }

    func update(file: PreparedGroupShare?, onCompletion: @escaping @MainActor (Bool) -> Void) {
        pendingFile = file
        self.onCompletion = onCompletion
        schedulePresentation()
    }

    private func schedulePresentation() {
        // UIKit presentation and SwiftUI state updates must occur after the
        // representable's update pass, once this anchor is in its window.
        DispatchQueue.main.async { [weak self] in self?.presentIfReady() }
    }

    private func presentIfReady() {
        guard activity == nil, !isFinishing, viewIfLoaded?.window != nil,
              let file = pendingFile, file.id != completedID else { return }
        var presenter: UIViewController = self
        while let parent = presenter.parent { presenter = parent }
        if let existing = presenter.presentedViewController {
            // A context menu can still be finishing its dismissal after export.
            // Follow its transition instead of racing it or using a fixed delay.
            if existing.isBeingDismissed, let transition = existing.transitionCoordinator {
                transition.animate(alongsideTransition: nil) { [weak self] _ in
                    self?.schedulePresentation()
                }
            } else {
                completedID = file.id
                pendingFile = nil
                onCompletion?(true)
            }
            return
        }

        let controller = UIActivityViewController(activityItems: [GroupShareActivityItem(file: file)],
                                                  applicationActivities: nil)
        if traitCollection.userInterfaceIdiom == .pad { controller.modalPresentationStyle = .popover }
        activity = controller
        activeID = file.id
        controller.completionWithItemsHandler = { [weak self, weak controller] _, _, _, error in
            let failed = error != nil
            Task { @MainActor in
                guard let self, let controller else { return }
                self.finish(controller, failed: failed)
            }
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = view.bounds
            popover.permittedArrowDirections = []
        }
        controller.presentationController?.delegate = self
        presenter.present(controller, animated: true) { [weak self, weak controller] in
            controller?.presentationController?.delegate = self
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let activity, presentationController.presentedViewController === activity else { return }
        finish(activity, failed: false)
    }

    private func finish(_ controller: UIActivityViewController, failed: Bool) {
        guard activity === controller, let id = activeID, !isFinishing else { return }
        isFinishing = true
        let completion: @MainActor () -> Void = { [weak self] in
            guard let self, self.activeID == id, self.isFinishing else { return }
            self.completedID = self.activeID
            self.activeID = nil
            self.activity = nil
            self.pendingFile = nil
            self.isFinishing = false
            self.onCompletion?(failed)
        }
        if controller.isBeingDismissed, let transition = controller.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { _ in completion() }
        } else if controller.presentingViewController != nil {
            controller.dismiss(animated: true, completion: completion)
        } else {
            completion()
        }
    }
}

/// Returning a file URL preserves its extension and allows Files, AirDrop, and
/// other user-selected destinations to receive the same importable document.
private final class GroupShareActivityItem: NSObject, UIActivityItemSource {
    let file: PreparedGroupShare

    init(file: PreparedGroupShare) { self.file = file }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        file.fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        file.fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        file.name
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        "com.lvyufeng.appfolder.backup"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = file.name
        metadata.originalURL = file.fileURL
        metadata.url = file.fileURL
        return metadata
    }
}
