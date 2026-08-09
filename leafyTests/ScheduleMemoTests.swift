import Foundation
import SwiftData
import XCTest
@testable import Leafy

@MainActor
final class ScheduleMemoTests: XCTestCase {
    func testTagParserSupportsNestedTagsAndDeduplicatesCaseInsensitively() {
        XCTAssertEqual(
            ScheduleMemoTagParser.tags(in: "今天学了 #Swift 和 #学习/Swift，也复习 #swift。"),
            ["Swift", "学习/Swift"]
        )
    }

    func testSearchFiltersAndSortsPinnedMemoFirst() throws {
        let old = try date(2026, 1, 1)
        let new = try date(2026, 2, 1)
        let records = [
            ScheduleMemoSearchRecord(
                id: UUID(), body: "SwiftUI 动画", tags: ["学习/Swift"], createdAt: new,
                updatedAt: new, pinnedAt: nil, isTrashed: false, imageCount: 1, isLinked: false
            ),
            ScheduleMemoSearchRecord(
                id: UUID(), body: "复习 Swift", tags: ["学习/Swift"], createdAt: old,
                updatedAt: old, pinnedAt: new, isTrashed: false, imageCount: 0, isLinked: true
            ),
            ScheduleMemoSearchRecord(
                id: UUID(), body: "已删除 Swift", tags: [], createdAt: new,
                updatedAt: new, pinnedAt: nil, isTrashed: true, imageCount: 1, isLinked: true
            )
        ]

        let results = ScheduleMemoSearchEngine.results(
            in: records,
            query: "swift",
            tag: "学习/Swift",
            sort: .newest
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertNotNil(results.first?.pinnedAt)
        XCTAssertEqual(
            ScheduleMemoSearchEngine.results(in: records, query: "", requiresImages: true).count,
            1
        )
    }

    func testDailyReviewIsStableAndPrioritizesAnniversary() throws {
        let now = try date(2026, 8, 8, 12)
        let anniversary = ScheduleMemo(body: "去年今天", createdAt: try date(2025, 8, 8))
        let older = (1...8).map { ScheduleMemo(body: "旧随记 \($0)", createdAt: try! date(2025, 7, $0)) }
        let first = ScheduleMemoReviewEngine.selection(from: [anniversary] + older, now: now, page: 0)
        let repeated = ScheduleMemoReviewEngine.selection(from: [anniversary] + older, now: now, page: 0)

        XCTAssertEqual(first.map(\.id), repeated.map(\.id))
        XCTAssertEqual(first.count, 5)
        XCTAssertTrue(first.map(\.id).contains(anniversary.id))
        XCTAssertEqual(first.first?.id, anniversary.id)
        XCTAssertNotEqual(
            first.map(\.id),
            ScheduleMemoReviewEngine.selection(from: [anniversary] + older, now: now, page: 1).map(\.id)
        )
    }

    func testStatisticsCountsMemosTagsDaysAndHeatmap() throws {
        let now = try date(2026, 8, 8, 12)
        let memos = [
            ScheduleMemo(body: "#学习 第一条", createdAt: now),
            ScheduleMemo(body: "#学习 #Swift 第二条", createdAt: now.addingTimeInterval(-60)),
            ScheduleMemo(body: "昨天", createdAt: try date(2026, 8, 7)),
            ScheduleMemo(body: "删除", createdAt: now, trashedAt: now)
        ]
        let statistics = ScheduleMemoStatistics.make(memos: memos, now: now)

        XCTAssertEqual(statistics.memoCount, 3)
        XCTAssertEqual(statistics.tagCount, 2)
        XCTAssertEqual(statistics.recordingDayCount, 2)
        XCTAssertEqual(statistics.activityDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: now) })?.count, 2)
    }

    func testPhotoSelectionAllowsSixAndRemovingOneKeepsTheOthers() {
        XCTAssertEqual(ScheduleMemoImageStore.maximumImageCount, 6)
        XCTAssertEqual(
            ScheduleMemoPhotoSelection.removing(3, from: [1, 2, 3, 4, 5, 6]),
            [1, 2, 4, 5, 6]
        )
        XCTAssertEqual(
            ScheduleMemoPhotoSelection.merging(
                pickerItems: [1, 2, 3, 4],
                capturedItems: [5, 6],
                maximumCount: 6
            ),
            [1, 2, 3, 4, 5, 6]
        )
    }

    func testTrashRestoreAndPermanentDeleteRemoveOwnedMediaFiles() throws {
        let schema = Schema([
            ScheduleMemo.self,
            ScheduleMemoImage.self,
            ScheduleMemoAttachment.self,
            ScheduleMemoAudio.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let memo = ScheduleMemo(body: "待删除")
        let image = ScheduleMemoImage(memoID: memo.id, sortOrder: 0, localFilename: "image.jpg")
        let audio = ScheduleMemoAudio(memoID: memo.id, localFilename: "audio.m4a", duration: 12)
        context.insert(memo)
        context.insert(image)
        context.insert(audio)
        try context.save()

        try ScheduleMemoDeletionService.moveToTrash(memo, in: context)
        XCTAssertTrue(memo.isTrashed)
        try ScheduleMemoDeletionService.restore(memo, in: context)
        XCTAssertFalse(memo.isTrashed)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduleMemoDeletionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(image.localFilename)
        let audioURL = directory.appendingPathComponent(audio.localFilename)
        try Data([1, 2, 3]).write(to: fileURL)
        try Data([4, 5, 6]).write(to: audioURL)

        try ScheduleMemoDeletionService.permanentlyDelete(
            memo,
            images: [image],
            audioRecords: [audio],
            in: context,
            imageDirectory: directory,
            audioDirectory: directory
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemo>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoImage>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoAudio>()), 0)
    }

    func testScheduleLinkResolverHandlesBothStoresAndStaleLinks() {
        XCTAssertEqual(
            ScheduleMemoLinkResolver.title(
                kind: .timetableReminder, stableID: "cell", timetableTitles: ["cell": "小组讨论"], importantDateTitles: [:]
            ),
            "小组讨论"
        )
        XCTAssertEqual(
            ScheduleMemoLinkResolver.title(
                kind: .importantDate, stableID: "date", timetableTitles: [:], importantDateTitles: ["date": "提交作业"]
            ),
            "提交作业"
        )
        XCTAssertEqual(
            ScheduleMemoLinkResolver.title(
                kind: .importantDate, stableID: "missing", timetableTitles: [:], importantDateTitles: [:]
            ),
            "原日程已删除"
        )
    }

    func testAccountModelCleanupDeletesMemoRows() throws {
        let setup = AppModelContainerFactory.make()
        let context = setup.container.mainContext
        let memo = ScheduleMemo(body: "清理我")
        context.insert(memo)
        context.insert(ScheduleMemoImage(memoID: memo.id, sortOrder: 0, localFilename: "unused.jpg"))
        context.insert(ScheduleMemoAudio(memoID: memo.id, localFilename: "unused.m4a", duration: 1))
        try context.save()

        try AppSessionResetter.deleteAllModels(in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemo>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoImage>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoAudio>()), 0)
    }

    func testAddingMemoModelsPreservesExistingCourseAndGradeStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduleMemoMigrationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Leafy.store")
        let courseID = UUID()
        let gradeID = UUID()

        do {
            let oldSchema = Schema([Course.self, Grade.self])
            let configuration = ModelConfiguration("ScheduleMemoMigration", schema: oldSchema, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: oldSchema, configurations: [configuration])
            container.mainContext.insert(Course(
                id: courseID, courseName: "高等数学", teacher: "教师", room: "A101", dayOfWeek: 1, weeks: [1], duration: [1]
            ))
            container.mainContext.insert(Grade(
                id: gradeID, term: "2026", courseName: "高等数学", credit: "4", score: "95", type: "必修"
            ))
            try container.mainContext.save()
        }

        let expandedSchema = Schema([Course.self, Grade.self, ScheduleMemo.self, ScheduleMemoImage.self, ScheduleMemoAudio.self])
        let configuration = ModelConfiguration("ScheduleMemoMigration", schema: expandedSchema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: expandedSchema, configurations: [configuration])

        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Course>()).map(\.id), [courseID])
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Grade>()).map(\.id), [gradeID])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ScheduleMemo>()), 0)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }
}
