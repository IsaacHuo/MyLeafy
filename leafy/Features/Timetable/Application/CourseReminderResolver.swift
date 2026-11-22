import Foundation

@MainActor
enum CourseReminderResolver {
    static func record(courseKey: String, week: Int?, settings: [CourseReminderSetting]) -> CourseReminderSetting? {
        settings.filter { !$0.isUnassociated && $0.courseKey == courseKey && $0.week == week }
            .max { left, right in
                if left.updatedAt != right.updatedAt { return left.updatedAt < right.updatedAt }
                return left.id.uuidString < right.id.uuidString
            }
    }

    static func effective(courseKey: String, week: Int, settings: [CourseReminderSetting]) -> CourseReminderSetting? {
        record(courseKey: courseKey, week: week, settings: settings)
            ?? record(courseKey: courseKey, week: nil, settings: settings)
    }
}
