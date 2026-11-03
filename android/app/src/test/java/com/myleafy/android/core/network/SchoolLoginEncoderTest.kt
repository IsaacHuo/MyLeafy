package com.myleafy.android.core.network

import org.junit.Assert.assertEquals
import org.junit.Test
import kotlinx.serialization.json.*
import java.net.URLDecoder

class SchoolLoginEncoderTest {

    @Test
    fun sharedSchoolJavaScriptEncodingAndFormRoundtrip() {
        val raw = checkNotNull(javaClass.classLoader?.getResourceAsStream("jwxt/fixtures/login_encoding.json"))
            .bufferedReader().use { it.readText() }
        val input = Json.parseToJsonElement(raw).jsonObject
        val key = input.getValue("key").jsonPrimitive.content
        val cases = input.getValue("cases").jsonArray
        assertEquals(1235, cases.size)
        for (item in cases) {
            val fields = item.jsonObject
            val encoded = SchoolLoginEncoder.encodeKey(key, fields.getValue("account").jsonPrimitive.content,
                fields.getValue("password").jsonPrimitive.content)
            val decoded = URLDecoder.decode(SchoolLoginEncoder.formUrlEncode(encoded), "UTF-8")
            assertEquals(fields.getValue("encoded").jsonPrimitive.content, decoded)
        }
    }

    @Test
    fun malformedKeysAreRejected() {
        for (key in listOf("no", "", "<html>error</html>", "ABC#", "#123", "ABC#12x", "ABC#１２３", "ABC#1#2")) {
            assertEquals(false, SchoolLoginEncoder.isValidKey(key))
            assertEquals("", SchoolLoginEncoder.encodeKey(key, "2012", "pw"))
        }
    }

    @Test
    fun encodeKeyInterleavesSecretCodeByDigitShifts() {
        // key = "ABCDEF#123"，secretKey 数字位移 [1,2,3]
        val encoded = SchoolLoginEncoder.encodeKey("ABCDEF#123", "2012", "pw")
        assertEquals("2A0BC1DEF2%%%pw", encoded)
    }

    @Test
    fun encodeKeyWithoutSeparatorReturnsEmpty() {
        assertEquals("", SchoolLoginEncoder.encodeKey("invalid", "2012", "pw"))
    }

    @Test
    fun encodeKeyStopsAfterSecretKeyExhausted() {
        // secretKey 只有 1 位：交错 1 次后直接拼接剩余 code。
        // i=0: 'a' + shift=min(4,3)=3 → "XYZ"；i=1 越界 → 拼接 code[1:] = "bc%%%p"
        val encoded = SchoolLoginEncoder.encodeKey("XYZ#4", "abc", "p")
        assertEquals("aXYZbc%%%p", encoded)
    }

    @Test
    fun formUrlEncodeEncodesSpaceAndPlus() {
        assertEquals("a%20b%2Bc%25", SchoolLoginEncoder.formUrlEncode("a b+c%"))
    }
}
