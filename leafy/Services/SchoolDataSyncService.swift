import Foundation
import SwiftData

enum SchoolDataSyncOutcome: Equatable {
    case success(String)
    case partialSuccess(String)
    case failure(String)
    case needsLogin
    case needsReauthentication(SchoolReauthenticationContext)
}

enum SchoolDataRefreshScope: String, CaseIterable, Sendable {
    case timetable
    case grades
    case gradeSupplemental
    case exams
    case teachingPlan
    case trainingProgram
    case all
}

struct SchoolDataRefreshEvent: Sendable {
    let scopes: Set<SchoolDataRefreshScope>

    init(_ scopes: Set<SchoolDataRefreshScope>) {
        self.scopes = scopes
    }

    init(_ scope: SchoolDataRefreshScope) {
        self.init([scope])
    }

    func contains(_ scope: SchoolDataRefreshScope) -> Bool {
        scopes.contains(.all) || scopes.contains(scope)
    }
}

extension Notification.Name {
    static let schoolDataDidRefresh = Notification.Name("SchoolDataDidRefresh")
}

enum SchoolDataRefreshNotifier {
    static func post(_ scopes: Set<SchoolDataRefreshScope>) {
        guard !scopes.isEmpty else { return }
        NotificationCenter.default.post(
            name: .schoolDataDidRefresh,
            object: SchoolDataRefreshEvent(scopes)
        )
    }

    static func post(_ scope: SchoolDataRefreshScope) {
        post([scope])
    }
}

@MainActor
enum SchoolDataSyncService {
    static func syncAll(
        modelContext: ModelContext,
        language: AppLanguagePreference,
        userInitiated: Bool = false,
        progressReporter: AcademicOperationProgressReporter? = nil
    ) async -> SchoolDataSyncOutcome {
        let networkManager = ActiveCampusContext.networkManager

        if ReviewDemoMode.isEnabled {
            ReviewDemoDataSeeder.seed(using: modelContext)
            LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
            return .success(L10n.text("已刷新演示学校数据。社区数据仍使用真实服务。", language: language))
        }

        if ActiveCampusContext.identity?.isCustom == true {
            return .success(L10n.text("通用入口不连接教务系统。请在课表、成绩和考试页面使用“导入”更新本地数据。", language: language))
        }

        guard networkManager.hasCachedIdentity else {
            return .needsLogin
        }

        guard networkManager.isLoggedIn else {
            return .needsReauthentication(.schoolDataSync)
        }

        progressReporter?(.begin(.refreshingSemester))
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable(force: true)

        var results: [String] = []
        var successfulOperationCount = 0
        var failedOperationCount = 0
        var refreshedScopes: Set<SchoolDataRefreshScope> = []
        var parsedGrades: [Grade]?
        var gradeRankingsToSave: [GradeRankingRecord]?
        var gradeCreditSummaryToSave: GradeCreditSummary?
        var examScheduleToSave: [ExamArrangement]?
        var teachingPlanToSave: [TeachingPlanSection]?
        var trainingProgramToSave: TrainingProgramDocument?

        do {
            progressReporter?(.begin(.fetchingTimetable))
            let html = try await networkManager.fetchTimetable()
            progressReporter?(.begin(.processingTimetable))
            let parsed = try HTMLParser.parseTimetableResult(html: html).records.map { $0.makeCourse() }
            progressReporter?(.begin(.savingTimetable))
            try persistTimetable(
                parsed,
                semesterID: semesterConfig.semesterID,
                modelContext: modelContext
            )
            successfulOperationCount += 1
            results.append(L10n.text("课表 %d 门", language: language, parsed.count))
            if await TimetableSharingService.shared.publishExistingSnapshotIfNeeded(
                courses: parsed.map(SharedTimetableCourse.init(course:))
            ) {
                results.append(L10n.text("共享课表已更新", language: language))
            }
        } catch {
            modelContext.rollback()
            if requiresReauthentication(error, userInitiated: userInitiated) {
                progressReporter?(.fail(.fetchingTimetable, error.localizedDescription))
                return .needsReauthentication(.schoolDataSync)
            }
            progressReporter?(.fail(.fetchingTimetable, error.localizedDescription))
            TimetableCacheMetadata.lastFailureMessage = error.localizedDescription
            failedOperationCount += 1
            results.append(L10n.text("课表失败：%@", language: language, error.localizedDescription))
        }

        if networkManager.currentPortal == .undergraduate {
            do {
                progressReporter?(.begin(.fetchingGrades))
                let html = try await networkManager.fetchGrades()
                progressReporter?(.begin(.processingGrades))
                let parsed = try HTMLParser.parseGrades(html: html)
                let rankings = (try? HTMLParser.parseGradeRankings(html: html)) ?? []
                let creditSummary = try? HTMLParser.parseGradeCreditSummary(html: html)
                if !rankings.isEmpty {
                    gradeRankingsToSave = rankings
                }
                if let creditSummary {
                    gradeCreditSummaryToSave = creditSummary
                }
                parsedGrades = parsed
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingGrades, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingGrades, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("成绩失败：%@", language: language, error.localizedDescription))
            }

            do {
                progressReporter?(.begin(.fetchingRankings))
                let html = try await networkManager.fetchGradeRankings()
                let parsed = try HTMLParser.parseGradeRankings(html: html)
                gradeRankingsToSave = parsed
                if let creditSummary = try? HTMLParser.parseGradeCreditSummary(html: html) {
                    gradeCreditSummaryToSave = creditSummary
                }
                successfulOperationCount += 1
                results.append(L10n.text("排名 %d 条", language: language, parsed.count))
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingRankings, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingRankings, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("排名失败：%@", language: language, error.localizedDescription))
            }

            do {
                progressReporter?(.begin(.fetchingExams))
                let html = try await networkManager.fetchExamSchedule()
                progressReporter?(.begin(.processingExams))
                let parsed = try HTMLParser.parseExams(html: html)
                examScheduleToSave = parsed
                successfulOperationCount += 1
                results.append(L10n.text("考试 %d 条", language: language, parsed.count))
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingExams, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingExams, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("考试失败：%@", language: language, error.localizedDescription))
            }

            do {
                progressReporter?(.begin(.fetchingTeachingPlan))
                let html = try await networkManager.fetchTeachingPlan()
                progressReporter?(.begin(.processingTeachingPlan))
                let parsed = try HTMLParser.parseTeachingPlan(html: html)
                teachingPlanToSave = parsed
                successfulOperationCount += 1
                results.append(L10n.text("教学计划 %d 学期", language: language, parsed.count))
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingTeachingPlan, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingTeachingPlan, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("教学计划失败：%@", language: language, error.localizedDescription))
            }

            do {
                progressReporter?(.begin(.fetchingTrainingProgram))
                let html = try await networkManager.fetchGraduationRequirements()
                progressReporter?(.begin(.processingTrainingProgram))
                let document = try HTMLParser.parseTrainingProgram(html: html)
                trainingProgramToSave = document
                successfulOperationCount += 1
                results.append(L10n.text("培养方案 %d 类", language: language, document.creditRequirements.count))
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingTrainingProgram, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingTrainingProgram, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("培养方案失败：%@", language: language, error.localizedDescription))
            }
        }

        progressReporter?(.begin(.savingResults))
        if let parsedGrades {
            do {
                try persistGrades(parsedGrades, modelContext: modelContext)
                SchoolDataCache.markGradeDetailsSynced()
                refreshedScopes.insert(.grades)
                successfulOperationCount += 1
                results.append(L10n.text("成绩 %d 条", language: language, parsedGrades.count))
            } catch {
                modelContext.rollback()
                progressReporter?(.fail(.savingResults, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("成绩保存失败：%@", language: language, error.localizedDescription))
            }
        }

        if let gradeRankingsToSave {
            SchoolDataCache.saveGradeRankings(gradeRankingsToSave, notifies: false)
            refreshedScopes.insert(.gradeSupplemental)
        }
        if let gradeCreditSummaryToSave {
            SchoolDataCache.saveGradeCreditSummary(gradeCreditSummaryToSave, notifies: false)
            refreshedScopes.insert(.gradeSupplemental)
        }
        if let examScheduleToSave {
            SchoolDataCache.saveRemoteExamSchedule(examScheduleToSave, notifies: false)
            refreshedScopes.insert(.exams)
        }
        if let teachingPlanToSave {
            SchoolDataCache.saveTeachingPlan(teachingPlanToSave, notifies: false)
            refreshedScopes.insert(.teachingPlan)
        }
        if let trainingProgramToSave {
            SchoolDataCache.saveTrainingProgram(trainingProgramToSave, notifies: false)
            refreshedScopes.insert(.trainingProgram)
        }

        if examScheduleToSave != nil {
            LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        }
        SchoolDataRefreshNotifier.post(refreshedScopes)

        let message = L10n.text(
            failedOperationCount == 0 ? "同步完成：%@。" : "同步结果：%@。",
            language: language,
            results.joined(separator: L10n.text("，", language: language))
        )
        if failedOperationCount == 0 {
            return .success(message)
        }
        if successfulOperationCount > 0 {
            return .partialSuccess(message)
        }
        return .failure(message)
    }

    private static func persistTimetable(
        _ courses: [Course],
        semesterID: String,
        modelContext: ModelContext
    ) throws {
        let configurations = SemesterConfig.timelineConfigurations
        let academicYearTimetable = AcademicYearTimetable(
            configurations: configurations,
            semanticEvents: configurations.flatMap(\.calendarEvents)
        )
        for course in fetch(Course.self, from: modelContext) where
            course.sourceSemesterID == semesterID
            || !academicYearTimetable.courseIntersectsTimeline(course) {
            modelContext.delete(course)
        }
        for course in courses {
            modelContext.insert(course)
        }
        try modelContext.save()

        let now = Date()
        TimetableCacheMetadata.lastSyncAt = now
        TimetableCacheMetadata.lastFailureMessage = nil
        TimetableCacheMetadata.lastSyncedSemesterID = semesterID
        AppStoreReviewCoordinator.recordSuccessfulSync(kind: .timetable, date: now)
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        SchoolDataRefreshNotifier.post(.timetable)
    }

    static func persistGrades(_ grades: [Grade], modelContext: ModelContext) throws {
        for grade in fetch(Grade.self, from: modelContext) {
            modelContext.delete(grade)
        }
        for grade in grades {
            modelContext.insert(grade)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func requiresReauthentication(
        _ error: Error,
        userInitiated: Bool
    ) -> Bool {
        userInitiated
            ? SchoolReauthentication.shouldPromptForUserInitiatedAccess(error)
            : SchoolReauthentication.requiresReauthentication(error)
    }

    private static func fetch<T: PersistentModel>(_ model: T.Type, from modelContext: ModelContext) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }
}
