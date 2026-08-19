package com.myleafy.android.core.network

import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/**
 * 教务页面解码（对应 iOS `decodedHTML`）：严格 UTF-8 优先，失败回退 GB18030。
 * 解析器只消费已解码文本，不自行决定字符集。
 */
object SchoolEncoding {

    fun decodeUtf8OrGb18030(bytes: ByteArray): String {
        val utf8 = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return runCatching { utf8.decode(ByteBuffer.wrap(bytes)).toString() }
            .getOrElse { String(bytes, Charset.forName("GB18030")) }
    }
}
