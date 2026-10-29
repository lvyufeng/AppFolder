import AppFolderKit
import SafariServices
import SwiftUI
import UIKit

/// Created only by an explicit test/open action or an eligible fresh widget
/// launch. Changing an address or a browser preference never creates a request.
@MainActor
struct WebsiteBrowserRequest: Identifiable {
    let id: UUID
    let url: URL
    let canPresent: @MainActor () -> Bool

    init(id: UUID = UUID(), url: URL, canPresent: @escaping @MainActor () -> Bool = { true }) {
        self.id = id
        self.url = url
        self.canPresent = canPresent
    }
}

/// A background anchor, not a container for Safari. Safari is presented directly
/// using UIKit's complete modal browser experience, with its own visible chrome.
struct WebsiteBrowserPresenter: UIViewControllerRepresentable {
    let request: WebsiteBrowserRequest?
    let onDismiss: @MainActor (UUID) -> Void
    let onFailure: @MainActor (UUID) -> Void

    func makeUIViewController(context: Context) -> WebsiteBrowserPresentationController {
        WebsiteBrowserPresentationController()
    }

    func updateUIViewController(_ controller: WebsiteBrowserPresentationController, context: Context) {
        controller.update(request: request, onDismiss: onDismiss, onFailure: onFailure)
    }

    static func dismantleUIViewController(_ controller: WebsiteBrowserPresentationController, coordinator: ()) {
        controller.cancel()
    }
}

@MainActor
final class WebsiteBrowserPresentationController: UIViewController,
    @MainActor SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private var pending: WebsiteBrowserRequest?
    private var activeID: UUID?
    private var completedID: UUID?
    private var browser: SFSafariViewController?
    private var finishing = false
    private var onDismiss: (@MainActor (UUID) -> Void)?
    private var onFailure: (@MainActor (UUID) -> Void)?

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

    func update(request: WebsiteBrowserRequest?, onDismiss: @escaping @MainActor (UUID) -> Void,
                onFailure: @escaping @MainActor (UUID) -> Void) {
        pending = request
        self.onDismiss = onDismiss
        self.onFailure = onFailure
        if let activeID, activeID != request?.id {
            finish(failed: false)
        } else {
            schedulePresentation()
        }
    }

    func cancel() {
        pending = nil
        onDismiss = nil
        onFailure = nil
        finish(failed: false)
    }

    private func schedulePresentation() {
        DispatchQueue.main.async { [weak self] in self?.presentIfReady() }
    }

    private func presentIfReady() {
        guard browser == nil, !finishing,
              let request = pending, request.id != completedID else { return }
        var presenter: UIViewController = self
        while let parent = presenter.parent { presenter = parent }
        while let existing = presenter.presentedViewController {
            if existing.isBeingDismissed || existing.isBeingPresented {
                waitForTransition(existing, requestID: request.id)
                return
            }
            presenter = existing
        }
        if presenter.isBeingDismissed || presenter.isBeingPresented {
            waitForTransition(presenter, requestID: request.id)
            return
        }
        // The representable may update before its first appearance. Nothing is
        // created or loaded until an attached, active scene can present it.
        guard let window = presenter.viewIfLoaded?.window else { return }
        guard window.windowScene?.activationState == .foregroundActive,
              request.canPresent(), let url = WebsiteURL.validated(request.url.absoluteString) else {
            failPending(request.id)
            return
        }
        presenter.view.endEditing(true)
        let controller = SFSafariViewController(url: url)
        controller.delegate = self
        // Keep SFSafariViewController's default modal presentation and custom
        // transition. It is never embedded in a SwiftUI sheet or child hierarchy.
        activeID = request.id
        browser = controller
        presenter.present(controller, animated: true) { [weak self, weak controller] in
            guard let self, let controller, self.browser === controller else { return }
            controller.presentationController?.delegate = self
            if controller.presentingViewController == nil { self.finish(failed: true) }
        }
    }

    private func waitForTransition(_ controller: UIViewController, requestID: UUID) {
        guard let transition = controller.transitionCoordinator else {
            failPending(requestID)
            return
        }
        transition.animate(alongsideTransition: nil) { [weak self] _ in
            self?.schedulePresentation()
        }
    }

    private func failPending(_ id: UUID) {
        guard pending?.id == id, activeID == nil else { return }
        completedID = id
        pending = nil
        onFailure?(id)
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        guard controller === browser else { return }
        // Safari starts its own dismissal after this delegate callback returns.
        DispatchQueue.main.async { [weak self] in self?.finish(failed: false) }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === browser else { return }
        finish(failed: false)
    }

    private func finish(failed: Bool) {
        guard let controller = browser, let id = activeID, !finishing else { return }
        finishing = true
        let completion: @MainActor () -> Void = { [weak self] in
            guard let self, self.activeID == id else { return }
            self.completedID = id
            self.activeID = nil
            self.browser = nil
            self.finishing = false
            if self.pending?.id == id { self.pending = nil }
            if failed { self.onFailure?(id) }
            else { self.onDismiss?(id) }
            self.schedulePresentation()
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
