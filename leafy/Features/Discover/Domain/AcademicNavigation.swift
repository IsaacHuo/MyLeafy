import Foundation

nonisolated enum AcademicPrimaryTab: String, CaseIterable, Identifiable, Equatable, Sendable {
    case cultivation = "学校教学"
    case classrooms = "自习安排"
    case learning = "学习空间"
    case sports = "体育相关"
    case career = "职业规划"
    case postgraduate = "考研信息"
    case medical = "医疗事项"
    case weekendTravel = "周末去哪"
    case ratings = "评价相关"

    var id: String { rawValue }

    func title(language: AppLanguagePreference) -> String {
        L10n.text(rawValue, language: language)
    }

    func compactTitle(language: AppLanguagePreference) -> String {
        let key: String
        switch self {
        case .cultivation: key = "campus.sidebar.academics"
        case .classrooms: key = "campus.sidebar.study"
        case .learning: key = "campus.sidebar.spaces"
        case .sports: key = "campus.sidebar.sports"
        case .career: key = "campus.sidebar.career"
        case .postgraduate: key = "campus.sidebar.grad-school"
        case .medical: key = "campus.sidebar.health"
        case .weekendTravel: key = "campus.sidebar.explore"
        case .ratings: key = "campus.sidebar.ratings"
        }
        return L10n.text(key, language: language)
    }

    var icon: String {
        switch self {
        case .cultivation: return "graduationcap.fill"
        case .classrooms: return "building.2.crop.circle"
        case .learning: return "folder.fill"
        case .sports: return "figure.run"
        case .career: return "briefcase.fill"
        case .postgraduate: return "books.vertical.fill"
        case .ratings: return "star.bubble.fill"
        case .medical: return "cross.case.fill"
        case .weekendTravel: return "map.fill"
        }
    }

    static func visibleCases(
        isCustomCampus: Bool,
        isCommunityEnabled: Bool,
        isMedicalEnabled: Bool = false,
        campusID: CampusID = .bjfu
    ) -> [AcademicPrimaryTab] {
        allCases.filter { tab in
            tab.isVisible(
                isCustomCampus: isCustomCampus,
                isCommunityEnabled: isCommunityEnabled,
                isMedicalEnabled: isMedicalEnabled,
                campusID: campusID
            )
        }
    }

    func isVisible(
        isCustomCampus: Bool,
        isCommunityEnabled: Bool,
        isMedicalEnabled: Bool = false,
        campusID: CampusID = .bjfu
    ) -> Bool {
        if isCustomCampus {
            switch self {
            case .cultivation, .learning, .sports, .career, .postgraduate:
                return true
            case .classrooms, .ratings, .medical, .weekendTravel:
                return false
            }
        }
        if self == .medical {
            return isMedicalEnabled
        }
        if self == .weekendTravel {
            return campusID == .bjfu
        }
        return isCommunityEnabled || self != .ratings
    }
}

nonisolated enum CampusAcademicVisibility {
    static func isRouteVisible(
        _ route: AcademicDetailRoute,
        isCustomCampus: Bool,
        isCommunityEnabled: Bool,
        isMedicalEnabled: Bool = false
    ) -> Bool {
        if !isCustomCampus {
            return route.tab.isVisible(
                isCustomCampus: isCustomCampus,
                isCommunityEnabled: isCommunityEnabled,
                isMedicalEnabled: isMedicalEnabled
            )
        }

        switch route {
        case .grades,
             .examSchedule,
             .honorRecords,
             .gradeAnalytics,
             .studyTimeRecords,
             .learningWorkspace,
             .sunshineRun,
             .fitnessTestRecords:
            return true
        case .comprehensiveQuality,
             .medicalPolicy,
             .medicalScenarioAssistant,
             .medicalLedger,
             .teachingPlan,
             .trainingProgram,
             .emptyClassroom,
             .classroomLookup,
             .campusHeatmap,
             .sportsVenues,
             .schoolCalendar:
            return false
        }
    }
}

nonisolated struct AcademicNavigationItem: Hashable, Sendable {
    let id = UUID()
    let route: AcademicDetailRoute
}

nonisolated enum ScheduleDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case memos
    case scheduleHub
    case customSchedules
    case dailyReview
    case tags
    case export
    case statistics
    case scheduleReports
    case trash
    case timetableProcessing

    var id: String { rawValue }
}

nonisolated enum AcademicRoute: Hashable, Sendable {
    case grades
    case emptyClassroom
}

nonisolated enum LearningWorkspaceInitialTab: String, Hashable, Sendable {
    case overview
    case materials
    case tasks
    case records
}

nonisolated enum AcademicDetailRoute: Hashable, Sendable {
    case grades
    case gradeAnalytics
    case examSchedule
    case honorRecords
    case comprehensiveQuality
    case teachingPlan
    case trainingProgram
    case emptyClassroom
    case classroomLookup(building: String, room: String)
    case campusHeatmap
    case studyTimeRecords
    case learningWorkspace(LearningWorkspaceDestination, initialTab: LearningWorkspaceInitialTab = .tasks)
    case sunshineRun
    case fitnessTestRecords
    case sportsVenues
    case schoolCalendar
    case medicalPolicy
    case medicalScenarioAssistant
    case medicalLedger

    var tab: AcademicPrimaryTab {
        switch self {
        case .grades,
             .gradeAnalytics,
             .examSchedule,
             .comprehensiveQuality,
             .teachingPlan,
             .trainingProgram,
             .schoolCalendar:
            return .cultivation
        case .emptyClassroom,
             .classroomLookup,
             .campusHeatmap:
            return .classrooms
        case .honorRecords,
             .studyTimeRecords,
             .learningWorkspace:
            return .learning
        case .sunshineRun,
             .fitnessTestRecords,
             .sportsVenues:
            return .sports
        case .medicalPolicy,
             .medicalScenarioAssistant,
             .medicalLedger:
            return .medical
        }
    }
}

nonisolated enum AcademicRouteResolver {
    static func target(for route: AcademicRoute) -> (tab: AcademicPrimaryTab, detailRoute: AcademicDetailRoute) {
        switch route {
        case .grades:
            return (.cultivation, .grades)
        case .emptyClassroom:
            return (.classrooms, .emptyClassroom)
        }
    }
}
