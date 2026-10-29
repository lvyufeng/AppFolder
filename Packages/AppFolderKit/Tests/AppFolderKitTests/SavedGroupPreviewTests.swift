import Testing
@testable import AppFolderKit

@Suite("Saved group miniature previews")
struct SavedGroupPreviewTests {
    @Test("Actions at the fourth folder level remain visible from every ancestor")
    func deepestLegalActions() {
        var item = GroupItem.action(name: "Deep action")
        for depth in (1...SavedGroup.maximumDepth).reversed() {
            item = .folder(name: "Level \(depth)", children: [.spacer(), item])
            #expect(item.previewActionNames == ["Deep action"])
        }
        #expect(SavedGroup(name: "Four levels", items: [item]).isValid)
        #expect(item.previewActionNames == ["Deep action"])
    }

    @Test("Depth-first previews preserve repeated names, skip spaces, and stop at four")
    func orderedFourNames() {
        let item = GroupItem.folder(name: "Root", children: [
            .spacer(), .action(name: "Maps"),
            .folder(name: "Travel", children: [
                .action(name: "Camera"), .spacer(),
                .folder(name: "Again", children: [.action(name: "Maps")]),
                .action(name: "Tickets"), .action(name: "Not shown"),
            ]),
            .action(name: "Later sibling"),
        ])
        #expect(SavedGroup(name: "Ordered", items: [item]).isValid)
        #expect(item.previewActionNames == ["Maps", "Camera", "Maps", "Tickets"])
        #expect(item.previewActionNames.count == 4)
        #expect(item.previewActionNames.count == MiniGridDensity.maximumCapacity)
    }

    @Test("A final action at the 200-node boundary is included without reading beyond it")
    func nodeBudgetIncludesTheRoot() {
        let spaces = (0..<(SavedGroup.maximumItems - 2)).map { _ in GroupItem.spacer() }
        let last = GroupItem.action(name: "Last legal node")
        let legal = GroupItem.folder(name: "Root", children: spaces + [last])
        #expect(SavedGroup(name: "Full", items: [legal]).isValid)
        #expect(legal.previewActionNames == [last.name])

        let oversized = GroupItem.folder(name: "Root", children: spaces + [.spacer(), last])
        #expect(!SavedGroup(name: "Too many", items: [oversized]).isValid)
        #expect(oversized.previewActionNames.isEmpty)
    }

    @Test("An unsaved fifth folder level is skipped without hiding a later legal sibling")
    func depthBudgetSkipsOnlyTheTooDeepBranch() {
        var item = GroupItem.action(name: "Too deep")
        for depth in 1...(SavedGroup.maximumDepth + 1) {
            item = .folder(name: "Level \(depth)", children: [item])
        }
        item.children.append(.action(name: "Visible sibling"))
        #expect(!SavedGroup(name: "Too deep", items: [item]).isValid)
        #expect(item.previewActionNames == ["Visible sibling"])
    }

    @Test("Only folder children contribute descendant artwork")
    func leafAndEmptyShapes() {
        #expect(GroupItem.folder(name: "Empty").previewActionNames.isEmpty)
        #expect(GroupItem.spacer().previewActionNames.isEmpty)
        #expect(GroupItem.action(name: "Maps").previewActionNames == ["Maps"])
        let hidden = [GroupItem.action(name: "Hidden")]
        #expect(GroupItem(kind: .action, name: "Maps", children: hidden).previewActionNames == ["Maps"])
        #expect(GroupItem(kind: .spacer, children: hidden).previewActionNames.isEmpty)
    }
}
