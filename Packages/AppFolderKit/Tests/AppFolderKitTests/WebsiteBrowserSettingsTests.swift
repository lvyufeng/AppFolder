import Foundation
import Testing
@testable import AppFolderKit

@Suite("Local website browser settings")
struct WebsiteBrowserSettingsTests {
    @Test("Missing, unknown, malformed and recursive preferences read as system default without repairing stored data")
    func invalidPreferenceReads() throws {
        let suite = "WebsiteBrowserSettings.invalid.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(WebsiteBrowserSettings.selectedBrowser(in: defaults) == .systemDefault)
        #expect(defaults.object(forKey: WebsiteBrowserSettings.defaultsKey) == nil)
        let invalid: [Any] = ["", "unknown", "appDefault", " Chrome", "CHROME", 1, true,
                              Data([1, 2, 3]), ["chrome"], ["browser": "chrome"]]
        for value in invalid {
            defaults.set(value, forKey: WebsiteBrowserSettings.defaultsKey)
            let before = defaults.persistentDomain(forName: suite) ?? [:]
            #expect(WebsiteBrowserSettings.selectedBrowser(in: defaults) == .systemDefault)
            #expect(NSDictionary(dictionary: before).isEqual(to: defaults.persistentDomain(forName: suite) ?? [:]))
        }
    }

    @Test("Concrete choices persist in only the supplied defaults suite; recursive writes leave the last choice intact")
    func isolatedPersistence() throws {
        let firstSuite = "WebsiteBrowserSettings.first.\(UUID())"
        let secondSuite = "WebsiteBrowserSettings.second.\(UUID())"
        let first = try #require(UserDefaults(suiteName: firstSuite))
        let second = try #require(UserDefaults(suiteName: secondSuite))
        defer {
            first.removePersistentDomain(forName: firstSuite)
            second.removePersistentDomain(forName: secondSuite)
        }
        #expect(!WebsiteBrowserSettings.setBrowser(.appDefault, in: first))
        #expect(first.object(forKey: WebsiteBrowserSettings.defaultsKey) == nil)
        for browser in WebsiteBrowser.concreteCases {
            #expect(WebsiteBrowserSettings.setBrowser(browser, in: first))
            #expect(first.object(forKey: WebsiteBrowserSettings.defaultsKey) as? String == browser.rawValue)
            let reopened = try #require(UserDefaults(suiteName: firstSuite))
            #expect(WebsiteBrowserSettings.selectedBrowser(in: reopened) == browser)
            #expect(WebsiteBrowserSettings.selectedBrowser(in: second) == .systemDefault)
            #expect(second.object(forKey: WebsiteBrowserSettings.defaultsKey) == nil)
            #expect(!WebsiteBrowserSettings.setBrowser(.appDefault, in: first))
            #expect(WebsiteBrowserSettings.selectedBrowser(in: first) == browser)
        }
        #expect(WebsiteBrowserSettings.setBrowser(.chrome, in: first))
        #expect(WebsiteBrowserSettings.setBrowser(.firefox, in: second))
        #expect(WebsiteBrowserSettings.selectedBrowser(in: first) == .chrome)
        #expect(WebsiteBrowserSettings.selectedBrowser(in: second) == .firefox)
    }

    @Test("Only an explicit follow-app website inherits the local setting; old records and their revisions never change")
    func optInAndHistory() throws {
        let suite = "WebsiteBrowserSettings.history.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = SavedGroup(name: "Links", items: [
            .website(name: "Old nil", url: "https://example.org/"),
            .website(name: "Explicit system", url: "https://example.org/", browser: .systemDefault)
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let oldJSON = try encoder.encode(original)
        let oldRevision = original.revision
        var changed = original
        changed.items[0].websiteBrowser = .appDefault
        let followingJSON = try encoder.encode(changed)
        let followingRevision = changed.revision
        #expect(followingRevision != oldRevision)
        var history = SavedGroupEditHistory()
        let recorded = history.record(before: original, after: changed)
        #expect(recorded)
        for selection in WebsiteBrowser.concreteCases {
            #expect(WebsiteBrowserSettings.setBrowser(selection, in: defaults))
            let appBrowser = WebsiteBrowserSettings.selectedBrowser(in: defaults)
            #expect(original.items.allSatisfy { $0.effectiveWebsiteBrowser.resolved(using: appBrowser) == .systemDefault })
            #expect(changed.items[0].effectiveWebsiteBrowser.resolved(using: appBrowser) == selection)
            #expect(changed.items[1].effectiveWebsiteBrowser.resolved(using: appBrowser) == .systemDefault)
            #expect(try encoder.encode(original) == oldJSON && original.revision == oldRevision)
            #expect(try encoder.encode(changed) == followingJSON && changed.revision == followingRevision)
        }
        let undoResult = history.undo(current: changed)
        let undone = try #require(undoResult)
        #expect(undone == original && undone.items[0].websiteBrowser == nil)
        let redoResult = history.redo(current: undone)
        let redone = try #require(redoResult)
        #expect(redone == changed && redone.items[0].websiteBrowser == .appDefault)
    }
}
