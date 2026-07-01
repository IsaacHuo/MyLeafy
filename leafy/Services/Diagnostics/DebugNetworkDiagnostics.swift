import Foundation

#if DEBUG
enum DebugNetworkDiagnostics {
    static func runStartupProbe() {
        Task.detached {
            guard let config = try? LeafySupabase.shared.requireConfig() else {
                print("[DebugNetworkDiagnostics] Supabase config unavailable")
                return
            }

            await probe(name: "Supabase REST", url: config.url.appending(path: "rest/v1/"))
        }
    }

    private static func probe(name: String, url: URL) async {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let state = (200..<300).contains(status) ? "OK" : "FAILED"
            print("[DebugNetworkDiagnostics] \(name) \(state) status=\(status) url=\(url.absoluteString)")
        } catch {
            let nsError = error as NSError
            print("[DebugNetworkDiagnostics] \(name) FAILED domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription) url=\(url.absoluteString)")
            if let failingURL = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] {
                print("[DebugNetworkDiagnostics] \(name) failingURL=\(failingURL)")
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] {
                print("[DebugNetworkDiagnostics] \(name) underlying=\(underlying)")
            }
        }
    }
}
#endif
