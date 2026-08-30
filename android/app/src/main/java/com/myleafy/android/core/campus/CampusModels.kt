package com.myleafy.android.core.campus

/**
 * 校园能力模型（与 iOS `Core/Campus/CampusModels.swift` 行为一致）。
 *
 * 阶段 1 仅保留定义与 BJFU 内置描述，用于约束功能入口；后续接入实际教务
 * 数据时按 capability 门控页面与仓库实现。
 */
object CampusCapabilities {
    val AUTHENTICATION = "authentication"
    val TIMETABLE = "timetable"
    val GRADES = "grades"
    val EXAMS = "exams"
    val TEACHING_PLAN = "teachingPlan"
    val TRAINING_PROGRAM = "trainingProgram"
    val CLASSROOMS = "classrooms"
    val COMMUNITY = "community"
    val WEATHER = "weather"
    val SHARED_TIMETABLE = "sharedTimetable"
    val MEDICAL_SERVICES = "medicalServices"

    val all: Set<String> = setOf(
        AUTHENTICATION, TIMETABLE, GRADES, EXAMS, TEACHING_PLAN, TRAINING_PROGRAM,
        CLASSROOMS, COMMUNITY, WEATHER, SHARED_TIMETABLE, MEDICAL_SERVICES,
    )
}

/** 校园标识，rawValue 规范化小写（如 "bjfu"）。 */
data class CampusID(val rawValue: String) {
    init {
        require(rawValue == rawValue.lowercase()) { "CampusID must be lowercase" }
    }

    companion object {
        val bjfu = CampusID("bjfu")
        val custom = CampusID("custom")
        val guest = CampusID("guest")
    }
}

/** 校园描述：显示名、连接器类型与能力集合。 */
data class CampusDescriptor(
    val id: CampusID,
    val displayName: String,
    val shortName: String,
    val connectorKind: String, // "bjfu" | "custom"
    val capabilities: Set<String>,
    val undergraduateBaseUrl: String,
    val graduateBaseUrl: String?,
) {
    fun supports(capability: String): Boolean = capability in capabilities

    companion object {
        val bjfu = CampusDescriptor(
            id = CampusID.bjfu,
            displayName = "北京林业大学",
            shortName = "北林",
            connectorKind = "bjfu",
            capabilities = CampusCapabilities.all,
            undergraduateBaseUrl = "http://newjwxt.bjfu.edu.cn",
            graduateBaseUrl = "http://gradms.bjfu.edu.cn/gmis5",
        )

        val custom = CampusDescriptor(
            id = CampusID.custom,
            displayName = "通用模式",
            shortName = "通用",
            connectorKind = "custom",
            capabilities = setOf(
                CampusCapabilities.AUTHENTICATION,
                CampusCapabilities.TIMETABLE,
                CampusCapabilities.GRADES,
                CampusCapabilities.EXAMS,
                CampusCapabilities.COMMUNITY,
            ),
            undergraduateBaseUrl = "https://myleafy.space",
            graduateBaseUrl = null,
        )

        val guest = CampusDescriptor(
            id = CampusID.guest,
            displayName = "免登录入口",
            shortName = "访客",
            connectorKind = "guest",
            capabilities = setOf(
                CampusCapabilities.TIMETABLE,
                CampusCapabilities.GRADES,
                CampusCapabilities.EXAMS,
            ),
            undergraduateBaseUrl = "",
            graduateBaseUrl = null,
        )

        fun forCampus(campusId: CampusID): CampusDescriptor = when (campusId) {
            CampusID.bjfu -> bjfu
            CampusID.custom -> custom
            CampusID.guest -> guest
            else -> error("Unsupported campus: ${campusId.rawValue}")
        }
    }
}

/** 当前活动校园上下文。阶段 1 固定 BJFU；身份恢复与切换在后续阶段接入。 */
object ActiveCampusContext {
    var descriptor: CampusDescriptor = CampusDescriptor.bjfu
}
