import AppFolderKit
import CoreTransferable
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    static let savedGroupCanvasItem = UTType(
        exportedAs: "com.lvyufeng.appfolder.canvas-item", conformingTo: .data)
}

/// Only transient identities and a draft hash cross the native drag boundary.
private struct SavedGroupCanvasPayload: Codable, Transferable, Identifiable, Sendable {
    let source: SavedGroupDropSource
    var id: SavedGroupDropSource { source }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .savedGroupCanvasItem)
            .visibility(.ownProcess)
    }
}

@Observable @MainActor
final class SavedGroupCanvasDragController {
    private enum Mode { case idle, manual, native }
    private var session = SavedGroupDropSession()
    private var mode: Mode = .idle
    private var context: SavedGroupCanvasContext?
    private var nativeSessionID: DragSession.ID?
    private var nativeDropSessionID: DropSession.ID?
    private var nativeIsEnding = false
    private(set) var hoverTargetID: String?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var hoverToken: UUID?

    var activeSource: SavedGroupDropSource? { session.activeSource }
    var isManualSelection: Bool { mode == .manual && activeSource != nil }
    var isNativeDragging: Bool { mode == .native && activeSource != nil }

    @discardableResult
    func selectManual(itemID: UUID) -> Bool {
        guard let context, context.enabled, mode != .native else { return false }
        cancel()
        let source = session.source(groupID: context.groupID, itemID: itemID,
                                    revision: context.revision)
        guard session.begin(source) else { return false }
        mode = .manual
        return true
    }

    func requestManual(target: SavedGroupDropTarget) -> SavedGroupDropRequest? {
        guard mode == .manual, let source = activeSource, isCurrent(source),
              let request = session.consume(source, target: target) else { return nil }
        resetInteraction()
        return request
    }

    func cancel() {
        session.cancel()
        resetInteraction()
    }

    fileprivate func configure(_ next: SavedGroupCanvasContext) {
        guard context != next else { return }
        cancel()
        context = next
    }

    fileprivate func source(for itemID: UUID) -> SavedGroupDropSource? {
        guard let context, context.enabled, mode != .manual else { return nil }
        return session.source(groupID: context.groupID, itemID: itemID,
                              revision: context.revision)
    }

    fileprivate func payloads(for sources: [SavedGroupDropSource]) -> [SavedGroupCanvasPayload] {
        // SwiftUI can ask for transfer data after a drag ends. This getter never
        // begins a session or recreates permission revoked by cancel/consume.
        guard sources.count == 1, let source = sources.first, isCurrent(source),
              mode != .manual else { return [] }
        return [SavedGroupCanvasPayload(source: source)]
    }

    fileprivate func dragUpdated(_ drag: DragSession) {
        let sources = drag.draggedItemIDs(for: SavedGroupDropSource.self)
        guard sources.count == 1, let source = sources.first, isCurrent(source) else {
            if nativeSessionID == drag.id { cancel() }
            return
        }
        switch drag.phase {
        case .initial:
            guard mode == .idle, nativeSessionID == nil,
                  session.begin(source) else { return }
            mode = .native
            nativeSessionID = drag.id
            nativeIsEnding = false
        case .active:
            break
        case .ending(let operation), .ended(let operation):
            guard mode == .native, nativeSessionID == drag.id, activeSource == source else { return }
            cancelHover()
            if operation == .move {
                // Transfer decoding may complete after a successful lift ends.
                // Only the typed drop closure consumes the one-use permission.
                nativeIsEnding = true
            } else {
                cancel()
            }
        case .dataTransferCompleted:
            guard mode == .native, nativeSessionID == drag.id, activeSource == source else { return }
            cancel()
        @unknown default:
            if nativeSessionID == drag.id { cancel() }
        }
    }

    fileprivate var acceptsNativeDrop: Bool {
        context?.enabled == true && isNativeDragging
    }

    fileprivate func accepts(_ drop: DropSession) -> Bool {
        guard acceptsNativeDrop, drop.itemsCount == 1,
              let source = activeSource, isCurrent(source),
              let local = drop.localSession,
              local.draggedItemIDs(for: SavedGroupDropSource.self) == [source],
              nativeDropSessionID == nil || nativeDropSessionID == drop.id else { return false }
        return true
    }

    fileprivate func dropUpdated(_ drop: DropSession, targetID: String,
                                 onHover: (@MainActor () -> Void)?) {
        // An exiting target is not a cancelled drag: another page/folder may
        // become its next destination while the same native session continues.
        if drop.phase == .exiting {
            if nativeDropSessionID == drop.id, hoverTargetID == targetID { cancelHover() }
            return
        }
        guard accepts(drop) else {
            if nativeDropSessionID == drop.id { cancelHover() }
            return
        }
        if nativeDropSessionID == nil { nativeDropSessionID = drop.id }
        switch drop.phase {
        case .entering, .active:
            guard !nativeIsEnding else { return }
            if hoverTargetID != targetID {
                cancelHover()
                hoverTargetID = targetID
                if let onHover { scheduleHover(targetID: targetID, onHover: onHover) }
            }
        case .ended(let operation):
            cancelHover()
            if operation == .move { nativeIsEnding = true } else { cancel() }
        case .dataTransferCompleted:
            cancel()
        case .exiting:
            break
        @unknown default:
            cancel()
        }
    }

    fileprivate func performDrop(_ payloads: [SavedGroupCanvasPayload], drop: DropSession,
                                 target: SavedGroupDropTarget?,
                                 onDrop: @MainActor (SavedGroupDropRequest) -> Bool) -> Bool {
        guard accepts(drop), payloads.count == 1,
              let source = payloads.first?.source, source == activeSource,
              isCurrent(source) else { return false }
        guard let target else { cancel(); return false }
        guard let request = session.consume(source, target: target) else { return false }
        resetInteraction()
        return onDrop(request)
    }

    private func isCurrent(_ source: SavedGroupDropSource) -> Bool {
        guard let context, context.enabled, source.groupID == context.groupID,
              source.revision == context.revision else { return false }
        return source == session.source(groupID: context.groupID, itemID: source.itemID,
                                        revision: context.revision)
    }

    private func scheduleHover(targetID: String, onHover: @escaping @MainActor () -> Void) {
        guard let source = activeSource, let dragID = nativeSessionID,
              let dropID = nativeDropSessionID else { return }
        let token = UUID()
        hoverToken = token
        // Capture only immutable, Sendable session identifiers, never the
        // system DragSession/DropSession values across the suspension point.
        hoverTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard let self, !Task.isCancelled, self.hoverToken == token,
                  self.hoverTargetID == targetID, self.mode == .native,
                  !self.nativeIsEnding, self.nativeSessionID == dragID,
                  self.nativeDropSessionID == dropID, self.activeSource == source,
                  self.isCurrent(source) else { return }
            self.hoverTask = nil
            self.hoverToken = nil
            // Keep the target latched until it exits; repeated active updates
            // must not repeatedly flip pages while the pointer stays still.
            onHover()
        }
    }

    private func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
        hoverToken = nil
        hoverTargetID = nil
    }

    private func resetInteraction() {
        cancelHover()
        mode = .idle
        nativeSessionID = nil
        nativeDropSessionID = nil
        nativeIsEnding = false
    }
}

private struct SavedGroupCanvasContext: Equatable {
    let groupID: UUID
    let revision: String
    let enabled: Bool
}

@MainActor
extension View {
    func savedGroupCanvasDragContainer(controller: SavedGroupCanvasDragController,
                                       namespace: Namespace.ID, groupID: UUID,
                                       revision: String, enabled: Bool = true) -> some View {
        modifier(SavedGroupCanvasContainerModifier(controller: controller, namespace: namespace,
                                                   groupID: groupID, revision: revision, enabled: enabled))
    }

    func savedGroupCanvasDragSource(controller: SavedGroupCanvasDragController,
                                    namespace: Namespace.ID, itemID: UUID) -> some View {
        modifier(SavedGroupCanvasSourceModifier(controller: controller, namespace: namespace, itemID: itemID))
    }

    func savedGroupCanvasDropDestination(controller: SavedGroupCanvasDragController,
                                         targetID: String, target: SavedGroupDropTarget?,
                                         onHover: (@MainActor () -> Void)? = nil,
                                         onDrop: @escaping @MainActor (SavedGroupDropRequest) -> Bool) -> some View {
        modifier(SavedGroupCanvasDestinationModifier(controller: controller, targetID: targetID,
                                                     target: target, onHover: onHover, onDrop: onDrop))
    }
}

private struct SavedGroupCanvasContainerModifier: ViewModifier {
    let controller: SavedGroupCanvasDragController
    let namespace: Namespace.ID
    let groupID: UUID
    let revision: String
    let enabled: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var context: SavedGroupCanvasContext {
        .init(groupID: groupID, revision: revision, enabled: enabled && scenePhase == .active)
    }

    func body(content: Content) -> some View {
        content
            .dragContainer(for: SavedGroupCanvasPayload.self, in: namespace) {
                (sources: [SavedGroupDropSource]) in controller.payloads(for: sources)
            }
            .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowMove: true),
                                                  operationsOutsideApp: .init(allowCopy: false)))
            .onDragSessionUpdated { controller.dragUpdated($0) }
            .onAppear { controller.configure(context) }
            .onChange(of: context) { _, next in controller.configure(next) }
            .onDisappear { controller.cancel() }
    }
}

private struct SavedGroupCanvasSourceModifier: ViewModifier {
    let controller: SavedGroupCanvasDragController
    let namespace: Namespace.ID
    let itemID: UUID

    @ViewBuilder
    func body(content: Content) -> some View {
        if let source = controller.source(for: itemID) {
            content.draggable(containerItemID: source, containerNamespace: namespace)
        } else {
            content
        }
    }
}

private struct SavedGroupCanvasDestinationModifier: ViewModifier {
    let controller: SavedGroupCanvasDragController
    let targetID: String
    let target: SavedGroupDropTarget?
    let onHover: (@MainActor () -> Void)?
    let onDrop: @MainActor (SavedGroupDropRequest) -> Bool

    func body(content: Content) -> some View {
        content
            .dropDestination(for: SavedGroupCanvasPayload.self, isEnabled: controller.acceptsNativeDrop) {
                payloads, drop in
                _ = controller.performDrop(payloads, drop: drop, target: target, onDrop: onDrop)
            }
            .dropConfiguration { drop in
                DropConfiguration(operation: controller.accepts(drop) ? (target == nil ? .cancel : .move) : .forbidden)
            }
            .onDropSessionUpdated { drop in
                controller.dropUpdated(drop, targetID: targetID, onHover: onHover)
            }
    }
}
