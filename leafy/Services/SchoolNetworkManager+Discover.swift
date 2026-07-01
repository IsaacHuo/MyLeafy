import Foundation
import OSLog
import SwiftSoup

extension SchoolNetworkManager {
    private enum ClassroomUsageLookupResult {
        case slot(ClassroomUsageSlot)
        case reauthenticationNeeded(Error)
    }

    func fetchExamSchedule() async throws -> String {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式使用本地考试安排样例，不连接学校教务系统。")
        }

        try requireUndergraduatePortal(for: "考试安排")

        guard isLoggedIn else { throw URLError(.userAuthenticationRequired) }
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()
        guard let url = URL(string: "\(baseURL)/jsxsd/xsks/xsksap_list") else {
            throw URLError(.badURL)
        }

        var request = makeRequest(url: url, method: "POST", referer: URL(string: "\(baseURL)/jsxsd/framework/xsMain.jsp"))
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "xqlbmc", value: ""),
            URLQueryItem(name: "xnxqid", value: semesterConfig.semesterID),
            URLQueryItem(name: "xqlb", value: "")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let referer = URL(string: "\(baseURL)/jsxsd/framework/xsMain.jsp")
        let requests = mergeCandidateRequests(
            [request] +
            examScheduleDirectCandidateRequests(referer: referer)
        )

        var lastHTML = ""
        var lastResponse: HTTPURLResponse?

        for candidate in requests {
            let (html, response) = try await html(for: candidate)
            lastHTML = html
            lastResponse = response

            if isLoginPage(html) {
                continue
            }

            if isExamSchedulePage(html) {
                _ = persistDebugHTML(html, filename: "last_exam_schedule_page.html")
                return html
            }
        }

        if isLoginPage(lastHTML) {
            if await invalidateSessionIfNeeded() {
                throw SchoolNetworkError.sessionExpired
            }
            throw SchoolNetworkError.loginFailed(
                L10n.text("考试安排页面返回了登录页。") +
                pageDebugSummary(html: lastHTML, responseURL: lastResponse?.url, snapshotName: "last_exam_login_page.html")
            )
        }

        throw SchoolNetworkError.featureUnavailable(
            L10n.text("考试安排页面未返回可解析的数据。") +
            pageDebugSummary(html: lastHTML, responseURL: lastResponse?.url, snapshotName: "last_exam_unexpected_page.html")
        )
    }

    func fetchTeachingPlan() async throws -> String {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式使用本地教学计划样例，不连接学校教务系统。")
        }

        try requireUndergraduatePortal(for: "培养方案")

        guard isLoggedIn else { throw URLError(.userAuthenticationRequired) }
        guard let url = URL(string: "\(baseURL)/jsxsd/pyfa/pyfa_query") else {
            throw URLError(.badURL)
        }

        let request = makeRequest(url: url, referer: URL(string: "\(baseURL)/jsxsd/framework/xsMain.jsp"))
        let (html, response) = try await html(for: request)
        if isLoginPage(html) {
            if await invalidateSessionIfNeeded() {
                throw SchoolNetworkError.sessionExpired
            }
            throw SchoolNetworkError.loginFailed(
                L10n.text("教学计划页面返回了登录页。") +
                pageDebugSummary(html: html, responseURL: response.url, snapshotName: "last_plan_login_page.html")
            )
        }
        return html
    }

    func fetchGraduationRequirements() async throws -> String {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式使用本地培养方案样例，不连接学校教务系统。")
        }

        try requireUndergraduatePortal(for: "培养方案明细")

        guard isLoggedIn else { throw URLError(.userAuthenticationRequired) }
        guard let url = URL(string: "\(baseURL)/jsxsd/pyfa/pyfazd_query") else {
            throw URLError(.badURL)
        }

        let request = makeRequest(url: url, referer: URL(string: "\(baseURL)/jsxsd/framework/xsMain.jsp"))
        let (html, response) = try await html(for: request)
        if isLoginPage(html) {
            if await invalidateSessionIfNeeded() {
                throw SchoolNetworkError.sessionExpired
            }
            throw SchoolNetworkError.loginFailed(
                L10n.text("培养方案明细页面返回了登录页。") +
                pageDebugSummary(html: html, responseURL: response.url, snapshotName: "last_graduation_requirements_login_page.html")
            )
        }
        return html
    }

    func fetchGradeRankings() async throws -> String {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式使用本地排名样例，不连接学校教务系统。")
        }

        try requireUndergraduatePortal(for: "成绩排名")

        guard isLoggedIn else { throw URLError(.userAuthenticationRequired) }
        let html = try await fetchGrades()
        do {
            _ = try HTMLParser.parseGradeRankings(html: html)
            return html
        } catch {
            throw SchoolNetworkError.featureUnavailable(L10n.text("教务暂未开放成绩排名。"))
        }
    }

    private func gradeRankingDirectCandidateRequests(referer: URL) -> [URLRequest] {
        [
            "/jsxsd/kscj/cjpm_query",
            "/jsxsd/kscj/cjpm_list",
            "/jsxsd/kscj/cjpmcx_query",
            "/jsxsd/kscj/cjpmcx_list",
            "/jsxsd/kscj/cjcx_pm"
        ].compactMap { path in
            URL(string: "\(baseURL)\(path)").map {
                makeRequest(url: $0, referer: referer)
            }
        }
    }

    private func mergeCandidateRequests(_ requests: [URLRequest]) -> [URLRequest] {
        var seen = Set<String>()
        var result: [URLRequest] = []

        for request in requests {
            guard let urlString = request.url?.absoluteString,
                  !seen.contains(urlString) else {
                continue
            }
            seen.insert(urlString)
            result.append(request)
        }

        return result
    }

    private func examScheduleDirectCandidateRequests(referer: URL?) -> [URLRequest] {
        [
            "/jsxsd/xsks/xsksap_list",
            "/jsxsd/xsks/xsksap_query",
            "/jsxsd/xsks/xskscx_list",
            "/jsxsd/xsks/xskscx_query"
        ].compactMap { path in
            guard let url = URL(string: "\(baseURL)\(path)") else { return nil }
            return makeRequest(url: url, method: "GET", referer: referer)
        }
    }

    private func isExamSchedulePage(_ html: String) -> Bool {
        (html.contains("id=\"dataList\"") || html.contains("id='dataList'")) &&
        (
            html.contains("考试") ||
            html.contains("ksap") ||
            html.contains("xsks")
        )
    }

    private func isEmptyClassroomPage(_ html: String) -> Bool {
        (html.contains("id=\"dataList\"") || html.contains("id='dataList'")) &&
        (
            html.contains("项目列表") ||
            html.contains("jsjy_query2") ||
            html.contains("教室")
        )
    }

    private func extractGradeRankingCandidateRequests(from html: String, baseURL: URL) throws -> [URLRequest] {
        let document = try SwiftSoup.parse(html, baseURL.absoluteString)
        var candidates: [URLRequest] = []
        var seen = Set<String>()

        func appendURLString(_ rawValue: String, referer: URL) {
            let cleaned = rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
            guard !cleaned.isEmpty,
                  let url = URL(string: cleaned, relativeTo: baseURL)?.absoluteURL else {
                return
            }

            let absolute = url.absoluteString
            guard !seen.contains(absolute) else { return }
            guard absolute.contains("/jsxsd/") else { return }
            seen.insert(absolute)
            candidates.append(makeRequest(url: url, referer: referer))
        }

        func inspect(_ text: String, referer: URL) {
            let patterns = [
                #"(https?://[^'"\s)]+)"#,
                #"(/jsxsd/[^'"\s)]+)"#,
                #"['"]([^'"]*kscj[^'"]*(?:pm|rank|cjpm|排名)[^'"]*)['"]"#
            ]

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }
                let range = NSRange(text.startIndex..., in: text)
                for match in regex.matches(in: text, range: range) {
                    guard match.numberOfRanges > 1,
                          let captureRange = Range(match.range(at: 1), in: text) else {
                        continue
                    }
                    appendURLString(String(text[captureRange]), referer: referer)
                }
            }
        }

        let rankingLabels = ["成绩排名", "排名查询", "成绩排名查询"]
        for element in try document.select("a,span,li,div").array() {
            let text = try element.text()
            let html = (try? element.outerHtml()) ?? ""
            guard rankingLabels.contains(where: { text.contains($0) || html.contains($0) }) else {
                continue
            }

            appendURLString(try element.attr("href"), referer: baseURL)
            inspect(try element.attr("onclick"), referer: baseURL)
            inspect(html, referer: baseURL)
            if let parent = element.parent() {
                inspect((try? parent.outerHtml()) ?? "", referer: baseURL)
            }
        }

        return candidates
    }

    func fetchEmptyClassrooms(date: Date, start: Int, end: Int) async throws -> String {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式使用本地空教室样例，不连接学校教务系统。")
        }

        try requireUndergraduatePortal(for: "空教室查询")

        guard isLoggedIn else { throw URLError(.userAuthenticationRequired) }
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()
        let schedule = SemesterConfig.weekAndDay(for: date, config: semesterConfig)
        let dateString = DateFormatters.queryDate.string(from: date)

        let path = "\(baseURL)/jsxsd/kbxx/jsjy_query2"
        guard var components = URLComponents(string: path) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "xnxqh", value: semesterConfig.semesterID),
            URLQueryItem(name: "zc", value: String(schedule.week)),
            URLQueryItem(name: "zc2", value: String(schedule.week)),
            URLQueryItem(name: "jc", value: String(start)),
            URLQueryItem(name: "jc2", value: String(end)),
            URLQueryItem(name: "xqbh", value: ""),
            URLQueryItem(name: "jxqbh", value: ""),
            URLQueryItem(name: "jxlbh", value: ""),
            URLQueryItem(name: "jsbh", value: ""),
            URLQueryItem(name: "bjfh", value: ""),
            URLQueryItem(name: "rnrs", value: ""),
            URLQueryItem(name: "xnxqhmc", value: ""),
            URLQueryItem(name: "xq", value: String(schedule.day)),
            URLQueryItem(name: "xq2", value: String(schedule.day)),
            URLQueryItem(name: "jszt", value: "5")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = makeRequest(url: url, referer: URL(string: "\(baseURL)/jsxsd/framework/xsMain.jsp"))
        let (html, response) = try await html(for: request)
        if isLoginPage(html) {
            if await invalidateSessionIfNeeded() {
                throw SchoolNetworkError.sessionExpired
            }
            throw SchoolNetworkError.loginFailed(
                L10n.text("空教室页面返回了登录页（%@ %d-%d节）。", dateString, start, end) +
                pageDebugSummary(html: html, responseURL: response.url, snapshotName: "last_classroom_login_page.html")
            )
        }
        guard isEmptyClassroomPage(html) else {
            throw SchoolNetworkError.classroomDataUnavailable(
                L10n.text("（%@ %d-%d节）。", dateString, start, end) +
                pageDebugSummary(
                    html: html,
                    responseURL: response.url,
                    snapshotName: "last_classroom_unexpected_\(dateString)_\(start)_\(end).html"
                )
            )
        }
        return html
    }

    func fetchClassroomUsage(date: Date, building: String, room: String) async throws -> [ClassroomUsageSlot] {
        if ReviewDemoMode.isEnabled {
            return ReviewDemoDataSeeder.classroomUsage(for: date, building: building, room: room)
        }

        try requireUndergraduatePortal(for: "空教室查询")

        let target = ClassroomIdentity(building: building, room: room)
        let log = Logger(subsystem: "com.isaachuo.leafy", category: "ClassroomLookup")
        return try await withThrowingTaskGroup(of: ClassroomUsageLookupResult.self) { group in
            for period in 1...12 {
                group.addTask {
                    do {
                        let html = try await self.fetchEmptyClassrooms(date: date, start: period, end: period)
                        let rooms = try await MainActor.run {
                            try HTMLParser.parseEmptyClassrooms(html: html)
                        }
                        let status = ClassroomUsageStatusResolver.status(
                            html: html,
                            parsedRooms: rooms,
                            target: target,
                            rawBuilding: building,
                            rawRoom: room
                        )
                        log.info(
                            "Classroom usage period=\(period) target=\(target.building, privacy: .public)-\(target.room, privacy: .public) parsedRooms=\(rooms.count) status=\(status.rawValue, privacy: .public)"
                        )
                        return .slot(ClassroomUsageSlot(period: period, status: status))
                    } catch {
                        if ClassroomLookupReauthentication.requiresReauthentication(error) {
                            return .reauthenticationNeeded(error)
                        }
                        log.error(
                            "Classroom usage period=\(period) target=\(target.building, privacy: .public)-\(target.room, privacy: .public) status=unknown error=\(error.localizedDescription, privacy: .public)"
                        )
                        return .slot(ClassroomUsageSlot(period: period, status: .unknown))
                    }
                }
            }

            var result: [ClassroomUsageSlot] = []
            for try await lookupResult in group {
                switch lookupResult {
                case .slot(let slot):
                    result.append(slot)
                case .reauthenticationNeeded(let error):
                    group.cancelAll()
                    throw error
                }
            }
            return result.sorted { $0.period < $1.period }
        }
    }

    func calendarAssets() -> [CalendarAsset] {
        guard let calendarURL = URL(string: "\(baseURL)/images/xiaoli.jpg"),
              let timetableURL = URL(string: "\(baseURL)/images/schooltime.jpg") else {
            return []
        }

        return [
            CalendarAsset(id: "calendar", title: L10n.text("校历"), subtitle: L10n.text("官方学年校历"), url: calendarURL),
            CalendarAsset(id: "time", title: L10n.text("作息时间"), subtitle: L10n.text("上课节次与时间"), url: timetableURL)
        ]
    }
}
