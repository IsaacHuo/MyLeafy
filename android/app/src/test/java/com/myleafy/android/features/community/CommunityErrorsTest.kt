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
            "当前网络拦截了社区安全连接，请切换网络或关闭会接管流量的代理/VPN 后重试",
            message,
        )
        assertFalse(message.contains("certificate"))
        assertFalse(message.contains("supabase.co"))
    }
}
