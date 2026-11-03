import Foundation
import CommonCrypto
import Security
import SwiftSoup
import UIKit

extension SchoolNetworkManager {
    private func beginAuthenticationOperation() throws -> UUID {
        try Task.checkCancellation()
        guard authenticationOperationID == nil else {
            throw SchoolNetworkError.loginUnavailable("正在处理教务登录，请稍候再试。")
        }
        let id = UUID()
        authenticationOperationID = id
        return id
    }

    private func finishAuthenticationOperation(_ id: UUID) {
        if authenticationOperationID == id { authenticationOperationID = nil }
    }

    func cancelAuthenticationOperation() {
        if authenticationOperationID != nil { cancelInFlightRequests() }
    }

    func fetchCaptcha() async throws -> (key: String, image: UIImage) {
        try await fetchCaptcha(for: currentPortal)
    }

    func fetchCaptcha(for portal: SchoolPortal) async throws -> (key: String, image: UIImage) {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式不连接学校教务验证码。")
        }

        let operationID = try beginAuthenticationOperation()
        defer { finishAuthenticationOperation(operationID) }
        let scope = CampusOperationScope()
        let previousCookies = persistedCookieValues
        do {
            switch portal {
            case .undergraduate:
                return try await fetchUndergraduateCaptcha()
            case .graduate:
                return try await fetchGraduateCaptcha()
            }
        } catch {
            // A failed captcha request usually means the campus network/VPN is
            // unreachable. Preserve the previous session so connectivity is
            // not mistaken for a real logout.
            try scope.check()
            guard authenticationOperationID == operationID else { throw CancellationError() }
            persistedCookieValues = previousCookies
            for url in [URL(string: baseURL), URL(string: graduateBaseURL)].compactMap({ $0 }) {
                syncPersistedCookiesToStorage(for: url)
            }
            throw error
        }
    }

    private func fetchUndergraduateCaptcha() async throws -> (key: String, image: UIImage) {
        let scope = CampusOperationScope()
        guard let codeUrl = URL(string: "\(baseURL)/Logon.do?method=logon&flag=sess") else {
            throw URLError(.badURL)
        }

        clearPersistedCookies()

        let codeRequest = makeRequest(url: codeUrl)
        let (keyData, keyResponse) = try await data(for: codeRequest)
        try scope.check()
        if let httpResponse = keyResponse as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: codeUrl)
        }
        let keyString = try undergraduateLoginKey(from: keyData, response: keyResponse)

        guard let verifyUrl = URL(string: "\(baseURL)/verifycode.servlet") else {
            throw URLError(.badURL)
        }

        let verifyRequest = makeRequest(url: verifyUrl)
        let (imgData, verifyResponse) = try await data(for: preparedRequest(from: verifyRequest))
        try scope.check()
        if let httpResponse = verifyResponse as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: verifyUrl)
        }
        guard let image = UIImage(data: imgData) else {
            throw URLError(.cannotDecodeRawData)
        }

        return (keyString, image)
    }

    private func fetchGraduateCaptcha() async throws -> (key: String, image: UIImage) {
        let scope = CampusOperationScope()
        guard let loginUrl = graduateURL(path: "/home/stulogin"),
              let verifyUrl = graduateURL(path: "/home/verificationcode?codetype=stucode") else {
            throw URLError(.badURL)
        }

        clearPersistedCookies()

        let (loginHTML, loginResponse) = try await html(for: makeRequest(url: loginUrl))
        try scope.check()
        updatePersistedCookies(from: loginResponse, requestURL: loginUrl)

        let publicKey = try extractGraduatePublicKey(from: loginHTML)
        let verifyRequest = makeRequest(url: verifyUrl, referer: loginUrl)
        let (imgData, verifyResponse) = try await data(for: preparedRequest(from: verifyRequest))
        try scope.check()
        if let httpResponse = verifyResponse as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: verifyUrl)
        }
        guard let image = UIImage(data: imgData) else {
            throw URLError(.cannotDecodeRawData)
        }

        return (publicKey, image)
    }

    func refreshLoginKey() async throws -> String {
        let scope = CampusOperationScope()
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式不连接学校教务登录。")
        }

        guard let codeUrl = URL(string: "\(baseURL)/Logon.do?method=logon&flag=sess") else {
            throw URLError(.badURL)
        }

        let request = makeRequest(url: codeUrl, method: "POST", referer: URL(string: baseURL))
        let (keyData, response) = try await data(for: preparedRequest(from: request))
        try scope.check()
        if let httpResponse = response as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: codeUrl)
        }

        return try undergraduateLoginKey(from: keyData, response: response)
    }

    func performLogin(account: String, password: String, captcha: String, key: String) async throws -> Bool {
        try await performLogin(account: account, password: password, captcha: captcha, key: key, portal: currentPortal)
    }

    func performLogin(account: String, password: String, captcha: String, key: String,
                      portal: SchoolPortal) async throws -> Bool {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("请先退出演示模式，再连接校园网登录教务系统。")
        }

        let operationID = try beginAuthenticationOperation()
        defer { finishAuthenticationOperation(operationID) }
        let didLogin: Bool
        switch portal {
        case .undergraduate:
            didLogin = try await performUndergraduateLogin(account: account, password: password, captcha: captcha)
        case .graduate:
            didLogin = try await performGraduateLogin(
                account: account,
                password: password,
                captcha: captcha,
                publicKey: key
            )
        }

        if didLogin {
            _ = SchoolLoginCredentialStore.save(
                account: account,
                password: password,
                campusID: campusDescriptor.id,
                portal: portal
            )
        }
        return didLogin
    }

    private func performUndergraduateLogin(account: String, password: String, captcha: String) async throws -> Bool {
        let scope = CampusOperationScope()
        let operationID = authenticationOperationID
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveKey = try await refreshLoginKey()
        try scope.check()
        let encodedStr = try encodeKey(key: effectiveKey, account: trimmedAccount, password: password)

        guard let loginUrl = URL(string: "\(baseURL)/Logon.do?method=logon") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: loginUrl)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = formURLEncodedBody(queryItems: [
            URLQueryItem(name: "useDogCode", value: ""),
            URLQueryItem(name: "encoded", value: encodedStr),
            URLQueryItem(name: "RANDOMCODE", value: captcha.trimmingCharacters(in: .whitespacesAndNewlines))
        ])

        let (data, response) = try await data(for: preparedRequest(from: request))
        try scope.check()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SchoolNetworkError.loginUnavailable("学校登录响应无效，请刷新验证码后重试。")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw SchoolNetworkError.loginUnavailable("学校登录服务暂时不可用（HTTP \(httpResponse.statusCode)），请稍后重试。")
        }
        updatePersistedCookies(from: httpResponse, requestURL: loginUrl)
        persistLandingURL(httpResponse.url)

        let html = try decodedHTML(from: data)
        if let message = extractLoginMessage(from: html) {
            throw SchoolNetworkError.loginFailed(message)
        }
        let loggedInFromSessionCheck = try await verifyUndergraduateLoginSession()
        try scope.check()
        guard authenticationOperationID == operationID else { throw CancellationError() }

        if loggedInFromSessionCheck {
            currentPortal = .undergraduate
            persistAuthenticatedIdentity(eduID: trimmedAccount)
            isLoggedIn = true
            return true
        }

        if isLoginPage(html) {
            throw SchoolNetworkError.loginUnavailable(
                "登录未成功，服务端仍返回登录页。" +
                    pageDebugSummary(
                        html: html,
                        responseURL: httpResponse.url,
                        snapshotName: "last_login_failed_page.html"
                    )
            )
        }

        throw SchoolNetworkError.loginUnavailable("登录请求已发送，但未能确认登录成功。请刷新验证码后重试。")
    }

    private func performGraduateLogin(account: String, password: String, captcha: String,
                                      publicKey: String) async throws -> Bool {
        let scope = CampusOperationScope()
        let operationID = authenticationOperationID
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let loginUrl = graduateURL(path: "/home/stulogin_do"),
              let refererURL = graduateURL(path: "/home/stulogin"),
              let nameURL = graduateURL(path: "/student/default/getxscardinfo") else {
            throw URLError(.badURL)
        }

        let encryptedPassword = try encryptGraduatePassword(password, publicKeyPEM: publicKey)
        let verification = captcha.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadObject: [String: Any] = [
            "UserId": trimmedAccount,
            "Password": encryptedPassword,
            "VeriCode": Int(verification) ?? verification,
            "url": "",
            "city": ""
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject)
        guard let payload = String(data: payloadData, encoding: .utf8) else {
            throw URLError(.cannotCreateFile)
        }

        var request = makeRequest(url: loginUrl, method: "POST", referer: refererURL)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        request.httpBody = formURLEncodedBody(queryItems: [
            URLQueryItem(name: "json", value: payload)
        ])

        let (data, response) = try await data(for: preparedRequest(from: request))
        try scope.check()
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        updatePersistedCookies(from: httpResponse, requestURL: loginUrl)

        let rawBody = String(data: data, encoding: .utf8) ?? ""
        let decryptedBody = decryptGraduateAES(rawBody)
        _ = try parseGraduateLoginRedirect(
            from: decryptedBody,
            rawBody: rawBody,
            responseURL: httpResponse.url,
            statusCode: httpResponse.statusCode
        )

        let displayName = (try? await fetchGraduateDisplayName(from: nameURL)) ?? trimmedAccount
        try scope.check()
        guard authenticationOperationID == operationID else { throw CancellationError() }
        currentPortal = .graduate
        persistAuthenticatedIdentity(eduID: trimmedAccount, displayName: displayName)
        isLoggedIn = true
        return true
    }

    private func verifyUndergraduateLoginSession() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/jsxsd/framework/xsMain.jsp") else { throw URLError(.badURL) }
        for attempt in 0 ... 2 {
            let (page, _) = try await html(from: url)
            if isAuthenticatedResponse(url: nil, html: page) { return true }
            if attempt < 2 { try await Task.sleep(for: .milliseconds(300)) }
        }
        return false
    }

    private func undergraduateLoginKey(from data: Data, response: URLResponse) throws -> String {
        guard let response = response as? HTTPURLResponse, (200 ... 299).contains(response.statusCode) else {
            throw SchoolNetworkError.loginUnavailable("学校登录服务暂时不可用，请刷新验证码后重试。")
        }
        let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _ = try undergraduateKeyParts(key)
        return key
    }

    private func undergraduateKeyParts(_ key: String) throws -> (secret: [UInt16], shifts: [UInt16]) {
        let parts = key.components(separatedBy: "#")
        guard parts.count == 2, !parts[0].isEmpty, !parts[0].contains("<"), !parts[0].contains(">"),
              !parts[1].isEmpty, parts[1].utf16.allSatisfy({ (48 ... 57).contains($0) }) else {
            throw SchoolNetworkError.loginUnavailable("学校登录密钥无效，请刷新验证码后重试。")
        }
        return (Array(parts[0].utf16), Array(parts[1].utf16))
    }

    func encodeKey(key: String, account: String, password: String) throws -> String {
        let (secret, shifts) = try undergraduateKeyParts(key)
        let code = Array((account + "%%%" + password).utf16)
        var encoded: [UInt16] = []
        var secretOffset = 0
        for index in code.indices {
            encoded.append(code[index])
            if index < 20, index < shifts.count {
                let end = min(secretOffset + Int(shifts[index] - 48), secret.count)
                encoded.append(contentsOf: secret[secretOffset ..< end])
                secretOffset = end
            }
        }
        return String(decoding: encoded, as: UTF16.self)
    }

    func formURLEncodedBody(queryItems: [URLQueryItem]) -> Data {
        var components = URLComponents()
        components.queryItems = queryItems
        let bodyString = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        return Data(bodyString.utf8)
    }
}

extension SchoolNetworkManager {
    var graduateAESKey: String { "southsoft12345!#" }

    func graduateURL(path: String) -> URL? {
        URL(string: "\(graduateBaseURL)\(path)")
    }

    func extractGraduatePublicKey(from html: String) throws -> String {
        let document = try SwiftSoup.parse(html)
        let value = try document.select("#pubkey").first()?.attr("value")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            throw SchoolNetworkError.loginFailed("研究生系统未返回登录公钥，请刷新验证码后重试。")
        }
        return value
    }

    func encryptGraduatePassword(_ password: String, publicKeyPEM: String) throws -> String {
        let key = try makeGraduateRSAKey(publicKeyPEM)
        guard SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1) else {
            throw SchoolNetworkError.loginFailed("当前设备不支持研究生系统密码加密方式。")
        }

        let plainData = Data(password.utf8) as CFData
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, plainData, &error) else {
            throw error?.takeRetainedValue() as Error? ?? SchoolNetworkError.loginFailed("研究生系统密码加密失败。")
        }

        return (encrypted as Data).base64EncodedString()
    }

    func makeGraduateRSAKey(_ publicKeyPEM: String) throws -> SecKey {
        let normalized = publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        guard let keyData = Data(base64Encoded: normalized) else {
            throw SchoolNetworkError.loginFailed("研究生系统登录公钥格式异常。")
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 2048
        ]
        var error: Unmanaged<CFError>?
        if let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) {
            return key
        }

        let stripped = stripSubjectPublicKeyInfoHeader(from: keyData)
        guard stripped != keyData else {
            throw error?.takeRetainedValue() as Error? ?? SchoolNetworkError.loginFailed("研究生系统登录公钥不可用。")
        }

        if let key = SecKeyCreateWithData(stripped as CFData, attributes as CFDictionary, &error) {
            return key
        }

        throw error?.takeRetainedValue() as Error? ?? SchoolNetworkError.loginFailed("研究生系统登录公钥不可用。")
    }

    func stripSubjectPublicKeyInfoHeader(from data: Data) -> Data {
        let bytes = [UInt8](data)
        let rsaEncryptionOID: [UInt8] = [
            0x30,
            0x0d,
            0x06,
            0x09,
            0x2a,
            0x86,
            0x48,
            0x86,
            0xf7,
            0x0d,
            0x01,
            0x01,
            0x01,
            0x05,
            0x00,
            0x03
        ]
        guard let oidRange = bytes.firstRange(of: rsaEncryptionOID) else { return data }
        var index = oidRange.upperBound
        guard index < bytes.count else { return data }

        if bytes[index] == 0x82 {
            index += 3
        } else if bytes[index] == 0x81 {
            index += 2
        } else {
            index += 1
        }

        guard index < bytes.count, bytes[index] == 0x00 else { return data }
        index += 1
        return Data(bytes[index ..< bytes.count])
    }

    func decryptGraduateAES(_ cipherText: String) -> String {
        let cipherText = cipherText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentinel = Data("==gwJPTxzG0iY2qTiSUo7wB6".utf8).base64EncodedString()
        if cipherText == sentinel {
            return "-"
        }

        guard let cipherData = Data(base64Encoded: cipherText),
              let keyData = graduateAESKey.data(using: .utf8) else {
            return ""
        }

        return decryptGraduateAESECB(cipherData: cipherData, keyData: keyData)
    }

    func decryptGraduateAESECB(cipherData: Data, keyData: Data) -> String {
        let blockSize = kCCBlockSizeAES128
        let outputLength = cipherData.count + blockSize
        var output = Data(count: outputLength)
        var decryptedLength: size_t = 0

        let result = output.withUnsafeMutableBytes { outputBytes in
            cipherData.withUnsafeBytes { cipherBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        keyData.count,
                        nil,
                        cipherBytes.baseAddress,
                        cipherData.count,
                        outputBytes.baseAddress,
                        outputLength,
                        &decryptedLength
                    )
                }
            }
        }

        guard result == kCCSuccess else { return "" }
        output.removeSubrange(decryptedLength ..< output.count)
        return String(data: output, encoding: .utf8) ?? ""
    }

    func parseGraduateLoginRedirect(
        from decryptedBody: String,
        rawBody: String? = nil,
        responseURL: URL? = nil,
        statusCode: Int? = nil
    ) throws -> String {
        let trimmed = decryptedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SchoolNetworkError.loginFailed(
                "研究生系统登录响应无法解密。" +
                    graduateLoginDebugSummary(rawBody: rawBody, responseURL: responseURL, statusCode: statusCode)
            )
        }

        guard let bodyData = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            throw SchoolNetworkError.loginFailed(
                "研究生系统登录响应格式异常。" +
                    graduateLoginDebugSummary(
                        rawBody: rawBody ?? trimmed,
                        responseURL: responseURL,
                        statusCode: statusCode
                    )
            )
        }

        let status = graduateJSONValue(object["jg"])
        let message = graduateJSONValue(object["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let redirect = graduateJSONValue(object["url"]).trimmingCharacters(in: .whitespacesAndNewlines)

        if status == "1", !redirect.isEmpty {
            return redirect
        }

        if !message.isEmpty {
            throw SchoolNetworkError.loginFailed(message)
        }

        throw SchoolNetworkError.loginFailed(
            "研究生系统未确认登录成功，请刷新验证码后重试。" +
                graduateLoginDebugSummary(rawBody: rawBody ?? trimmed, responseURL: responseURL, statusCode: statusCode)
        )
    }

    func graduateJSONValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }

    func graduateLoginDebugSummary(rawBody: String?, responseURL: URL?, statusCode: Int?) -> String {
        let urlPart = responseURL?.absoluteString ?? "unknown"
        let statusPart = statusCode.map(String.init) ?? "unknown"

        #if DEBUG
            let snapshotName = "last_graduate_login_response.txt"
            let savedURL = rawBody.flatMap { persistDebugHTML($0, filename: snapshotName) }
            let filePart = savedURL?.lastPathComponent ?? snapshotName
            return L10n.text("HTTP: %@，URL: %@，调试文件: %@", statusPart, urlPart, filePart)
        #else
            return L10n.text("HTTP: %@，URL: %@。请确认校园网连接，或刷新验证码后重试。", statusPart, urlPart)
        #endif
    }

    func fetchGraduateDisplayName(
        from url: URL,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> String {
        let scope = CampusOperationScope()
        var request = makeRequest(url: url, method: "POST", referer: graduateURL(path: "/home/stulogin"))
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await data(for: preparedRequest(from: request))
        try scope.check()
        if let httpResponse = response as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: url)
        }

        let rawBody = String(data: data, encoding: .utf8) ?? ""
        if response.url?.path.lowercased().contains("stulogin") == true ||
            rawBody.lowercased().contains("stulogin") ||
            rawBody.lowercased().contains("</script>") {
            throw SchoolNetworkError.sessionExpired
        }
        let decryptedBody = decryptGraduateAES(rawBody)
        guard let bodyData = decryptedBody.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: bodyData) as? [[String: Any]],
              let name = array.first?["xm"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func verifyGraduateAuthenticatedSession(retryCount: Int) async -> Bool {
        guard let url = graduateURL(path: "/student/default/getxscardinfo") else {
            return false
        }

        let scope = CampusOperationScope()
        for attempt in 0 ... max(0, retryCount) {
            guard scope.isCurrent, !Task.isCancelled else { return false }
            do {
                _ = try await fetchGraduateDisplayName(from: url)
                return scope.isCurrent && !Task.isCancelled
            } catch {
            }

            if attempt < retryCount {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        return false
    }
}
