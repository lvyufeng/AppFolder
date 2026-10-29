import Foundation

/// A date icon stores a style, never a captured date or a user's calendar events.
/// Callers supply the same calendar to formatting and timeline planning.
public struct DateIconContent: Equatable, Sendable {
    public let month: String
    public let day: String
    public let accessibilityText: String

    public init(date: Date, calendar: Calendar = .current, locale: Locale = .current) {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        month = formatter.string(from: date)

        let number = NumberFormatter()
        number.locale = locale
        number.numberStyle = .decimal
        number.usesGroupingSeparator = false
        day = number.string(from: NSNumber(value: calendar.component(.day, from: date))) ?? ""

        formatter.dateStyle = .full
        formatter.timeStyle = .none
        accessibilityText = formatter.string(from: date)
    }
}

/// Predictable local day boundaries can be delivered ahead of time. The first
/// boundary also requests a fresh timeline so changes in settings or artwork are
/// picked up before the reserve entries run out. WidgetKit controls delivery.
public struct DateIconTimelinePlan: Equatable, Sendable {
    public let dates: [Date]
    public let reloadDate: Date?

    public init(now: Date, containsDateIcon: Bool, needsArtworkRetry: Bool,
                calendar: Calendar = .current) {
        var dates = [now]
        if containsDateIcon {
            var cursor = now
            // A small reserve survives a delayed reload without multiplying the
            // retained image payload into an unbounded daily timeline.
            for _ in 0..<3 {
                guard let end = calendar.dateInterval(of: .day, for: cursor)?.end,
                      end > cursor, end.timeIntervalSinceReferenceDate.isFinite else { break }
                dates.append(end)
                cursor = end
            }
        }
        self.dates = dates
        let nextDay = dates.dropFirst().first
        let retry = needsArtworkRetry || (containsDateIcon && nextDay == nil)
            ? now.addingTimeInterval(15 * 60) : nil
        reloadDate = [nextDay, retry].compactMap { $0 }.min()
    }
}
