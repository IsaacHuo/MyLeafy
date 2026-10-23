package com.myleafy.android.features.community

import javax.net.ssl.SSLPeerUnverifiedException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class CommunityErrorsTest {
    @Test
    fun certificateHostnameMismatchUsesSafeActionableMessage() {
        val error = IllegalStateException(
            "request failed",
            SSLPeerUnverifiedException(
                "Hostname example.supabase.co not verified; certificate DN: CN=*.bjfu.edu.cn",
            ),
        )

        val message = error.toCommunityMessage("社区加载失败")

        assertEquals(
            "当前网络替换了 MyLeafy 的安全证书（bjfu-wifi 的登录/拦截页会返回 *.bjfu.edu.cn 证书）。请先完成校园网登录，或切换到移动数据/全局 VPN 后重试。",
            message,
        )
        assertFalse(message.contains("supabase.co"))
        org.junit.Assert.assertTrue(error.isPermanentTlsFailure())
    }
}
