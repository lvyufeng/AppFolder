import Foundation
import Testing
@testable import AppFolderKit

@Suite("Contact identity routes")
struct ContactLaunchRouteTests {
    @Test("Routes carry only canonical identities and survive a folder move")
    func roundtripAndMove() throws {
        let target = try #require(ContactTarget(operation: .message, number: "+1 (202) 555-0123"))
        let contact = GroupItem.contact(name: "Fixture", target: target)
        let folder = GroupItem.folder(name: "Destination")
        var group = SavedGroup(name: "Contacts", items: [contact, folder])
        let route = ContactLaunchRoute(groupID: group.id, itemID: contact.id)
        #expect(ContactLaunchRoute(url: route.url) == route)
        #expect(!route.url.absoluteString.contains("Fixture") && !route.url.absoluteString.contains("2025550123"))
        #expect(route.resolve(in: group) == contact)
        let moved = group.move(itemID: contact.id, to: [folder.id])
        #expect(moved)
        #expect(route.resolve(in: group) == contact)
        group.items[0].children.removeAll()
        #expect(route.resolve(in: group) == nil)
    }

    @Test("A stale route does not select a replacement or a different kind")
    func noFallback() throws {
        let target = try #require(ContactTarget(operation: .phone, number: "2025550123"))
        let contact = GroupItem.contact(name: "Fixture", target: target)
        var group = SavedGroup(name: "Contacts", items: [contact])
        let route = ContactLaunchRoute(groupID: group.id, itemID: contact.id)
        group.items = [.contact(name: contact.name, target: target)]
        #expect(route.resolve(in: group) == nil)
        group.items = [.init(id: contact.id, kind: .action, name: contact.name)]
        #expect(route.resolve(in: group) == nil)
        group.items = [contact]
        group.id = UUID()
        #expect(route.resolve(in: group) == nil)
    }

    @Test("Untrusted routes cannot carry a number, operation, alternate authority or duplicate identity")
    func strictParsing() throws {
        let group = "aaaaaaaa-0000-0000-0000-000000000001"
        let item = "bbbbbbbb-0000-0000-0000-000000000002"
        let valid = "appfolder://contact?group=\(group)&item=\(item)"
        let invalid = [
            valid + "&number=2025550123", valid + "&operation=faceTimeVideo", valid + "#fragment",
            valid + "&group=\(group)", valid + "&", valid.replacingOccurrences(of: "&item=", with: "&group="),
            valid.replacingOccurrences(of: "contact?", with: "contact:80?"),
            valid.replacingOccurrences(of: "contact?", with: "user@contact?"),
            valid.replacingOccurrences(of: "contact?", with: "contact/?"),
            valid.replacingOccurrences(of: "appfolder:", with: "https:"),
            valid.replacingOccurrences(of: group, with: group.uppercased()),
            valid.replacingOccurrences(of: group, with: group.replacingOccurrences(of: "-", with: "%2D")),
            "appfolder://contact?item=\(item)", "appfolder://contact?group=\(group)&item=",
        ]
        for raw in invalid {
            let url = try #require(URL(string: raw))
            #expect(ContactLaunchRoute(url: url) == nil, "Rejected noncanonical route")
        }
        let reordered = try #require(URL(string: "appfolder://contact?item=\(item)&group=\(group)"))
        #expect(ContactLaunchRoute(url: reordered) != nil)
    }
}
