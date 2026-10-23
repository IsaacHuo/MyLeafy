import Foundation
import SwiftData

enum ReviewDemoMode {
    static let storageKey = "reviewDemoMode"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: storageKey)
    }
}

enum ReviewDemoDataSeeder {
    private static let seededKey = "reviewDemoMode.seeded"
    private static let installationIDKey = "reviewDemoMode.installationID"
    private static let courseBackupKey = "reviewDemoMode.backup.courses"
    private static let gradeBackupKey = "reviewDemoMode.backup.grades"
    private static let defaultsBackupKey = "reviewDemoMode.backup.defaults"

    static var demoEduID: String {
        demoEduID(userDefaults: .standard)
    }

    static let campusID = CampusID.bjfu.rawValue

    static var displayName: String {
        "\(AppBrand.displayName) 审核演示"
    }

    @MainActor
    static func enter(using modelContext: ModelContext) throws {
        ReviewDemoMode.isEnabled = true
        ActiveCampusContext.networkManager.persistDemoIdentity(eduID: demoEduID, displayName: displayName)
        do {
            // The login context predates identity activation and may be an in-memory store.
            let context = AppRuntimeEnvironment.isRunningUnitTests ? modelContext : try AppModelContainerFactory.make()
                .container.mainContext
            try seedIfNeeded(using: context)
        } catch {
            ReviewDemoMode.disable()
            ActiveCampusContext.networkManager.clearSession()
            throw error
        }
    }

    @MainActor
    static func seedIfNeeded(using modelContext: ModelContext) throws {
        guard ReviewDemoMode.isEnabled else { return }
        if !UserDefaults.standard.bool(forKey: seededKey) {
            try seed(using: modelContext)
            UserDefaults.standard.set(true, forKey: seededKey)
        } else {
            ActiveCampusContext.networkManager.persistDemoIdentity(eduID: demoEduID, displayName: displayName)
        }
    }

    @MainActor
    static func seed(
        using modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let oldCourses = try modelContext.fetch(FetchDescriptor<Course>())
        let oldGrades = try modelContext.fetch(FetchDescriptor<Grade>())
        let favorites = try modelContext.fetch(FetchDescriptor<FavoriteClassroom>())
        try preserveCurrentSchoolDataIfNeeded(courses: oldCourses, grades: oldGrades, defaults: defaults)
        var added: [any PersistentModel] = sampleCourses + sampleGrades
        if !favorites.contains(where: { $0.building == "二教" && $0.room == "205" }) {
            added.append(FavoriteClassroom(building: "二教", room: "205"))
        }
        let removed: [any PersistentModel] = oldCourses + oldGrades
        removed.forEach { modelContext.delete($0) }
        added.forEach { modelContext.insert($0) }
        try LocalModelSave.save(modelContext, undo: {
            added.forEach { modelContext.delete($0) }
            removed.forEach { modelContext.insert($0) }
        }, using: save)
        try seedSchoolCaches()
    }

    /// Refreshing the timetable must not reseed grades, exams, or other school caches.
    @MainActor
    static func refreshTimetable(using modelContext: ModelContext) throws -> TimetablePersistResult {
        let records = sampleCourses.map {
            ParsedCourseRecord(
                courseName: $0.courseName, teacher: $0.teacher, classInfo: $0.classInfo,
                room: $0.room, location: $0.location, dayOfWeek: $0.dayOfWeek,
                weeks: $0.weeks, duration: $0.duration
            )
        }
        return try TimetableRefreshUseCase().persist(
            records: records,
            existingCourses: modelContext.fetch(FetchDescriptor<Course>()),
            modelContext: modelContext
        )
    }

    @MainActor
    static func exit(
        using modelContext: ModelContext? = nil,
        defaults: UserDefaults = .standard,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        if let modelContext { try restorePreservedSchoolData(using: modelContext, defaults: defaults, save: save) }
        ReviewDemoMode.isEnabled = false
        UserDefaults.standard.removeObject(forKey: seededKey)
    }

    static func refreshSchoolCaches() throws {
        try seedSchoolCaches()
    }

    static func demoEduID(userDefaults: UserDefaults) -> String {
        if let stored = userDefaults.string(forKey: installationIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           UUID(uuidString: stored) != nil {
            return "review-demo-\(stored.lowercased())"
        }

        let installationID = UUID().uuidString
        userDefaults.set(installationID, forKey: installationIDKey)
        return "review-demo-\(installationID.lowercased())"
    }

    nonisolated static func isDemoEduID(_ eduID: String?) -> Bool {
        let normalized = eduID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalized == "review-demo" || normalized.hasPrefix("review-demo-")
    }

    nonisolated static func isLegacySharedDemoEduID(_ eduID: String?) -> Bool {
        eduID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "review-demo"
    }

    nonisolated static func isInstallationScopedDemoEduID(_ eduID: String?) -> Bool {
        let normalized = eduID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let prefix = "review-demo-"
        guard normalized.hasPrefix(prefix) else { return false }
        return UUID(uuidString: String(normalized.dropFirst(prefix.count))) != nil
    }

    static func emptyClassrooms(for date: Date, start: Int, end: Int) -> [EmptyClassroom] {
        let rooms = [
            EmptyClassroom(building: "二教", room: "205"),
            EmptyClassroom(building: "二教", room: "306"),
            EmptyClassroom(building: "主楼", room: "112"),
            EmptyClassroom(building: "学研中心", room: "B203"),
            EmptyClassroom(building: "图书馆", room: "研讨间 3")
        ]
        SchoolDataCache.saveEmptyClassrooms(rooms, date: date, start: start, end: end)
        return rooms
    }

    static func classroomUsage(for date: Date, building: String, room: String) -> [ClassroomUsageSlot] {
        let usage = (1 ... 12).map { period in
            ClassroomUsageSlot(period: period, status: ![3, 4, 9].contains(period) ? .available : .occupied)
        }
        SchoolDataCache.saveClassroomUsage(usage, date: date, building: building, room: room)
        return usage
    }

    static func teacherSummaries(search: String = "") -> [TeacherRatingSummary] {
        let now = ISO8601DateFormatter().string(from: Date())
        let teacherProfiles = [
            TeacherProfile(
                id: 1,
                name: "林青",
                unit: "信息学院",
                ratingAverage: 4.8,
                ratingCount: 26,
                rating1Count: 0,
                rating2Count: 1,
                rating3Count: 2,
                rating4Count: 5,
                rating5Count: 18,
                createdAt: now,
                updatedAt: now
            ),
            TeacherProfile(
                id: 2,
                name: "周木",
                unit: "理学院",
                ratingAverage: 4.5,
                ratingCount: 19,
                rating1Count: 0,
                rating2Count: 1,
                rating3Count: 3,
                rating4Count: 6,
                rating5Count: 9,
                createdAt: now,
                updatedAt: now
            ),
            TeacherProfile(
                id: 3,
                name: "叶岚",
                unit: "经济管理学院",
                ratingAverage: 4.2,
                ratingCount: 11,
                rating1Count: 1,
                rating2Count: 0,
                rating3Count: 2,
                rating4Count: 4,
                rating5Count: 4,
                createdAt: now,
                updatedAt: now
            )
        ]
        let normalizedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return teacherProfiles
            .filter { teacher in
                normalizedSearch.isEmpty
                    || teacher.name.localizedCaseInsensitiveContains(normalizedSearch)
                    || teacher.unit.localizedCaseInsensitiveContains(normalizedSearch)
            }
            .map { teacher in
                TeacherRatingSummary(
                    teacher: teacher,
                    myRating: TeacherRating(
                        teacherID: teacher.id,
                        userID: demoCommunityUserID,
                        stars: 5,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }
    }

    static func updatedTeacherSummary(teacherID: Int64, stars: Int) -> TeacherRatingSummary {
        let now = ISO8601DateFormatter().string(from: Date())
        let fallback = teacherSummaries().first(where: { $0.teacher.id == teacherID })?.teacher
            ?? TeacherProfile(
                id: teacherID,
                name: "演示教师",
                unit: "信息学院",
                ratingAverage: Double(stars),
                ratingCount: 1,
                rating1Count: 0,
                rating2Count: 0,
                rating3Count: 0,
                rating4Count: 0,
                rating5Count: 1,
                createdAt: now,
                updatedAt: now
            )

        return TeacherRatingSummary(
            teacher: TeacherProfile(
                id: fallback.id,
                name: fallback.name,
                unit: fallback.unit,
                ratingAverage: Double(stars),
                ratingCount: max(fallback.ratingCount, 1),
                rating1Count: stars == 1 ? max(fallback.rating1Count, 1) : fallback.rating1Count,
                rating2Count: stars == 2 ? max(fallback.rating2Count, 1) : fallback.rating2Count,
                rating3Count: stars == 3 ? max(fallback.rating3Count, 1) : fallback.rating3Count,
                rating4Count: stars == 4 ? max(fallback.rating4Count, 1) : fallback.rating4Count,
                rating5Count: stars == 5 ? max(fallback.rating5Count, 1) : fallback.rating5Count,
                createdAt: fallback.createdAt,
                updatedAt: now
            ),
            myRating: TeacherRating(
                teacherID: teacherID,
                userID: demoCommunityUserID,
                stars: stars,
                createdAt: now,
                updatedAt: now
            )
        )
    }

    static func courseRatingSummaries(
        search: String = "",
        category: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) -> [CourseRatingSummary] {
        let now = ISO8601DateFormatter().string(from: Date())
        let courseProfiles = [
            CourseProfile(
                id: 1,
                name: "森林生态学导论",
                unit: "林学院",
                category: "公选课",
                credit: 2,
                ratingAverage: 4.7,
                ratingCount: 31,
                rating1Count: 0,
                rating2Count: 1,
                rating3Count: 2,
                rating4Count: 6,
                rating5Count: 22,
                createdAt: now,
                updatedAt: now
            ),
            CourseProfile(
                id: 2,
                name: "审美艺术导论",
                unit: "艺术设计学院",
                category: "公选课",
                credit: 2,
                ratingAverage: 4.4,
                ratingCount: 18,
                rating1Count: 0,
                rating2Count: 1,
                rating3Count: 3,
                rating4Count: 5,
                rating5Count: 9,
                createdAt: now,
                updatedAt: now
            ),
            CourseProfile(
                id: 3,
                name: "写作与沟通",
                unit: "人文社会科学学院",
                category: "公选课",
                credit: 1.5,
                ratingAverage: 4.1,
                ratingCount: 12,
                rating1Count: 1,
                rating2Count: 0,
                rating3Count: 2,
                rating4Count: 5,
                rating5Count: 4,
                createdAt: now,
                updatedAt: now
            )
        ]
        let normalizedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = courseProfiles
            .filter { course in
                normalizedSearch.isEmpty
                    || course.name.localizedCaseInsensitiveContains(normalizedSearch)
                    || course.unit.localizedCaseInsensitiveContains(normalizedSearch)
                    || course.category.localizedCaseInsensitiveContains(normalizedSearch)
            }
            .filter { course in
                guard let normalizedCategory, !normalizedCategory.isEmpty else { return true }
                return course.category == normalizedCategory
            }

        return Array(filtered.dropFirst(max(offset, 0)).prefix(max(limit, 1))).map { course in
            CourseRatingSummary(
                course: course,
                myRating: CourseRating(
                    courseID: course.id,
                    userID: demoCommunityUserID,
                    stars: 5,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
    }

    static func updatedCourseSummary(courseID: Int64, stars: Int) -> CourseRatingSummary {
        let now = ISO8601DateFormatter().string(from: Date())
        let fallback = courseRatingSummaries().first(where: { $0.course.id == courseID })?.course
            ?? CourseProfile(
                id: courseID,
                name: "演示课程",
                unit: "开课单位",
                category: "公选课",
                credit: 2,
                ratingAverage: Double(stars),
                ratingCount: 1,
                rating1Count: 0,
                rating2Count: 0,
                rating3Count: 0,
                rating4Count: 0,
                rating5Count: 1,
                createdAt: now,
                updatedAt: now
            )

        return CourseRatingSummary(
            course: CourseProfile(
                id: fallback.id,
                name: fallback.name,
                unit: fallback.unit,
                category: fallback.category,
                credit: fallback.credit,
                ratingAverage: Double(stars),
                ratingCount: max(fallback.ratingCount, 1),
                rating1Count: stars == 1 ? max(fallback.rating1Count, 1) : fallback.rating1Count,
                rating2Count: stars == 2 ? max(fallback.rating2Count, 1) : fallback.rating2Count,
                rating3Count: stars == 3 ? max(fallback.rating3Count, 1) : fallback.rating3Count,
                rating4Count: stars == 4 ? max(fallback.rating4Count, 1) : fallback.rating4Count,
                rating5Count: stars == 5 ? max(fallback.rating5Count, 1) : fallback.rating5Count,
                createdAt: fallback.createdAt,
                updatedAt: now
            ),
            myRating: CourseRating(
                courseID: courseID,
                userID: demoCommunityUserID,
                stars: stars,
                createdAt: now,
                updatedAt: now
            )
        )
    }

    static func dishRatingSummaries(
        search: String = "",
        canteen: String? = nil,
        location: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) -> [DishRatingSummary] {
        let now = ISO8601DateFormatter().string(from: Date())
        let dishProfiles = [
            DishProfile(
                id: 1,
                name: "番茄牛腩饭",
                location: "东区食堂 · 一层 · 学一食堂",
                ratingAverage: 4.6,
                ratingCount: 24,
                rating1Count: 0,
                rating2Count: 1,
                rating3Count: 2,
                rating4Count: 5,
                rating5Count: 16,
                createdAt: now,
                updatedAt: now
            ),
            DishProfile(
                id: 2,
                name: "鸡腿盖饭",
                location: "东区食堂 · 二层 · 学四食堂",
                ratingAverage: 4.3,
                ratingCount: 18,
                rating1Count: 1,
                rating2Count: 1,
                rating3Count: 2,
                rating4Count: 6,
                rating5Count: 8,
                createdAt: now,
                updatedAt: now
            ),
            DishProfile(
                id: 3,
                name: "麻辣香锅",
                location: "西区食堂 · 二层 · 齐芳阁餐厅",
                ratingAverage: 4.8,
                ratingCount: 36,
                rating1Count: 0,
                rating2Count: 0,
                rating3Count: 2,
                rating4Count: 4,
                rating5Count: 30,
                createdAt: now,
                updatedAt: now
            ),
            DishProfile(
                id: 4,
                name: "热干面",
                location: "西区食堂 · B1层 · 小食光餐厅",
                ratingAverage: 4.2,
                ratingCount: 13,
                rating1Count: 1,
                rating2Count: 0,
                rating3Count: 2,
                rating4Count: 4,
                rating5Count: 6,
                createdAt: now,
                updatedAt: now
            )
        ]
        let normalizedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCanteen = canteen?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = dishProfiles
            .filter { dish in
                normalizedSearch.isEmpty
                    || dish.name.localizedCaseInsensitiveContains(normalizedSearch)
                    || dish.location.localizedCaseInsensitiveContains(normalizedSearch)
            }
            .filter { dish in
                guard let normalizedCanteen, !normalizedCanteen.isEmpty else { return true }
                return dish.location.hasPrefix(normalizedCanteen)
            }
            .filter { dish in
                guard let normalizedLocation, !normalizedLocation.isEmpty else { return true }
                return dish.location == normalizedLocation
            }

        return Array(filtered.dropFirst(max(offset, 0)).prefix(max(limit, 1))).map { dish in
            DishRatingSummary(
                dish: dish,
                myRating: DishRating(
                    dishID: dish.id,
                    userID: demoCommunityUserID,
                    stars: 5,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
    }

    static func updatedDishSummary(dishID: Int64, stars: Int) -> DishRatingSummary {
        let now = ISO8601DateFormatter().string(from: Date())
        let fallback = dishRatingSummaries().first(where: { $0.dish.id == dishID })?.dish
            ?? DishProfile(
                id: dishID,
                name: "演示菜品",
                location: "东区食堂 · 一层 · 学一食堂",
                ratingAverage: Double(stars),
                ratingCount: 1,
                rating1Count: 0,
                rating2Count: 0,
                rating3Count: 0,
                rating4Count: 0,
                rating5Count: 1,
                createdAt: now,
                updatedAt: now
            )

        return DishRatingSummary(
            dish: DishProfile(
                id: fallback.id,
                name: fallback.name,
                location: fallback.location,
                ratingAverage: Double(stars),
                ratingCount: max(fallback.ratingCount, 1),
                rating1Count: stars == 1 ? max(fallback.rating1Count, 1) : fallback.rating1Count,
                rating2Count: stars == 2 ? max(fallback.rating2Count, 1) : fallback.rating2Count,
                rating3Count: stars == 3 ? max(fallback.rating3Count, 1) : fallback.rating3Count,
                rating4Count: stars == 4 ? max(fallback.rating4Count, 1) : fallback.rating4Count,
                rating5Count: stars == 5 ? max(fallback.rating5Count, 1) : fallback.rating5Count,
                createdAt: fallback.createdAt,
                updatedAt: now
            ),
            myRating: DishRating(
                dishID: dishID,
                userID: demoCommunityUserID,
                stars: stars,
                createdAt: now,
                updatedAt: now
            )
        )
    }

    private static let demoCommunityUserID = UUID(uuidString: "DEDEDEDE-DEDE-4DED-9DED-DEDEDEDEDEDE") ?? UUID()

    private static var sampleCourses: [Course] {
        [
            Course(
                courseName: "数据结构",
                teacher: "林青",
                classInfo: "演示班",
                room: "二教 205",
                location: "二教 205",
                dayOfWeek: 1,
                weeks: Array(1 ... 16),
                duration: [1, 2]
            ),
            Course(
                courseName: "高等数学 A",
                teacher: "周木",
                classInfo: "演示班",
                room: "主楼 112",
                location: "主楼 112",
                dayOfWeek: 2,
                weeks: Array(1 ... 18),
                duration: [3, 4]
            ),
            Course(
                courseName: "大学英语",
                teacher: "叶岚",
                classInfo: "演示班",
                room: "学研中心 B203",
                location: "学研中心 B203",
                dayOfWeek: 3,
                weeks: Array(1 ... 16),
                duration: [5, 6]
            ),
            Course(
                courseName: "森林生态学导论",
                teacher: "陈森",
                classInfo: "演示班",
                room: "二教 306",
                location: "二教 306",
                dayOfWeek: 4,
                weeks: Array(3 ... 14),
                duration: [7, 8]
            ),
            Course(
                courseName: "体育",
                teacher: "王青",
                classInfo: "演示班",
                room: "操场",
                location: "操场",
                dayOfWeek: 5,
                weeks: Array(1 ... 16),
                duration: [3, 4]
            )
        ]
    }

    private static var sampleGrades: [Grade] {
        [
            Grade(term: "2025-2026-2", courseName: "数据结构", credit: "3.0", score: "92", type: "必修"),
            Grade(term: "2025-2026-2", courseName: "大学英语", credit: "2.0", score: "88", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "高等数学 A", credit: "5.0", score: "90", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "森林生态学导论", credit: "2.0", score: "优秀", type: "公选")
        ]
    }

    private static func seedSchoolCaches() throws {
        let today = Date()
        try SchoolDataCache.saveExamSchedule([
            ExamArrangement(
                id: 1,
                courseID: "DS-001",
                name: "数据结构",
                date: futureDateString(days: 9),
                start: "09:00",
                end: "11:00",
                location: "二教 205"
            ),
            ExamArrangement(
                id: 2,
                courseID: "MATH-001",
                name: "高等数学 A",
                date: futureDateString(days: 16),
                start: "14:00",
                end: "16:00",
                location: "主楼 112"
            )
        ])
        SchoolDataCache.saveTeachingPlan([
            TeachingPlanSection(term: "2025-2026-1", courses: [
                TeachingPlanCourse(
                    id: 1,
                    period: "2025-2026-1",
                    name: "高等数学 A",
                    unit: "理学院",
                    credit: 5,
                    duration: "80",
                    type: "必修",
                    exam: "考试"
                ),
                TeachingPlanCourse(
                    id: 2,
                    period: "2025-2026-1",
                    name: "程序设计基础",
                    unit: "信息学院",
                    credit: 3,
                    duration: "48",
                    type: "必修",
                    exam: "考试"
                )
            ]),
            TeachingPlanSection(term: "2025-2026-2", courses: [
                TeachingPlanCourse(
                    id: 3,
                    period: "2025-2026-2",
                    name: "数据结构",
                    unit: "信息学院",
                    credit: 3,
                    duration: "48",
                    type: "必修",
                    exam: "考试"
                ),
                TeachingPlanCourse(
                    id: 4,
                    period: "2025-2026-2",
                    name: "森林生态学导论",
                    unit: "林学院",
                    credit: 2,
                    duration: "32",
                    type: "公选",
                    exam: "考查"
                )
            ])
        ])
        SchoolDataCache.saveGradeRankings([
            GradeRankingRecord(
                term: "全部学期",
                rankingRange: "专业",
                rank: 12,
                totalCount: 186,
                percentile: 0.064,
                metricText: "综合排名",
                rawFields: ["范围": "全部学期"]
            ),
            GradeRankingRecord(
                term: "2025-2026-1",
                rankingRange: "专业",
                rank: 15,
                totalCount: 186,
                percentile: 0.081,
                metricText: "学期排名",
                rawFields: [:]
            )
        ])
        SchoolDataCache.saveGradeCreditSummary(
            GradeCreditSummary(
                totalCredits: 12,
                requiredCredits: 170,
                professionalElectiveCredits: 0,
                professionalMajorElectiveCredits: 0,
                professionalCrossMajorElectiveCredits: 0,
                publicElectiveCredits: 2,
                officialGPA: 3.86,
                officialWeightedAverage: 91.08,
                officialCreditPoint: 44.6,
                publicElectiveBuckets: [
                    GradeCreditBucket(name: "自然科学", credits: 2),
                    GradeCreditBucket(name: "人文社科", credits: 0)
                ],
                rawFields: [:]
            )
        )
        SchoolDataCache.saveTrainingProgram(
            TrainingProgramDocument(
                title: "计算机科学与技术专业培养方案（演示）",
                sections: [
                    TrainingProgramSection(id: "goal", title: "培养目标", body: "培养具备计算思维、工程实践和校园信息化服务能力的复合型人才。"),
                    TrainingProgramSection(id: "courses", title: "课程体系", body: "课程包含数学基础、程序设计、数据结构、数据库、软件工程和实践训练。")
                ],
                creditRequirements: [
                    GraduationCreditRequirement(
                        id: "total",
                        category: "总学分",
                        courseName: "毕业要求",
                        requiredCredits: 170,
                        plannedCredits: 170,
                        isAggregate: true
                    ),
                    GraduationCreditRequirement(
                        id: "public",
                        category: "公共选修",
                        courseName: "通识课程",
                        requiredCredits: 8,
                        plannedCredits: 8,
                        isAggregate: true
                    ),
                    GraduationCreditRequirement(
                        id: "major",
                        category: "专业选修",
                        courseName: "专业方向课程",
                        requiredCredits: 24,
                        plannedCredits: 24,
                        isAggregate: true
                    )
                ]
            )
        )
        _ = emptyClassrooms(for: today, start: 1, end: 2)
        _ = classroomUsage(for: today, building: "二教", room: "205")
        TimetableCacheMetadata.lastSyncAt = Date()
        TimetableCacheMetadata.lastFailureMessage = nil
    }

    @MainActor
    private static func preserveCurrentSchoolDataIfNeeded(
        courses: [Course],
        grades: [Grade],
        defaults: UserDefaults
    ) throws {
        let keys = [courseBackupKey, gradeBackupKey, defaultsBackupKey]
        if keys.contains(where: { defaults.object(forKey: $0) != nil }) {
            _ = try preservedValues(defaults: defaults)
            return
        }
        let courseData = try JSONEncoder().encode(courses.map(CourseBackup.init))
        let gradeData = try JSONEncoder().encode(grades.map(GradeBackup.init))
        let prefixes = [
            "schoolCache.",
            "timetable.",
            CampusScopedDefaults.key("schoolCache."),
            CampusScopedDefaults.key("timetable.")
        ]
        let snapshot = defaults.dictionaryRepresentation().filter { key, _ in prefixes.contains(where: key.hasPrefix) }
        defaults.set(courseData, forKey: courseBackupKey)
        defaults.set(gradeData, forKey: gradeBackupKey)
        defaults.set(snapshot, forKey: defaultsBackupKey)
    }

    private static func preservedValues(defaults: UserDefaults) throws
        -> ([CourseBackup], [GradeBackup], [String: Any]) {
        guard let courseData = defaults.data(forKey: courseBackupKey),
              let gradeData = defaults.data(forKey: gradeBackupKey),
              let snapshot = defaults.dictionary(forKey: defaultsBackupKey)
        else { throw CocoaError(.fileReadCorruptFile) }
        let courses = try JSONDecoder().decode([CourseBackup].self, from: courseData)
        let grades = try JSONDecoder().decode([GradeBackup].self, from: gradeData)
        guard courses.allSatisfy({ $0.id != nil && $0.sourceSemesterID != nil }),
              grades.allSatisfy({ $0.id != nil }) else {
            throw ReviewDemoBackupError()
        }
        return (courses, grades, snapshot)
    }

    @MainActor
    private static func restorePreservedSchoolData(
        using modelContext: ModelContext, defaults: UserDefaults,
        save: (ModelContext) throws -> Void
    ) throws {
        let keys = [courseBackupKey, gradeBackupKey, defaultsBackupKey]
        guard keys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        let (courses, grades, snapshot) = try preservedValues(defaults: defaults)
        let removed: [any PersistentModel] = try modelContext.fetch(FetchDescriptor<Course>()) + modelContext
            .fetch(FetchDescriptor<Grade>())
        let restored: [any PersistentModel] = try courses.map { try $0.makeCourse() } + grades
            .map { try $0.makeGrade() }
        removed.forEach { modelContext.delete($0) }
        restored.forEach { modelContext.insert($0) }
        try LocalModelSave.save(modelContext, undo: {
            restored.forEach { modelContext.delete($0) }
            removed.forEach { modelContext.insert($0) }
        }, using: save)
        SchoolDataCache.clearDiscoverCaches()
        TimetableCacheMetadata.clear()
        for (key, value) in snapshot { defaults.set(value, forKey: key) }
        for key in keys { defaults.removeObject(forKey: key) }
    }

    private static func futureDateString(days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return DateFormatters.queryDate.string(from: date)
    }

    private struct CourseBackup: Codable {
        let id: UUID?
        let sourceSemesterID: String?
        let courseName: String
        let teacher: String
        let classInfo: String
        let room: String
        let location: String
        let dayOfWeek: Int
        let weeks: [Int]
        let duration: [Int]

        init(_ course: Course) {
            id = course.id
            sourceSemesterID = course.sourceSemesterID
            courseName = course.courseName
            teacher = course.teacher
            classInfo = course.classInfo
            room = course.room
            location = course.location
            dayOfWeek = course.dayOfWeek
            weeks = course.weeks
            duration = course.duration
        }

        func makeCourse() throws -> Course {
            guard let id, let sourceSemesterID else { throw CocoaError(.fileReadCorruptFile) }
            return Course(
                id: id,
                courseName: courseName,
                teacher: teacher,
                classInfo: classInfo,
                room: room,
                location: location,
                dayOfWeek: dayOfWeek,
                weeks: weeks,
                duration: duration,
                sourceSemesterID: sourceSemesterID
            )
        }
    }

    private struct GradeBackup: Codable {
        let id: UUID?
        let updatedAt: Date?
        let term: String
        let courseName: String
        let credit: String
        let score: String
        let type: String
        let courseCode: String?
        let courseAttribute: String?
        let courseCategory: String?
        let examNature: String?

        init(_ grade: Grade) {
            id = grade.id
            updatedAt = grade.updatedAt
            term = grade.term
            courseName = grade.courseName
            credit = grade.credit
            score = grade.score
            type = grade.type
            courseCode = grade.courseCode
            courseAttribute = grade.courseAttribute
            courseCategory = grade.courseCategory
            examNature = grade.examNature
        }

        func makeGrade() throws -> Grade {
            guard let id else { throw CocoaError(.fileReadCorruptFile) }
            let model = Grade(
                id: id,
                term: term,
                courseName: courseName,
                credit: credit,
                score: score,
                type: type,
                courseCode: courseCode,
                courseAttribute: courseAttribute,
                courseCategory: courseCategory,
                examNature: examNature
            )
            model.updatedAt = updatedAt
            return model
        }
    }
}

private struct ReviewDemoBackupError: LocalizedError {
    var errorDescription: String? { L10n.text("演示备份缺少原始记录标识或学期，已保留备份和当前数据，尚未恢复。") }
}
