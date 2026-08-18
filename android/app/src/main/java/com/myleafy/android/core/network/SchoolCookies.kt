package com.myleafy.android.core.network

/**
 * 教务 Cookie 契约（对应 iOS `SchoolNetworkManager` 的 cookie 处理）。
 *
 * - 应用自持 Cookie 名值对字典为事实来源，持久化于 Keystore（按身份隔离）。
 * - 每个请求显式携带 `Cookie` 头：名值对**按名称排序**，以 `"; "` 拼接。
 * - 每个响应解析 `Set-Cookie`，合并回字典并持久化。
 */
object SchoolCookies {

    /** 生成请求的 Cookie 头值：name=value 按名称排序，"; " 拼接。 */
    fun headerValue(cookies: Map<String, String>): String? {
        if (cookies.isEmpty()) return null
        return cookies.entries
            .sortedBy { it.key }
            .joinToString("; ") { (name, value) -> "$name=$value" }
    }

    /**
     * 从响应头解析 Set-Cookie 并合并回字典。
     * 只保留 name=value 部分，忽略 path/expires 等属性（教务服务器不需要）。
     */
    fun mergeSetCookie(current: Map<String, String>, setCookieHeaders: List<String>): Map<String, String> {
        val merged = current.toMutableMap()
        for (header in setCookieHeaders) {
            val entry = header.substringBefore(';')
            val separator = entry.indexOf('=')
            if (separator <= 0) continue
            merged[entry.substring(0, separator).trim()] = entry.substring(separator + 1).trim()
        }
        return merged
    }
}
