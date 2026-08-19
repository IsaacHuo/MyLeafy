package com.myleafy.android.core.network

/**
 * 强智登录编码（对应 iOS `encodeKey` 与 `formURLEncodedBody`，行为一致）。
 */
object SchoolLoginEncoder {

    /**
     * encodeKey 混淆：code = account + "%%%" + password。
     * 逐字符与 secretKey 数字位移交错 secretCode 前缀；越界后直接拼接剩余 code。
     * key 不含 "#" 时返回空串（与 iOS 一致）。
     */
    fun encodeKey(key: String, account: String, password: String): String {
        val parts = key.split("#")
        if (parts.size != 2) return ""

        var secretCode = parts[0]
        val secretKey = parts[1]
        val code = account + "%%%" + password
        val encoded = StringBuilder()

        for (i in code.indices) {
            if (i < 20 && i < secretKey.length) {
                encoded.append(code[i])
                val shift = secretKey[i].digitToIntOrNull() ?: 0
                val prefixCount = minOf(shift, secretCode.length)
                encoded.append(secretCode.take(prefixCount))
                secretCode = secretCode.drop(prefixCount)
            } else {
                encoded.append(code.substring(i))
                break
            }
        }
        return encoded.toString()
    }

    /**
     * 表单值编码：与 iOS `percentEncodedQuery` + "+"→"%2B" 一致
     * （空格 → %20，字面 '+' → %2B，其余按 RFC3986）。
     */
    fun formUrlEncode(value: String): String =
        java.net.URLEncoder.encode(value, "UTF-8").replace("+", "%20")
}
