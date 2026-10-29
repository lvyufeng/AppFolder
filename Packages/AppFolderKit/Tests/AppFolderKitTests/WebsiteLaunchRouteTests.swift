import Foundation
import Testing
@testable import AppFolderKit

@Suite("Website launch identity routes")
struct WebsiteLaunchRouteTests {
    @Test("Routes resolve the current website and choice after moves and edits, never a remembered URL")
    func freshResolution() throws {
        let item = GroupItem.website(name: "Site", url: "https://example.org/old", browser: .chrome)
        var group = SavedGroup(name: "Links", items: [item])
        let route = WebsiteLaunchRoute(groupID: group.id, itemID: item.id)
        #expect(WebsiteLaunchRoute(url: route.url) == route)
        #expect(route.resolve(in: group) == item)
        var edited = item
        edited.websiteURL = "https://example.org/new?q=A%2BB#part"
        edited.websiteBrowser = .firefox
        group.items = [.folder(name: "Moved", children: [edited])]
        #expect(route.resolve(in: group) == edited)
        #expect(route.resolve(in: group)?.effectiveWebsiteBrowser == .firefox)
        group.items[0].children = [.website(name: item.name, url: item.websiteURL!)]
        #expect(route.resolve(in: group) == nil)
        group.items = []
        #expect(route.resolve(in: group) == nil)
    }

    @Test("Routes cannot inject destinations, browser selections, duplicate IDs or alternate authorities")
    func rejectsUntrustedRoutes() throws {
        let group = "00000000-0000-0000-0000-000000000001"
        let item = "aaaaaaaa-0000-0000-0000-000000000002"
        let prefix = "appfolder://website?"
        let query = "group=\(group)&item=\(item)"
        let valid = try #require(URL(string: prefix + query))
        #expect(WebsiteLaunchRoute(url: valid) != nil)
        for raw in [
            prefix + query + "&url=https://evil.example", prefix + query + "&browser=chrome",
            prefix + query + "&group=\(group)", prefix + "group=\(group)&group=\(group)",
            prefix + "group=\(group)&item=\(item.uppercased())", prefix + query + "#fragment",
            "appfolder://user@website?" + query, "appfolder://website:80?" + query,
            "appfolder://website/?" + query, "appfolder://contact?" + query,
            prefix + "group=%30" + group.dropFirst() + "&item=\(item)", prefix + query + "&"
        ] {
            #expect(WebsiteLaunchRoute(url: try #require(URL(string: raw))) == nil)
        }
        let relative = try #require(URL(string: "?" + query, relativeTo: URL(string: "appfolder://website")))
        #expect(relative.absoluteString == valid.absoluteString && relative.baseURL != nil)
        #expect(WebsiteLaunchRoute(url: relative) == nil)
    }

    @Test("Wrong group, changed node kind and invalid saved state cannot launch")
    func invalidSavedState() {
        let item = GroupItem.website(name: "Site", url: "https://example.org/", browser: .inAppSafari)
        let original = SavedGroup(name: "Links", items: [item])
        let route = WebsiteLaunchRoute(groupID: original.id, itemID: item.id)
        var group = original
        group.id = UUID()
        #expect(route.resolve(in: group) == nil)
        group = original
        group.items[0] = .init(id: item.id, kind: .action, name: "Site")
        #expect(route.resolve(in: group) == nil)
        group = original
        group.items[0].websiteURL = "javascript:alert(1)"
        #expect(route.resolve(in: group) == nil)
        group = original
        group.items.append(item)
        #expect(route.resolve(in: group) == nil)
    }
}
