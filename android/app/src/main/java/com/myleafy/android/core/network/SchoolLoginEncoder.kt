package com.myleafy.android.core.network

/**
 * 强智登录编码：与学校 JavaScript 的 UTF-16 交错及浏览器表单字符转换一致。
 */
object SchoolLoginEncoder {

    /**
     * encodeKey 混淆：code = account + "%%%" + password。
     * 逐字符与 secretKey 数字位移交错 secretCode 前缀；越界后直接拼接剩余 code。
     * 无效 key 返回空串；网络层必须在提交前拒绝无效 key。
     */
    fun isValidKey(key: String): Boolean {
        val parts = key.split("#")
        return parts.size == 2 && parts[0].isNotEmpty() && '<' !in parts[0] && '>' !in parts[0] &&
            parts[1].isNotEmpty() && parts[1].all { it in '0'..'9' }
    }

    fun encodeKey(key: String, account: String, password: String): String {
        val parts = key.split("#")
        if (!isValidKey(key)) return ""

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

    /** 表单值编码：空格 → %20，字面 '+' → %2B，解码后与浏览器提交的值一致。 */
    fun formUrlEncode(value: String): String {
        // HTML forms convert unpaired UTF-16 surrogates to U+FFFD. Java's
        // default UTF-8 encoder uses '?' instead, so normalize before encoding.
        val wellFormed = buildString {
            var index = 0
            while (index < value.length) {
                val char = value[index]
                if (char.isHighSurrogate() && index + 1 < value.length && value[index + 1].isLowSurrogate()) {
                    append(char)
                    append(value[++index])
                } else {
                    append(if (char.isSurrogate()) '\uFFFD' else char)
                }
                index++
            }
        }
        return java.net.URLEncoder.encode(wellFormed, "UTF-8").replace("+", "%20")
    }
}
