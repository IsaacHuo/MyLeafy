import Foundation
import Observation

@MainActor
@Observable
final class RatingCatalogLoadState {
    private(set) var hasLoaded = false
    private var requestID: UUID?

    func begin() -> UUID {
        let id = UUID()
        hasLoaded = false
        requestID = id
        return id
    }
    func isCurrent(_ id: UUID) -> Bool { requestID == id }
    func complete(_ id: UUID) {
        guard isCurrent(id) else { return }
        hasLoaded = true
    }
    func cancel() { requestID = nil }
}

@MainActor
@Observable
final class TeacherRatingCatalogStore {
    let load = RatingCatalogLoadState()
    var search = ""
    var selectedUnit: String?
    var selectedStars: Int?
    var isFilterExpanded = false
    var teachers: [TeacherRatingSummary] = []
    var filteredTeachers: [TeacherRatingSummary] = []
    var availableUnits: [String] = []
    var isLoading = false
    var isLoadingMore = false
    var canLoadMore = false
    var sourceOffset = 0
    var errorMessage: String?
}

@MainActor
@Observable
final class CourseRatingCatalogStore {
    let load = RatingCatalogLoadState()
    var search = ""
    var selectedCategory: String?
    var selectedStars: Int?
    var isFilterExpanded = false
    var courses: [CourseRatingSummary] = []
    var filteredCourses: [CourseRatingSummary] = []
    var availableCategories: [String] = []
    var isLoading = false
    var isLoadingMore = false
    var canLoadMore = false
    var errorMessage: String?
}

@MainActor
@Observable
final class DishRatingCatalogStore {
    let load = RatingCatalogLoadState()
    var search = ""
    var selectedCanteen: String?
    var selectedLocation: String?
    var selectedStars: Int?
    var isFilterExpanded = false
    var dishes: [DishRatingSummary] = []
    var filteredDishes: [DishRatingSummary] = []
    var isLoading = false
    var isLoadingMore = false
    var canLoadMore = false
    var errorMessage: String?
}

@MainActor
@Observable
final class RatingCatalogWorkspace {
    let teachers = TeacherRatingCatalogStore()
    let courses = CourseRatingCatalogStore()
    let dishes = DishRatingCatalogStore()
}
