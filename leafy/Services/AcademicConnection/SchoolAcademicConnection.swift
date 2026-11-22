import Combine
import Foundation

/// One student's current user action. School parsers and identity validation stay in SchoolNetworkManager.
@MainActor
final class SchoolAcademicConnection: ObservableObject {
    @TaskLocal private static var actionID: UUID?

    weak var manager: SchoolNetworkManager?
    @Published private(set) var cleanupWarning: String?
    @Published private(set) var isConnected = false
    private let settings: SchoolVPNSettingsStore
    private let clientProvider: @MainActor () throws -> any AcademicConnectorServicing
    private let identityProvider: @MainActor () -> CampusIdentity?
    private let willActivate: @MainActor (CampusIdentity) -> Void
    private var credentialOwner: CampusIdentity?
    private var expectedIdentity: CampusIdentity?
    private var client: (any AcademicConnectorServicing)?
    private var lease: AcademicConnectorLease?
    private var creating: Task<AcademicConnectorLease, Error>?
    private var creationID: UUID?
    private var closing: Task<AcademicConnectorCloseResult, Never>?
    private var requests: [UUID: Task<AcademicSchoolResponse, Error>] = [:]
    private var tail: Task<Void, Never>?
    private var currentID: UUID?
    private var currentKind: AcademicOperationKind?
    private var awaitingAuthentication = false
    private var executing = false
    private var cancelled = false
    private var settingsRevision: UInt64 = 0
    private var beganBeforeIdentity = false
    var actionIdentifier: UUID? { currentID }

    init(
        settings: SchoolVPNSettingsStore,
        credentialOwner: CampusIdentity?,
        client: @escaping @MainActor () throws -> any AcademicConnectorServicing,
        identity: @escaping @MainActor () -> CampusIdentity? = { CampusIdentityStore.currentIdentity() },
        willActivate: @escaping @MainActor (CampusIdentity) -> Void = { _ in }
    ) {
        self.settings = settings
        self.credentialOwner = credentialOwner
        clientProvider = client
        identityProvider = identity
        expectedIdentity = identity()
        self.willActivate = willActivate
    }

    func prepareRecovery(_ kind: AcademicOperationKind) throws {
        if currentID == nil { begin(kind) }
        guard !executing, currentKind == kind else { throw busy() }
        awaitingAuthentication = true
    }

    func perform<T>(
        kind: AcademicOperationKind?,
        retainingForLogin: Bool = false,
        operation: @MainActor () async throws -> T
    ) async throws -> T {
        if let currentID, Self.actionID == currentID { return try await operation() }
        if cancelled { await finish() }
        if currentID == nil { begin(kind) }
        guard let id = currentID, !executing,
              currentKind == kind || (kind == nil && awaitingAuthentication)
        else { throw busy() }
        executing = true
        do {
            let result = try await Self.$actionID.withValue(id) {
                try await ensureLease(id)
                return try await operation()
            }
            try requireCurrent(id)
            executing = false
            if retainingForLogin || (kind == nil && currentKind != nil) {
                awaitingAuthentication = true
            } else {
                await finish(expectedID: id)
            }
            return result
        } catch {
            guard currentID == id else { throw CancellationError() }
            executing = false
            let recovery = SchoolReauthentication.requiresReauthentication(error)
                || (kind == nil && error is SchoolNetworkError)
            if recovery, !Task.isCancelled, !cancelled {
                awaitingAuthentication = true
            } else { await finish(expectedID: id) }
            throw error
        }
    }

    private func begin(_ kind: AcademicOperationKind?) {
        currentID = UUID()
        currentKind = kind
        settingsRevision = settings.revision
        beganBeforeIdentity = identityProvider() == nil
        expectedIdentity = identityProvider()
        awaitingAuthentication = false
        executing = false
        cancelled = false
        cleanupWarning = nil
    }

    private func requireCurrent(_ id: UUID) throws {
        try Task.checkCancellation()
        guard currentID == id, !cancelled, expectedIdentity?.scopeKey == identityProvider()?.scopeKey else {
            throw CancellationError()
        }
    }

    private func ensureLease(_ id: UUID) async throws {
        try requireCurrent(id)
        if lease != nil { return }
        if let closing { _ = await closing.value; try requireCurrent(id) }
        let api: any AcademicConnectorServicing
        if let client { api = client } else { api = try clientProvider(); client = api }
        if creating == nil {
            guard let credential = try settings.credential(for: credentialOwner) else {
                throw AcademicConnectorFailure(
                    status: 0,
                    code: "vpn_credentials_required",
                    message: "请先填写北林 VPN 账号和密码，再继续同步。",
                    requestID: nil
                )
            }
            let cookies = manager?.persistedCookieValues ?? [:]
            creationID = UUID()
            creating = Task { try await api.start(credential: credential, cookies: cookies) }
        }
        guard let job = creating else { throw CancellationError() }
        let pendingID = creationID
        let value = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        do { try requireCurrent(id) }
        catch {
            if creationID == pendingID {
                lease = value
                creating = nil
                creationID = nil
                await finish(expectedID: id)
            }
            throw error
        }
        lease = value
        creating = nil
        creationID = nil
        isConnected = true
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let id = currentID, Self.actionID == id, let api = client, let lease else {
            throw AcademicConnectorFailure(
                status: 0,
                code: "academic_manual_action_required",
                message: "请点击同步或下拉刷新后再连接教务。",
                requestID: nil
            )
        }
        try requireCurrent(id)
        let scope = CampusOperationScope()
        let previous = tail
        let requestID = UUID()
        let job = Task { @MainActor [self] in
            if let previous { await previous.value }
            try requireCurrent(id)
            try scope.check()
            let input = try AcademicSchoolRequest(request: request, cookies: manager?.persistedCookieValues ?? [:])
            let result = try await api.execute(input, lease: lease)
            try requireCurrent(id)
            try scope.check()
            // This check must precede persistence; an old response cannot write another identity's cookie jar.
            manager?.replaceTransportCookies(result.cookies)
            return result
        }
        requests[requestID] = job
        tail = Task { _ = try? await job.value }
        defer { requests.removeValue(forKey: requestID) }
        let value = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        guard let response = value.response else { throw AcademicConnectorFailure.invalidResponse }
        return (value.data, response)
    }

    func activateVerifiedIdentity(_ identity: CampusIdentity) {
        expectedIdentity = identity
        credentialOwner = identity
        do { try settings.bindPendingLogin(to: identity) }
        catch {
            let message = "教务登录成功，但 VPN 凭据未能保存，请在“教务连接”中重新设置。"
            settings.storageWarning = message
            cleanupWarning = message
        }
        willActivate(identity)
    }

    func cancel(matching expectedID: UUID? = nil) {
        guard let id = currentID, expectedID == nil || expectedID == id else { return }
        cancelled = true
        creating?.cancel()
        for job in requests.values { job.cancel() }
        Task { await finish(expectedID: id) }
    }

    func finish(expectedID: UUID? = nil) async {
        guard currentID != nil else {
            if let closing { _ = await closing.value }
            return
        }
        guard expectedID == nil || expectedID == currentID else { return }
        let oldID = currentID
        let oldLease = lease
        let pending = creating
        let api = client
        currentID = nil
        currentKind = nil
        executing = false
        awaitingAuthentication = false
        cancelled = false
        lease = nil
        creating = nil
        creationID = nil
        pending?.cancel()
        for job in requests.values { job.cancel() }
        requests.removeAll()
        tail = nil
        isConnected = false
        settings.finishUse(for: credentialOwner, revision: settingsRevision)
        if beganBeforeIdentity { settings.finishUse(for: nil, revision: settingsRevision) }
        guard oldID != nil, let api else { return }
        let ending = Task { () -> AcademicConnectorCloseResult in
            if let oldLease { return await api.close(oldLease) }
            if let pending, case .success(let lateLease) = await pending.result { return await api.close(lateLease) }
            return .alreadyReleased
        }
        closing = ending
        let result = await ending.value
        if currentID == nil, case .unconfirmed(let message) = result { cleanupWarning = message }
    }

    private func busy() -> AcademicConnectorFailure {
        AcademicConnectorFailure(
            status: 409,
            code: "academic_operation_busy",
            message: "正在处理教务操作，请稍候再试。",
            requestID: nil
        )
    }
}
