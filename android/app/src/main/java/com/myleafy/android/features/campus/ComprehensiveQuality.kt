package com.myleafy.android.features.campus

/**
 * 综素测算的本地规则与计算（对应 iOS `ComprehensiveQualityRules`）。
 *
 * 纯本地计算，不依赖登录与网络；公式与权重来自学院公开来源的本地整理，
 * 最终结果以学院官方公示为准。
 */
enum class ComprehensiveQualityComponentKind(val title: String) {
    VOLUNTEER_SERVICE("志愿服务"),
    INTERNATIONAL_INTERNSHIP("国际组织"),
    RESEARCH_ACHIEVEMENT("科研成果"),
    COMPETITION_AWARD("竞赛获奖"),
}

enum class ComprehensiveQualityRuleStatus(val title: String) {
    READY("可开始估算"),
    MANUAL_ONLY("仅手动记录"),
    NEEDS_RULE_SOURCE("待补齐细则"),
    NOT_APPLICABLE("暂不适用"),
}

data class ComprehensiveQualityComponentRule(
    val kind: ComprehensiveQualityComponentKind,
    val weightPercent: Double,
    val detail: String,
)

data class ComprehensiveQualityCollegeRule(
    val collegeName: String,
    val status: ComprehensiveQualityRuleStatus,
    val sourceTitle: String,
    val sourceUrl: String,
    val attachmentUrl: String?,
    val applicableText: String,
    val calculationNote: String,
    val components: List<ComprehensiveQualityComponentRule>,
    val updatedAtText: String,
) {
    val totalWeightPercent: Double get() = components.sumOf { it.weightPercent }

    fun componentRule(kind: ComprehensiveQualityComponentKind): ComprehensiveQualityComponentRule? =
        components.firstOrNull { it.kind == kind }
}

data class ComprehensiveQualityComponentInput(
    val kind: ComprehensiveQualityComponentKind,
    val rawScore: Double? = null,
    val peerMaxScore: Double? = null,
    val officialStandardScore: Double? = null,
)

data class ComprehensiveQualityComponentResult(
    val kind: ComprehensiveQualityComponentKind,
    val standardScore: Double?,
    val contribution: Double?,
    val isOfficialStandard: Boolean,
) {
    val isComplete: Boolean get() = standardScore != null && contribution != null
}

data class ComprehensiveQualityCalculationResult(
    val componentResults: List<ComprehensiveQualityComponentResult>,
    val qualityContribution: Double?,
    val compositeScore: Double?,
    val isComplete: Boolean,
)

object ComprehensiveQualityCalculator {

    fun calculate(
        rule: ComprehensiveQualityCollegeRule,
        academicStandardScore: Double?,
        inputs: List<ComprehensiveQualityComponentInput>,
    ): ComprehensiveQualityCalculationResult {
        if (rule.status != ComprehensiveQualityRuleStatus.READY) {
            return ComprehensiveQualityCalculationResult(emptyList(), null, null, false)
        }
        val inputByKind = inputs.associateBy { it.kind }
        val componentResults = rule.components.map { result(it, inputByKind[it.kind]) }
        if (componentResults.any { !it.isComplete }) {
            return ComprehensiveQualityCalculationResult(componentResults, null, null, false)
        }
        val qualityContribution = componentResults.mapNotNull { it.contribution }.sum()
        val compositeScore = academicStandardScore?.let { it * 0.95 + qualityContribution }
        return ComprehensiveQualityCalculationResult(
            componentResults = componentResults,
            qualityContribution = qualityContribution,
            compositeScore = compositeScore,
            isComplete = true,
        )
    }

    fun result(
        componentRule: ComprehensiveQualityComponentRule,
        input: ComprehensiveQualityComponentInput?,
    ): ComprehensiveQualityComponentResult {
        if (input == null) {
            return ComprehensiveQualityComponentResult(componentRule.kind, null, null, false)
        }
        val standardScore: Double?
        val isOfficialStandard: Boolean
        val official = boundedScore(input.officialStandardScore)
        if (official != null) {
            standardScore = official
            isOfficialStandard = true
        } else if (input.rawScore != null && input.peerMaxScore != null &&
            input.rawScore >= 0 && input.peerMaxScore > 0
        ) {
            standardScore = boundedScore(input.rawScore / input.peerMaxScore * 100)
            isOfficialStandard = false
        } else {
            standardScore = null
            isOfficialStandard = false
        }
        val contribution = standardScore?.let { it * componentRule.weightPercent / 100 }
        return ComprehensiveQualityComponentResult(
            kind = componentRule.kind,
            standardScore = standardScore,
            contribution = contribution,
            isOfficialStandard = isOfficialStandard,
        )
    }

    private fun boundedScore(value: Double?): Double? {
        if (value == null || !value.isFinite()) return null
        return minOf(maxOf(value, 0.0), 100.0)
    }
}

object ComprehensiveQualityRuleCatalog {

    val participatingCollegeNames: List<String> = listOf(
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
        "马克思主义学院",
    )

    val allRules: List<ComprehensiveQualityCollegeRule> =
        listOf(
            readyRule("林学院", "北京林业大学林学院推荐2026届优秀应届本科毕业生免试攻读研究生工作方案", "https://lxy.bjfu.edu.cn/rcpy/bkspy/aeb8e3cab7c44a54b9417959459644e2.htm", "适用于林学院 2026 届普通推免生测算。", "2025-09-09"),
            catalogRule("水土保持学院", "水土保持学院推荐2023届优秀应届本科毕业生免试攻读研究生工作方案", "https://shuibao.bjfu.edu.cn/rcpy/bkspy/927aa29ed57b42c9ad655845cb2089ba.htm", null, "2022-09-13"),
            catalogRule("生物科学与技术学院", "生物科学与技术学院本科学生综合素质评价暂行条例", "https://biology.bjfu.edu.cn/xzzq/xsgl/1bef8b0d813a4454856f64d086324341.htm", "https://biology.bjfu.edu.cn/docs/2023-10/c2bf47491afb4102843461e3510a9695.rtf", "2012-06-13"),
            readyRule("园林学院", "园林学院本科生综合素质评价实施方案（适用于2023级及以后入学本科生）（2025年修订）", "https://sola.bjfu.edu.cn/cn/information/notice/5f3e40e65ed4472dba18c97a6209a7cd.html", "适用于园林学院 2023 级及以后入学本科生综合素质评价。", "2025-05-14", attachmentUrl = "https://sola.bjfu.edu.cn/docs//2025-05/5219e07da4694530b1332edb354de5d7.pdf"),
            readyRule("经济管理学院", "经济管理学院关于推荐2026届优秀应届本科毕业生免试攻读硕士研究生工作方案", "https://em.bjfu.edu.cn/rcpy/bkjy/tzggb/8cb82dcb541a4b6cb36e85d45e68f7c4.htm", "适用于经济管理学院 2026 届普通推免生测算。", "2025-09-09"),
            engineeringRule(),
            readyRule("材料科学与技术学院", "材料学院推荐2026届优秀应届本科毕业生免试攻读硕士研究生工作方案", "https://clxy.bjfu.edu.cn/rcpy/508eb922b0f0415ca7d99594252f44e7.html", "适用于材料科学与技术学院 2026 届普通推免生测算。", "2025-09-09"),
            catalogRule("人文社会科学学院", "人文社会科学学院推荐2025届优秀应届本科毕业生免试攻读研究生工作实施方案", "https://renwen.bjfu.edu.cn/tzgg/eac9d3c2135248a98a310c1715663fda.html", "https://renwen.bjfu.edu.cn/docs//2024-09/50cc57147a114c3193733046885815d6.docx", "2024-09-09"),
            catalogRule("外语学院", "外语学院推荐2025届优秀应届本科毕业生免试攻读研究生工作方案", "https://waiyu.bjfu.edu.cn/xygg/276c866295d046d692570d4f0319165b.html", "https://waiyu.bjfu.edu.cn/docs//2024-09/9be33cab4c664d96b7705a48a5d5ca65.pdf", "2024-09-09"),
            catalogRule("信息学院", "信息学院推荐2026届优秀应届本科毕业生免试攻读研究生工作方案", "https://it.bjfu.edu.cn/bkspy/pydt/c1dcd33379924cf08487b3562cb1d5f9.html", "https://it.bjfu.edu.cn/docs//2025-09/92e0ffe446f24c1aa5a9b9530f767aab.pdf", "2025-09-09"),
            catalogRule("理学院", "北京林业大学理学院综合素质分评分细则（2013年9月启用版）", "https://cos.bjfu.edu.cn/bkjx/gzzd/307906.html", null, "2013-11-06"),
            readyRule("生态与自然保护学院", "生态与自然保护学院推荐2026届优秀应届本科毕业生免试攻读硕士研究生工作方案", "https://styzrbh.bjfu.edu.cn/rcpy/bks/c72057dd74b64230928802bc6765788f.htm", "适用于生态与自然保护学院 2026 届普通推免生测算。", "2025-09-09", attachmentUrl = "https://styzrbh.bjfu.edu.cn/docs//2025-09/b7730800c66b444e9ea8f6b43037296f.docx"),
            catalogRule("环境科学与工程学院", "环境学院本科生综合素质评价实施办法（试行）（适用于2023级及之后）", "https://hjxy.bjfu.edu.cn/xsgz/zczd/index.htm", "https://hjxy.bjfu.edu.cn/docs/2025-08/3a9cdf71347940098e67300eb373e4ab.pdf", "2025-08-25"),
            catalogRule("艺术设计学院", "关于印发《艺术设计学院本科生综合素质评价实施细则（试行）》的通知", "https://ad.bjfu.edu.cn/tzgg/c3d51cd3e66d4064bbd4d41f8f84fa05.htm", "https://ad.bjfu.edu.cn/docs//2026-06/00efc954468f41d49c250efc732b66bc.pdf", "2026-06-08"),
            catalogRule("草业与草原学院", "草业与草原学院本科生综合素质评价实施方案（2024）", "https://cxy.bjfu.edu.cn/jyjx/bksjy/index.html", "https://cxy.bjfu.edu.cn/docs/2024-12/e0ed48902be942f2a5821ec3c12ebd83.pdf", "2024-12-24"),
            catalogRule("马克思主义学院", "北京林业大学马克思主义学院2026年接收优秀应届本科毕业生推荐免试攻读研究生工作方案", "https://marxism.bjfu.edu.cn/tzgg/bac42edc813f4a74a12b48b2f1ac093a.html", null, "2025-09-09"),
        ).sortedBy { rule ->
            participatingCollegeNames.indexOf(rule.collegeName).let { if (it < 0) Int.MAX_VALUE else it }
        }

    fun ruleFor(collegeName: String): ComprehensiveQualityCollegeRule =
        allRules.firstOrNull { it.collegeName == collegeName } ?: pendingRule(collegeName)

    fun isSelectableCollege(collegeName: String): Boolean = collegeName in participatingCollegeNames

    private const val readyCalculationNote =
        "综合成绩 = 全学程学分积标准分 * 95% + 四项综素标准分按 2%、0.5%、1%、1.5%折算；未填满四项时不出最终综合成绩。"

    private val commonComponentTemplate = listOf(
        ComprehensiveQualityComponentRule(ComprehensiveQualityComponentKind.VOLUNTEER_SERVICE, 2.0, "通常对应志愿服务、社会活动、荣誉和文体活动等条目，具体口径以学院当年细则为准。"),
        ComprehensiveQualityComponentRule(ComprehensiveQualityComponentKind.INTERNATIONAL_INTERNSHIP, 0.5, "通常对应国际组织实习或任职经历，证明材料和时长档位以学院当年细则为准。"),
        ComprehensiveQualityComponentRule(ComprehensiveQualityComponentKind.RESEARCH_ACHIEVEMENT, 1.0, "通常对应论文著作、科研项目、专利和软著等成果，认定范围以学院当年细则为准。"),
        ComprehensiveQualityComponentRule(ComprehensiveQualityComponentKind.COMPETITION_AWARD, 1.5, "通常对应竞赛获奖、等级考试、文体竞赛等项目，认定目录以学院当年细则为准。"),
    )

    private fun readyRule(
        collegeName: String,
        sourceTitle: String,
        sourceUrl: String,
        applicableText: String,
        updatedAtText: String,
        attachmentUrl: String? = null,
    ) = ComprehensiveQualityCollegeRule(
        collegeName = collegeName,
        status = ComprehensiveQualityRuleStatus.READY,
        sourceTitle = sourceTitle,
        sourceUrl = sourceUrl,
        attachmentUrl = attachmentUrl,
        applicableText = applicableText,
        calculationNote = readyCalculationNote,
        components = commonComponentTemplate,
        updatedAtText = updatedAtText,
    )

    private fun catalogRule(
        collegeName: String,
        sourceTitle: String,
        sourceUrl: String,
        attachmentUrl: String?,
        updatedAtText: String,
    ) = ComprehensiveQualityCollegeRule(
        collegeName = collegeName,
        status = ComprehensiveQualityRuleStatus.READY,
        sourceTitle = sourceTitle,
        sourceUrl = sourceUrl,
        attachmentUrl = attachmentUrl,
        applicableText = "参考学院已公开来源，页面按统一四项权重提供本地估算；最终以学院官方公示为准。",
        calculationNote = readyCalculationNote,
        components = commonComponentTemplate,
        updatedAtText = updatedAtText,
    )

    private fun engineeringRule() = ComprehensiveQualityCollegeRule(
        collegeName = "工学院",
        status = ComprehensiveQualityRuleStatus.READY,
        sourceTitle = "工学院推荐2026届优秀应届本科毕业生免试攻读研究生工作方案",
        sourceUrl = "https://gxy.bjfu.edu.cn/benkejiaoxue/jiaowutongzhi/05f759cb01134f239656ca4707bd68d5.html",
        attachmentUrl = "https://gxy.bjfu.edu.cn/docs//2025-09/930421c05b0c41e592f4488b3aba6ca7.pdf",
        applicableText = "适用于工学院 2026 届普通推免生测算。",
        calculationNote = "综合成绩 = 全学程学分积标准分 * 95% + 综素贡献分。综素贡献由四项标准分按 2%、0.5%、1%、1.5%折算，满分 5 分。",
        components = listOf(
            ComprehensiveQualityComponentRule(ComprehensiveQualityComponentKind.VOLUNTEER_SERVICE, 2.0, "参照三年综素测评中德育、文体美等相关条目，单项加分和备注以当年细则为准。"),
            ComprehensiveQualityComponentRule(ComprehensiveQualityComponentKind.INTERNATIONAL_INTERNSHIP, 0.5, "满 3 个月及以上按 100 原始分；满 2 个月不满 3 个月按 70；满 1 个月不满 2 个月按 40；不足 1 个月按 10。"),
            ComprehensiveQualityComponentRule(ComprehensiveQualityComponentKind.RESEARCH_ACHIEVEMENT, 1.0, "参照三年综素测评智育部分的论文著作、科研项目、专利、软著四个方面。"),
            ComprehensiveQualityComponentRule(ComprehensiveQualityComponentKind.COMPETITION_AWARD, 1.5, "参照三年综素测评智育和文体美部分的竞赛、考试、认证和晋级等条目。"),
        ),
        updatedAtText = "2025-09-08",
    )

    private fun pendingRule(collegeName: String) = ComprehensiveQualityCollegeRule(
        collegeName = collegeName,
        status = ComprehensiveQualityRuleStatus.NEEDS_RULE_SOURCE,
        sourceTitle = "待补齐该学院官方综素/推免细则",
        sourceUrl = "",
        attachmentUrl = null,
        applicableText = "该学院可先整理材料并录入公示结果，自动估算需补齐官方细则后启用。",
        calculationNote = "不同学院的综素条目和证明口径可能不同；未核验前不自动计算，避免误导。",
        components = commonComponentTemplate,
        updatedAtText = "待补齐",
    )
}
