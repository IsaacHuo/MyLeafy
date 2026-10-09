import Foundation

enum CampusSidebarDestination: Hashable, Identifiable {
    case schedule
    case community
    case academic(AcademicPrimaryTab)

    var id: Self { self }

    var section: CampusSection {
        switch self {
        case .schedule: return .schedule
        case .community: return .community
        case .academic: return .academics
        }
    }

    var icon: String {
        switch self {
        case .schedule: return "calendar.day.timeline.left"
        case .community: return "person.2.fill"
        case .academic(let tab): return tab.icon
        }
    }

    func title(language: AppLanguagePreference) -> String {
        switch self {
        case .schedule: return L10n.text("campus.sidebar.journal", language: language)
        case .community: return L10n.text("campus.sidebar.community", language: language)
        case .academic(let tab): return tab.compactTitle(language: language)
        }
    }

    static func visibleCases(
        isCustomCampus: Bool,
        isCommunityEnabled: Bool,
        isMedicalEnabled: Bool,
        campusID: CampusID
    ) -> [Self] {
        var destinations: [Self] = []
        if isCommunityEnabled { destinations.append(.community) }
        destinations.append(.schedule)
        destinations += AcademicPrimaryTab.visibleCases(
            isCustomCampus: isCustomCampus,
            isCommunityEnabled: isCommunityEnabled,
            isMedicalEnabled: isMedicalEnabled,
            campusID: campusID
        ).map(Self.academic)
        return destinations
    }
}
