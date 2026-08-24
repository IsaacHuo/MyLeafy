import CryptoKit
import Foundation
import UIKit

nonisolated struct CampusID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static let bjfu = CampusID(rawValue: "bjfu")
    static let custom = CampusID(rawValue: "custom")
    static let guest = CampusID(rawValue: "guest")
}

nonisolated enum CampusCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case authentication
    case timetable
    case grades
    case exams
    case teachingPlan
    case trainingProgram
    case classrooms
    case community
    case weather
    case sharedTimetable
    case medicalServices
}

nonisolated enum CampusConnectorKind: String, Codable, Hashable, Sendable {
    case bjfu
    case custom
    case guest
}

nonisolated struct CampusCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

nonisolated struct CampusLink: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
}

nonisolated struct CampusFeatureFlags: Codable, Hashable, Sendable {
    let campusPickerEnabled: Bool
    let crossCampusCommunityEnabled: Bool
}

nonisolated struct CampusDescriptor: Codable, Hashable, Identifiable, Sendable {
    let id: CampusID
    let displayName: String
    let shortName: String
    let timeZoneIdentifier: String
    let connectorKind: CampusConnectorKind
    let capabilities: Set<CampusCapability>
    let networkHint: String
    let defaultStudentDisplayName: String
    let undergraduateBaseURL: URL
    let graduateBaseURL: URL
    let weatherCoordinate: CampusCoordinate
    let weatherCityCode: String
    let commonLinks: [CampusLink]
    let featureFlags: CampusFeatureFlags

    func supports(_ capability: CampusCapability) -> Bool {
        capabilities.contains(capability)
    }

    static let bjfu = CampusDescriptor(
        id: .bjfu,
        displayName: "北京林业大学",
        shortName: "北林",
        timeZoneIdentifier: "Asia/Shanghai",
        connectorKind: .bjfu,
        capabilities: Set(CampusCapability.allCases),
        networkHint: "连接 bjfu-wifi 后可访问教务系统。",
        defaultStudentDisplayName: "北林同学",
        undergraduateBaseURL: URL(string: "http://newjwxt.bjfu.edu.cn")!,
        graduateBaseURL: URL(string: "http://gradms.bjfu.edu.cn/gmis5")!,
        weatherCoordinate: CampusCoordinate(latitude: 40.006, longitude: 116.352),
        weatherCityCode: "110108",
        commonLinks: [
            CampusLink(id: "seat", title: "图书馆座位", url: URL(string: "https://seat.bjfu.edu.cn")!),
            CampusLink(id: "undergraduate", title: "本科教务", url: URL(string: "http://newjwxt.bjfu.edu.cn")!),
            CampusLink(id: "graduate", title: "研究生系统", url: URL(string: "http://gradms.bjfu.edu.cn/gmis5")!)
        ],
        featureFlags: CampusFeatureFlags(
            campusPickerEnabled: false,
            crossCampusCommunityEnabled: false
        )
    )

    static let custom = CampusDescriptor(
        id: .custom,
        displayName: "通用学校入口",
        shortName: "通用学校",
        timeZoneIdentifier: "Asia/Shanghai",
        connectorKind: .custom,
        capabilities: [
            .authentication,
            .timetable,
            .grades,
            .exams,
            .community
        ],
        networkHint: "通用学校入口使用本地导入数据，不连接学校教务系统。",
        defaultStudentDisplayName: "同学",
        undergraduateBaseURL: URL(string: "https://myleafy.space")!,
        graduateBaseURL: URL(string: "https://myleafy.space")!,
        weatherCoordinate: CampusCoordinate(latitude: 0, longitude: 0),
        weatherCityCode: "",
        commonLinks: [],
        featureFlags: CampusFeatureFlags(
            campusPickerEnabled: true,
            crossCampusCommunityEnabled: false
        )
    )

    static let guest = CampusDescriptor(
        id: .guest,
        displayName: "免登录入口",
        shortName: "本地",
        timeZoneIdentifier: "Asia/Shanghai",
        connectorKind: .guest,
        capabilities: [
            .timetable,
            .grades,
            .exams
        ],
        networkHint: "免登录入口数据全部保存在本机，不连接任何账号或后台。",
        defaultStudentDisplayName: "本地用户",
        undergraduateBaseURL: URL(string: "https://myleafy.space")!,
        graduateBaseURL: URL(string: "https://myleafy.space")!,
        weatherCoordinate: CampusCoordinate(latitude: 0, longitude: 0),
        weatherCityCode: "",
        commonLinks: [],
        featureFlags: CampusFeatureFlags(
            campusPickerEnabled: true,
            crossCampusCommunityEnabled: false
        )
    )
}

nonisolated enum CampusIdentityKind: String, Codable, Hashable, Sendable {
    case schoolPortal
    case customSupabase
    case guest
}

nonisolated struct CampusIdentity: Codable, Equatable, Hashable, Sendable {
    let campusID: CampusID
    let eduID: String
    let displayName: String?
    let portal: SchoolPortal
    let kind: CampusIdentityKind

    init(
        campusID: CampusID,
        eduID: String,
        displayName: String?,
        portal: SchoolPortal,
        kind: CampusIdentityKind = .schoolPortal
    ) {
        self.campusID = campusID
        self.eduID = eduID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.portal = portal
        self.kind = kind
    }

    var isCustom: Bool {
        kind == .customSupabase || kind == .guest || campusID == .custom || campusID == .guest
    }

    var isGuest: Bool {
        kind == .guest
    }

    var scopeKey: String {
        let normalized: String
        if isCustom {
            normalized = "\(campusID.rawValue):\(kind.rawValue):\(eduID.lowercased())"
        } else {
            normalized = "\(campusID.rawValue):\(kind.rawValue):\(portal.rawValue):\(eduID.lowercased())"
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private enum CodingKeys: String, CodingKey {
        case campusID
        case eduID
        case displayName
        case portal
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let campusID = try container.decode(CampusID.self, forKey: .campusID)
        let eduID = try container.decode(String.self, forKey: .eduID)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let portal = try container.decode(SchoolPortal.self, forKey: .portal)
        let kind = try container.decode(CampusIdentityKind.self, forKey: .kind)
        self.init(campusID: campusID, eduID: eduID, displayName: displayName, portal: portal, kind: kind)
    }
}

nonisolated enum CampusCatalog {
    static let builtIn: [CampusDescriptor] = [.bjfu, .custom, .guest]
    static let production: [CampusDescriptor] = [.bjfu, .custom, .guest]

    static var activeCampus: CampusDescriptor {
        let campusID = CampusIdentityStore.currentIdentity()?.campusID ?? .bjfu
        return builtIn.first(where: { $0.id == campusID }) ?? .bjfu
    }

    static var showsCampusPicker: Bool {
        production.count > 1 && production.contains(where: \.featureFlags.campusPickerEnabled)
    }

    static var showsCrossCampusCommunity: Bool {
        production.count > 1 && production.contains(where: \.featureFlags.crossCampusCommunityEnabled)
    }
}

nonisolated enum CampusIdentityStore {
    private static let activeIdentityKey = "leafy.activeCampusIdentity.v1"

    static func currentIdentity(defaults: UserDefaults = .standard) -> CampusIdentity? {
        storedIdentity(defaults: defaults)
    }

    private static func storedIdentity(defaults: UserDefaults) -> CampusIdentity? {
        guard let data = defaults.data(forKey: activeIdentityKey),
              let identity = try? JSONDecoder().decode(CampusIdentity.self, from: data),
              !identity.eduID.isEmpty else {
            return nil
        }
        return identity
    }

    static func activate(_ identity: CampusIdentity, defaults: UserDefaults = .standard) {
        guard !identity.eduID.isEmpty,
              let data = try? JSONEncoder().encode(identity) else {
            return
        }
        let previousScopeKey = storedIdentity(defaults: defaults)?.scopeKey
        defaults.set(data, forKey: activeIdentityKey)
        if previousScopeKey != identity.scopeKey {
            NotificationCenter.default.post(name: .campusIdentityDidChange, object: identity)
        }
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: activeIdentityKey)
        NotificationCenter.default.post(name: .campusIdentityDidChange, object: nil)
    }
}

nonisolated enum CampusScopedDefaults {
    static func key(
        _ baseKey: String,
        identity: CampusIdentity? = nil,
        defaults: UserDefaults = .standard
    ) -> String {
        guard let identity = identity ?? CampusIdentityStore.currentIdentity(defaults: defaults) else {
            return baseKey
        }
        return "leafy.campus.\(identity.scopeKey).\(baseKey)"
    }

}

nonisolated enum ActiveCampusContext {
    static var descriptor: CampusDescriptor {
        CampusCatalog.activeCampus
    }

    static var identity: CampusIdentity? {
        CampusIdentityStore.currentIdentity()
    }

    @MainActor
    static var networkManager: SchoolNetworkManager {
        SchoolNetworkManager.shared
    }
}

extension Notification.Name {
    nonisolated static let campusIdentityDidChange = Notification.Name("CampusIdentityDidChange")
}

@MainActor
protocol CampusAuthenticationProviding: AnyObject {
    var isLoggedIn: Bool { get }
    var hasCachedIdentity: Bool { get }
    var currentPortal: SchoolPortal { get set }
    var authenticatedEduID: String? { get }
    var authenticatedDisplayName: String? { get }

    func fetchCaptcha(for portal: SchoolPortal) async throws -> (key: String, image: UIImage)
    func performLogin(account: String, password: String, captcha: String, key: String, portal: SchoolPortal) async throws -> Bool
    func clearSession()
}

@MainActor
protocol CampusTimetableProviding: AnyObject {
    func fetchTimetable() async throws -> FetchedTimetableDocument
    func fetchGrades() async throws -> String
}

@MainActor
protocol CampusAcademicProviding: AnyObject {
    func fetchExamSchedule() async throws -> String
    func fetchTeachingPlan() async throws -> String
    func fetchGraduationRequirements() async throws -> String
    func fetchGradeRankings() async throws -> String
}

@MainActor
protocol CampusClassroomProviding: AnyObject {
    func fetchEmptyClassrooms(date: Date, start: Int, end: Int) async throws -> String
    func fetchClassroomUsage(date: Date, building: String, room: String) async throws -> [ClassroomUsageSlot]
}

protocol CampusAcademicConnector:
    CampusAuthenticationProviding,
    CampusTimetableProviding,
    CampusAcademicProviding,
    CampusClassroomProviding
{
    var campusDescriptor: CampusDescriptor { get }
}

extension SchoolNetworkManager: CampusAcademicConnector {
    var campusDescriptor: CampusDescriptor {
        .bjfu
    }
}
