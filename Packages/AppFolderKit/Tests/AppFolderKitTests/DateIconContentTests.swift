import Foundation
import Testing
@testable import AppFolderKit

@Suite("Local date content and timeline boundaries")
struct DateIconContentTests {
    private let english = Locale(identifier: "en_US_POSIX")

    @Test("Los Angeles spring and autumn boundaries follow 23-hour and 25-hour local days")
    func daylightSavingDays() throws {
        let calendar = try calendar(.gregorian, zone: "America/Los_Angeles")
        let spring = try instant("2024-03-10T08:00:00Z") // March 10, 00:00 PST
        let springPlan = DateIconTimelinePlan(now: spring, containsDateIcon: true, needsArtworkRetry: false, calendar: calendar)
        #expect(springPlan.dates == [spring, try instant("2024-03-11T07:00:00Z"),
                                    try instant("2024-03-12T07:00:00Z"), try instant("2024-03-13T07:00:00Z")])
        #expect(springPlan.dates[1].timeIntervalSince(spring) == 23 * 60 * 60)
        #expect(springPlan.reloadDate == springPlan.dates[1])
        #expect(springPlan.dates.map { DateIconContent(date: $0, calendar: calendar, locale: english).day } == ["10", "11", "12", "13"])

        let autumn = try instant("2024-11-03T07:00:00Z") // November 3, 00:00 PDT
        let autumnPlan = DateIconTimelinePlan(now: autumn, containsDateIcon: true, needsArtworkRetry: false, calendar: calendar)
        #expect(autumnPlan.dates == [autumn, try instant("2024-11-04T08:00:00Z"),
                                    try instant("2024-11-05T08:00:00Z"), try instant("2024-11-06T08:00:00Z")])
        #expect(autumnPlan.dates[1].timeIntervalSince(autumn) == 25 * 60 * 60)
        #expect(autumnPlan.reloadDate == autumnPlan.dates[1])
    }

    @Test("São Paulo's skipped midnight starts the next date at 01:00")
    func missingMidnight() throws {
        let calendar = try calendar(.gregorian, zone: "America/Sao_Paulo")
        let now = try instant("2018-11-03T15:00:00Z") // November 3, noon
        let plan = DateIconTimelinePlan(now: now, containsDateIcon: true, needsArtworkRetry: false, calendar: calendar)
        #expect(plan.dates == [now, try instant("2018-11-04T03:00:00Z"),
                              try instant("2018-11-05T02:00:00Z"), try instant("2018-11-06T02:00:00Z")])
        let first = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.dates[1])
        #expect(first.year == 2018 && first.month == 11 && first.day == 4 && first.hour == 1 && first.minute == 0)
        #expect(plan.dates[2].timeIntervalSince(plan.dates[1]) == 23 * 60 * 60)
        #expect(plan.dates.map { DateIconContent(date: $0, calendar: calendar, locale: english).day } == ["3", "4", "5", "6"])
    }

    @Test("Apia's skipped December 30 creates no phantom date and crosses the year correctly")
    func skippedCalendarDay() throws {
        let calendar = try calendar(.gregorian, zone: "Pacific/Apia")
        let now = try instant("2011-12-29T22:00:00Z") // December 29, noon, before the dateline move
        let plan = DateIconTimelinePlan(now: now, containsDateIcon: true, needsArtworkRetry: false, calendar: calendar)
        #expect(plan.dates == [now, try instant("2011-12-30T10:00:00Z"),
                              try instant("2011-12-31T10:00:00Z"), try instant("2012-01-01T10:00:00Z")])
        let content = plan.dates.map { DateIconContent(date: $0, calendar: calendar, locale: english) }
        #expect(content.map(\.day) == ["29", "31", "1", "2"])
        #expect(content.map(\.month) == ["Dec", "Dec", "Jan", "Jan"])
        #expect(content[2].accessibilityText.contains("2012"))
        #expect(plan.reloadDate == plan.dates[1])
    }

    @Test("Leap day, month end, year end and an exact midnight keep four distinct entries")
    func calendarRollovers() throws {
        let calendar = try calendar(.gregorian, zone: "UTC")
        let february = try instant("2024-02-28T23:50:00Z")
        let leap = DateIconTimelinePlan(now: february, containsDateIcon: true, needsArtworkRetry: false, calendar: calendar)
        #expect(leap.dates == [february, try instant("2024-02-29T00:00:00Z"),
                              try instant("2024-03-01T00:00:00Z"), try instant("2024-03-02T00:00:00Z")])
        let leapContent = DateIconContent(date: leap.dates[1], calendar: calendar, locale: english)
        #expect(leapContent.day == "29" && leapContent.month == "Feb" && leapContent.accessibilityText.contains("2024"))
        let yearEnd = try instant("2024-12-31T23:59:00Z")
        let nextYear = DateIconTimelinePlan(now: yearEnd, containsDateIcon: true, needsArtworkRetry: false, calendar: calendar)
        #expect(nextYear.dates == [yearEnd, try instant("2025-01-01T00:00:00Z"),
                                  try instant("2025-01-02T00:00:00Z"), try instant("2025-01-03T00:00:00Z")])
        let january = DateIconContent(date: nextYear.dates[1], calendar: calendar, locale: english)
        #expect(january.day == "1" && january.month == "Jan" && january.accessibilityText.contains("2025"))
        let midnight = try instant("2025-01-01T00:00:00Z")
        let atMidnight = DateIconTimelinePlan(now: midnight, containsDateIcon: true, needsArtworkRetry: false, calendar: calendar)
        #expect(atMidnight.dates == [midnight, try instant("2025-01-02T00:00:00Z"),
                                    try instant("2025-01-03T00:00:00Z"), try instant("2025-01-04T00:00:00Z")])
    }

    @Test("The supplied time zone determines both the displayed date and its next boundary")
    func sameInstantDifferentZones() throws {
        let now = try instant("2024-01-01T01:00:00Z")
        let losAngeles = try calendar(.gregorian, zone: "America/Los_Angeles")
        let tokyo = try calendar(.gregorian, zone: "Asia/Tokyo")
        let west = DateIconContent(date: now, calendar: losAngeles, locale: english)
        let east = DateIconContent(date: now, calendar: tokyo, locale: english)
        #expect(west.day == "31" && west.month == "Dec" && west.accessibilityText.contains("2023"))
        #expect(east.day == "1" && east.month == "Jan" && east.accessibilityText.contains("2024"))
        let westPlan = DateIconTimelinePlan(now: now, containsDateIcon: true, needsArtworkRetry: false, calendar: losAngeles)
        let eastPlan = DateIconTimelinePlan(now: now, containsDateIcon: true, needsArtworkRetry: false, calendar: tokyo)
        #expect(westPlan.reloadDate == (try instant("2024-01-01T08:00:00Z")))
        #expect(eastPlan.reloadDate == (try instant("2024-01-01T15:00:00Z")))
    }

    @Test("Hebrew Adar I and Adar II retain different month names and their own day numbers")
    func hebrewLeapMonths() throws {
        let hebrew = try calendar(.hebrew, zone: "UTC")
        let first = DateIconContent(date: try instant("2024-02-10T12:00:00Z"), calendar: hebrew, locale: english)
        let second = DateIconContent(date: try instant("2024-03-11T12:00:00Z"), calendar: hebrew, locale: english)
        #expect(first.day == "1" && second.day == "1")
        #expect(first.month.contains("Adar") && second.month.contains("Adar") && first.month != second.month)
        #expect(first.accessibilityText.contains("5784") && second.accessibilityText.contains("5784"))
    }

    @Test("Chinese leap second month remains distinguishable from the ordinary second month")
    func chineseLeapMonth() throws {
        let chinese = try calendar(.chinese, zone: "Asia/Shanghai")
        let locale = Locale(identifier: "zh_CN")
        let ordinary = DateIconContent(date: try instant("2023-02-20T04:00:00Z"), calendar: chinese, locale: locale)
        let leap = DateIconContent(date: try instant("2023-03-22T04:00:00Z"), calendar: chinese, locale: locale)
        #expect(ordinary.day == "1" && leap.day == "1")
        #expect(!ordinary.month.contains("闰") && leap.month.contains("闰") && ordinary.month != leap.month)
        #expect(leap.accessibilityText.contains("闰"))
    }

    @Test("Arabic Egyptian content uses local decimal digits without changing the chosen Gregorian date")
    func localizedDigits() throws {
        let gregorian = try calendar(.gregorian, zone: "UTC")
        let content = DateIconContent(date: try instant("2024-02-29T12:00:00Z"), calendar: gregorian, locale: Locale(identifier: "ar_EG"))
        #expect(content.day == "٢٩")
        #expect(!content.month.isEmpty && content.month.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) })
        #expect(content.accessibilityText.contains("٢٩") && content.accessibilityText.contains("٢٠٢٤"))
    }

    @Test("Static artwork stays on one entry; retry uses fifteen minutes or the earlier next day")
    func refreshPolicy() throws {
        let calendar = try calendar(.gregorian, zone: "UTC")
        let noon = try instant("2024-06-01T12:00:00Z")
        let staticPlan = DateIconTimelinePlan(now: noon, containsDateIcon: false, needsArtworkRetry: false, calendar: calendar)
        #expect(staticPlan.dates == [noon] && staticPlan.reloadDate == nil)
        let staticRetry = DateIconTimelinePlan(now: noon, containsDateIcon: false, needsArtworkRetry: true, calendar: calendar)
        #expect(staticRetry.dates == [noon])
        #expect(staticRetry.reloadDate == (try instant("2024-06-01T12:15:00Z")))
        let dateRetry = DateIconTimelinePlan(now: noon, containsDateIcon: true, needsArtworkRetry: true, calendar: calendar)
        #expect(dateRetry.dates == [noon, try instant("2024-06-02T00:00:00Z"),
                                   try instant("2024-06-03T00:00:00Z"), try instant("2024-06-04T00:00:00Z")])
        #expect(dateRetry.reloadDate == (try instant("2024-06-01T12:15:00Z")))
        let almostMidnight = try instant("2024-06-01T23:55:00Z")
        let earlierDay = DateIconTimelinePlan(now: almostMidnight, containsDateIcon: true, needsArtworkRetry: true, calendar: calendar)
        #expect(earlierDay.dates.count == 4)
        #expect(earlierDay.reloadDate == (try instant("2024-06-02T00:00:00Z")))
    }

    private func calendar(_ identifier: Calendar.Identifier, zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private func instant(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
