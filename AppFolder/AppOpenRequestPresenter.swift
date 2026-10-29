import SwiftUI
import UIKit

/// External widget links and backup documents can arrive while an editor sheet
/// is open. Present above that sheet so its state survives the external visit.
struct AppOpenRequestPresenter: UIViewControllerRepresentable {
    let request: AppOpenRequest?
    let onDismiss: @MainActor (UUID) -> Void

    func makeUIViewController(context: Context) -> AppOpenPresentationController {
        AppOpenPresentationController()
    }

    func updateUIViewController(_ controller: AppOpenPresentationController, context: Context) {
        controller.update(request: request, onDismiss: onDismiss)
    }
}

@MainActor
final class AppOpenPresentationController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private var pending: AppOpenRequest?
    private var activeID: UUID?
    private var completedID: UUID?
    private var contentController: UIHostingController<AnyView>?
    private var finishing = false
    private var onDismiss: (@MainActor (UUID) -> Void)?

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

    func update(request: AppOpenRequest?, onDismiss: @escaping @MainActor (UUID) -> Void) {
        pending = request
        self.onDismiss = onDismiss
        schedulePresentation()
    }

    private func schedulePresentation() {
        DispatchQueue.main.async { [weak self] in self?.presentIfReady() }
    }

    private func presentIfReady() {
        guard contentController == nil, !finishing,
              let request = pending, request.id != completedID else { return }
        var presenter: UIViewController = self
        while let parent = presenter.parent { presenter = parent }
        // A full-screen editor may hide this anchor while its presenting root
        // still owns a valid scene. Walk that scene's existing presentation chain.
        while let existing = presenter.presentedViewController {
            if existing.isBeingDismissed || existing.isBeingPresented {
                if let transition = existing.transitionCoordinator {
                    transition.animate(alongsideTransition: nil) { [weak self] _ in
                        self?.schedulePresentation()
                    }
                }
                return
            }
            presenter = existing
        }
        guard presenter.viewIfLoaded?.window != nil else { return }
        presenter.view.endEditing(true)
        let close: () -> Void = { [weak self] in self?.finish() }
        let content = NavigationStack {
            switch request.destination {
            case .backup(let url): BackupView(initialImportURL: url, onClose: close)
            case .groupHelp(let route): WidgetConfigurationHelpView(route: route, onClose: close)
            case .contact(let route):
                ContactLaunchView(route: route, automaticLaunchPermission: request.automaticContactLaunchPermission,
                                  receivedAt: request.receivedAt, onClose: close)
            case .website(let route):
                WebsiteLaunchView(route: route, automaticLaunchPermission: request.automaticWebsiteLaunchPermission,
                                  receivedAt: request.receivedAt, onClose: close)
            }
        }
        let controller = UIHostingController(rootView: AnyView(content))
        controller.modalPresentationStyle = .pageSheet
        activeID = request.id
        contentController = controller
        controller.presentationController?.delegate = self
        presenter.present(controller, animated: true) { [weak self, weak controller] in
            controller?.presentationController?.delegate = self
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === contentController else { return }
        finish()
    }

    private func finish() {
        guard let controller = contentController, let id = activeID, !finishing else { return }
        finishing = true
        let completion: @MainActor () -> Void = { [weak self] in
            guard let self, self.activeID == id else { return }
            self.completedID = id
            self.activeID = nil
            self.contentController = nil
            self.finishing = false
            self.pending = nil
            self.onDismiss?(id)
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
