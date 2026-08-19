package com.myleafy.android.core.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SchoolPageDetectorTest {

    @Test
    fun isLoginPageDetectsMarkers() {
        assertTrue(SchoolPageDetector.isLoginPage("""<input name="RANDOMCODE">"""))
        assertTrue(SchoolPageDetector.isLoginPage("<html>验证码</html>"))
        assertTrue(SchoolPageDetector.isLoginPage("stulogin_do"))
        assertFalse(SchoolPageDetector.isLoginPage("<html>学生课表</html>"))
    }

    @Test
    fun authenticatedResponseByUrlMarker() {
        assertTrue(
            SchoolPageDetector.isAuthenticatedResponse(
                url = "http://newjwxt.bjfu.edu.cn/jsxsd/framework/xsMain.jsp",
                html = "<html>content</html>",
            ),
        )
        // 登录 URL 不算
        assertFalse(
            SchoolPageDetector.isAuthenticatedResponse(
                url = "http://newjwxt.bjfu.edu.cn/Logon.do?method=logon",
                html = "<html>content</html>",
            ),
        )
    }

    @Test
    fun authenticatedResponseByHtmlMarker() {
        assertTrue(
            SchoolPageDetector.isAuthenticatedResponse(
                url = "http://newjwxt.bjfu.edu.cn/whatever",
                html = "<html>退出系统</html>",
            ),
        )
    }

    @Test
    fun loginPageIsNeverAuthenticated() {
        assertFalse(
            SchoolPageDetector.isAuthenticatedResponse(
                url = "http://newjwxt.bjfu.edu.cn/jsxsd/framework/xsMain.jsp",
                html = "<html>验证码</html>",
            ),
        )
    }

    @Test
    fun extractLoginMessageFromAlert() {
        assertEquals("验证码错误", SchoolPageDetector.extractLoginMessage("""<script>alert('验证码错误')</script>"""))
    }

    @Test
    fun extractLoginMessageFromRedFont() {
        assertEquals(
            "账号或密码错误",
            SchoolPageDetector.extractLoginMessage("""<font color="red">账号或密码错误</font>"""),
        )
    }

    @Test
    fun extractLoginMessageIgnoresKnownNoise() {
        assertNull(SchoolPageDetector.extractLoginMessage("""alert('请输入完整的登陆信息！')"""))
    }

    @Test
    fun extractLoginMessageReturnsNullWithoutMatch() {
        assertNull(SchoolPageDetector.extractLoginMessage("<html>正常页面</html>"))
    }
}
