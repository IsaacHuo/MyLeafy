import Foundation

/// Only undergraduate login and timetable opt into this transport. Other academic features keep their own entry points.
@MainActor
final class SchoolTimetableConnection {
    static let shared = SchoolTimetableConnection()
    private var vpnManager: SchoolNetworkManager?
    private var owner: String?
    private var revision: UInt64?

    func manager(mode: SchoolConnectionMode? = nil, portal: SchoolPortal = .undergraduate) -> SchoolNetworkManager {
        let settings = SchoolVPNSettingsStore.shared
        let identity = ActiveCampusContext.identity
        let selection = mode ?? SchoolConnectionRoute.modeOverride
        guard portal == .undergraduate, !ReviewDemoMode.isEnabled,
              selection != .campusDirect, settings.isEnabled(for: identity)
        else { return ActiveCampusContext.networkManager }
        if owner != identity?.scopeKey || revision != settings.revision {
            vpnManager?.academicConnection?.cancel()
            vpnManager = nil
        }
        if let vpnManager { return vpnManager }
        owner = identity?.scopeKey
        revision = settings.revision
        let connection = SchoolAcademicConnection(
            settings: settings,
            credentialOwner: identity,
            client: {
                guard !AppRuntimeEnvironment.isRunningUnitTests else { throw URLError(.unsupportedURL) }
                return try AcademicConnectorClient(baseURL: MyLeafyBackendEnvironment.client().baseURL)
            },
            willActivate: { [weak self] identity in self?.owner = identity.scopeKey }
        )
        let manager = SchoolNetworkManager(connectionMode: .serverVPN, academicConnection: connection)
        connection.manager = manager
        vpnManager = manager
        return manager
    }

    func cancel() { vpnManager?.academicConnection?.cancel() }
}
