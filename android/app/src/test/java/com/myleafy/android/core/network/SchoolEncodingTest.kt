package com.myleafy.android.core.network

import java.nio.charset.Charset
import org.junit.Assert.assertEquals
import org.junit.Test

class SchoolEncodingTest {

    @Test
    fun decodesValidUtf8() {
        val bytes = "森林生态学".toByteArray(Charsets.UTF_8)
        assertEquals("森林生态学", SchoolEncoding.decodeUtf8OrGb18030(bytes))
    }

    @Test
    fun fallsBackToGb18030ForNonUtf8Bytes() {
        // GB18030 编码的中文在 UTF-8 下是非法的，应回退
        val bytes = "数据结构".toByteArray(Charset.forName("GB18030"))
        assertEquals("数据结构", SchoolEncoding.decodeUtf8OrGb18030(bytes))
    }

    @Test
    fun asciiPassthrough() {
        assertEquals("hello world", SchoolEncoding.decodeUtf8OrGb18030("hello world".toByteArray()))
    }
}
