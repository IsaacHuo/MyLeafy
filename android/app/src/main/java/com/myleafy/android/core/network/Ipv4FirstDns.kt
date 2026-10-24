package com.myleafy.android.core.network

import java.net.Inet6Address
import java.net.InetAddress
import okhttp3.Dns

/**
 * 校园网/部分移动网络会出现 IPv6 有地址但不可达的情况。
 * OkHttp 默认按系统 DNS 顺序尝试；IPv6 黑洞会让每个请求先卡到连接超时。
 * 这里只调整尝试顺序，IPv4 全部失败后仍会回退 IPv6，不改变 TLS 或域名校验。
 */
object Ipv4FirstDns : Dns {
    override fun lookup(hostname: String): List<InetAddress> =
        order(Dns.SYSTEM.lookup(hostname))

    internal fun order(addresses: List<InetAddress>): List<InetAddress> =
        addresses.sortedBy { if (it is Inet6Address) 1 else 0 }
}
