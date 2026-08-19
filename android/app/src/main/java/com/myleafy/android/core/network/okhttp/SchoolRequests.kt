package com.myleafy.android.core.network.okhttp

import okhttp3.Request

/**
 * 教务请求构造（对应 iOS `SchoolNetworkManager` 的请求头与缓存策略）。
 * User-Agent 与 iOS 完全一致（Chrome-on-mac），全局 Referer 由调用方按需设置。
 */
object SchoolRequests {
    const val USER_AGENT =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"

    fun builder(url: String, referer: String? = null): Request.Builder =
        Request.Builder()
            .url(url)
            .header("User-Agent", USER_AGENT)
            .header("Cache-Control", "no-cache")
            .header("Pragma", "no-cache")
            .apply { if (referer != null) header("Referer", referer) }
}
