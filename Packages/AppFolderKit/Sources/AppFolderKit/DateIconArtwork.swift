#if canImport(SwiftUI)
import SwiftUI

private struct DateIconContentKey: EnvironmentKey {
    static let defaultValue: DateIconContent? = nil
}

private struct DateIconRefreshTokenKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Widgets format once per entry, including future entries, and share the
    /// result with every full tile, miniature and accessibility value.
    public var dateIconContent: DateIconContent? {
        get { self[DateIconContentKey.self] }
        set { self[DateIconContentKey.self] = newValue }
    }

    /// App settings/time notifications invalidate visible previews immediately.
    public var dateIconRefreshToken: Int {
        get { self[DateIconRefreshTokenKey.self] }
        set { self[DateIconRefreshTokenKey.self] = newValue }
    }
}

/// Shares formatting and the clock between visual artwork and the editor's
/// accessible full-date label. No calendar database or network is consulted.
private struct DateIconClock<Content: View>: View {
    @Environment(\.dateIconContent) private var timelineContent
    @Environment(\.dateIconRefreshToken) private var refreshToken
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    let content: (DateIconContent) -> Content

    var body: some View {
        if let timelineContent {
            content(timelineContent)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(value(at: context.date))
            }
            .id(refreshToken)
        }
    }

    private func value(at date: Date) -> DateIconContent {
        var currentCalendar = calendar
        currentCalendar.timeZone = timeZone
        return DateIconContent(date: date, calendar: currentCalendar, locale: locale)
    }
}

struct DateIconGlyph: View {
    let side: CGFloat

    var body: some View {
        DateIconClock { value in
            VStack(spacing: side * 0.01) {
                Text(verbatim: value.month)
                    .font(.system(size: side * 0.18, weight: .semibold))
                    .opacity(0.85)
                Text(verbatim: value.day)
                    .font(.system(size: side * 0.47, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: side * 0.84, height: side * 0.84)
        }
    }
}

public struct DateIconCurrentDateLabel: View {
    public init() {}

    public var body: some View {
        DateIconClock { value in
            Text(verbatim: value.accessibilityText)
        }
    }
}

private struct DateIconAccessibilityValue: ViewModifier {
    let variants: CustomIconVariants?
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder func body(content: Content) -> some View {
        if variants?.resolved(isDark: colorScheme == .dark)?.kind == .date {
            DateIconClock { value in
                content.accessibilityValue(Text(verbatim: value.accessibilityText))
            }
        } else {
            content
        }
    }
}

extension View {
    /// Attach to the accessible tile/button, not its decorative artwork child.
    /// A missing or non-date variant leaves the existing status value untouched.
    public func dateIconAccessibilityValue(_ variants: CustomIconVariants?) -> some View {
        modifier(DateIconAccessibilityValue(variants: variants))
    }
}
#endif
