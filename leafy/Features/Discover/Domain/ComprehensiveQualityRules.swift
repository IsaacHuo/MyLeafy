import Foundation

nonisolated enum ComprehensiveQualityComponentKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case volunteerService
    case internationalInternship
    case researchAchievement
    case competitionAward

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volunteerService:
            return "志愿服务"
        case .internationalInternship:
            return "国际组织"
        case .researchAchievement:
            return "科研成果"
        case .competitionAward:
            return "竞赛获奖"
        }
    }

    var icon: String {
        switch self {
        case .volunteerService:
            return "hands.sparkles.fill"
        case .internationalInternship:
            return "globe.asia.australia.fill"
        case .researchAchievement:
            return "doc.text.magnifyingglass"
        case .competitionAward:
            return "trophy.fill"
        }
    }

    static func normalized(_ rawValue: String) -> ComprehensiveQualityComponentKind {
        ComprehensiveQualityComponentKind(rawValue: rawValue) ?? .volunteerService
    }
}

nonisolated enum ComprehensiveQualityRuleStatus: String, Codable, Sendable {
    case ready
    case manualOnly
    case needsRuleSource
    case notApplicable

    var title: String {
        switch self {
        case .ready:
            return "可开始估算"
        case .manualOnly:
            return "仅手动记录"
        case .needsRuleSource:
            return "待补齐细则"
        case .notApplicable:
            return "暂不适用"
        }
    }
}

nonisolated struct ComprehensiveQualityComponentRule: Identifiable, Hashable, Sendable {
    let kind: ComprehensiveQualityComponentKind
    let weightPercent: Double
    let detail: String

    var id: ComprehensiveQualityComponentKind { kind }
}

nonisolated struct ComprehensiveQualityCollegeRule: Identifiable, Hashable, Sendable {
    let collegeName: String
    let status: ComprehensiveQualityRuleStatus
    let sourceTitle: String
    let sourceURLString: String
    let attachmentURLString: String?
    let applicableText: String
    let calculationNote: String
    let components: [ComprehensiveQualityComponentRule]
    let updatedAtText: String

    var id: String { collegeName }

    var sourceURL: URL? {
        URL(string: sourceURLString)
    }

    var attachmentURL: URL? {
        attachmentURLString.flatMap(URL.init(string:))
    }

    var totalWeightPercent: Double {
        components.reduce(0) { $0 + $1.weightPercent }
    }

    func componentRule(for kind: ComprehensiveQualityComponentKind) -> ComprehensiveQualityComponentRule? {
        components.first { $0.kind == kind }
    }
}

nonisolated struct ComprehensiveQualityComponentInput: Hashable, Sendable {
    let kind: ComprehensiveQualityComponentKind
    let rawScore: Double?
    let peerMaxScore: Double?
    let officialStandardScore: Double?

    init(
        kind: ComprehensiveQualityComponentKind,
        rawScore: Double? = nil,
        peerMaxScore: Double? = nil,
        officialStandardScore: Double? = nil
    ) {
        self.kind = kind
        self.rawScore = rawScore
        self.peerMaxScore = peerMaxScore
        self.officialStandardScore = officialStandardScore
    }
}

nonisolated struct ComprehensiveQualityComponentResult: Hashable, Sendable {
    let kind: ComprehensiveQualityComponentKind
    let standardScore: Double?
    let contribution: Double?
    let isOfficialStandard: Bool

    var isComplete: Bool {
        standardScore != nil && contribution != nil
    }
}

nonisolated struct ComprehensiveQualityCalculationResult: Hashable, Sendable {
    let componentResults: [ComprehensiveQualityComponentResult]
    let qualityContribution: Double?
    let compositeScore: Double?
    let isComplete: Bool
}

nonisolated enum ComprehensiveQualityCalculator {
    static func calculate(
        rule: ComprehensiveQualityCollegeRule,
        academicStandardScore: Double?,
        inputs: [ComprehensiveQualityComponentInput]
    ) -> ComprehensiveQualityCalculationResult {
        guard rule.status == .ready else {
            return ComprehensiveQualityCalculationResult(
                componentResults: [],
                qualityContribution: nil,
                compositeScore: nil,
                isComplete: false
            )
        }

        let inputByKind = Dictionary(uniqueKeysWithValues: inputs.map { ($0.kind, $0) })
        let componentResults = rule.components.map { componentRule in
            result(for: componentRule, input: inputByKind[componentRule.kind])
        }

        guard componentResults.allSatisfy(\.isComplete) else {
            return ComprehensiveQualityCalculationResult(
                componentResults: componentResults,
                qualityContribution: nil,
                compositeScore: nil,
                isComplete: false
            )
        }

        let qualityContribution = componentResults.compactMap(\.contribution).reduce(0, +)
        let compositeScore = academicStandardScore.map { $0 * 0.95 + qualityContribution }
        return ComprehensiveQualityCalculationResult(
            componentResults: componentResults,
            qualityContribution: qualityContribution,
            compositeScore: compositeScore,
            isComplete: true
        )
    }

    static func result(
        for componentRule: ComprehensiveQualityComponentRule,
        input: ComprehensiveQualityComponentInput?
    ) -> ComprehensiveQualityComponentResult {
        guard let input else {
            return ComprehensiveQualityComponentResult(
                kind: componentRule.kind,
                standardScore: nil,
                contribution: nil,
                isOfficialStandard: false
            )
        }

        let standardScore: Double?
        let isOfficialStandard: Bool
        if let official = boundedScore(input.officialStandardScore) {
            standardScore = official
            isOfficialStandard = true
        } else if let rawScore = input.rawScore,
                  let peerMaxScore = input.peerMaxScore,
                  rawScore >= 0,
                  peerMaxScore > 0 {
            standardScore = boundedScore(rawScore / peerMaxScore * 100)
            isOfficialStandard = false
        } else {
            standardScore = nil
            isOfficialStandard = false
        }

        let contribution = standardScore.map { $0 * componentRule.weightPercent / 100 }
        return ComprehensiveQualityComponentResult(
            kind: componentRule.kind,
            standardScore: standardScore,
            contribution: contribution,
            isOfficialStandard: isOfficialStandard
        )
    }

    private static func boundedScore(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }
}

nonisolated enum ComprehensiveQualityRuleCatalog {
    static let excludedCollegeNames: Set<String> = [
        "继续教育学院",
        "国际学院"
    ]

    static let participatingCollegeNames: [String] = [
        "林学院",
        "水土保持学院",
        "生物科学与技术学院",
        "园林学院",
        "经济管理学院",
        "工学院",
        "材料科学与技术学院",
        "人文社会科学学院",
        "外语学院",
        "信息学院",
        "理学院",
        "生态与自然保护学院",
        "环境科学与工程学院",
        "艺术设计学院",
        "草业与草原学院",
        "马克思主义学院"
    ]

    static let allRules: [ComprehensiveQualityCollegeRule] = {
        let rules = [
            forestryRule,
            soilWaterRule,
            biologyRule,
            landscapeRule,
            economicsRule,
            engineeringRule,
            materialRule,
            humanitiesRule,
            foreignLanguagesRule,
            informationRule,
            scienceRule,
            ecologyRule,
            environmentRule,
            artRule,
            grasslandRule,
            marxismRule
        ]
        return rules.sorted { lhs, rhs in
            guard let lhsIndex = participatingCollegeNames.firstIndex(of: lhs.collegeName),
                  let rhsIndex = participatingCollegeNames.firstIndex(of: rhs.collegeName)
            else {
                return lhs.collegeName < rhs.collegeName
            }
            return lhsIndex < rhsIndex
        }
    }()

    static func rule(for collegeName: String) -> ComprehensiveQualityCollegeRule {
        allRules.first { $0.collegeName == collegeName } ?? pendingRule(collegeName: collegeName)
    }

    static func isSelectableCollege(_ collegeName: String) -> Bool {
        participatingCollegeNames.contains(collegeName) && !excludedCollegeNames.contains(collegeName)
    }

    private static let commonComponentTemplate: [ComprehensiveQualityComponentRule] = [
        ComprehensiveQualityComponentRule(
            kind: .volunteerService,
            weightPercent: 2,
            detail: "通常对应志愿服务、社会活动、荣誉和文体活动等条目，具体口径以学院当年细则为准。"
        ),
        ComprehensiveQualityComponentRule(
            kind: .internationalInternship,
            weightPercent: 0.5,
            detail: "通常对应国际组织实习或任职经历，证明材料和时长档位以学院当年细则为准。"
        ),
        ComprehensiveQualityComponentRule(
            kind: .researchAchievement,
            weightPercent: 1,
            detail: "通常对应论文著作、科研项目、专利和软著等成果，认定范围以学院当年细则为准。"
        ),
        ComprehensiveQualityComponentRule(
            kind: .competitionAward,
            weightPercent: 1.5,
            detail: "通常对应竞赛获奖、等级考试、文体竞赛等项目，认定目录以学院当年细则为准。"
        )
    ]

    private static let readyCalculationNote = "综合成绩 = 全学程学分积标准分 * 95% + 四项综素标准分按 2%、0.5%、1%、1.5%折算；未填满四项时不出最终综合成绩。"

    private static func readyRule(
        collegeName: String,
        sourceTitle: String,
        sourceURLString: String,
        attachmentURLString: String? = nil,
        applicableText: String,
        updatedAtText: String
    ) -> ComprehensiveQualityCollegeRule {
        ComprehensiveQualityCollegeRule(
            collegeName: collegeName,
            status: .ready,
            sourceTitle: sourceTitle,
            sourceURLString: sourceURLString,
            attachmentURLString: attachmentURLString,
            applicableText: applicableText,
            calculationNote: readyCalculationNote,
            components: commonComponentTemplate,
            updatedAtText: updatedAtText
        )
    }

    private static func catalogRule(
        collegeName: String,
        sourceTitle: String,
        sourceURLString: String,
        attachmentURLString: String? = nil,
        applicableText: String,
        calculationNote: String = readyCalculationNote,
        updatedAtText: String
    ) -> ComprehensiveQualityCollegeRule {
        ComprehensiveQualityCollegeRule(
            collegeName: collegeName,
            status: .ready,
            sourceTitle: sourceTitle,
            sourceURLString: sourceURLString,
            attachmentURLString: attachmentURLString,
            applicableText: applicableText,
            calculationNote: calculationNote,
            components: commonComponentTemplate,
            updatedAtText: updatedAtText
        )
    }

    private static let forestryRule = readyRule(
        collegeName: "林学院",
        sourceTitle: "北京林业大学林学院推荐2026届优秀应届本科毕业生免试攻读研究生工作方案",
        sourceURLString: "https://lxy.bjfu.edu.cn/rcpy/bkspy/aeb8e3cab7c44a54b9417959459644e2.htm",
        applicableText: "适用于林学院 2026 届普通推免生测算。",
        updatedAtText: "2025-09-09"
    )

    private static let soilWaterRule = catalogRule(
        collegeName: "水土保持学院",
        sourceTitle: "水土保持学院推荐2023届优秀应届本科毕业生免试攻读研究生工作方案",
        sourceURLString: "https://shuibao.bjfu.edu.cn/rcpy/bkspy/927aa29ed57b42c9ad655845cb2089ba.htm",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        updatedAtText: "2022-09-13"
    )

    private static let biologyRule = catalogRule(
        collegeName: "生物科学与技术学院",
        sourceTitle: "生物科学与技术学院本科学生综合素质评价暂行条例",
        sourceURLString: "https://biology.bjfu.edu.cn/xzzq/xsgl/1bef8b0d813a4454856f64d086324341.htm",
        attachmentURLString: "https://biology.bjfu.edu.cn/docs/2023-10/c2bf47491afb4102843461e3510a9695.rtf",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        updatedAtText: "2012-06-13"
    )

    private static let engineeringRule = ComprehensiveQualityCollegeRule(
        collegeName: "工学院",
        status: .ready,
        sourceTitle: "工学院推荐2026届优秀应届本科毕业生免试攻读研究生工作方案",
        sourceURLString: "https://gxy.bjfu.edu.cn/benkejiaoxue/jiaowutongzhi/05f759cb01134f239656ca4707bd68d5.html",
        attachmentURLString: "https://gxy.bjfu.edu.cn/docs//2025-09/930421c05b0c41e592f4488b3aba6ca7.pdf",
        applicableText: "适用于工学院 2026 届普通推免生测算。",
        calculationNote: "综合成绩 = 全学程学分积标准分 * 95% + 综素贡献分。综素贡献由四项标准分按 2%、0.5%、1%、1.5%折算，满分 5 分。",
        components: [
            ComprehensiveQualityComponentRule(
                kind: .volunteerService,
                weightPercent: 2,
                detail: "参照三年综素测评中德育、文体美等相关条目，单项加分和备注以当年细则为准。"
            ),
            ComprehensiveQualityComponentRule(
                kind: .internationalInternship,
                weightPercent: 0.5,
                detail: "满 3 个月及以上按 100 原始分；满 2 个月不满 3 个月按 70；满 1 个月不满 2 个月按 40；不足 1 个月按 10。"
            ),
            ComprehensiveQualityComponentRule(
                kind: .researchAchievement,
                weightPercent: 1,
                detail: "参照三年综素测评智育部分的论文著作、科研项目、专利、软著四个方面。"
            ),
            ComprehensiveQualityComponentRule(
                kind: .competitionAward,
                weightPercent: 1.5,
                detail: "参照三年综素测评智育和文体美部分的竞赛、考试、认证和晋级等条目。"
            )
        ],
        updatedAtText: "2025-09-08"
    )

    private static let economicsRule = readyRule(
        collegeName: "经济管理学院",
        sourceTitle: "经济管理学院关于推荐2026届优秀应届本科毕业生免试攻读硕士研究生工作方案",
        sourceURLString: "https://em.bjfu.edu.cn/rcpy/bkjy/tzggb/8cb82dcb541a4b6cb36e85d45e68f7c4.htm",
        applicableText: "适用于经济管理学院 2026 届普通推免生测算。",
        updatedAtText: "2025-09-09"
    )

    private static let materialRule = readyRule(
        collegeName: "材料科学与技术学院",
        sourceTitle: "材料学院推荐2026届优秀应届本科毕业生免试攻读硕士研究生工作方案",
        sourceURLString: "https://clxy.bjfu.edu.cn/rcpy/508eb922b0f0415ca7d99594252f44e7.html",
        applicableText: "适用于材料科学与技术学院 2026 届普通推免生测算。",
        updatedAtText: "2025-09-09"
    )

    private static let landscapeRule = ComprehensiveQualityCollegeRule(
        collegeName: "园林学院",
        status: .ready,
        sourceTitle: "园林学院本科生综合素质评价实施方案（适用于2023级及以后入学本科生）（2025年修订）",
        sourceURLString: "https://sola.bjfu.edu.cn/cn/information/notice/5f3e40e65ed4472dba18c97a6209a7cd.html",
        attachmentURLString: "https://sola.bjfu.edu.cn/docs//2025-05/5219e07da4694530b1332edb354de5d7.pdf",
        applicableText: "适用于园林学院 2023 级及以后入学本科生综合素质评价。",
        calculationNote: readyCalculationNote,
        components: commonComponentTemplate,
        updatedAtText: "2025-05-14"
    )

    private static let humanitiesRule = catalogRule(
        collegeName: "人文社会科学学院",
        sourceTitle: "人文社会科学学院推荐2025届优秀应届本科毕业生免试攻读研究生工作实施方案",
        sourceURLString: "https://renwen.bjfu.edu.cn/tzgg/eac9d3c2135248a98a310c1715663fda.html",
        attachmentURLString: "https://renwen.bjfu.edu.cn/docs//2024-09/50cc57147a114c3193733046885815d6.docx",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        updatedAtText: "2024-09-09"
    )

    private static let foreignLanguagesRule = catalogRule(
        collegeName: "外语学院",
        sourceTitle: "外语学院推荐2025届优秀应届本科毕业生免试攻读研究生工作方案",
        sourceURLString: "https://waiyu.bjfu.edu.cn/xygg/276c866295d046d692570d4f0319165b.html",
        attachmentURLString: "https://waiyu.bjfu.edu.cn/docs//2024-09/9be33cab4c664d96b7705a48a5d5ca65.pdf",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        updatedAtText: "2024-09-09"
    )

    private static let informationRule = ComprehensiveQualityCollegeRule(
        collegeName: "信息学院",
        status: .ready,
        sourceTitle: "信息学院推荐2026届优秀应届本科毕业生免试攻读研究生工作方案",
        sourceURLString: "https://it.bjfu.edu.cn/bkspy/pydt/c1dcd33379924cf08487b3562cb1d5f9.html",
        attachmentURLString: "https://it.bjfu.edu.cn/docs//2025-09/92e0ffe446f24c1aa5a9b9530f767aab.pdf",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        calculationNote: readyCalculationNote,
        components: commonComponentTemplate,
        updatedAtText: "2025-09-09"
    )

    private static let scienceRule = catalogRule(
        collegeName: "理学院",
        sourceTitle: "北京林业大学理学院综合素质分评分细则（2013年9月启用版）",
        sourceURLString: "https://cos.bjfu.edu.cn/bkjx/gzzd/307906.html",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        updatedAtText: "2013-11-06"
    )

    private static let ecologyRule = readyRule(
        collegeName: "生态与自然保护学院",
        sourceTitle: "生态与自然保护学院推荐2026届优秀应届本科毕业生免试攻读硕士研究生工作方案",
        sourceURLString: "https://styzrbh.bjfu.edu.cn/rcpy/bks/c72057dd74b64230928802bc6765788f.htm",
        attachmentURLString: "https://styzrbh.bjfu.edu.cn/docs//2025-09/b7730800c66b444e9ea8f6b43037296f.docx",
        applicableText: "适用于生态与自然保护学院 2026 届普通推免生测算。",
        updatedAtText: "2025-09-09"
    )

    private static let environmentRule = catalogRule(
        collegeName: "环境科学与工程学院",
        sourceTitle: "环境学院本科生综合素质评价实施办法（试行）（适用于2023级及之后）",
        sourceURLString: "https://hjxy.bjfu.edu.cn/xsgz/zczd/index.htm",
        attachmentURLString: "https://hjxy.bjfu.edu.cn/docs/2025-08/3a9cdf71347940098e67300eb373e4ab.pdf",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        updatedAtText: "2025-08-25"
    )

    private static let artRule = catalogRule(
        collegeName: "艺术设计学院",
        sourceTitle: "关于印发《艺术设计学院本科生综合素质评价实施细则（试行）》的通知",
        sourceURLString: "https://ad.bjfu.edu.cn/tzgg/c3d51cd3e66d4064bbd4d41f8f84fa05.htm",
        attachmentURLString: "https://ad.bjfu.edu.cn/docs//2026-06/00efc954468f41d49c250efc732b66bc.pdf",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        updatedAtText: "2026-06-08"
    )

    private static let grasslandRule = catalogRule(
        collegeName: "草业与草原学院",
        sourceTitle: "草业与草原学院本科生综合素质评价实施方案（2024）",
        sourceURLString: "https://cxy.bjfu.edu.cn/jyjx/bksjy/index.html",
        attachmentURLString: "https://cxy.bjfu.edu.cn/docs/2024-12/e0ed48902be942f2a5821ec3c12ebd83.pdf",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        updatedAtText: "2024-12-24"
    )

    private static let marxismRule = catalogRule(
        collegeName: "马克思主义学院",
        sourceTitle: "北京林业大学马克思主义学院2026年接收优秀应届本科毕业生推荐免试攻读研究生工作方案",
        sourceURLString: "https://marxism.bjfu.edu.cn/tzgg/bac42edc813f4a74a12b48b2f1ac093a.html",
        applicableText: "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        updatedAtText: "2025-09-09"
    )

    private static func pendingRule(collegeName: String) -> ComprehensiveQualityCollegeRule {
        ComprehensiveQualityCollegeRule(
            collegeName: collegeName,
            status: .needsRuleSource,
            sourceTitle: "待补齐该学院官方综素/推免细则",
            sourceURLString: "",
            attachmentURLString: nil,
            applicableText: "该学院可先整理材料并录入公示结果，自动估算需补齐官方细则后启用。",
            calculationNote: "不同学院的综素条目和证明口径可能不同；未核验前不自动计算，避免误导。",
            components: commonComponentTemplate,
            updatedAtText: "待补齐"
        )
    }
}
