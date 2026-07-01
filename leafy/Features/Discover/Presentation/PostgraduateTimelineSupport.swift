import Foundation

enum PostgraduateTimelineStatus: Equatable {
    case completed
    case current
    case upcoming
}

enum PostgraduateTimelinePhase: String, CaseIterable, Identifiable {
    case explore
    case catalog
    case registration
    case confirmation
    case initialExam
    case scoreLine
    case retest
    case admission

    var id: String { rawValue }
}

struct PostgraduateTimelineNode: Identifiable, Equatable {
    let phase: PostgraduateTimelinePhase
    let examYear: Int
    let title: String
    let periodText: String
    let detail: String
    let nextStep: String
    let actionTitle: String
    let actionURLString: String
    let icon: String
    let status: PostgraduateTimelineStatus

    var id: String { "\(examYear)-\(phase.rawValue)" }

    var actionURL: URL? {
        URL(string: actionURLString)
    }
}

enum PostgraduateTimelineBuilder {
    static func nodes(
        forExamYear examYear: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PostgraduateTimelineNode] {
        PostgraduateTimelinePhase.allCases.map { phase in
            let window = phase.window(forExamYear: examYear)
            return PostgraduateTimelineNode(
                phase: phase,
                examYear: examYear,
                title: phase.title,
                periodText: periodText(for: window),
                detail: phase.detail,
                nextStep: phase.nextStep,
                actionTitle: phase.actionTitle,
                actionURLString: phase.actionURLString,
                icon: phase.icon,
                status: status(for: window, now: now, calendar: calendar)
            )
        }
    }

    private static func status(
        for window: PostgraduateTimelineWindow,
        now: Date,
        calendar: Calendar
    ) -> PostgraduateTimelineStatus {
        guard
            let startDate = date(year: window.startYear, month: window.startMonth, calendar: calendar),
            let endDate = date(year: window.endYear, month: window.endMonth + 1, calendar: calendar)
        else {
            return .upcoming
        }

        if now < startDate {
            return .upcoming
        }
        if now >= endDate {
            return .completed
        }
        return .current
    }

    private static func date(year: Int, month: Int, calendar: Calendar) -> Date? {
        let normalizedYear = year + (month - 1) / 12
        let normalizedMonth = ((month - 1) % 12) + 1
        return calendar.date(from: DateComponents(year: normalizedYear, month: normalizedMonth, day: 1))
    }

    private static func periodText(for window: PostgraduateTimelineWindow) -> String {
        if window.startYear == window.endYear {
            if window.startMonth == window.endMonth {
                return "\(window.startYear)年\(window.startMonth)月"
            }
            return "\(window.startYear)年\(window.startMonth)-\(window.endMonth)月"
        }
        return "\(window.startYear)年\(window.startMonth)月-\(window.endYear)年\(window.endMonth)月"
    }
}

enum PostgraduateTargetSelector {
    static func primaryTarget(
        from targets: [PostgraduateTarget],
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) -> PostgraduateTarget? {
        sortedActiveTargets(from: targets, currentYear: currentYear).first
    }

    static func sortedActiveTargets(
        from targets: [PostgraduateTarget],
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) -> [PostgraduateTarget] {
        targets
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let lhsRank = stateRank(lhs.state)
                let rhsRank = stateRank(rhs.state)
                if lhsRank != rhsRank { return lhsRank < rhsRank }

                let lhsDistance = yearDistance(lhs.examYear, currentYear: currentYear)
                let rhsDistance = yearDistance(rhs.examYear, currentYear: currentYear)
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }

                return lhs.updatedAt > rhs.updatedAt
            }
    }

    static func sortedArchivedTargets(from targets: [PostgraduateTarget]) -> [PostgraduateTarget] {
        targets
            .filter(\.isArchived)
            .sorted {
                if $0.examYear != $1.examYear { return $0.examYear > $1.examYear }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private static func stateRank(_ state: PostgraduateTargetState) -> Int {
        switch state {
        case .focused:
            return 0
        case .active:
            return 1
        case .archived:
            return 2
        }
    }

    private static func yearDistance(_ examYear: Int, currentYear: Int) -> Int {
        if examYear >= currentYear {
            return examYear - currentYear
        }
        return 1_000 + currentYear - examYear
    }
}

enum PostgraduateSourcePresentation {
    static func sortedSources(
        for target: PostgraduateTarget?,
        from sources: [PostgraduateSource]
    ) -> [PostgraduateSource] {
        guard let target else {
            return sources.sorted { $0.sortDate > $1.sortDate }
        }

        return PostgraduateSourceMatcher.sortedSources(
            for: target,
            from: sources,
            includingGeneral: true
        )
    }
}

private struct PostgraduateTimelineWindow {
    let startYear: Int
    let startMonth: Int
    let endYear: Int
    let endMonth: Int
}

private extension PostgraduateTimelinePhase {
    func window(forExamYear examYear: Int) -> PostgraduateTimelineWindow {
        switch self {
        case .explore:
            return PostgraduateTimelineWindow(startYear: examYear - 1, startMonth: 3, endYear: examYear - 1, endMonth: 6)
        case .catalog:
            return PostgraduateTimelineWindow(startYear: examYear - 1, startMonth: 7, endYear: examYear - 1, endMonth: 9)
        case .registration:
            return PostgraduateTimelineWindow(startYear: examYear - 1, startMonth: 10, endYear: examYear - 1, endMonth: 10)
        case .confirmation:
            return PostgraduateTimelineWindow(startYear: examYear - 1, startMonth: 11, endYear: examYear - 1, endMonth: 11)
        case .initialExam:
            return PostgraduateTimelineWindow(startYear: examYear - 1, startMonth: 12, endYear: examYear - 1, endMonth: 12)
        case .scoreLine:
            return PostgraduateTimelineWindow(startYear: examYear, startMonth: 2, endYear: examYear, endMonth: 3)
        case .retest:
            return PostgraduateTimelineWindow(startYear: examYear, startMonth: 3, endYear: examYear, endMonth: 4)
        case .admission:
            return PostgraduateTimelineWindow(startYear: examYear, startMonth: 4, endYear: examYear, endMonth: 6)
        }
    }

    var title: String {
        switch self {
        case .explore:
            return "信息收集"
        case .catalog:
            return "招生目录"
        case .registration:
            return "网上报名"
        case .confirmation:
            return "网上确认"
        case .initialExam:
            return "初试准备"
        case .scoreLine:
            return "成绩与分数线"
        case .retest:
            return "复试与调剂"
        case .admission:
            return "拟录取与归档"
        }
    }

    var detail: String {
        switch self {
        case .explore:
            return "明确目标学校、院系、专业方向和考试科目，先把官方入口与备选目标收拢起来。"
        case .catalog:
            return "等待招生简章和专业目录集中更新，重点核对招生计划、考试科目、学习方式和备注限制。"
        case .registration:
            return "报名期开启后完成网报信息填写，检查报考点、考试方式和学历学籍校验状态。"
        case .confirmation:
            return "按报考点要求完成网上确认，留意材料上传、审核结果和补充提交窗口。"
        case .initialExam:
            return "围绕准考证、考场、考试用品和最后一轮复盘做收口，避免临考前再找流程入口。"
        case .scoreLine:
            return "关注初试成绩、国家线和目标学校复试线，整理可进入复试或调剂的判断依据。"
        case .retest:
            return "跟进复试通知、调剂系统、材料提交和面试安排，优先查看学校研究生院原文。"
        case .admission:
            return "关注拟录取、调档、政审和后续通知，把重要来源和个人经验沉淀到本地备注。"
        }
    }

    var nextStep: String {
        switch self {
        case .explore:
            return "下一步：先查专业目录，建立目标清单。"
        case .catalog:
            return "下一步：逐项核对招生简章和考试科目。"
        case .registration:
            return "下一步：进入统考网报并保存报名信息。"
        case .confirmation:
            return "下一步：按报考点通知完成确认材料。"
        case .initialExam:
            return "下一步：回到研招网核对考试相关公告。"
        case .scoreLine:
            return "下一步：查看成绩、复试线和学校通知。"
        case .retest:
            return "下一步：查看调剂入口和学校复试公告。"
        case .admission:
            return "下一步：归档来源和个人备注。"
        }
    }

    var actionTitle: String {
        switch self {
        case .explore, .initialExam, .scoreLine, .admission:
            return "打开研招网"
        case .catalog:
            return "查专业目录"
        case .registration, .confirmation:
            return "进入网报"
        case .retest:
            return "看调剂入口"
        }
    }

    var actionURLString: String {
        switch self {
        case .explore, .initialExam, .scoreLine, .admission:
            return "https://yz.chsi.com.cn/"
        case .catalog:
            return "https://yz.chsi.com.cn/zsml/"
        case .registration, .confirmation:
            return "https://yz.chsi.com.cn/wap/yzwb/"
        case .retest:
            return "https://yz.chsi.com.cn/yztj/"
        }
    }

    var icon: String {
        switch self {
        case .explore:
            return "scope"
        case .catalog:
            return "doc.text.magnifyingglass"
        case .registration:
            return "square.and.pencil"
        case .confirmation:
            return "checkmark.seal"
        case .initialExam:
            return "pencil.and.list.clipboard"
        case .scoreLine:
            return "chart.line.uptrend.xyaxis"
        case .retest:
            return "person.2.wave.2"
        case .admission:
            return "archivebox"
        }
    }
}
