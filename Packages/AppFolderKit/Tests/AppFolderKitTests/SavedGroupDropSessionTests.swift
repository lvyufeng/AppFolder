import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group drop sessions")
struct SavedGroupDropSessionTests {
    @Test("Rendered sources are stable within one epoch and active identity cannot be replaced by another drag")
    func beginIdentity() throws {
        var session = SavedGroupDropSession()
        let group = UUID(), item = UUID()
        let first = session.source(groupID: group, itemID: item, revision: "snapshot")
        #expect(first == session.source(groupID: group, itemID: item, revision: "snapshot"))
        #expect(session.activeSource == nil)
        #expect(session.consume(first, target: .append(folderID: nil)) == nil)
        let began = session.begin(first)
        #expect(began && session.activeSource == first)
        let repeated = session.begin(first)
        #expect(repeated)
        for other in [session.source(groupID: group, itemID: UUID(), revision: "snapshot"),
                      session.source(groupID: group, itemID: item, revision: "changed"),
                      session.source(groupID: UUID(), itemID: item, revision: "snapshot")] {
            let replaced = session.begin(other)
            #expect(!replaced && session.activeSource == first)
            #expect(session.consume(other, target: .append(folderID: nil)) == nil && session.activeSource == first)
        }
        let encoded = try JSONEncoder().encode(first)
        let decoded = try JSONDecoder().decode(SavedGroupDropSource.self, from: encoded)
        #expect(decoded == first && Set([first, decoded]).count == 1)
        let keys = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(keys.keys) == ["sessionID", "groupID", "itemID", "revision"])
    }

    @Test("Cancel invalidates both rendered and active sources; a foreign editor cannot begin or consume this session")
    func cancelAndForeignEpoch() {
        for started in [false, true] {
            var session = SavedGroupDropSession()
            let group = UUID(), item = UUID()
            let old = session.source(groupID: group, itemID: item, revision: "same")
            if started { _ = session.begin(old) }
            session.cancel()
            let restartedOld = session.begin(old)
            #expect(!restartedOld && session.activeSource == nil)
            #expect(session.consume(old, target: .append(folderID: nil)) == nil)
            let current = session.source(groupID: group, itemID: item, revision: "same")
            #expect(current.sessionID != old.sessionID && current.itemID == old.itemID)
            let foreign = SavedGroupDropSession().source(groupID: group, itemID: item, revision: "same")
            let beganForeign = session.begin(foreign)
            #expect(!beganForeign && session.activeSource == nil)
            let began = session.begin(current)
            #expect(began)
            #expect(session.consume(foreign, target: .append(folderID: nil)) == nil && session.activeSource == current)
        }
    }

    @Test("Consume rotates the epoch before returning, so duplicate callbacks and failed model operations cannot replay")
    func oneUseConsumption() throws {
        var session = SavedGroupDropSession()
        let item = GroupItem.action(name: "A")
        var group = SavedGroup(name: "Grid", items: [item])
        let original = group
        let source = session.source(groupID: group.id, itemID: item.id, revision: group.revision)
        _ = session.begin(source)
        let target = SavedGroupDropTarget.before(itemID: UUID())
        let consumed = session.consume(source, target: target)
        let request = try #require(consumed)
        #expect(request == .init(groupID: group.id, itemID: item.id, expectedRevision: source.revision, target: target))
        #expect(session.activeSource == nil)
        #expect(session.source(groupID: group.id, itemID: item.id, revision: group.revision).sessionID != source.sessionID)
        #expect(session.consume(source, target: target) == nil)
        let replay = session.begin(source)
        #expect(!replay)
        let result = group.applyDrop(request)
        #expect(result == .rejected(.invalidTarget) && group == original)
        let fresh = session.source(groupID: group.id, itemID: item.id, revision: group.revision)
        let began = session.begin(fresh)
        #expect(began && session.activeSource == fresh)
    }

    @Test("Cancelling for undo prevents an old drag from reviving after redo restores the identical group revision")
    func undoRedoDoesNotRevive() throws {
        let a = GroupItem.action(name: "A"), b = GroupItem.action(name: "B")
        let before = SavedGroup(name: "Grid", items: [a, b])
        var after = before
        after.items.swapAt(0, 1)
        var history = SavedGroupEditHistory()
        history.record(before: before, after: after)
        var session = SavedGroupDropSession()
        let old = session.source(groupID: after.id, itemID: a.id, revision: after.revision)
        _ = session.begin(old)
        session.cancel()
        let undo = history.undo(current: after)
        let restored = try #require(undo)
        let redo = history.redo(current: restored)
        let current = try #require(redo)
        #expect(current == after && current.revision == old.revision)
        let revived = session.begin(old)
        #expect(!revived && session.consume(old, target: .append(folderID: nil)) == nil)
        #expect(current == after)
        let fresh = session.source(groupID: current.id, itemID: a.id, revision: current.revision)
        let began = session.begin(fresh)
        #expect(began)
    }
}
