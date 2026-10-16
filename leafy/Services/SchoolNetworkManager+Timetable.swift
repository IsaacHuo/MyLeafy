import Foundation
import SwiftSoup

nonisolated struct FetchedTimetableDocument: Sendable {
    let html: String
    /// Source metadata only; never used to gate import or choose dates.
    let sourceSemesterID: String
}

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

    func resolvedTimetableSemesterID(from html: String) -> String? {
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

    func timetableDocument(html: String, requestedSemesterID: String = "") -> FetchedTimetableDocument {
        let source = resolvedTimetableSemesterID(from: html)
            ?? (requestedSemesterID.isEmpty ? "school-current" : requestedSemesterID)
        return FetchedTimetableDocument(html: html, sourceSemesterID: source)
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
            return (pageHTML, response)
        }

        if let followUpRequest = try resolveTimetableRequest(from: pageHTML, preferredSemesterID: preferredSemesterID) {
            let (resolvedHTML, resolvedResponse) = try await html(for: followUpRequest)
            if isTimetablePage(resolvedHTML) {
                return (resolvedHTML, resolvedResponse)
            }
            return (resolvedHTML, resolvedResponse)
        }

        if isStudentCenterPage(pageHTML),
           let responseURL = response.url {
            for candidate in try extractTimetableCandidateRequests(from: pageHTML, baseURL: responseURL) {
                let (candidateHTML, candidateResponse) = try await html(for: candidate)
                if isTimetablePage(candidateHTML) {
                    return (candidateHTML, candidateResponse)
                }

                if let followUpRequest = try resolveTimetableRequest(from: candidateHTML, preferredSemesterID: preferredSemesterID) {
                    let (resolvedHTML, resolvedResponse) = try await html(for: followUpRequest)
                    if isTimetablePage(resolvedHTML) {
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

    func fetchTimetable() async throws -> FetchedTimetableDocument {
        if ReviewDemoMode.isEnabled { throw SchoolNetworkError.featureUnavailable("演示模式使用本地课表样例，不连接学校教务系统。") }
        if currentPortal == .graduate { return try await fetchGraduateTimetable() }
        let initial = try await fetchDefaultTimetable()
        let options = try timetableTermOptions(in: initial.html, selector: "select[name=xnxq01id] option")
        for term in options {
            let document: FetchedTimetableDocument
            if term == resolvedTimetableSemesterID(from: initial.html) { document = initial }
            else { document = try await fetchDefaultTimetable(preferredSemesterID: term) }
            let parsed = try HTMLParser.parseTimetableResult(html: document.html)
            if !parsed.records.isEmpty { return document }
        }
        // Some valid school responses omit term controls entirely.
        _ = try HTMLParser.parseTimetableResult(html: initial.html)
        return initial
    }

    func timetableTermOptions(in html: String, selector: String) throws -> [String] {
        let doc = try SwiftSoup.parse(html)
        return Array(Set(try doc.select(selector).array().compactMap {
            guard !$0.hasAttr("disabled") else { return nil }
            let value = try $0.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        })).sorted { $0.compare($1, options: .numeric) == .orderedDescending }
    }

    private func fetchDefaultTimetable(preferredSemesterID requestedTerm: String? = nil) async throws -> FetchedTimetableDocument {
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

        let preferredSemesterID = requestedTerm ?? ""

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
                return timetableDocument(
                    html: candidateHTML,
                    requestedSemesterID: preferredSemesterID
                )
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
                return timetableDocument(
                    html: mainHTML,
                    requestedSemesterID: preferredSemesterID
                )
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
                    return timetableDocument(
                        html: candidateHTML,
                        requestedSemesterID: preferredSemesterID
                    )
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
                    return timetableDocument(
                        html: renderedBootstrap.html,
                        requestedSemesterID: preferredSemesterID
                    )
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

                    guard isTimetablePage(candidateHTML) else { return nil }
                    return timetableDocument(
                        html: candidateHTML,
                        requestedSemesterID: preferredSemesterID
                    ).html
                }

                for frameSource in renderedBootstrap.frameSources {
                    guard let frameURL = URL(string: frameSource, relativeTo: renderedBaseURL)?.absoluteURL else { continue }
                    if let html = try await tryCandidate(makeRequest(url: frameURL, referer: renderedBaseURL)) {
                        return timetableDocument(
                            html: html,
                            requestedSemesterID: preferredSemesterID
                        )
                    }
                }

                for request in try extractTimetableCandidateRequests(from: renderedBootstrap.html, baseURL: renderedBaseURL) {
                    if let html = try await tryCandidate(request) {
                        return timetableDocument(
                            html: html,
                            requestedSemesterID: preferredSemesterID
                        )
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

        return timetableDocument(
            html: lastHTML,
            requestedSemesterID: preferredSemesterID
        )
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
        var request = makeRequest(url: url, method: "POST", referer: URL(string: "\(baseURL)/jsxsd/kscj/cjcx_query"))
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = "kksj=&kcxz=&kcmc=&xsfs=all".data(using: .utf8)
        let (html, _) = try await html(for: request)
        if isLoginPage(html), await invalidateSessionIfNeeded() {
            throw SchoolNetworkError.sessionExpired
        }
        return html
    }

    private func fetchGraduateTimetable() async throws -> FetchedTimetableDocument {
        guard isLoggedIn else { throw URLError(.userAuthenticationRequired) }
        guard let url = URL(string: "\(graduateBaseURL)/student/pygl/py_kbcx_ew") else { throw URLError(.badURL) }
        func fetch(_ term: String?) async throws -> String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "kblx", value: "xs")]
            if let term { components.queryItems?.append(URLQueryItem(name: "termcode", value: term)) }
            let request = makeRequest(url: components.url!, referer: URL(string: "\(graduateBaseURL)/home/stulogin"))
            let (data, response) = try await self.data(for: preparedRequest(from: request))
            if let response = response as? HTTPURLResponse { updatePersistedCookies(from: response, requestURL: request.url) }
            let raw = String(data: data, encoding: .utf8) ?? ""
            if raw.contains("stulogin") || isLoginPage(raw) {
                if await invalidateSessionIfNeeded() { throw SchoolNetworkError.sessionExpired }
                throw SchoolNetworkError.timetableDataUnavailable("研究生课表返回登录页，请重新登录。")
            }
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || raw.contains("<select") { return raw }
            let decrypted = decryptGraduateAES(raw)
            guard !decrypted.isEmpty else { throw SchoolNetworkError.timetableDataUnavailable("研究生课表数据解密失败。") }
            return decrypted
        }
        let initial = try await fetch(nil)
        let options = try timetableTermOptions(in: initial, selector: "select[name=termcode] option, select[id=termcode] option")
        for term in options {
            let html = try await fetch(term)
            if !(try HTMLParser.parseTimetableResult(html: html)).records.isEmpty {
                return FetchedTimetableDocument(html: html, sourceSemesterID: term)
            }
        }
        _ = try HTMLParser.parseTimetableResult(html: initial)
        return FetchedTimetableDocument(html: initial, sourceSemesterID: "school-current")
    }
}
