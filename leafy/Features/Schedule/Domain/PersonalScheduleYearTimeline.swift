import Foundation

nonisolated struct PersonalScheduleYearTimeline: Equatable, Sendable {
    let year: Int
    let startDate: Date
    let endDate: Date
    let weeks: [Date]

    init(year: Int, calendar: Calendar = .current) {
        self.year = year
        startDate = calendar.date(
            from: DateComponents(calendar: calendar, year: year, month: 1, day: 1)
        )!
        endDate = calendar.date(byAdding: .year, value: 1, to: startDate)!

        let firstWeek = Self.monday(containing: startDate, calendar: calendar)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: endDate)!
        let lastWeek = Self.monday(containing: lastDay, calendar: calendar)
        var values: [Date] = []
        var week = firstWeek
        while week <= lastWeek {
            values.append(week)
            week = calendar.date(byAdding: .day, value: 7, to: week)!
        }
        weeks = values
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= startDate && day < endDate
    }

    func pageIndex(containing date: Date, calendar: Calendar = .current) -> Int? {
        guard contains(date, calendar: calendar) else { return nil }
        let weekStart = Self.monday(containing: date, calendar: calendar)
        guard let index = weeks.firstIndex(of: weekStart) else { return nil }
        return index + 1
    }

    func weekStart(at page: Int) -> Date? {
        guard weeks.indices.contains(page - 1) else { return nil }
        return weeks[page - 1]
    }

    func date(page: Int, dayOfWeek: Int, calendar: Calendar = .current) -> Date? {
        guard let weekStart = weekStart(at: page), (1...7).contains(dayOfWeek) else { return nil }
        return calendar.date(byAdding: .day, value: dayOfWeek - 1, to: weekStart)
    }

    private static func monday(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day)!
    }
}
