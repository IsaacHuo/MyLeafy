import Foundation
import SwiftData

/// Explicit allowlist: credentials, community caches and unrelated models never enter sync.
@MainActor
protocol ICloudModelValue: Codable {
    associatedtype Model: PersistentModel
    static var kind: String { get }
    var id: UUID { get set }
    var syncDate: Date { get }
    init(_ model: Model)
    func make() -> Model
    func apply(to model: Model)
}

nonisolated struct SyncedCourse: Codable {
    var id: UUID
    var sourceSemesterID: String
    var courseName: String
    var teacher: String
    var classInfo: String
    var room: String
    var location: String
    var dayOfWeek: Int
    var weeks: [Int]
    var duration: [Int]
}

extension SyncedCourse: ICloudModelValue {
    typealias Model = Course
    var syncDate: Date { .distantPast }
    static var kind: String { "Course" }
    @MainActor init(_ model: Course) {
        id = model.id
        sourceSemesterID = model.sourceSemesterID
        courseName = model.courseName
        teacher = model.teacher
        classInfo = model.classInfo
        room = model.room
        location = model.location
        dayOfWeek = model.dayOfWeek
        weeks = model.weeks
        duration = model.duration
    }
    @MainActor func make() -> Course {
        let model = Course(id: id, courseName: courseName, teacher: teacher, classInfo: classInfo, room: room, location: location, dayOfWeek: dayOfWeek, weeks: weeks, duration: duration, sourceSemesterID: sourceSemesterID)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: Course) {
        model.id = id
        model.sourceSemesterID = sourceSemesterID
        model.courseName = courseName
        model.teacher = teacher
        model.classInfo = classInfo
        model.room = room
        model.location = location
        model.dayOfWeek = dayOfWeek
        model.weeks = weeks
        model.duration = duration
    }
}

nonisolated struct SyncedGrade: Codable {
    var id: UUID
    var term: String
    var courseName: String
    var credit: String
    var score: String
    var type: String
    var courseCode: String?
    var courseAttribute: String?
    var courseCategory: String?
    var examNature: String?
}

extension SyncedGrade: ICloudModelValue {
    typealias Model = Grade
    var syncDate: Date { .distantPast }
    static var kind: String { "Grade" }
    @MainActor init(_ model: Grade) {
        id = model.id
        term = model.term
        courseName = model.courseName
        credit = model.credit
        score = model.score
        type = model.type
        courseCode = model.courseCode
        courseAttribute = model.courseAttribute
        courseCategory = model.courseCategory
        examNature = model.examNature
    }
    @MainActor func make() -> Grade {
        let model = Grade(id: id, term: term, courseName: courseName, credit: credit, score: score, type: type, courseCode: courseCode, courseAttribute: courseAttribute, courseCategory: courseCategory, examNature: examNature)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: Grade) {
        model.id = id
        model.term = term
        model.courseName = courseName
        model.credit = credit
        model.score = score
        model.type = type
        model.courseCode = courseCode
        model.courseAttribute = courseAttribute
        model.courseCategory = courseCategory
        model.examNature = examNature
    }
}

nonisolated struct SyncedCourseNote: Codable {
    var isUnassociated: Bool
    var sourceCourseTitle: String
    var id: UUID
    var courseKey: String
    var text: String
    var updatedAt: Date
}

extension SyncedCourseNote: ICloudModelValue {
    typealias Model = CourseNote
    var syncDate: Date { updatedAt }
    static var kind: String { "CourseNote" }
    @MainActor init(_ model: CourseNote) {
        isUnassociated = model.isUnassociated
        sourceCourseTitle = model.sourceCourseTitle
        id = model.id
        courseKey = model.courseKey
        text = model.text
        updatedAt = model.updatedAt
    }
    @MainActor func make() -> CourseNote {
        let model = CourseNote(id: id, courseKey: courseKey, text: text, updatedAt: updatedAt)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: CourseNote) {
        model.isUnassociated = isUnassociated
        model.sourceCourseTitle = sourceCourseTitle
        model.id = id
        model.courseKey = courseKey
        model.text = text
        model.updatedAt = updatedAt
    }
}

nonisolated struct SyncedCourseOccurrenceNote: Codable {
    var isUnassociated: Bool
    var sourceCourseTitle: String
    var id: UUID
    var courseKey: String
    var occurrenceKey: String
    var week: Int
    var dayOfWeek: Int
    var text: String
    var updatedAt: Date
}

extension SyncedCourseOccurrenceNote: ICloudModelValue {
    typealias Model = CourseOccurrenceNote
    var syncDate: Date { updatedAt }
    static var kind: String { "CourseOccurrenceNote" }
    @MainActor init(_ model: CourseOccurrenceNote) {
        isUnassociated = model.isUnassociated
        sourceCourseTitle = model.sourceCourseTitle
        id = model.id
        courseKey = model.courseKey
        occurrenceKey = model.occurrenceKey
        week = model.week
        dayOfWeek = model.dayOfWeek
        text = model.text
        updatedAt = model.updatedAt
    }
    @MainActor func make() -> CourseOccurrenceNote {
        let model = CourseOccurrenceNote(id: id, courseKey: courseKey, occurrenceKey: occurrenceKey, week: week, dayOfWeek: dayOfWeek, text: text, updatedAt: updatedAt)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: CourseOccurrenceNote) {
        model.isUnassociated = isUnassociated
        model.sourceCourseTitle = sourceCourseTitle
        model.id = id
        model.courseKey = courseKey
        model.occurrenceKey = occurrenceKey
        model.week = week
        model.dayOfWeek = dayOfWeek
        model.text = text
        model.updatedAt = updatedAt
    }
}

nonisolated struct SyncedCourseReminderSetting: Codable {
    var isUnassociated: Bool
    var sourceCourseTitle: String
    var id: UUID
    var courseKey: String
    var minutesBefore: Int
    var anchorPeriod: Int?
    var updatedAt: Date
}

extension SyncedCourseReminderSetting: ICloudModelValue {
    typealias Model = CourseReminderSetting
    var syncDate: Date { updatedAt }
    static var kind: String { "CourseReminderSetting" }
    @MainActor init(_ model: CourseReminderSetting) {
        isUnassociated = model.isUnassociated
        sourceCourseTitle = model.sourceCourseTitle
        id = model.id
        courseKey = model.courseKey
        minutesBefore = model.minutesBefore
        anchorPeriod = model.anchorPeriod
        updatedAt = model.updatedAt
    }
    @MainActor func make() -> CourseReminderSetting {
        let model = CourseReminderSetting(id: id, courseKey: courseKey, minutesBefore: minutesBefore, anchorPeriod: anchorPeriod, updatedAt: updatedAt)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: CourseReminderSetting) {
        model.isUnassociated = isUnassociated
        model.sourceCourseTitle = sourceCourseTitle
        model.id = id
        model.courseKey = courseKey
        model.minutesBefore = minutesBefore
        model.anchorPeriod = anchorPeriod
        model.updatedAt = updatedAt
    }
}

nonisolated struct SyncedTimetableCellReminder: Codable {
    var id: UUID
    var cellKey: String
    var week: Int
    var dayOfWeek: Int
    var period: Int
    var endPeriod: Int?
    var title: String
    var location: String?
    var note: String?
    var startsAt: Date?
    var endsAt: Date?
    var minutesBefore: Int
    var createdAt: Date?
    var updatedAt: Date
}

extension SyncedTimetableCellReminder: ICloudModelValue {
    typealias Model = TimetableCellReminder
    var syncDate: Date { updatedAt }
    static var kind: String { "TimetableCellReminder" }
    @MainActor init(_ model: TimetableCellReminder) {
        id = model.id
        cellKey = model.cellKey
        week = model.week
        dayOfWeek = model.dayOfWeek
        period = model.period
        endPeriod = model.endPeriod
        title = model.title
        location = model.location
        note = model.note
        startsAt = model.startsAt
        endsAt = model.endsAt
        minutesBefore = model.minutesBefore
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }
    @MainActor func make() -> TimetableCellReminder {
        let model = TimetableCellReminder(id: id, week: week, dayOfWeek: dayOfWeek, period: period, endPeriod: endPeriod, title: title, location: location ?? "", note: note ?? "", startsAt: startsAt, endsAt: endsAt, minutesBefore: minutesBefore, createdAt: createdAt, updatedAt: updatedAt)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: TimetableCellReminder) {
        model.id = id
        model.cellKey = cellKey
        model.week = week
        model.dayOfWeek = dayOfWeek
        model.period = period
        model.endPeriod = endPeriod
        model.title = title
        model.location = location
        model.note = note
        model.startsAt = startsAt
        model.endsAt = endsAt
        model.minutesBefore = minutesBefore
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct SyncedScheduleMemo: Codable {
    var id: UUID
    var body: String
    var kindRawValue: String
    var title: String?
    var tagsRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var pinnedAt: Date?
    var trashedAt: Date?
    var linkedScheduleKindRawValue: String?
    var linkedScheduleID: String?
}

extension SyncedScheduleMemo: ICloudModelValue {
    typealias Model = ScheduleMemo
    var syncDate: Date { updatedAt }
    static var kind: String { "ScheduleMemo" }
    @MainActor init(_ model: ScheduleMemo) {
        id = model.id
        body = model.body
        kindRawValue = model.kindRawValue
        title = model.title
        tagsRawValue = model.tagsRawValue
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        pinnedAt = model.pinnedAt
        trashedAt = model.trashedAt
        linkedScheduleKindRawValue = model.linkedScheduleKindRawValue
        linkedScheduleID = model.linkedScheduleID
    }
    @MainActor func make() -> ScheduleMemo {
        let model = ScheduleMemo(id: id, body: body, createdAt: createdAt, updatedAt: updatedAt, pinnedAt: pinnedAt, trashedAt: trashedAt, linkedScheduleKindRawValue: linkedScheduleKindRawValue, linkedScheduleID: linkedScheduleID, kindRawValue: kindRawValue, title: title)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: ScheduleMemo) {
        model.id = id
        model.body = body
        model.kindRawValue = kindRawValue
        model.title = title
        model.tagsRawValue = tagsRawValue
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.pinnedAt = pinnedAt
        model.trashedAt = trashedAt
        model.linkedScheduleKindRawValue = linkedScheduleKindRawValue
        model.linkedScheduleID = linkedScheduleID
    }
}

nonisolated struct SyncedScheduleMemoImage: Codable {
    var id: UUID
    var memoID: UUID
    var sortOrder: Int
    var localFilename: String
    var importedAt: Date
}

extension SyncedScheduleMemoImage: ICloudModelValue {
    typealias Model = ScheduleMemoImage
    var syncDate: Date { importedAt }
    static var kind: String { "ScheduleMemoImage" }
    @MainActor init(_ model: ScheduleMemoImage) {
        id = model.id
        memoID = model.memoID
        sortOrder = model.sortOrder
        localFilename = model.localFilename
        importedAt = model.importedAt
    }
    @MainActor func make() -> ScheduleMemoImage {
        let model = ScheduleMemoImage(id: id, memoID: memoID, sortOrder: sortOrder, localFilename: localFilename, importedAt: importedAt)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: ScheduleMemoImage) {
        model.id = id
        model.memoID = memoID
        model.sortOrder = sortOrder
        model.localFilename = localFilename
        model.importedAt = importedAt
    }
}

nonisolated struct SyncedScheduleMemoAttachment: Codable {
    var id: UUID
    var memoID: UUID
    var sortOrder: Int
    var originalFilename: String
    var localFilename: String
    var contentTypeIdentifier: String
    var importedAt: Date
}

extension SyncedScheduleMemoAttachment: ICloudModelValue {
    typealias Model = ScheduleMemoAttachment
    var syncDate: Date { importedAt }
    static var kind: String { "ScheduleMemoAttachment" }
    @MainActor init(_ model: ScheduleMemoAttachment) {
        id = model.id
        memoID = model.memoID
        sortOrder = model.sortOrder
        originalFilename = model.originalFilename
        localFilename = model.localFilename
        contentTypeIdentifier = model.contentTypeIdentifier
        importedAt = model.importedAt
    }
    @MainActor func make() -> ScheduleMemoAttachment {
        let model = ScheduleMemoAttachment(id: id, memoID: memoID, sortOrder: sortOrder, originalFilename: originalFilename, localFilename: localFilename, contentTypeIdentifier: contentTypeIdentifier, importedAt: importedAt)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: ScheduleMemoAttachment) {
        model.id = id
        model.memoID = memoID
        model.sortOrder = sortOrder
        model.originalFilename = originalFilename
        model.localFilename = localFilename
        model.contentTypeIdentifier = contentTypeIdentifier
        model.importedAt = importedAt
    }
}

nonisolated struct SyncedScheduleMemoAudio: Codable {
    var id: UUID
    var memoID: UUID
    var localFilename: String
    var duration: TimeInterval
    var recordedAt: Date
}

extension SyncedScheduleMemoAudio: ICloudModelValue {
    typealias Model = ScheduleMemoAudio
    var syncDate: Date { recordedAt }
    static var kind: String { "ScheduleMemoAudio" }
    @MainActor init(_ model: ScheduleMemoAudio) {
        id = model.id
        memoID = model.memoID
        localFilename = model.localFilename
        duration = model.duration
        recordedAt = model.recordedAt
    }
    @MainActor func make() -> ScheduleMemoAudio {
        let model = ScheduleMemoAudio(id: id, memoID: memoID, localFilename: localFilename, duration: duration, recordedAt: recordedAt)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: ScheduleMemoAudio) {
        model.id = id
        model.memoID = memoID
        model.localFilename = localFilename
        model.duration = duration
        model.recordedAt = recordedAt
    }
}

