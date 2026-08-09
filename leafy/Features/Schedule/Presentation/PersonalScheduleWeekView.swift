import SwiftUI

struct PersonalScheduleBlockValue: Identifiable {
    enum Source {
        case reminder(UUID)
        case event(String)
    }

    let id: String
    let source: Source
    let title: String
    let locationText: String
    let startsAt: Date
    let endsAt: Date
    let startPeriod: Int
    let endPeriod: Int

    init(reminder: TimetableCellReminder) {
        let start = reminder.resolvedStartDate ?? Date()
        let end = reminder.resolvedEndDate.flatMap { $0 > start ? $0 : nil }
            ?? start.addingTimeInterval(45 * 60)
        let range = TimetablePeriodSchedule.periodRange(overlapping: start, endDate: end)
        let fallback = TimetablePeriodSchedule.periodForFocus(containing: start)?.period ?? 1
        id = "reminder-\(reminder.id.uuidString)"
        source = .reminder(reminder.id)
        title = reminder.title
        locationText = reminder.locationText
        startsAt = start
        endsAt = end
        startPeriod = range?.lowerBound ?? fallback
        endPeriod = range?.upperBound ?? fallback
    }

    init(event: CustomScheduleEvent) {
        let end = event.endsAt.flatMap { $0 > event.startsAt ? $0 : nil }
            ?? event.startsAt.addingTimeInterval(45 * 60)
        let range = TimetablePeriodSchedule.periodRange(overlapping: event.startsAt, endDate: end)
        let fallback = TimetablePeriodSchedule.periodForFocus(containing: event.startsAt)?.period ?? 1
        id = "event-\(event.id)"
        source = .event(event.id)
        title = event.title
        locationText = event.locationText
        startsAt = event.startsAt
        endsAt = end
        startPeriod = range?.lowerBound ?? fallback
        endPeriod = range?.upperBound ?? fallback
    }

    init(reminder: TimetableCellReminderRenderValue) {
        let start = reminder.resolvedStartDate ?? Date()
        let end = reminder.resolvedEndDate.flatMap { $0 > start ? $0 : nil }
            ?? start.addingTimeInterval(45 * 60)
        id = "reminder-\(reminder.id.uuidString)"
        source = .reminder(reminder.id)
        title = reminder.title
        locationText = reminder.locationText
        startsAt = start
        endsAt = end
        startPeriod = reminder.displayStartPeriod
        endPeriod = reminder.displayEndPeriod
    }

    init(countdown: TimetableCountdownProjection) {
        id = "event-\(countdown.eventID)"
        source = .event(countdown.eventID)
        title = countdown.title
        locationText = ""
        startsAt = countdown.startsAt
        endsAt = countdown.endsAt
        startPeriod = countdown.startPeriod
        endPeriod = countdown.endPeriod
    }
}

struct PersonalScheduleBlockView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @AppStorage("appThemeColorPreference") private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue

    let value: PersonalScheduleBlockValue
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2.5 * leafyControlScale) {
            HStack(alignment: .firstTextBaseline, spacing: 4 * leafyControlScale) {
                Image(systemName: "bell.fill")
                    .font(.system(size: iconFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))

                Text(value.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(height < 40 * leafyControlScale ? 1 : 2)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }

            if height > 34 * leafyControlScale {
                Text(subtitle)
                    .font(.system(size: captionFontSize, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 4.5 * leafyControlScale)
        .padding(.vertical, 4 * leafyControlScale)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(blockBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small * 0.72, style: .continuous)
                .stroke(AppTheme.accent.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small * 0.72, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.025), radius: 1)
        .accessibilityLabel(accessibilityText)
    }

    private var titleFontSize: CGFloat { (height < 36 * leafyControlScale ? 9.2 : 10.4) * leafyControlScale }
    private var iconFontSize: CGFloat { (height < 36 * leafyControlScale ? 8.2 : 9.2) * leafyControlScale }
    private var captionFontSize: CGFloat { (height < 42 * leafyControlScale ? 7.4 : 8.2) * leafyControlScale }

    private var subtitle: String {
        let time = "\(DateFormatters.timeOnly.string(from: value.startsAt))–\(DateFormatters.timeOnly.string(from: value.endsAt))"
        return value.locationText.isEmpty ? time : "\(time) · \(value.locationText)"
    }

    private var blockBackground: Color {
        if colorScheme == .dark {
            return AppTheme.accent(for: themeColorPreference).opacity(0.3)
        }
        return AppTheme.courseCardColor(
            for: value.id + value.title,
            themeColorPreferenceRaw: appThemeColorPreferenceRaw
        )
        .opacity(0.9)
    }

    private var accessibilityText: String {
        value.locationText.isEmpty
            ? "\(value.title)，\(subtitle)"
            : "\(value.title)，\(value.locationText)，\(subtitle)"
    }
}
