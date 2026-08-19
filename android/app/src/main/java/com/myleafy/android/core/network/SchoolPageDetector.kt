package com.myleafy.android.core.network

/**
 * 教务页面识别（对应 iOS `isLoginPage` / `isAuthenticatedResponse` /
 * `extractLoginMessage`，标记与正则完全一致）。
 */
object SchoolPageDetector {

    private val loginPageMarkers = listOf(
        "Logon.do?method=logon",
        "stulogin_do",
        "name=\"RANDOMCODE\"",
        "name='RANDOMCODE'",
        "verifycode.servlet",
        "verificationcode",
        "pubkey",
        "验证码",
    )

    fun isLoginPage(html: String): Boolean =
        loginPageMarkers.any { html.contains(it) }

    fun isAuthenticatedResponse(url: String, html: String): Boolean {
        if (isLoginPage(html)) return false

        val urlMarkers = listOf(
            "xsMain.jsp",
            "/jsxsd/framework/",
            "/jsxsd/xsks/",
            "/jsxsd/xskb/",
            "/jsxsd/kscj/",
        )
        if (urlMarkers.any { url.contains(it) } && !url.contains("Logon.do?method=logon")) {
            return true
        }

        val htmlMarkers = listOf(
            "xsMain.jsp",
            "退出系统",
            "安全退出",
            "个人信息",
            "学生课表",
            "成绩查询",
        )
        return htmlMarkers.any { html.contains(it) }
    }

    private val ignoredLoginMessages = setOf(
        "请输入完整的登陆信息！",
        "系统检查到您两次登录的账号不一致，是否确定用新账号登录？",
    )

    private val loginMessagePatterns = listOf(
        Regex("""alert\(['"]([^'"]+)['"]\)""", RegexOption.IGNORE_CASE),
        Regex("""showMsg\(['"]([^'"]+)['"]\)""", RegexOption.IGNORE_CASE),
        Regex("""<font[^>]*color=['"]?red['"]?[^>]*>([^<]+)</font>""", RegexOption.IGNORE_CASE),
    )

    /** 从登录失败页提取提示消息；无有效消息返回 null。 */
    fun extractLoginMessage(html: String): String? {
        for (pattern in loginMessagePatterns) {
            val message = pattern.find(html)?.groupValues?.getOrNull(1)?.trim()
            if (!message.isNullOrEmpty() && message !in ignoredLoginMessages) {
                return message
            }
        }
        return null
    }
}
