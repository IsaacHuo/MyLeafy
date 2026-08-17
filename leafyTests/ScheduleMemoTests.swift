import Foundation
import SwiftData
import XCTest
@testable import Leafy

@MainActor
final class ScheduleMemoTests: XCTestCase {
    func testMediaIndexGroupsAndSortsMemoResources() {
        let firstMemoID = UUID()
        let secondMemoID = UUID()
        let images = [
            ScheduleMemoImage(memoID: firstMemoID, sortOrder: 2, localFilename: "third.jpg"),
            ScheduleMemoImage(memoID: secondMemoID, sortOrder: 0, localFilename: "other.jpg"),
            ScheduleMemoImage(memoID: firstMemoID, sortOrder: 0, localFilename: "first.jpg")
        ]
        let attachments = [
            ScheduleMemoAttachment(
                memoID: firstMemoID,
                sortOrder: 1,
                originalFilename: "second.pdf",
                localFilename: "second.pdf",
                contentTypeIdentifier: "com.adobe.pdf"
            ),
            ScheduleMemoAttachment(
                memoID: firstMemoID,
                sortOrder: 0,
                originalFilename: "first.pdf",
                localFilename: "first.pdf",
                contentTypeIdentifier: "com.adobe.pdf"
            )
        ]
        let audio = ScheduleMemoAudio(memoID: firstMemoID, localFilename: "audio.m4a", duration: 12)

        let index = ScheduleMemoMediaIndex(
            images: images,
            attachments: attachments,
            audioRecords: [audio]
        )

        XCTAssertEqual(index.imagesByMemoID[firstMemoID]?.map(\.localFilename), ["first.jpg", "third.jpg"])
        XCTAssertEqual(index.imagesByMemoID[secondMemoID]?.map(\.localFilename), ["other.jpg"])
        XCTAssertEqual(index.attachmentsByMemoID[firstMemoID]?.map(\.originalFilename), ["first.pdf", "second.pdf"])
        XCTAssertEqual(index.audioByMemoID[firstMemoID]?.id, audio.id)
    }

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

    func testStatisticsSnapshotExcludesTrashAndCountsNaturalYearMonthsAndLeapDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try date(2024, 3, 1, 12, calendar: calendar)
        let memos = [
            ScheduleMemo(body: "一月", createdAt: try date(2024, 1, 31, 23, calendar: calendar)),
            ScheduleMemo(body: "闰日 #学习", createdAt: try date(2024, 2, 29, 9, calendar: calendar)),
            ScheduleMemo(body: "闰日 #学习", createdAt: try date(2024, 2, 29, 10, calendar: calendar)),
            ScheduleMemo(body: "回收站", createdAt: try date(2024, 2, 29, 11, calendar: calendar), trashedAt: now)
        ]

        let statistics = ScheduleMemoStatistics.snapshot(memos: memos, selectedYear: 2024, now: now, calendar: calendar)

        XCTAssertEqual(statistics.memoCount, 3)
        XCTAssertEqual(statistics.recordingDayCount, 2)
        XCTAssertEqual(statistics.selectedYearMonths.map(\.memoCount), [1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(statistics.selectedYearMonths.map(\.recordingDayCount), [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(statistics.firstRecordingDate, try date(2024, 1, 31, calendar: calendar))
        XCTAssertEqual(statistics.peakDate, try date(2024, 2, 29, calendar: calendar))
        XCTAssertEqual(statistics.peakMemoCount, 2)
        XCTAssertEqual(statistics.recordingMonthCount, 2)
    }

    func testStatisticsSnapshotCountsStreaksAndThirtyDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try date(2026, 8, 30, 12, calendar: calendar)
        let dates = try [
            date(2026, 8, 30, 1, calendar: calendar), date(2026, 8, 29, 22, calendar: calendar),
            date(2026, 8, 28, 8, calendar: calendar), date(2026, 8, 26, 12, calendar: calendar),
            date(2026, 8, 25, 12, calendar: calendar), date(2026, 8, 24, 12, calendar: calendar),
            date(2026, 7, 31, 12, calendar: calendar), date(2026, 7, 30, 12, calendar: calendar)
        ]
        let memos = dates.enumerated().map { index, createdAt in
            ScheduleMemo(body: "记录 \(index)", createdAt: createdAt)
        }

        let statistics = ScheduleMemoStatistics.snapshot(memos: memos, selectedYear: 2026, now: now, calendar: calendar)

        XCTAssertEqual(statistics.currentStreak, 3) // 今天、昨天、前天
        XCTAssertEqual(statistics.longestStreak, 3)
        XCTAssertEqual(statistics.recent30Days.count, 30)
        XCTAssertEqual(statistics.recent30Days.first?.date, try date(2026, 8, 1, calendar: calendar))
        XCTAssertEqual(statistics.recent30Days.last?.date, try date(2026, 8, 30, calendar: calendar))
        XCTAssertEqual(statistics.recent30DayMemoCount, 6)
        XCTAssertEqual(statistics.previous30DayMemoCount, 2)
        XCTAssertEqual(statistics.recent30DayRecordingDayCount, 6)
        XCTAssertEqual(statistics.previous30DayRecordingDayCount, 2)
    }

    func testStatisticsSnapshotCountsWeekdaysPeriodsAndTopTagsDeterministically() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try date(2026, 8, 10, 12, calendar: calendar) // Monday
        let memos = [
            ScheduleMemo(body: "#Beta #alpha", createdAt: try date(2026, 8, 10, 5, calendar: calendar)),
            ScheduleMemo(body: "#alpha", createdAt: try date(2026, 8, 11, 9, calendar: calendar)),
            ScheduleMemo(body: "#BETA", createdAt: try date(2026, 8, 12, 12, calendar: calendar)),
            ScheduleMemo(body: "#alpha", createdAt: try date(2026, 8, 13, 18, calendar: calendar)),
            ScheduleMemo(body: "#gamma", createdAt: try date(2026, 8, 14, 0, calendar: calendar)),
            ScheduleMemo(body: "#alpha", createdAt: try date(2026, 8, 15, 23, calendar: calendar)),
            ScheduleMemo(body: "#delta", createdAt: try date(2026, 8, 16, 4, calendar: calendar))
        ]

        let statistics = ScheduleMemoStatistics.snapshot(memos: memos, selectedYear: 2026, now: now, calendar: calendar)

        XCTAssertEqual(statistics.weekdayDistribution, [1, 1, 1, 1, 1, 1, 1])
        XCTAssertEqual(statistics.timePeriodDistribution.map(\.count), [1, 1, 1, 2, 2])
        XCTAssertEqual(statistics.topTags, [
            ScheduleMemoFrequency(name: "alpha", count: 4),
            ScheduleMemoFrequency(name: "Beta", count: 2),
            ScheduleMemoFrequency(name: "delta", count: 1),
            ScheduleMemoFrequency(name: "gamma", count: 1)
        ])
    }

    func testStatisticsAccessibilitySummariesDescribeChartValues() {
        let months = [
            ScheduleMemoMonthStatistics(month: 1, memoCount: 2, recordingDayCount: 1),
            ScheduleMemoMonthStatistics(month: 2, memoCount: 0, recordingDayCount: 0)
        ]
        XCTAssertEqual(
            ScheduleMemoStatisticsAccessibility.annualSummary(
                selectedYear: 2026,
                months: months,
                metric: .memoCount,
                language: .zhHans
            ),
            "2026 年全年记录频率（随记数）：1 月 2 条随记、2 月 0 条随记"
        )
        XCTAssertEqual(
            ScheduleMemoStatisticsAccessibility.annualSummary(
                selectedYear: 2026,
                months: months,
                metric: .recordingDays,
                language: .zhHans
            ),
            "2026 年全年记录频率（记录天数）：1 月记录 1 天、2 月记录 0 天"
        )
        XCTAssertEqual(
            ScheduleMemoStatisticsAccessibility.monthSummary(months[0], language: .zhHans),
            "1 月 · 2 条随记 · 记录 1 天"
        )
        XCTAssertEqual(
            ScheduleMemoStatisticsAccessibility.monthSummary(months[0], language: .enUS),
            "1 month · 2 note(s) · 1 recording day(s)"
        )

        XCTAssertEqual(
            ScheduleMemoStatisticsAccessibility.weekdaySummary(
                counts: [1, 0, 2, 0, 0, 0, 0],
                language: .zhHans
            ),
            "星期分布：周一：1 条随记、周二：0 条随记、周三：2 条随记、周四：0 条随记、周五：0 条随记、周六：0 条随记、周日：0 条随记"
        )
        XCTAssertEqual(
            ScheduleMemoStatisticsAccessibility.timePeriodSummary(
                periods: [
                    ScheduleMemoTimePeriodFrequency(period: .earlyMorning, count: 1),
                    ScheduleMemoTimePeriodFrequency(period: .morning, count: 2),
                    ScheduleMemoTimePeriodFrequency(period: .afternoon, count: 3),
                    ScheduleMemoTimePeriodFrequency(period: .evening, count: 4),
                    ScheduleMemoTimePeriodFrequency(period: .lateNight, count: 5)
                ],
                language: .zhHans
            ),
            "时间段分布：清晨：1 条随记、上午：2 条随记、下午：3 条随记、晚间：4 条随记、深夜：5 条随记"
        )
        XCTAssertEqual(
            ScheduleMemoStatisticsAccessibility.heatmapSummary(
                days: (0..<30).map {
                    ScheduleMemoActivityDay(
                        date: Date(timeIntervalSince1970: TimeInterval($0) * 86_400),
                        count: $0 == 0 ? 2 : 0
                    )
                },
                language: .zhHans
            ),
            "近 30 天热力图：2 条随记，1 天有记录。"
        )
    }

    func testStatisticsSnapshotHandlesEmptyDataAndKeepsYesterdayStreakCurrent() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try date(2026, 8, 10, 12, calendar: calendar)

        let empty = ScheduleMemoStatistics.snapshot(
            memos: [],
            selectedYear: 2026,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(empty.memoCount, 0)
        XCTAssertEqual(empty.currentStreak, 0)
        XCTAssertEqual(empty.longestStreak, 0)
        XCTAssertEqual(empty.recent30Days.count, 30)
        XCTAssertEqual(empty.selectedYearMonths.count, 12)

        let yesterdayStreak = ScheduleMemoStatistics.snapshot(
            memos: [
                ScheduleMemo(body: "昨天", createdAt: try date(2026, 8, 9, 8, calendar: calendar)),
                ScheduleMemo(body: "前天", createdAt: try date(2026, 8, 8, 8, calendar: calendar))
            ],
            selectedYear: 2026,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(yesterdayStreak.currentStreak, 2)
        XCTAssertEqual(yesterdayStreak.longestStreak, 2)
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

    func testPhotoSelectionTransactionCommitsCancelsAndCarriesPendingSelectionToFullPicker() {
        var transaction = ScheduleMemoPhotoSelectionTransaction(committed: [1, 2])
        transaction.pending = [1, 2, 3]
        XCTAssertEqual(transaction.fullPickerSelection, [1, 2, 3])
        XCTAssertEqual(transaction.cancel(), [1, 2])

        transaction.pending = [1, 2, 4]
        XCTAssertEqual(transaction.commit(), [1, 2, 4])
        transaction.pending = [1, 2, 4, 5]
        XCTAssertEqual(transaction.cancel(), [1, 2, 4])
    }

    func testFinalAudioDurationPreservesTimeCapturedBeforeRecorderStops() {
        XCTAssertEqual(
            ScheduleMemoAudioDuration.finalElapsed(
                recorderTime: 2.4,
                observedElapsed: 2.3
            ),
            2.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScheduleMemoAudioDuration.finalElapsed(
                recorderTime: 0,
                observedElapsed: 1.8
            ),
            1.8,
            accuracy: 0.001
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

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar = .current) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }
}
