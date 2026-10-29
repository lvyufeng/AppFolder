import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group local help routes")
struct SavedGroupHelpRouteTests {
    private let groupID = UUID(uuidString: "A1B2C3D4-1234-5678-9ABC-123456789ABC")!
    private let itemID = UUID(uuidString: "D4C3B2A1-4321-8765-CBA9-CBA987654321")!
    private let reportID = String(repeating: "0123456789abcdef", count: 4)

    @Test("Every optional context combination round trips using identifiers only")
    func roundTrips() {
        let routes = [
            SavedGroupHelpRoute(groupID: groupID),
            SavedGroupHelpRoute(groupID: groupID, itemID: itemID),
            SavedGroupHelpRoute(groupID: groupID, reportID: reportID),
            SavedGroupHelpRoute(groupID: groupID, itemID: itemID, reportID: reportID),
        ]
        for route in routes {
            #expect(route.surface == .homeScreen)
            #expect(!route.url.absoluteString.contains("surface="))
            #expect(SavedGroupHelpRoute(url: route.url) == route)
            #expect(route.url.absoluteString.utf8.count <= SavedGroupHelpRoute.maximumUTF8Bytes)
            #expect(route.url.scheme == "appfolder")
            #expect(route.url.host == "group-help")
        }
        #expect(routes[0].url.absoluteString == "appfolder://group-help?group=\(groupID.uuidString)")
        #expect(routes[3].url.absoluteString == "appfolder://group-help?group=\(groupID.uuidString)&item=\(itemID.uuidString)&report=\(reportID)")
    }

    @Test("Lock screen help retains its context with any optional item or report")
    func lockScreenContext() throws {
        for item in [nil, itemID] {
            for report in [nil, reportID] {
                let route = SavedGroupHelpRoute(groupID: groupID, itemID: item, reportID: report, surface: .lockScreen)
                let home = SavedGroupHelpRoute(groupID: groupID, itemID: item, reportID: report)
                #expect(route.url.absoluteString == home.url.absoluteString + "&surface=lock-screen")
                #expect(SavedGroupHelpRoute(url: route.url) == route)
                #expect(route != home)
                #expect(route.url.absoluteString.utf8.count <= SavedGroupHelpRoute.maximumUTF8Bytes)
            }
        }
        let reordered = try #require(URL(string: "appfolder://group-help?surface=lock-screen&report=\(reportID)&item=\(itemID.uuidString)&group=\(groupID.uuidString)"))
        let parsed = try #require(SavedGroupHelpRoute(url: reordered))
        #expect(parsed == SavedGroupHelpRoute(groupID: groupID, itemID: itemID, reportID: reportID, surface: .lockScreen))
    }

    @Test("Unknown, duplicated or escaped surface hints cannot become desktop help")
    func rejectsMalformedSurface() {
        let prefix = "appfolder://group-help?group=\(groupID.uuidString)"
        let suffixes = [
            "&surface=", "&surface=home-screen", "&surface=lockScreen", "&surface=LOCK-SCREEN",
            "&surface=%6cock-screen", "&surface=lock%2Dscreen", "&surface=lock-screen%00",
            "&surface=lock-screen#fragment", "&surface=lock-screen&surface=lock-screen",
            "&surface=lock-screen&surface=", "&%73urface=lock-screen", "&Surface=lock-screen",
            "&surface=lock-screen&item=\(itemID.uuidString)&report=\(reportID)&extra=1",
            "&surface=lock-screen&report=invalid",
        ]
        for suffix in suffixes {
            let url = URL(string: prefix + suffix)
            #expect(url.flatMap(SavedGroupHelpRoute.init(url:)) == nil, "Rejected context: \(suffix)")
        }
    }

    @Test("Actual report IDs preserve the exact widget configuration and revision")
    func existingReportIdentity() throws {
        let item = GroupItem.action(name: "Private action name")
        var group = SavedGroup(name: "Private group title", items: [item])
        let first = try #require(SavedGroupBindingReport(group: group, configurationKey: "first-widget",
                                                        grid: .nine, familyRawValue: 0, actionNames: []))
        let second = try #require(SavedGroupBindingReport(group: group, configurationKey: "second-widget",
                                                         grid: .nine, familyRawValue: 0, actionNames: []))
        group.items.append(.action(name: "Another action"))
        let changed = try #require(SavedGroupBindingReport(group: group, configurationKey: "first-widget",
                                                          grid: .nine, familyRawValue: 0, actionNames: []))
        var routes: [SavedGroupHelpRoute] = []
        for report in [first, second, changed] {
            let route = SavedGroupHelpRoute(groupID: group.id, itemID: item.id, reportID: report.id)
            #expect(SavedGroupHelpRoute(url: route.url)?.reportID == report.id)
            #expect(!route.url.absoluteString.contains("Private"))
            #expect(!route.url.absoluteString.contains("widget"))
            routes.append(route)
        }
        #expect(routes[0] != routes[1])
        #expect(routes[0] != routes[2])
    }

    @Test("Query order and UUID letter case do not change navigation identity")
    func queryOrderAndUUIDCase() throws {
        let url = try #require(URL(string: "appfolder://group-help?report=\(reportID)&item=\(itemID.uuidString.lowercased())&group=\(groupID.uuidString.lowercased())"))
        let route = try #require(SavedGroupHelpRoute(url: url))
        #expect(route == SavedGroupHelpRoute(groupID: groupID, itemID: itemID, reportID: reportID))
        #expect(SavedGroupHelpRoute(url: route.url) == route)
    }

    @Test("Foreign or decorated authorities and fragments cannot enter local help")
    func rejectsOtherDestinations() {
        let suffix = "?group=\(groupID.uuidString)"
        let authorities = [
            "https://group-help", "file://group-help", "other://group-help", "APPFOLDER://group-help",
            "appfolder:group-help", "appfolder:///group-help", "appfolder://GROUP-HELP",
            "appfolder://other", "appfolder://group-help.evil.test", "appfolder://group-help.",
            "appfolder://user@group-help", "appfolder://:password@group-help", "appfolder://@group-help",
            "appfolder://group-help:80", "appfolder://group-help:", "appfolder://group-help:65536",
            "appfolder://group-help/", "appfolder://group-help/path", "appfolder://group-help/..",
            "appfolder://%67roup-help", "appfolder://group%2dhelp", "appfolder://group-help%2F",
        ]
        for authority in authorities {
            let result = URL(string: authority + suffix).flatMap(SavedGroupHelpRoute.init(url:))
            #expect(result == nil, "Rejected authority: \(authority)")
        }
        for fragment in ["#", "#help", "#&report=\(reportID)"] {
            let url = URL(string: "appfolder://group-help" + suffix + fragment)
            #expect(url.flatMap(SavedGroupHelpRoute.init(url:)) == nil)
        }
        let base = URL(string: "appfolder://group-help")!
        let relative = URL(string: suffix, relativeTo: base)!
        #expect(SavedGroupHelpRoute(url: relative) == nil)
    }

    @Test("Unknown, duplicate, missing and escaped query fields are rejected")
    func rejectsAmbiguousQuery() {
        let group = "group=\(groupID.uuidString)"
        let item = "item=\(itemID.uuidString)"
        let queries = [
            "", "group", "group=", item, "report=\(reportID)",
            "\(group)&\(group)", "\(group)&\(item)&\(item)",
            "\(group)&report=\(reportID)&report=\(reportID)",
            "\(group)&url=https://example.com", "\(group)&action=Maps", "\(group)&unknown=1",
            "\(group)&", "&\(group)", "\(group)&&\(item)", "\(group)&item=", "\(group)&report=",
            "\(group)=extra", "\(group);\(item)", "Group=\(groupID.uuidString)",
            "%67roup=\(groupID.uuidString)", "\(group)&%69tem=\(itemID.uuidString)",
            "\(group)&\(item)&report=\(reportID)&extra=1",
            "\(group)%26item%3D\(itemID.uuidString)", "group%3D\(groupID.uuidString)",
        ]
        for query in queries {
            let result = URL(string: "appfolder://group-help?" + query).flatMap(SavedGroupHelpRoute.init(url:))
            #expect(result == nil, "Rejected query: \(query)")
        }
    }

    @Test("Identifiers cannot contain alternate UUID formats or escaped controls")
    func rejectsInvalidUUIDs() {
        let values = [
            "not-a-uuid", String(groupID.uuidString.dropLast()), groupID.uuidString + "0",
            groupID.uuidString.replacingOccurrences(of: "-", with: ""),
            "{\(groupID.uuidString)}", "urn:uuid:\(groupID.uuidString)",
            "%41" + groupID.uuidString.dropFirst(), groupID.uuidString + "%00",
            groupID.uuidString + "%0A", groupID.uuidString + "+", groupID.uuidString + " ",
            "A1B2C3D4-1234-5678-9ABC-123456789ABＧ", groupID.uuidString + "%",
        ]
        for value in values {
            for query in ["group=\(value)", "group=\(groupID.uuidString)&item=\(value)"] {
                let result = URL(string: "appfolder://group-help?" + query).flatMap(SavedGroupHelpRoute.init(url:))
                #expect(result == nil, "Rejected identifier: \(value)")
            }
        }
    }

    @Test("Invalid optional report hints are safe in typed construction but rejected in URLs")
    func reportValidation() {
        let invalid = [
            "", String(repeating: "a", count: 63), String(repeating: "a", count: 65),
            reportID.uppercased(), String(repeating: "g", count: 64),
            String(repeating: "Ａ", count: 64), String(repeating: "é", count: 32),
            "%30" + reportID.dropFirst(), reportID + "%00", reportID + "#fragment",
        ]
        for value in invalid {
            let route = SavedGroupHelpRoute(groupID: groupID, itemID: itemID, reportID: value)
            #expect(route.reportID == nil)
            #expect(SavedGroupHelpRoute(url: route.url) == route)
            let url = URL(string: "appfolder://group-help?group=\(groupID.uuidString)&report=\(value)")
            #expect(url.flatMap(SavedGroupHelpRoute.init(url:)) == nil)
        }
    }

    @Test("Oversized URL input is rejected without truncating to a valid prefix")
    func boundsInput() throws {
        let prefix = SavedGroupHelpRoute(groupID: groupID).url.absoluteString
        for extra in [String(repeating: "a", count: 1_025), String(repeating: "中", count: 400)] {
            let url = try #require(URL(string: prefix + extra))
            #expect(url.absoluteString.utf8.count > SavedGroupHelpRoute.maximumUTF8Bytes)
            #expect(SavedGroupHelpRoute(url: url) == nil)
        }
    }
}
