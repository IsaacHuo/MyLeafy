package com.myleafy.android.core.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SchoolCookiesTest {

    @Test
    fun headerValueIsSortedByCookieName() {
        val cookies = mapOf("JSESSIONID" to "abc", "Campus" to "bjfu", "Auth" to "1")
        assertEquals("Auth=1; Campus=bjfu; JSESSIONID=abc", SchoolCookies.headerValue(cookies))
    }

    @Test
    fun emptyCookiesProduceNullHeader() {
        assertNull(SchoolCookies.headerValue(emptyMap()))
    }

    @Test
    fun mergeSetCookieOnlyKeepsNameValuePair() {
        val merged = SchoolCookies.mergeSetCookie(
            current = mapOf("existing" to "1"),
            setCookieHeaders = listOf(
                "JSESSIONID=ABC123; Path=/; HttpOnly",
                "Campus=bjfu; Path=/",
            ),
        )
        assertEquals(
            mapOf("existing" to "1", "JSESSIONID" to "ABC123", "Campus" to "bjfu"),
            merged,
        )
    }
}
