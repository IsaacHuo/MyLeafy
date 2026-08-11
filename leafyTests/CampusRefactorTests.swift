import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase
import SwiftData
@testable import Leafy

extension PerformanceRefactorTests {
    func testPeriodRangeUsesOverlappingClassSlots() throws {
        let calendar = Calendar.current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 8, minute: 10)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 9, minute: 0)))
        let gapStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12, minute: 20)))
        let gapEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 13, minute: 0)))

        XCTAssertEqual(TimetablePeriodSchedule.periodRange(overlapping: start, endDate: end), 1...2)
        XCTAssertNil(TimetablePeriodSchedule.periodRange(overlapping: gapStart, endDate: gapEnd))
        XCTAssertNil(TimetablePeriodSchedule.periodRange(overlapping: end, endDate: start))
    }

    @MainActor
    func testMultipleResumeRecordsReplaceAndDeleteIndependently() throws {
        try? CareerDocumentFileStore.deleteAllFiles()
        defer { try? CareerDocumentFileStore.deleteAllFiles() }

        let schema = Schema([CareerResumeDocument.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafyResumeSources-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        let productSource = sourceDirectory.appendingPathComponent("product.pdf")
        let designSource = sourceDirectory.appendingPathComponent("design.pdf")
        let replacementSource = sourceDirectory.appendingPathComponent("product-v2.pdf")
        try Data("product-v1".utf8).write(to: productSource)
        try Data("design-v1".utf8).write(to: designSource)
        try Data("product-v2".utf8).write(to: replacementSource)

        let productFile = try CareerDocumentFileStore.importFile(from: productSource)
        let designFile = try CareerDocumentFileStore.importFile(from: designSource)
        let productResume = CareerResumeDocument(
            title: "产品实习版",
            note: "面向产品岗位",
            originalFilename: productSource.lastPathComponent,
            localFilename: productFile.localFilename,
            contentTypeIdentifier: productFile.contentTypeIdentifier
        )
        let designResume = CareerResumeDocument(
            title: "设计实习版",
            note: "面向设计岗位",
            originalFilename: designSource.lastPathComponent,
            localFilename: designFile.localFilename,
            contentTypeIdentifier: designFile.contentTypeIdentifier
        )
        context.insert(productResume)
        context.insert(designResume)
        try context.save()

        let previousFilename = productResume.localFilename
        let replacementFile = try CareerDocumentFileStore.importFile(from: replacementSource)
        productResume.originalFilename = replacementSource.lastPathComponent
        productResume.localFilename = replacementFile.localFilename
        productResume.contentTypeIdentifier = replacementFile.contentTypeIdentifier
        try context.save()
        try CareerDocumentFileStore.deleteFile(named: previousFilename)

        XCTAssertEqual(productResume.title, "产品实习版")
        XCTAssertEqual(productResume.note, "面向产品岗位")
        XCTAssertNotNil(CareerDocumentFileStore.fileURL(for: productResume))
        XCTAssertNotNil(CareerDocumentFileStore.fileURL(for: designResume))

        try CareerDocumentFileStore.deleteFile(named: designResume.localFilename)
        context.delete(designResume)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<CareerResumeDocument>())
        XCTAssertEqual(remaining.map(\.title), ["产品实习版"])

        try CareerDocumentFileStore.deleteAllFiles()
        XCTAssertNil(CareerDocumentFileStore.fileURL(for: productResume))
    }

    func testFirstValueMapKeepsFirstRemoteValueForDuplicateKeys() throws {
        let postID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let pollID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let firstOptionID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondOptionID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let firstSignedURL = URL(string: "https://example.com/first")!
        let secondSignedURL = URL(string: "https://example.com/second")!

        let postOrder = LeafyFirstValueMap.build([(postID, 0), (postID, 1)])
        let profileMap = LeafyFirstValueMap.build([(profileID, "first"), (profileID, "second")])
        let signedMap = LeafyFirstValueMap.build([("images/post.jpg", firstSignedURL), ("images/post.jpg", secondSignedURL)])
        let voteMap = LeafyFirstValueMap.build([(pollID, firstOptionID), (pollID, secondOptionID)])

        XCTAssertEqual(postOrder[postID], 0)
        XCTAssertEqual(profileMap[profileID], "first")
        XCTAssertEqual(signedMap["images/post.jpg"], firstSignedURL)
        XCTAssertEqual(voteMap[pollID], firstOptionID)
    }

    func testCustomCampusRegistrationUsesSignupRequestsWithoutPasswordUpdate() async {
        AuthRecordingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthRecordingURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "test-anon-key",
            options: SupabaseClientOptions(global: .init(session: URLSession(configuration: configuration)))
        )
        let service = CustomCampusAuthService(clientProvider: { client })

        do {
            try await service.startSignUp(email: "student@example.com", password: "password123")
            XCTFail("Expected the recording transport to return an error.")
        } catch {}

        do {
            try await service.resendSignUpCode(email: "student@example.com")
            XCTFail("Expected the recording transport to return an error.")
        } catch {}

        do {
            _ = try await service.verifySignUpCode(email: "student@example.com", code: "12345678")
            XCTFail("Expected the recording transport to return an error.")
        } catch {}

        let requests = AuthRecordingURLProtocol.snapshot()
        XCTAssertEqual(requests.map(\.path), [
            "/auth/v1/signup",
            "/auth/v1/resend",
            "/auth/v1/verify"
        ])
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "POST"])
        guard requests.count == 3 else { return }
        XCTAssertEqual(requests[0].body["email"] as? String, "student@example.com")
        XCTAssertEqual(requests[0].body["password"] as? String, "password123")
        XCTAssertEqual(requests[1].body["type"] as? String, "signup")
        XCTAssertEqual(requests[2].body["type"] as? String, "signup")
        XCTAssertFalse(requests.contains { $0.path == "/auth/v1/user" })
    }

    @MainActor
    func testManualGradeDraftValidationAndCRUDRemainContainerScoped() throws {
        XCTAssertThrowsError(
            try ManualGradeDraft(
                term: "",
                courseName: "数据结构",
                credit: "3",
                score: "优秀",
                type: "必修"
            ).validated()
        ) { error in
            XCTAssertEqual(error as? ManualGradeValidationError, .missingTerm)
        }
        XCTAssertThrowsError(
            try ManualGradeDraft(
                term: "2025-2026-2",
                courseName: "数据结构",
                credit: "三",
                score: "优秀",
                type: "必修"
            ).validated()
        ) { error in
            XCTAssertEqual(error as? ManualGradeValidationError, .invalidCredit)
        }

        let schema = Schema([Grade.self])
        let firstContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let secondContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )

        let grade = try ManualGradeStore.save(
            draft: ManualGradeDraft(
                term: " 2025-2026-2 ",
                courseName: " 数据结构 ",
                credit: " 3.0 ",
                score: " 优秀 ",
                type: " 必修 "
            ),
            editing: nil,
            in: firstContainer.mainContext
        )
        XCTAssertEqual(grade.term, "2025-2026-2")
        XCTAssertEqual(grade.score, "优秀")
        XCTAssertEqual(try firstContainer.mainContext.fetch(FetchDescriptor<Grade>()).count, 1)
        XCTAssertTrue(try secondContainer.mainContext.fetch(FetchDescriptor<Grade>()).isEmpty)

        try ManualGradeStore.save(
            draft: ManualGradeDraft(
                term: "2025-2026-2",
                courseName: "数据结构",
                credit: "3.0",
                score: "92",
                type: "专业必修"
            ),
            editing: grade,
            in: firstContainer.mainContext
        )
        XCTAssertEqual(grade.score, "92")
        XCTAssertEqual(grade.type, "专业必修")

        try ManualGradeStore.delete(grade, in: firstContainer.mainContext)
        XCTAssertTrue(try firstContainer.mainContext.fetch(FetchDescriptor<Grade>()).isEmpty)
    }

    func testCustomCampusCSVParserReportsMissingColumns() {
        let csv = """
        term,courseName,score,type
        2025-2026-2,数据结构,92,必修
        """

        XCTAssertThrowsError(try CustomCampusCSVParser.parseGrades(csv)) { error in
            guard case CustomCampusImportError.missingColumns(let columns) = error else {
                return XCTFail("Expected missingColumns, got \(error)")
            }
            XCTAssertEqual(columns, ["credit"])
        }
    }

    func testProfileCacheSummaryBuildsEmptyCacheRows() throws {
        let summary = ProfileCacheSummary.make(
            language: .zhHans,
            courseCount: 0,
            gradeCount: 0,
            timetableLastSyncAt: nil,
            gradeRankingCount: 0,
            gradeRankingLastSyncAt: nil,
            gradeCreditTotal: nil,
            examCount: 0,
            examLastSyncAt: nil,
            graduationRequirementCount: 0,
            graduationRequirementLastSyncAt: nil,
            classroomsLastSyncAt: nil,
            noteCount: 0,
            reminderCount: 0,
            cellReminderCount: 0,
            favoriteClassroomCount: 0,
            postgraduateTargetCount: 0,
            learningMaterialCount: 0,
            learningProjectCount: 0,
            learningTaskCount: 0,
            studyTimeRecordCount: 0,
            fitnessTestRecordCount: 0
        )

        XCTAssertEqual(summary.rows.count, 11)
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "所得学分" }).value, "未缓存")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "课表" }).detail, "暂无同步记录")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "本地数据" }).value, "0 条备注 / 0 个收藏")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "学习空间" }).value, "0 个空间 / 0 份资料")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "体测记录" }).value, "0 条记录")
    }

    func testProfileCacheSummaryBuildsPopulatedCacheRows() throws {
        let syncedAt = reviewDate(2026, 5, 14)
        let summary = ProfileCacheSummary.make(
            language: .zhHans,
            courseCount: 6,
            gradeCount: 12,
            timetableLastSyncAt: syncedAt,
            gradeRankingCount: 3,
            gradeRankingLastSyncAt: syncedAt,
            gradeCreditTotal: 42.5,
            examCount: 2,
            examLastSyncAt: syncedAt,
            graduationRequirementCount: 9,
            graduationRequirementLastSyncAt: syncedAt,
            classroomsLastSyncAt: syncedAt,
            noteCount: 4,
            reminderCount: 5,
            cellReminderCount: 6,
            favoriteClassroomCount: 7,
            postgraduateTargetCount: 3,
            learningMaterialCount: 8,
            learningProjectCount: 2,
            learningTaskCount: 10,
            studyTimeRecordCount: 11,
            fitnessTestRecordCount: 9
        )

        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "所得学分" }).value, "42.5 学分")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "考试安排" }).value, "2 条考试")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "本地数据" }).detail, "11 个提醒")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "学习空间" }).value, "2 个空间 / 8 份资料")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "学习空间" }).detail, "10 个任务 / 11 条记录")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "体测记录" }).value, "9 条记录")
        XCTAssertTrue(try XCTUnwrap(summary.rows.first { $0.title == "课表" }).detail.contains("最近同步："))
    }

    func testAcademicPrimaryTabPlacesLearningBeforeSports() throws {
        let tabs = AcademicPrimaryTab.allCases
        let learningIndex = try XCTUnwrap(tabs.firstIndex(of: .learning))
        let sportsIndex = try XCTUnwrap(tabs.firstIndex(of: .sports))

        XCTAssertEqual(learningIndex + 1, sportsIndex)
    }

    func testLearningMaterialCategoryFallsBackToOther() {
        XCTAssertEqual(LearningMaterialCategory.normalized("四六级"), .cet)
        XCTAssertEqual(LearningMaterialCategory.normalized("未知"), .other)
    }

    func testLearningFixedSpaceOrder() {
        XCTAssertEqual(LearningMaterialCategory.fixedSpaceOrder, [.cet, .exam, .courseware, .other])
    }

    func testLearningProjectKindFallsBackToGeneral() {
        XCTAssertEqual(LearningProjectKind.normalized("course"), .course)
        XCTAssertEqual(LearningProjectKind.normalized("unknown"), .general)
    }

    func testPostgraduateTargetStateFallsBackToActive() {
        XCTAssertEqual(PostgraduateTargetState.normalized("focused"), .focused)
        XCTAssertEqual(PostgraduateTargetState.normalized("unknown"), .active)
    }

    func testPostgraduateSourceTrustLevelFallsBackToCurated() {
        XCTAssertEqual(PostgraduateSourceTrustLevel.normalized("official"), .official)
        XCTAssertEqual(PostgraduateSourceTrustLevel.normalized("unknown"), .curated)
    }

    func testPostgraduatePublishedSourceExposesOfficialURLAndKind() {
        let source = PostgraduateSource(
            id: UUID(),
            title: "北林招生简章",
            summary: "招生政策",
            sourceURLString: "https://graduate.bjfu.edu.cn/",
            sourceKindRawValue: PostgraduateSourceKind.admissionNotice.rawValue,
            trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
            school: "北京林业大学",
            unit: nil,
            major: nil,
            examYear: 2026,
            publishedAt: nil,
            verifiedAt: nil,
            status: "published",
            createdAt: nil,
            updatedAt: nil
        )

        XCTAssertEqual(source.sourceURL?.scheme, "https")
        XCTAssertEqual(source.sourceKind, .admissionNotice)
        XCTAssertEqual(source.trustLevel, .official)
    }

    func testPostgraduateSourceMatcherPrefersExactTargetMatch() throws {
        let target = PostgraduateTarget(
            school: "北京林业大学",
            unit: "园林学院",
            major: "风景园林",
            examYear: 2026
        )
        let exactID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let schoolID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let generalID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let sources = [
            PostgraduateSource(
                id: generalID,
                title: "研招网",
                summary: "硕士专业目录",
                sourceURLString: "https://yz.chsi.com.cn/",
                sourceKindRawValue: PostgraduateSourceKind.majorCatalog.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
                school: nil,
                unit: nil,
                major: nil,
                examYear: nil,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            ),
            PostgraduateSource(
                id: schoolID,
                title: "北京林业大学硕士招生简章",
                summary: "学校招生信息",
                sourceURLString: "https://graduate.bjfu.edu.cn/",
                sourceKindRawValue: PostgraduateSourceKind.admissionNotice.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
                school: "北京林业大学",
                unit: nil,
                major: nil,
                examYear: 2026,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            ),
            PostgraduateSource(
                id: exactID,
                title: "北京林业大学风景园林复试线",
                summary: "园林学院风景园林复试信息",
                sourceURLString: "https://graduate.bjfu.edu.cn/",
                sourceKindRawValue: PostgraduateSourceKind.scoreLine.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.verifiedUser.rawValue,
                school: "北京林业大学",
                unit: "园林学院",
                major: "风景园林",
                examYear: 2026,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            )
        ]

        let sorted = PostgraduateSourceMatcher.sortedSources(for: target, from: sources)

        XCTAssertEqual(sorted.map(\.id), [exactID, schoolID, generalID])
    }

    func testPostgraduateTimelineSpansPreviousYearThroughAdmissionYear() {
        let nodes = PostgraduateTimelineBuilder.nodes(
            forExamYear: 2027,
            now: reviewDate(2026, 1, 1),
            calendar: reviewTestCalendar
        )

        XCTAssertEqual(nodes.map(\.phase), PostgraduateTimelinePhase.allCases)
        XCTAssertEqual(nodes.first?.periodText, "2026年3-6月")
        XCTAssertEqual(nodes.last?.periodText, "2027年4-6月")
    }

    func testPostgraduateTimelineMarksCurrentPhaseFromMonthWindow() {
        let nodes = PostgraduateTimelineBuilder.nodes(
            forExamYear: 2027,
            now: reviewDate(2026, 10, 12),
            calendar: reviewTestCalendar
        )

        XCTAssertEqual(nodes.first { $0.phase == .catalog }?.status, .completed)
        XCTAssertEqual(nodes.first { $0.phase == .registration }?.status, .current)
        XCTAssertEqual(nodes.first { $0.phase == .confirmation }?.status, .upcoming)
    }

    func testPostgraduateTargetSelectorPrefersFocusedAndSkipsArchived() throws {
        let archivedID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let activeID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000102"))
        let focusedID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000103"))
        let archived = PostgraduateTarget(
            id: archivedID,
            school: "归档大学",
            major: "林学",
            examYear: 2026,
            stateRawValue: PostgraduateTargetState.archived.rawValue
        )
        let active = PostgraduateTarget(
            id: activeID,
            school: "活跃大学",
            major: "生态学",
            examYear: 2026
        )
        let focused = PostgraduateTarget(
            id: focusedID,
            school: "聚焦大学",
            major: "风景园林",
            examYear: 2028,
            stateRawValue: PostgraduateTargetState.focused.rawValue
        )

        let selected = PostgraduateTargetSelector.primaryTarget(
            from: [archived, active, focused],
            currentYear: 2026
        )
        let activeTargets = PostgraduateTargetSelector.sortedActiveTargets(
            from: [archived, active, focused],
            currentYear: 2026
        )

        XCTAssertEqual(selected?.id, focusedID)
        XCTAssertEqual(activeTargets.map(\.id), [focusedID, activeID])
        XCTAssertFalse(activeTargets.contains { $0.id == archivedID })
    }

    func testPostgraduateSourcePresentationKeepsGeneralFallbackForTarget() throws {
        let target = PostgraduateTarget(
            school: "北京林业大学",
            unit: "园林学院",
            major: "风景园林",
            examYear: 2027
        )
        let exactID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000201"))
        let generalID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000202"))
        let unrelatedID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000203"))
        let sources = [
            PostgraduateSource(
                id: unrelatedID,
                title: "其他学校招生简章",
                summary: "无关来源",
                sourceURLString: "https://example.com/",
                sourceKindRawValue: PostgraduateSourceKind.admissionNotice.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
                school: "其他学校",
                unit: nil,
                major: "软件工程",
                examYear: 2027,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            ),
            PostgraduateSource(
                id: generalID,
                title: "研招网硕士专业目录",
                summary: "通用来源",
                sourceURLString: "https://yz.chsi.com.cn/zsml/",
                sourceKindRawValue: PostgraduateSourceKind.majorCatalog.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
                school: nil,
                unit: nil,
                major: nil,
                examYear: nil,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            ),
            PostgraduateSource(
                id: exactID,
                title: "北京林业大学风景园林复试线",
                summary: "园林学院风景园林复试信息",
                sourceURLString: "https://graduate.bjfu.edu.cn/",
                sourceKindRawValue: PostgraduateSourceKind.scoreLine.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.curated.rawValue,
                school: "北京林业大学",
                unit: "园林学院",
                major: "风景园林",
                examYear: 2027,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            )
        ]

        let sorted = PostgraduateSourcePresentation.sortedSources(for: target, from: sources)

        XCTAssertEqual(sorted.map(\.id), [exactID, generalID])
    }

    func testLearningWorkspaceSummaryScopesFixedAndProjectContent() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
        let now = reviewDate(2026, 5, 14)
        let sameWeek = reviewDate(2026, 5, 13)
        let oldDate = reviewDate(2026, 4, 1)
        let materials = [
            LearningMaterialDocument(title: "CET", categoryRawValue: LearningMaterialCategory.cet.rawValue, originalFilename: "cet.pdf", localFilename: "cet.pdf", contentTypeIdentifier: UTType.pdf.identifier),
            LearningMaterialDocument(projectID: projectID.uuidString, title: "Project", originalFilename: "p.pdf", localFilename: "p.pdf", contentTypeIdentifier: UTType.pdf.identifier)
        ]
        let tasks = [
            LearningProjectTask(categoryRawValue: LearningMaterialCategory.cet.rawValue, title: "背单词"),
            LearningProjectTask(projectID: projectID.uuidString, title: "刷题", isCompleted: true)
        ]
        let records = [
            StudyTimeRecord(categoryRawValue: LearningMaterialCategory.cet.rawValue, startedAt: sameWeek, endedAt: sameWeek.addingTimeInterval(3600), content: "听力", location: "图书馆"),
            StudyTimeRecord(projectID: projectID.uuidString, startedAt: oldDate, endedAt: oldDate.addingTimeInterval(1800), content: "项目", location: "图书馆")
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

        let fixed = LearningWorkspaceSummary.make(destination: .fixed(.cet), materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)
        XCTAssertEqual(fixed.materialCount, 1)
        XCTAssertEqual(fixed.pendingTaskCount, 1)
        XCTAssertEqual(fixed.weekDuration, 3600)

        let project = LearningWorkspaceSummary.make(destination: .project(projectID), materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)
        XCTAssertEqual(project.materialCount, 1)
        XCTAssertEqual(project.completedTaskCount, 1)
        XCTAssertEqual(project.totalDuration, 1800)
    }

    func testStudyTimeRecordsWithoutTopicBelongToOtherSpace() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000125"))
        let now = reviewDate(2026, 5, 14)
        let unscopedRecord = StudyTimeRecord(startedAt: now, endedAt: now.addingTimeInterval(900), content: "专注学习", location: "图书馆")
        let fixedRecord = StudyTimeRecord(categoryRawValue: LearningMaterialCategory.exam.rawValue, startedAt: now, endedAt: now.addingTimeInterval(1200), content: "专业课", location: "图书馆")
        let projectRecord = StudyTimeRecord(projectID: projectID.uuidString, startedAt: now, endedAt: now.addingTimeInterval(1800), content: "项目", location: "图书馆")
        let records = [unscopedRecord, fixedRecord, projectRecord]

        XCTAssertTrue(unscopedRecord.belongs(to: .fixed(.other)))
        XCTAssertEqual(LearningWorkspaceSummary.make(destination: .fixed(.other), materials: [], tasks: [], records: records, now: now).totalDuration, 900)
        XCTAssertEqual(LearningWorkspaceSummary.make(destination: .fixed(.exam), materials: [], tasks: [], records: records, now: now).totalDuration, 1200)
        XCTAssertEqual(LearningWorkspaceSummary.make(destination: .project(projectID), materials: [], tasks: [], records: records, now: now).totalDuration, 1800)
        let index = LearningWorkspaceIndex.make(materials: [], tasks: [], records: records, now: now)
        XCTAssertEqual(index.summary(for: .fixed(.other)).totalDuration, 900)
        XCTAssertEqual(records.learningDuration, 3900)
    }

    @MainActor
    func testPassFailGradeKeepsRawScoreAndSkipsNumericStatistics() {
        let grades = [
            Grade(term: "2025-2026-2", courseName: "劳动教育", credit: "1.0", score: "合格", type: "必修"),
            Grade(term: "2025-2026-2", courseName: "森林生态学", credit: "2.0", score: "90", type: "必修")
        ]

        let analytics = GradeAnalytics.calculate(from: grades, creditSummary: nil)
        let passFailCourse = analytics.courses.first { $0.name == "劳动教育" }

        XCTAssertEqual(passFailCourse?.rawScore, "合格")
        XCTAssertNil(passFailCourse?.score)
        XCTAssertEqual(passFailCourse?.isPassed, true)
        XCTAssertEqual(passFailCourse?.isIncludedInStatistics, false)
        XCTAssertEqual(analytics.totalCredits, 3.0)
        XCTAssertEqual(analytics.passedCredits, 3.0)
        XCTAssertEqual(analytics.passRate, 1.0)
        XCTAssertEqual(analytics.weightedAverage, 90.0)
        XCTAssertEqual(analytics.medianScore, 90.0)
        XCTAssertEqual(analytics.scoreDistribution.first { $0.range == "90+" }?.count, 1)
        XCTAssertEqual(analytics.scoreDistribution.first { $0.range == "60-69" }?.count, 0)
    }

    @MainActor
    func testFailingTextGradeCountsAsRiskWithoutPassedCredits() {
        let grades = [
            Grade(term: "2025-2026-2", courseName: "劳动教育", credit: "1.0", score: "不合格", type: "必修"),
            Grade(term: "2025-2026-2", courseName: "森林生态学", credit: "2.0", score: "良好", type: "必修")
        ]

        let analytics = GradeAnalytics.calculate(from: grades, creditSummary: nil)
        let failingCourse = analytics.courses.first { $0.name == "劳动教育" }
        let gradedCourse = analytics.courses.first { $0.name == "森林生态学" }

        XCTAssertEqual(failingCourse?.rawScore, "不合格")
        XCTAssertNil(failingCourse?.score)
        XCTAssertEqual(failingCourse?.isPassed, false)
        XCTAssertEqual(failingCourse?.isIncludedInStatistics, false)
        XCTAssertEqual(gradedCourse?.score, 85)
        XCTAssertEqual(analytics.totalCredits, 3.0)
        XCTAssertEqual(analytics.passedCredits, 2.0)
        XCTAssertEqual(analytics.passRate, 0.5)
        XCTAssertEqual(analytics.riskCourseCount, 1)
        XCTAssertEqual(analytics.weightedAverage, 85.0)
    }

    func testLearningProjectContentRelocationMovesProjectContentToUnfiled() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000456"))
        let now = reviewDate(2026, 5, 14)
        let updatedAt = reviewDate(2026, 5, 15)
        let material = LearningMaterialDocument(projectID: projectID.uuidString, title: "Project", originalFilename: "p.pdf", localFilename: "p.pdf", contentTypeIdentifier: UTType.pdf.identifier)
        let task = LearningProjectTask(projectID: projectID.uuidString, title: "刷题")
        let record = StudyTimeRecord(projectID: projectID.uuidString, startedAt: now, endedAt: now.addingTimeInterval(1800), content: "项目", location: "图书馆")
        let otherMaterial = LearningMaterialDocument(title: "Other", originalFilename: "o.pdf", localFilename: "o.pdf", contentTypeIdentifier: UTType.pdf.identifier)
        let materials = [material, otherMaterial]
        let tasks = [task]
        let records = [record]

        LearningProjectContentRelocation.moveToUnfiled(
            projectID: projectID,
            materials: materials,
            tasks: tasks,
            records: records,
            updatedAt: updatedAt
        )

        XCTAssertEqual(material.projectID, "")
        XCTAssertEqual(material.category, .other)
        XCTAssertEqual(material.updatedAt, updatedAt)
        XCTAssertEqual(task.projectID, "")
        XCTAssertEqual(task.category, .other)
        XCTAssertEqual(record.projectID, "")
        XCTAssertEqual(record.category, .other)

        let project = LearningWorkspaceSummary.make(destination: .project(projectID), materials: materials, tasks: tasks, records: records, now: now)
        XCTAssertEqual(project, LearningWorkspaceSummary(materialCount: 0, taskCount: 0, completedTaskCount: 0, recordCount: 0, totalDuration: 0, weekDuration: 0))

        let other = LearningWorkspaceSummary.make(destination: .fixed(.other), materials: materials, tasks: tasks, records: records, now: now)
        XCTAssertEqual(other.materialCount, 2)
        XCTAssertEqual(other.taskCount, 1)
        XCTAssertEqual(other.recordCount, 1)
        XCTAssertEqual(other.totalDuration, 1800)
    }

    @MainActor
    func testDeletingFixedWorkspaceContentsLeavesOtherDestinationsUntouched() throws {
        let schema = Schema([
            LearningMaterialDocument.self,
            LearningProjectTask.self,
            StudyTimeRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let projectID = UUID()
        let now = Date()

        let targetMaterial = LearningMaterialDocument(
            title: "考试资料",
            categoryRawValue: LearningMaterialCategory.exam.rawValue,
            originalFilename: "exam.pdf",
            localFilename: "missing-\(UUID().uuidString).pdf",
            contentTypeIdentifier: UTType.pdf.identifier
        )
        let otherMaterial = LearningMaterialDocument(
            title: "其他资料",
            categoryRawValue: LearningMaterialCategory.other.rawValue,
            originalFilename: "other.pdf",
            localFilename: "missing-\(UUID().uuidString).pdf",
            contentTypeIdentifier: UTType.pdf.identifier
        )
        let projectTask = LearningProjectTask(projectID: projectID.uuidString, title: "项目任务")
        let targetTask = LearningProjectTask(categoryRawValue: LearningMaterialCategory.exam.rawValue, title: "考试任务")
        let targetRecord = StudyTimeRecord(
            categoryRawValue: LearningMaterialCategory.exam.rawValue,
            startedAt: now,
            endedAt: now.addingTimeInterval(1800),
            content: "复习",
            location: "图书馆"
        )

        [targetMaterial, otherMaterial].forEach(context.insert)
        [projectTask, targetTask].forEach(context.insert)
        context.insert(targetRecord)
        try context.save()

        try LearningProjectContentRelocation.deleteContents(
            in: .fixed(.exam),
            materials: [targetMaterial, otherMaterial],
            tasks: [projectTask, targetTask],
            records: [targetRecord],
            modelContext: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningMaterialDocument>()).map(\.id), [otherMaterial.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningProjectTask>()).map(\.id), [projectTask.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyTimeRecord>()).isEmpty)
    }

    func testLearningMaterialDisplayTypeUsesContentTypeAndFilename() {
        XCTAssertEqual(
            LearningMaterialDocument.displayType(contentTypeIdentifier: UTType.pdf.identifier, originalFilename: "exam.pdf"),
            "PDF"
        )
        XCTAssertEqual(
            LearningMaterialDocument.displayType(contentTypeIdentifier: UTType.data.identifier, originalFilename: "课件.pptx"),
            "PPT"
        )
        XCTAssertEqual(
            LearningMaterialDocument.displayType(contentTypeIdentifier: UTType.data.identifier, originalFilename: "成绩表.xlsx"),
            "表格"
        )
        XCTAssertEqual(
            LearningMaterialDocument.displayType(contentTypeIdentifier: UTType.data.identifier, originalFilename: "notes.unknown"),
            "文件"
        )
    }

    func testLearningMaterialLocalFilenameKeepsExtensionWhenPresent() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))

        XCTAssertEqual(
            LearningMaterialLocalFile.localFilename(originalExtension: ".pptx", uuid: uuid),
            "00000000-0000-0000-0000-000000000001.pptx"
        )
        XCTAssertEqual(
            LearningMaterialLocalFile.localFilename(originalExtension: "", uuid: uuid),
            "00000000-0000-0000-0000-000000000001"
        )
    }

    func testFitnessTestItemDefaultUnits() {
        XCTAssertEqual(FitnessTestItem.height.defaultUnit, .centimeter)
        XCTAssertEqual(FitnessTestItem.weight.defaultUnit, .kilogram)
        XCTAssertEqual(FitnessTestItem.vitalCapacity.defaultUnit, .milliliter)
        XCTAssertEqual(FitnessTestItem.sprint50m.defaultUnit, .second)
        XCTAssertEqual(FitnessTestItem.pullUps.defaultUnit, .count)
        XCTAssertEqual(FitnessTestItem.run800m.defaultUnit, .minuteSecond)
        XCTAssertEqual(FitnessTestItem.run1000m.defaultUnit, .minuteSecond)
    }

    func testFitnessTestMinuteSecondFormatting() {
        XCTAssertEqual(FitnessTestRecordFormatter.minuteSecondText(seconds: 214), "3分34秒")
        XCTAssertEqual(FitnessTestRecordFormatter.valueText(value: 486, unit: .minuteSecond), "8分6秒")
    }

    @MainActor
    func testFitnessTestRecordsSortByTestDateDescending() {
        let older = FitnessTestRecord(
            testedAt: reviewDate(2026, 5, 1),
            itemRawValue: FitnessTestItem.height.rawValue,
            value: 170,
            unitRawValue: FitnessTestUnit.centimeter.rawValue,
            createdAt: reviewDate(2026, 5, 1)
        )
        let newer = FitnessTestRecord(
            testedAt: reviewDate(2026, 5, 3),
            itemRawValue: FitnessTestItem.weight.rawValue,
            value: 60,
            unitRawValue: FitnessTestUnit.kilogram.rawValue,
            createdAt: reviewDate(2026, 5, 3)
        )
        let sameDateLaterCreated = FitnessTestRecord(
            testedAt: reviewDate(2026, 5, 3),
            itemRawValue: FitnessTestItem.sprint50m.rawValue,
            value: 8.2,
            unitRawValue: FitnessTestUnit.second.rawValue,
            createdAt: reviewDate(2026, 5, 4)
        )

        let sorted = FitnessTestRecordFormatter.sortedRecords([older, newer, sameDateLaterCreated])

        XCTAssertEqual(sorted.map(\.itemRawValue), [
            FitnessTestItem.sprint50m.rawValue,
            FitnessTestItem.weight.rawValue,
            FitnessTestItem.height.rawValue
        ])
    }
}
