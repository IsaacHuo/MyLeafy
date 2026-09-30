package com.myleafy.android.core.network.okhttp

import com.myleafy.android.core.network.SchoolNetworkError
import okhttp3.FormBody
import okhttp3.HttpUrl
import okhttp3.Request
import org.jsoup.Jsoup

/** School forms, links and frames are the source of truth, never a guessed empty timetable. */
internal object TimetablePageResolver {
    fun isTimetable(html: String): Boolean = Jsoup.parse(html).select("#kbtable, .kbcontent, [id^=kbcontent_]").isNotEmpty()

    fun verifySemester(html: String, semester: String) {
        val document = Jsoup.parse(html)
        val actual = document.selectFirst("select[name=xnxq01id] option[selected]")?.attr("value")
            ?: document.selectFirst("input[name=xnxq01id]")?.attr("value")
        if (actual?.trim() != semester) throw SchoolNetworkError.TimetableSemesterMismatch
    }

    fun candidates(html: String, page: HttpUrl, origin: HttpUrl, semester: String): List<Request> {
        val document = Jsoup.parse(html, page.toString())
        val result = mutableListOf<Request>()
        fun allowed(url: HttpUrl) = url.host == origin.host && url.port == origin.port && url.scheme == origin.scheme
        document.select("form").filter { it.attr("action").contains("xskb") || it.select("[name=xnxq01id]").isNotEmpty() }.forEach { form ->
            val endpoint = page.resolve(form.attr("action").ifBlank { "/jsxsd/xskb/xskb_list.do" }) ?: return@forEach
            if (!allowed(endpoint)) return@forEach
            val values = linkedMapOf<String, String>()
            form.select("input[name]").forEach { input ->
                val type = input.attr("type").lowercase()
                if (type !in listOf("submit", "button", "image", "reset", "file") &&
                    (type !in listOf("checkbox", "radio") || input.hasAttr("checked"))) values[input.attr("name")] = input.attr("value")
            }
            form.select("select[name]").forEach { select ->
                val name = select.attr("name")
                val option = select.selectFirst("option[selected]") ?: select.selectFirst("option[value]")
                values[name] = if (name == "xnxq01id") semester else option?.attr("value").orEmpty()
            }
            form.select("textarea[name]").forEach { values[it.attr("name")] = it.text() }
            values["xnxq01id"] = semester
            val request = SchoolRequests.builder(endpoint.toString(), page.toString())
            if (form.attr("method").equals("post", true)) {
                request.post(FormBody.Builder().apply { values.forEach { (key, value) -> add(key, value) } }.build())
            } else {
                request.url(endpoint.newBuilder().apply { values.forEach { (key, value) -> setQueryParameter(key, value) } }.build())
            }
            result += request.build()
        }
        val links = document.select("a[href], iframe[src], frame[src]").map { it.attr(if (it.hasAttr("href")) "href" else "src") } +
            Regex("['\"]([^'\"\\s]*(?:xskb|kbxx)[^'\"\\s]*)['\"]").findAll(document.select("script").joinToString("\n") { it.data() }).map { it.groupValues[1] }.toList()
        links.forEach { raw ->
            val target = page.resolve(raw.replace("&amp;", "&")) ?: return@forEach
            if (allowed(target) && (target.encodedPath.contains("xskb") || target.encodedPath.contains("kbxx"))) {
                result += SchoolRequests.builder(target.newBuilder().setQueryParameter("xnxq01id", semester).build().toString(), page.toString()).build()
            }
        }
        return result.distinctBy { "${it.method}|${it.url}|${it.body?.let { body -> okio.Buffer().also(body::writeTo).readUtf8() }}" }
    }
}
