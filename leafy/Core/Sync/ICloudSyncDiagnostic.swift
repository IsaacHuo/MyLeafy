import CloudKit
import Foundation

nonisolated enum ICloudSyncPhase: String {
    case idle, account, localData, assets, cloudSpace, download, merge, upload
    var title: String {
        switch self {
        case .idle: "同步 iCloud 数据"
        case .account: "检查 iCloud 账号"
        case .localData: "准备本机数据"
        case .assets: "下载并校验附件"
        case .cloudSpace: "准备云端空间"
        case .download: "读取云端更新"
        case .merge: "合并数据"
        case .upload: "上传更新"
        }
    }
}

nonisolated struct ICloudSyncDiagnostic {
    let message: String
    let details: String

    init(error: Error, phase: ICloudSyncPhase, container: String, environment: String) {
        var errors: [NSError] = []
        func collect(_ error: NSError, depth: Int) {
            guard depth < 5 else { return }
            errors.append(error)
            if let underlying = error
                .userInfo[NSUnderlyingErrorKey] as? NSError { collect(underlying, depth: depth + 1) }
            if let partial = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                for child in partial.values.prefix(8) { collect(child as NSError, depth: depth + 1) }
            }
        }
        collect(error as NSError, depth: 0)
        let cloud = errors
            .first {
                $0.domain == CKErrorDomain && $0.code != CKError.partialFailure.rawValue && $0.code != CKError
                    .batchRequestFailed.rawValue }
        let status = errors.compactMap { ($0.userInfo["CKHTTPStatus"] as? NSNumber)?.intValue }.first
        let reason: String
        switch cloud?.code {
        case CKError.serverRejectedRequest.rawValue:
            if let status, (500 ... 599).contains(status) {
                reason = "iCloud 服务返回 HTTP \(status)，暂时无法完成请求。本机数据和待同步记录已保留，请稍后重试。"
            } else {
                reason = "iCloud 服务拒绝了请求。本机数据已保留，请查看错误详情中的服务端原因。"
            }
        case CKError.missingEntitlement.rawValue, CKError.badContainer.rawValue:
            reason = "当前安装包的 iCloud 容器或签名配置不可用，需要开发者修复后重新安装。"
        case CKError.notAuthenticated.rawValue:
            reason = "无法使用当前 iCloud 账号，请检查系统设置中的 Apple 账号和 iCloud。"
        case CKError.quotaExceeded.rawValue:
            reason = "iCloud 可用空间不足，请清理或增加空间后重试。"
        case CKError.networkUnavailable.rawValue, CKError.networkFailure.rawValue:
            reason = "暂时无法连接 iCloud，请检查网络后重试。本机数据已保留。"
        default:
            reason = error.localizedDescription
        }
        message = "\(phase.title)失败：\(reason)"
        var lines = ["MyLeafy iCloud 诊断", "时间：" + ISO8601DateFormatter().string(from: Date()),
                     "阶段：" + phase.title, "容器：" + container, "环境：" + environment]
        // Only include diagnostic metadata. Never dump CKRecords, headers, tokens, or payloads.
        for item in errors {
            lines.append("\(item.domain) \(item.code)：\(item.localizedDescription)")
            for key in [
                NSLocalizedFailureReasonErrorKey,
                "CKErrorDescription",
                "ServerMessage",
                "CKHTTPStatus",
                "RequestUUID",
                "CKRequestUUID",
                "OperationID",
                CKErrorRetryAfterKey
            ] {
                if let value = item.userInfo[key] as? String { lines.append("\(key)：" + String(value.prefix(2_000))) }
                else if let value = item.userInfo[key] as? NSNumber { lines.append("\(key)：\(value)") }
            }
        }
        details = lines.joined(separator: "\n")
    }
}

@MainActor
enum ICloudZonePreparation {
    static func ensure(fetch: () async throws -> Void, create: () async throws -> Void) async throws {
        do { try await fetch() }
        catch let error as CKError where error.code == .zoneNotFound { try await create() }
    }
}
