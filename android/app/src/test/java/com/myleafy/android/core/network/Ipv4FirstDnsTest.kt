package com.myleafy.android.core.network

import java.net.InetAddress
import org.junit.Assert.assertEquals
import org.junit.Test

class Ipv4FirstDnsTest {
    @Test
    fun ipv4AddressesAreTriedBeforeIpv6() {
        val ipv4 = InetAddress.getByName("172.67.137.216")
        val ipv6 = InetAddress.getByName("2606:4700:3037::ac43:89d8")

        assertEquals(listOf(ipv4, ipv6), Ipv4FirstDns.order(listOf(ipv6, ipv4)))
    }

    @Test
    fun orderKeepsSameFamilyOrder() {
        val first = InetAddress.getByName("1.1.1.1")
        val second = InetAddress.getByName("8.8.8.8")

        assertEquals(listOf(first, second), Ipv4FirstDns.order(listOf(first, second)))
    }
}
