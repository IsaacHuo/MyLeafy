package com.myleafy.android.features.campus

import com.myleafy.android.parsers.JsoupHtmlParser
import org.junit.Assert.*
import org.junit.Test

class CampusReliabilityTest {
    @Test fun allCollegeRulesInitializeBeforeFirstScreenOpen() {
        assertEquals(16, ComprehensiveQualityRuleCatalog.allRules.size)
        ComprehensiveQualityRuleCatalog.participatingCollegeNames.forEach { name ->
            val rule = ComprehensiveQualityRuleCatalog.ruleFor(name)
            assertEquals(name, rule.collegeName)
            if (rule.status == ComprehensiveQualityRuleStatus.READY) assertTrue(rule.components.isNotEmpty())
        }
        assertEquals(ComprehensiveQualityRuleStatus.NEEDS_RULE_SOURCE, ComprehensiveQualityRuleCatalog.ruleFor("未收录学院").status)
    }

    @Test fun graduationRequirementsDoNotReadCourseCodesOrHoursAsCredits() {
        val result = JsoupHtmlParser().parseTrainingProgram("""
            <p>电气工程及其自动化专业本科培养方案</p><p>一、培养目标</p><p>培养目标正文</p>
            <table><tr><th>类别</th><th>课程编号</th><th>课程名称</th><th>学分</th></tr>
            <tr><td>专业核心课</td><td>22008160</td><td>电气测量</td><td>3</td></tr></table>
            <table><tr><th>类别</th><th>学时</th><th>学分要求</th></tr>
            <tr><td>毕业生应取得总学分</td><td>2800</td><td>167</td></tr>
            <tr><td>专业核心课</td><td>500</td><td>25</td></tr>
            <tr><td rowspan="2">通识必修课</td><td>360</td><td>43</td></tr>
            <tr><td>说明</td><td>43</td></tr></table>
        """.trimIndent())
        assertEquals(listOf(167.0, 25.0, 43.0), result.creditRequirements.map { it.credits })
        assertTrue(result.tables.isNotEmpty())
        assertEquals(listOf("通识必修课", "说明", "43"), result.tables.last().rows.last())
    }

    @Test fun unlabelledNumbersAreNotInventedRequirements() {
        val result = JsoupHtmlParser().parseTrainingProgram("""
            <p>测试专业本科培养方案</p><p>一、培养目标</p><p>正文</p>
            <table><tr><td>专业核心课</td><td>22008160</td><td>3</td></tr></table>
        """)
        assertTrue(result.creditRequirements.isEmpty())
    }
    @Test fun realMergedCatalogueFooterKeepsAllGraduationRequirements() {
        val html = requireNotNull(javaClass.getResource("/school/training-program-footer.html")).readText()
        val values = JsoupHtmlParser().parseTrainingProgram(html).creditRequirements.associate { it.label to it.credits }
        assertEquals(9, values.size)
        assertEquals(167.0, values["毕业生应取得总学分"])
        assertEquals(8.5, values["通识选修课"])
        assertEquals(15.0, values["专业核心课"])
        assertEquals(9.0, values["拓展教育"])
        assertFalse(values.values.any { it > 500 })
    }
}
