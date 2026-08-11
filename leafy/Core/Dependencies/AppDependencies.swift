import SwiftUI

struct LeafyDependencies {
    var schoolTimetableRepository: any SchoolTimetableRepository
    var communityRepository: any CommunityRepository
    var communityActivityRepository: any CommunityActivityRepository
    var communityBannerRepository: any CommunityBannerRepository
    var communityPostDraftRepository: any CommunityPostDraftRepository
    var communityImageProcessor: any CommunityImageProcessing
    var classroomLookupService: any ClassroomLookupServicing
    var campusHeatmapService: any CampusHeatmapServicing
    var widgetSnapshotPublisher: any WidgetSnapshotPublishing
    var weatherService: any WeatherServicing
    var timetableWeatherService: any TimetableWeatherServicing

    static let live = LeafyDependencies(
        schoolTimetableRepository: LiveSchoolTimetableRepository(),
        communityRepository: LiveCommunityRepository(),
        communityActivityRepository: LiveCommunityActivityRepository(),
        communityBannerRepository: LiveCommunityBannerRepository(),
        communityPostDraftRepository: LocalCommunityPostDraftRepository.shared,
        communityImageProcessor: CommunityImageProcessor.shared,
        classroomLookupService: LiveClassroomLookupService(),
        campusHeatmapService: LiveCampusHeatmapService(),
        widgetSnapshotPublisher: WidgetSnapshotPublisher.shared,
        weatherService: WeatherKitWeatherService(),
        timetableWeatherService: WeatherKitTimetableWeatherService()
    )
}

private struct LeafyDependenciesKey: EnvironmentKey {
    static let defaultValue = LeafyDependencies.live
}

extension EnvironmentValues {
    var leafyDependencies: LeafyDependencies {
        get { self[LeafyDependenciesKey.self] }
        set { self[LeafyDependenciesKey.self] = newValue }
    }
}
