import Foundation
import SwiftSoup

extension SchoolNetworkManager {
    func isTimetablePage(_ html: String) -> Bool {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.contains("\"rows\"") {
            return true
        }

        let markers = [
            "id=\"kbtable\"",
            "id='kbtable'",
            "kbcontent_",
            "class=\"kbcontent\"",
            "class='kbcontent'"
        ]
        return markers.contains { html.contains($0) }
    }

    func isStudentCenterPage(_ html: String) -> Bool {
        let markers = [
            "学生个人中心",
            "培养管理",
            "选课中心",
            "基本管理",
            "课程成绩查询"
        ]
        return markers.contains { html.contains($0) }
    }

    func resolvedTimetableSemesterID(from html: String, responseURL: URL? = nil) -> String? {
        if let responseURL,
           let semesterID = URLComponents(url: responseURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "xnxq01id" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !semesterID.isEmpty {
            return semesterID
        }

        guard let document = try? SwiftSoup.parse(html) else { return nil }
        if let selected = try? document.select("select[name=xnxq01id] option[selected]").first(),
           let value = try? selected.attr("value").trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        if let hidden = try? document.select("input[name=xnxq01id]").first(),
           let value = try? hidden.attr("value").trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        return nil
    }

    func validateTimetableSemester(
        html: String,
        responseURL: URL?,
        expectedSemesterID: String?
    ) throws {
        let expected = expectedSemesterID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !expected.isEmpty,
              let actual = resolvedTimetableSemesterID(from: html, responseURL: responseURL),
              actual != expected else {
            return
        }
        throw SchoolNetworkError.timetableSemesterMismatch(expected: expected, actual: actual)
    }

    func extractURLCandidates(from raw: String) -> [String] {
        let normalized = raw
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        var candidates: [String] = []

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard trimmed.contains("xskb") || trimmed.contains("kb") || trimmed.contains("课表") else { return }
            candidates.append(trimmed)
        }

        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") || normalized.hasPrefix("/") || normalized.hasPrefix("jsxsd/") {
            append(normalized)
        }

        let patterns = [
            #"https?://[^'"\s)\\]+"#,
            #"/[^'"\s)\\]*(?:xskb|kb)[^'"\s)\\]*"#,
            #"jsxsd/[^'"\s)\\]*(?:xskb|kb)[^'"\s)\\]*"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(normalized.startIndex..., in: normalized)
            for match in regex.matches(in: normalized, options: [], range: range) {
                guard let matchRange = Range(match.range, in: normalized) else { continue }
                append(String(normalized[matchRange]))
            }
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    func extractTimetableCandidateRequests(from html: String, baseURL: URL) throws -> [URLRequest] {
        let document = try SwiftSoup.parse(html)
        var candidates: [URLRequest] = []
        var seen: Set<String> = []

        func appendRequest(rawValue: String, referer: URL?) {
            for urlString in extractURLCandidates(from: rawValue) {
                guard let resolvedURL = URL(string: urlString, relativeTo: baseURL)?.absoluteURL else { continue }
                let key = resolvedURL.absoluteString
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                candidates.append(makeRequest(url: resolvedURL, referer: referer))
            }
        }

        func inspectElement(_ element: Element, referer: URL?) {
            for attribute in ["href", "src", "url", "data-url", "onclick"] {
                let value = (try? element.attr(attribute)) ?? ""
                appendRequest(rawValue: value, referer: referer)
            }
        }

        let preferredLabels = ["本人课表", "学生课表", "学期理论课表", "课表"]
        for element in try document.getAllElements() {
            let text = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = ((try? element.attr("title")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ariaLabel = ((try? element.attr("aria-label")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = "\(text) \(title) \(ariaLabel)"

            if preferredLabels.contains(where: { combined.contains($0) }) {
                inspectElement(element, referer: baseURL)
                if let parent = element.parent() {
                    inspectElement(parent, referer: baseURL)
                }
                for child in try element.getElementsByTag("a").array() {
                    inspectElement(child, referer: baseURL)
                }
            }
        }

        for selector in ["a[href]", "iframe[src]", "frame[src]", "[url]", "[data-url]", "[onclick]"] {
            for element in try document.select(selector).array() {
                inspectElement(element, referer: baseURL)
            }
        }

        let scriptText = try document.select("script").array().map { (try? $0.html()) ?? "" }.joined(separator: "\n")
        for candidate in extractURLCandidates(from: scriptText) {
            appendRequest(rawValue: candidate, referer: baseURL)
        }

        let pairedPatterns = [
            #"本人课表[^"'\\\n]{0,240}['"]([^'"]+)['"]"#,
            #"['"]([^'"]+)['"][^"'\\\n]{0,240}本人课表"#,
            #"学生课表[^"'\\\n]{0,240}['"]([^'"]+)['"]"#,
            #"['"]([^'"]+)['"][^"'\\\n]{0,240}学生课表"#
        ]

        for pattern in pairedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(scriptText.startIndex..., in: scriptText)
            for match in regex.matches(in: scriptText, options: [], range: range) {
                guard match.numberOfRanges > 1,
                      let captureRange = Range(match.range(at: 1), in: scriptText) else {
                    continue
                }

                appendRequest(rawValue: String(scriptText[captureRange]), referer: baseURL)
            }
        }

        return candidates
    }

    func timetableURL(_ url: URL, applyingSemesterID semesterID: String) -> URL {
        let trimmedSemesterID = semesterID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSemesterID.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "xnxq01id" }
        queryItems.append(URLQueryItem(name: "xnxq01id", value: trimmedSemesterID))
        components.queryItems = queryItems
        return components.url ?? url
    }

    func shouldUseCachedTimetableLandingURL(_ url: URL, preferredSemesterID: String) -> Bool {
        let trimmedSemesterID = preferredSemesterID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSemesterID.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let semesterValue = components.queryItems?
                  .first(where: { $0.name == "xnxq01id" })?
                  .value?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !semesterValue.isEmpty else {
            return true
        }

        return semesterValue == trimmedSemesterID
    }

    func fetchTimetableHTML(using request: URLRequest, preferredSemesterID: String? = nil) async throws -> (String, HTTPURLResponse) {
        let (pageHTML, response) = try await html(for: request)
        if isTimetablePage(pageHTML) {
            try validateTimetableSemester(
                html: pageHTML,
                responseURL: response.url,
                expectedSemesterID: preferredSemesterID
            )
            return (pageHTML, response)
        }

        if let followUpRequest = try resolveTimetableRequest(from: pageHTML, preferredSemesterID: preferredSemesterID) {
            let (resolvedHTML, resolvedResponse) = try await html(for: followUpRequest)
            if isTimetablePage(resolvedHTML) {
                try validateTimetableSemester(
                    html: resolvedHTML,
                    responseURL: resolvedResponse.url,
                    expectedSemesterID: preferredSemesterID
                )
                return (resolvedHTML, resolvedResponse)
            }
            return (resolvedHTML, resolvedResponse)
        }

        if isStudentCenterPage(pageHTML),
           let responseURL = response.url {
            for candidate in try extractTimetableCandidateRequests(from: pageHTML, baseURL: responseURL) {
                let (candidateHTML, candidateResponse) = try await html(for: candidate)
                if isTimetablePage(candidateHTML) {
                    try validateTimetableSemester(
                        html: candidateHTML,
                        responseURL: candidateResponse.url,
                        expectedSemesterID: preferredSemesterID
                    )
                    return (candidateHTML, candidateResponse)
                }

                if let followUpRequest = try resolveTimetableRequest(from: candidateHTML, preferredSemesterID: preferredSemesterID) {
                    let (resolvedHTML, resolvedResponse) = try await html(for: followUpRequest)
                    if isTimetablePage(resolvedHTML) {
                        try validateTimetableSemester(
                            html: resolvedHTML,
                            responseURL: resolvedResponse.url,
                            expectedSemesterID: preferredSemesterID
                        )
                        return (resolvedHTML, resolvedResponse)
                    }
                }
            }
        }

        return (pageHTML, response)
    }

    func resolveTimetableRequest(from html: String, preferredSemesterID: String? = nil) throws -> URLRequest? {
        let document = try SwiftSoup.parse(html)
        let forms = try document.select("form").array()

        guard let form = forms.first(where: { form in
            let action = (try? form.attr("action")) ?? ""
            let hasTermSelect = ((try? form.select("select[name=xnxq01id]").isEmpty()) == false)
            return action.contains("xskb") || hasTermSelect
        }) ?? forms.first else {
            return nil
        }

        let action = try form.attr("action")
        let resolvedURL = URL(string: action.isEmpty ? "/jsxsd/xskb/xskb_list.do" : action,
                              relativeTo: URL(string: baseURL))?.absoluteURL
        guard let endpoint = resolvedURL else {
            throw URLError(.badURL)
        }

        var params: [String: String] = [:]

        for input in try form.select("input[name]").array() {
            let name = try input.attr("name").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }

            let type = try input.attr("type").lowercased()
            if ["submit", "button", "image", "reset", "file"].contains(type) {
                continue
            }
            if ["checkbox", "radio"].contains(type), !input.hasAttr("checked") {
                continue
            }
            params[name] = try input.attr("value")
        }

        for select in try form.select("select[name]").array() {
            let name = try select.attr("name").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }

            let options = try select.select("option").array()
            let trimmedPreferredSemesterID = preferredSemesterID?.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "xnxq01id",
               let trimmedPreferredSemesterID,
               !trimmedPreferredSemesterID.isEmpty,
               let preferredOption = options.first(where: {
                   ((try? $0.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)) ?? "") == trimmedPreferredSemesterID
               }) {
                params[name] = try preferredOption.attr("value")
                continue
            }

            let selectedOption = options.first(where: { $0.hasAttr("selected") })
                ?? options.first(where: { !((try? $0.attr("value").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?? true) })
                ?? options.first

            if let selectedOption {
                params[name] = try selectedOption.attr("value")
            }
        }

        for textarea in try form.select("textarea[name]").array() {
            let name = try textarea.attr("name").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                params[name] = try textarea.text()
            }
        }

        guard !params.isEmpty else {
            return nil
        }

        let method = (try? form.attr("method").lowercased()) ?? "get"
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)
        let queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        if method == "post" {
            var request = makeRequest(url: endpoint, method: "POST")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            components?.queryItems = queryItems
            request.httpBody = components?.percentEncodedQuery?.data(using: .utf8)
            return request
        }

        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        return makeRequest(url: url)
    }

    func fetchTimetable() async throws -> String {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式使用本地课表样例，不连接学校教务系统。")
        }

        if currentPortal == .graduate {
            return try await fetchGraduateTimetable()
        }

        guard isLoggedIn else { throw URLError(.userAuthenticationRequired) }
        guard let rootURL = URL(string: baseURL),
              let timetableURL = URL(string: "\(baseURL)/jsxsd/xskb/xskb_list.do"),
              let mainURL = URL(string: "\(baseURL)/jsxsd/framework/xsMain.jsp"),
              let upperMainURL = URL(string: "\(baseURL)/jsxsd/framework/xSMain.jsp") else {
            throw URLError(.badURL)
        }

        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()
        let preferredSemesterID = semesterConfig.semesterID

        var candidateRequests: [URLRequest] = []
        var seenRequestURLs: Set<String> = []

        func appendCandidate(_ request: URLRequest) {
            guard let url = request.url?.absoluteString else { return }
            guard !seenRequestURLs.contains(url) else { return }
            seenRequestURLs.insert(url)
            candidateRequests.append(request)
        }

        appendCandidate(makeRequest(url: self.timetableURL(timetableURL, applyingSemesterID: preferredSemesterID), referer: URL(string: "\(baseURL)/Logon.do?method=logon")))
        appendCandidate(makeRequest(url: timetableURL, referer: mainURL))
        appendCandidate(makeRequest(url: mainURL, referer: rootURL))
        appendCandidate(makeRequest(url: upperMainURL, referer: rootURL))

        if let lastLandingURLString,
           let landingURL = URL(string: lastLandingURLString),
           shouldUseCachedTimetableLandingURL(landingURL, preferredSemesterID: preferredSemesterID) {
            appendCandidate(makeRequest(url: landingURL, referer: rootURL))
        }

        var lastHTML = ""
        var lastResponse: HTTPURLResponse?

        for request in candidateRequests {
            let (candidateHTML, candidateResponse) = try await fetchTimetableHTML(using: request, preferredSemesterID: preferredSemesterID)
            lastHTML = candidateHTML
            lastResponse = candidateResponse
            persistLandingURL(candidateResponse.url)

            if isLoginPage(candidateHTML) {
                continue
            }

            if isTimetablePage(candidateHTML) {
                return candidateHTML
            }
        }

        for mainCandidateURL in [mainURL, upperMainURL] {
            let (mainHTML, mainResponse) = try await html(from: mainCandidateURL)
            lastHTML = mainHTML
            lastResponse = mainResponse

            if isLoginPage(mainHTML) {
                if await invalidateSessionIfNeeded() {
                    throw SchoolNetworkError.sessionExpired
                }

                throw SchoolNetworkError.timetableDataUnavailable(
                    pageDebugSummary(html: mainHTML, responseURL: mainResponse.url, snapshotName: "last_timetable_main_login_page.html")
                )
            }

            if isTimetablePage(mainHTML) {
                try validateTimetableSemester(
                    html: mainHTML,
                    responseURL: mainResponse.url,
                    expectedSemesterID: preferredSemesterID
                )
                return mainHTML
            }

            _ = persistDebugHTML(mainHTML, filename: "last_timetable_main_page.html")

            for request in try extractTimetableCandidateRequests(from: mainHTML, baseURL: mainCandidateURL) {
                let (candidateHTML, candidateResponse) = try await fetchTimetableHTML(using: request, preferredSemesterID: preferredSemesterID)
                lastHTML = candidateHTML
                lastResponse = candidateResponse
                persistLandingURL(candidateResponse.url)

                if isLoginPage(candidateHTML) {
                    continue
                }

                if isTimetablePage(candidateHTML) {
                    return candidateHTML
                }
            }
        }

        if isStudentCenterPage(lastHTML) {
            let renderedBootstrap: RenderedTimetableBootstrap?
            do {
                let bootstrapper = await MainActor.run { TimetableWebViewBootstrapper(manager: self) }
                renderedBootstrap = try await bootstrapper.bootstrap()
            } catch {
                renderedBootstrap = nil
            }

            if let renderedBootstrap {
                lastHTML = renderedBootstrap.html
                _ = persistDebugHTML(renderedBootstrap.html, filename: "last_timetable_rendered_page.html")

                if isTimetablePage(renderedBootstrap.html) {
                    try validateTimetableSemester(
                        html: renderedBootstrap.html,
                        responseURL: renderedBootstrap.url,
                        expectedSemesterID: preferredSemesterID
                    )
                    return renderedBootstrap.html
                }

                let renderedBaseURL = renderedBootstrap.url ?? mainURL
                var renderedSeen: Set<String> = []

                func tryCandidate(_ request: URLRequest) async throws -> String? {
                    guard let key = request.url?.absoluteString, !renderedSeen.contains(key) else { return nil }
                    renderedSeen.insert(key)

                    let (candidateHTML, candidateResponse) = try await fetchTimetableHTML(using: request, preferredSemesterID: preferredSemesterID)
                    lastHTML = candidateHTML
                    lastResponse = candidateResponse
                    persistLandingURL(candidateResponse.url)

                    if isLoginPage(candidateHTML) {
                        return nil
                    }

                    return isTimetablePage(candidateHTML) ? candidateHTML : nil
                }

                for frameSource in renderedBootstrap.frameSources {
                    guard let frameURL = URL(string: frameSource, relativeTo: renderedBaseURL)?.absoluteURL else { continue }
                    if let html = try await tryCandidate(makeRequest(url: frameURL, referer: renderedBaseURL)) {
                        return html
                    }
                }

                for request in try extractTimetableCandidateRequests(from: renderedBootstrap.html, baseURL: renderedBaseURL) {
                    if let html = try await tryCandidate(request) {
                        return html
                    }
                }
            }
        }

        if isLoginPage(lastHTML) {
            if await invalidateSessionIfNeeded() {
                throw SchoolNetworkError.sessionExpired
            }

            throw SchoolNetworkError.timetableDataUnavailable(
                pageDebugSummary(html: lastHTML, responseURL: lastResponse?.url, snapshotName: "last_timetable_initial_login_page.html")
            )
        }

        guard isTimetablePage(lastHTML) else {
            throw SchoolNetworkError.timetableDataUnavailable(
                pageDebugSummary(html: lastHTML, responseURL: lastResponse?.url, snapshotName: "last_timetable_resolved_unexpected.html")
            )
        }

        return lastHTML
    }

    func fetchGrades() async throws -> String {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式使用本地成绩样例，不连接学校教务系统。")
        }

        try requireUndergraduatePortal(for: "成绩查询")

        guard isLoggedIn else { throw URLError(.userAuthenticationRequired) }
        guard let url = URL(string: "\(baseURL)/jsxsd/kscj/cjcx_list") else {
            throw URLError(.badURL)
        }
        let (html, _) = try await html(from: url)
        if isLoginPage(html), await invalidateSessionIfNeeded() {
            throw SchoolNetworkError.sessionExpired
        }
        return html
    }

    private func fetchGraduateTimetable() async throws -> String {
        guard isLoggedIn else { throw URLError(.userAuthenticationRequired) }
        guard let url = URL(string: "\(graduateBaseURL)/student/pygl/py_kbcx_ew") else {
            throw URLError(.badURL)
        }
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()

        var request = makeRequest(url: url, referer: URL(string: "\(graduateBaseURL)/home/stulogin"))
        request.httpMethod = "GET"

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "kblx", value: "xs"),
            URLQueryItem(name: "termcode", value: semesterConfig.graduateTimetableTermCode)
        ]
        if let resolvedURL = components?.url {
            request = makeRequest(url: resolvedURL, referer: URL(string: "\(graduateBaseURL)/home/stulogin"))
        }

        let (data, response) = try await data(for: preparedRequest(from: request))
        if let httpResponse = response as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: request.url)
        }

        let rawText = String(data: data, encoding: .utf8) ?? ""
        if rawText.contains("</script>") || rawText.contains("stulogin") {
            if await invalidateSessionIfNeeded() {
                throw SchoolNetworkError.sessionExpired
            }
            throw SchoolNetworkError.timetableDataUnavailable("研究生课表页面返回了登录页，请连接校园网后重新登录并重试。")
        }

        let decrypted = decryptGraduateAES(rawText)
        guard !decrypted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchoolNetworkError.timetableDataUnavailable("研究生课表数据解密失败，请稍后重试。")
        }

        return decrypted
    }
}
