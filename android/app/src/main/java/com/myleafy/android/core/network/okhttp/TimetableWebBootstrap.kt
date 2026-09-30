package com.myleafy.android.core.network.okhttp

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.coroutines.resumeWithException
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.io.ByteArrayInputStream
import kotlin.coroutines.resume

data class RenderedSchoolPage(val url: String, val html: String, val cookies: Map<String, String>)

/** Executes the school's own timetable menu when the landing page needs JavaScript. */
class TimetableWebBootstrap(private val context: Context) {
    @SuppressLint("SetJavaScriptEnabled")
    suspend fun load(url: String, cookies: Map<String, String>): RenderedSchoolPage = webMutex.withLock { withContext(Dispatchers.Main.immediate) {
        val origin = url.toHttpUrl()
        val manager = CookieManager.getInstance()
        // This is the app's only WebView. Never inherit a previous school's browser session.
        suspendCancellableCoroutine { continuation ->
            manager.removeAllCookies { if (continuation.isActive) continuation.resume(Unit) }
        }
        android.webkit.WebStorage.getInstance().deleteAllData()
        cookies.forEach { (name, value) ->
            suspendCancellableCoroutine { continuation ->
                manager.setCookie(url, "$name=$value; Path=/") { if (continuation.isActive) continuation.resume(Unit) }
            }
        }
        val web = WebView(context)
        try {
            web.settings.javaScriptEnabled = true
            web.settings.domStorageEnabled = true
            web.settings.allowFileAccess = false
            web.settings.allowContentAccess = false
            web.settings.userAgentString = SchoolRequests.USER_AGENT
            web.webViewClient = object : WebViewClient() {
                private fun allowed(request: WebResourceRequest): Boolean =
                    request.url.host == origin.host && request.url.scheme == origin.scheme &&
                        (request.url.port == -1 || request.url.port == origin.port)
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = !allowed(request)
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                    if (allowed(request)) null else WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(byteArrayOf()))
            }
            web.loadUrl(url)
            withTimeout(15_000) {
                var menuOpened = false
                while (true) {
                    delay(400)
                    val captured = Json.parseToJsonElement(web.evaluate(CAPTURE)).jsonObject
                    val html = captured.getValue("html").jsonPrimitive.content
                    val capturedUrl = captured.getValue("url").jsonPrimitive.content
                    val page = capturedUrl.toHttpUrl()
                    if (page.host != origin.host || page.scheme != origin.scheme || page.port != origin.port) error("课表页面来源无效")
                    if (TimetablePageResolver.isTimetable(html)) return@withTimeout capturedUrl to html
                    if (!menuOpened && html.contains("培养管理")) {
                        web.evaluate(EXPAND_MENU)
                        menuOpened = true
                    }
                    if (menuOpened && TimetablePageResolver.candidates(html, page, origin, "").isNotEmpty()) return@withTimeout capturedUrl to html
                }
                @Suppress("UNREACHABLE_CODE") (url to "")
            }.let { (pageUrl, html) ->
                val updated = manager.getCookie(url).orEmpty().split(';').mapNotNull { entry ->
                    val pair = entry.trim().split('=', limit = 2)
                    if (pair.size == 2) pair[0] to pair[1] else null
                }.toMap()
                RenderedSchoolPage(pageUrl, html, updated)
            }
        } finally { web.stopLoading(); web.destroy(); manager.removeAllCookies(null) }
    } }

    private suspend fun WebView.evaluate(script: String): String = suspendCancellableCoroutine { continuation ->
        evaluateJavascript(script) { result ->
            if (continuation.isActive) {
                try { continuation.resume(Json.parseToJsonElement(result).jsonPrimitive.content) }
                catch (failure: Exception) { continuation.resumeWithException(failure) }
            }
        }
    }

    companion object {
        private val webMutex = Mutex()
        private val CAPTURE = """(() => {
          for (const frame of document.querySelectorAll('iframe,frame')) {
            try { const doc = frame.contentDocument;
              if (doc && doc.querySelector('#kbtable,.kbcontent,[name=xnxq01id]')) return JSON.stringify({url:doc.URL,html:doc.documentElement.outerHTML});
            } catch (_) {}
          }
          return JSON.stringify({url:location.href,html:document.documentElement ? document.documentElement.outerHTML : ''});
        })();"""
        private val EXPAND_MENU = """(() => {
          const click = labels => {
            const nodes = Array.from(document.querySelectorAll('a,li,button,span'));
            const target = nodes.find(n => labels.includes((n.textContent || '').replace(/\s+/g,'')));
            if (target) target.click();
          };
          click(['培养管理']); click(['本人课表','学生课表','学期理论课表']); return '';
        })();"""
    }
}
