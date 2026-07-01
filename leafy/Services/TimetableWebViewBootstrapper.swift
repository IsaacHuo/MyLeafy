import Foundation
import WebKit

struct RenderedTimetableBootstrap {
    let html: String
    let url: URL?
    let frameSources: [String]
}

@MainActor
final class TimetableWebViewBootstrapper: NSObject, WKNavigationDelegate {
    private let manager: SchoolNetworkManager
    private let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(manager: SchoolNetworkManager) {
        self.manager = manager

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()
        self.webView.navigationDelegate = self
        self.webView.isHidden = true
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
    }

    func bootstrap() async throws -> RenderedTimetableBootstrap {
        guard let timetableURL = URL(string: "\(manager.baseURL)/jsxsd/xskb/xskb_list.do"),
              let mainURL = URL(string: "\(manager.baseURL)/jsxsd/framework/xsMain.jsp") else {
            throw URLError(.badURL)
        }

        try await syncCookies(for: timetableURL)
        try await load(url: timetableURL)
        try await pause(milliseconds: 1200)

        let directHTML = try await captureBestHTML()
        let directFrames = try await captureFrameSources()
        if manager.isTimetablePage(directHTML) {
            return RenderedTimetableBootstrap(html: directHTML, url: webView.url, frameSources: directFrames)
        }

        try await syncCookies(for: mainURL)
        try await load(url: mainURL)
        try await pause(milliseconds: 800)
        _ = try? await evaluate(script: Self.expandTimetableMenuScript)
        try await pause(milliseconds: 1000)

        let html = try await captureBestHTML()
        let frameSources = try await captureFrameSources()
        return RenderedTimetableBootstrap(html: html, url: webView.url, frameSources: frameSources)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    private func load(url: URL) async throws {
        let request = manager.makeRequest(url: url, referer: URL(string: manager.baseURL))
        webView.load(request)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationContinuation = continuation
        }
    }

    private func syncCookies(for url: URL) async throws {
        manager.syncPersistedCookiesToStorage(for: url)
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        let cookies = HTTPCookieStorage.shared.cookies?.filter { cookie in
            guard let host = url.host else { return true }
            return cookie.domain.contains(host) || host.contains(cookie.domain.replacingOccurrences(of: ".", with: ""))
        } ?? []

        for cookie in cookies {
            await withCheckedContinuation { continuation in
                cookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    private func evaluate(script: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result as Any)
            }
        }
    }

    private func captureBestHTML() async throws -> String {
        let script = """
        (() => {
          const isTimetable = (html) => /id=["']kbtable["']|kbcontent_|class=["']kbcontent["']/.test(html || "");
          const frames = Array.from(document.querySelectorAll('iframe,frame'));
          for (const frame of frames) {
            try {
              const doc = frame.contentDocument;
              if (!doc || !doc.documentElement) continue;
              const html = doc.documentElement.outerHTML || "";
              if (isTimetable(html)) return html;
            } catch (e) {}
          }
          return document.documentElement ? document.documentElement.outerHTML : "";
        })();
        """

        let result = try await evaluate(script: script)
        return result as? String ?? ""
    }

    private func captureFrameSources() async throws -> [String] {
        let script = """
        (() => JSON.stringify(
          Array.from(document.querySelectorAll('iframe,frame'))
            .map(frame => frame.getAttribute('src') || frame.src || '')
            .filter(Boolean)
        ))();
        """

        let result = try await evaluate(script: script)
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return values
    }

    private func pause(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private static let expandTimetableMenuScript = """
    (() => {
      const norm = (value) => (value || '').replace(/\\s+/g, '');
      const clickFirst = (labels) => {
        const nodes = Array.from(document.querySelectorAll('li,a,span,div,button'));
        const target = nodes.find(node => {
          const combined = `${norm(node.textContent)} ${norm(node.getAttribute('title'))}`;
          return labels.some(label => combined.includes(label));
        });
        if (target && typeof target.click === 'function') {
          target.click();
          return true;
        }
        return false;
      };

      clickFirst(['培养管理']);
      clickFirst(['本人课表', '学生课表', '学期理论课表']);
      return true;
    })();
    """
}
