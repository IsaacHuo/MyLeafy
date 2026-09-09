import Combine
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import os

struct CourseSectionView: View {
    @Environment(\.leafyDependencies) private var dependencies

    @Binding var selectedCourse: CourseRatingSummary?
    let refreshID: UUID
    let isActive: Bool
    @Bindable var store: CourseRatingCatalogStore

    private let pageSize = 50

    private var search: String {
        get { store.search }
        nonmutating set { store.search = newValue }
    }
    private var selectedCategory: String? {
        get { store.selectedCategory }
        nonmutating set { store.selectedCategory = newValue }
    }
    private var selectedStars: Int? {
        get { store.selectedStars }
        nonmutating set { store.selectedStars = newValue }
    }
    private var isFilterExpanded: Bool {
        get { store.isFilterExpanded }
        nonmutating set { store.isFilterExpanded = newValue }
    }
    private var courses: [CourseRatingSummary] {
        get { store.courses }
        nonmutating set { store.courses = newValue }
    }
    private var filteredCourses: [CourseRatingSummary] {
        get { store.filteredCourses }
        nonmutating set { store.filteredCourses = newValue }
    }
    private var availableCategories: [String] {
        get { store.availableCategories }
        nonmutating set { store.availableCategories = newValue }
    }
    private var isLoading: Bool {
        get { store.isLoading }
        nonmutating set { store.isLoading = newValue }
    }
    private var isLoadingMore: Bool {
        get { store.isLoadingMore }
        nonmutating set { store.isLoadingMore = newValue }
    }
    private var canLoadMore: Bool {
        get { store.canLoadMore }
        nonmutating set { store.canLoadMore = newValue }
    }
    private var errorMessage: String? {
        get { store.errorMessage }
        nonmutating set { store.errorMessage = newValue }
    }
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestionSheet: CatalogSuggestionSheetContext?

    private var hasActiveFilters: Bool {
        selectedCategory != nil || selectedStars != nil || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isActive {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    HStack(alignment: .top, spacing: 12) {
                        LeafySectionTitle("评课", subtitle: "公选课课程库由后台维护，每个账号对每门课保留一条星级评分。")
                        Spacer(minLength: 8)
                        CatalogSuggestionPromptButton(title: "缺课程", systemName: "plus.circle.fill") {
                            openCourseSuggestion()
                        }
                    }

                    CourseFilterToolbar(
                        search: $store.search,
                        selectedCategory: $store.selectedCategory,
                        selectedStars: $store.selectedStars,
                        isExpanded: $store.isFilterExpanded,
                        availableCategories: availableCategories,
                        hasActiveFilters: hasActiveFilters,
                        clearFilters: clearFilters
                    )

                    courseContent
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: isActive) {
            guard isActive, !store.load.hasLoaded else { return }
            await loadCourses(reset: true)
        }
        .onChange(of: search) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await loadCourses(reset: true)
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            scheduleCourseLoad(reset: true)
        }
        .onChange(of: selectedStars) { _, _ in
            updateDerivedCourseState()
        }
        .onChange(of: refreshID) { _, _ in
            scheduleCourseLoad(reset: true)
        }
        .onDisappear {
            searchTask?.cancel()
            store.load.cancel()
            isLoading = false
            isLoadingMore = false
        }
        .leafySheet(item: $suggestionSheet) { context in
            CatalogSuggestionSheet(context: context)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var courseContent: some View {
        if (isLoading || (!store.load.hasLoaded && errorMessage == nil)) && courses.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else if let errorMessage, courses.isEmpty {
            TeacherSectionMessageCard(
                title: "评课加载失败",
                message: errorMessage,
                actionTitle: "重试",
                action: { scheduleCourseLoad(reset: true) }
            )
        } else if courses.isEmpty {
            TeacherSectionMessageCard(
                title: emptyCourseTitle,
                message: emptyCourseMessage,
                actionTitle: "提交缺失课程",
                action: openCourseSuggestion
            )
        } else if filteredCourses.isEmpty {
            if hasActiveFilters {
                TeacherSectionMessageCard(
                    title: "没有匹配的课程",
                    message: "换一个分类、星级或关键词再试。",
                    actionTitle: "提交缺失课程",
                    action: openCourseSuggestion
                )
            } else {
                TeacherSectionMessageCard(
                    title: "没有匹配的课程",
                    message: "换一个分类、星级或关键词再试。",
                    actionTitle: "提交缺失课程",
                    action: openCourseSuggestion
                )
            }
        } else {
            if let errorMessage {
                Text(errorMessage)
                    .leafyBody()
                    .foregroundStyle(AppTheme.danger)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }

            ForEach(filteredCourses) { summary in
                Button {
                    selectedCourse = summary
                } label: {
                    CourseCard(summary: summary)
                }
                .buttonStyle(.plain)
            }

            if canLoadMore {
                RatingLoadMoreButton(isLoading: isLoadingMore) {
                    scheduleCourseLoad(reset: false)
                }
            }
        }
    }

    private var emptyCourseTitle: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategory == nil
            ? "暂无课程库"
            : "没有找到课程"
    }

    private var emptyCourseMessage: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategory == nil
            ? "先在 Supabase 的 course_catalog 表导入 name,unit,category,credit CSV，导入后这里会显示公选课列表。"
            : "换一个课程名、开课单位或分类关键词再试。"
    }

    @MainActor
    private func loadCourses(reset: Bool) async {
        let signpostState = LeafyPerformanceSignposter.ratings.beginInterval("courses-load")
        defer { LeafyPerformanceSignposter.ratings.endInterval("courses-load", signpostState) }

        guard reset || (!isLoading && !isLoadingMore && canLoadMore) else { return }
        let loadID = store.load.begin()
        let requestSearch = search
        let requestSelectedCategory = selectedCategory
        isLoading = reset
        isLoadingMore = !reset
        defer {
            if store.load.isCurrent(loadID) {
                isLoading = false
                isLoadingMore = false
            }
        }

        if ReviewDemoMode.isEnabled {
            let demoCourses = ReviewDemoDataSeeder.courseRatingSummaries(
                search: search,
                category: selectedCategory,
                limit: pageSize,
                offset: reset ? 0 : courses.count
            )
            if reset {
                courses = demoCourses
            } else {
                let existingIDs = Set(courses.map(\.id))
                courses.append(contentsOf: demoCourses.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = demoCourses.count == pageSize
            store.load.complete(loadID)
            errorMessage = nil
            updateDerivedCourseState()
            return
        }

        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch, selectedCategory == requestSelectedCategory else { return }
            let fetchedCourses = try await dependencies.communityRepository.fetchCourseRatingSummaries(
                search: search,
                category: selectedCategory,
                limit: pageSize,
                offset: reset ? 0 : courses.count
            )
                guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch, selectedCategory == requestSelectedCategory else { return }
            if reset {
                courses = fetchedCourses
            } else {
                let existingIDs = Set(courses.map(\.id))
                courses.append(contentsOf: fetchedCourses.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = fetchedCourses.count == pageSize
            store.load.complete(loadID)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch, selectedCategory == requestSelectedCategory else { return }
            errorMessage = error.localizedDescription
        }
        updateDerivedCourseState()
    }

    private func clearFilters() {
        searchTask?.cancel()
        search = ""
        selectedCategory = nil
        selectedStars = nil
        scheduleCourseLoad(reset: true)
    }

    private func openCourseSuggestion() {
        suggestionSheet = CatalogSuggestionSheetContext(
            type: .course,
            initialName: search.trimmingCharacters(in: .whitespacesAndNewlines),
            initialCategory: selectedCategory,
            initialLocation: nil
        )
    }

    private func scheduleCourseLoad(reset: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            await loadCourses(reset: reset)
        }
    }

    private func updateDerivedCourseState() {
        filteredCourses = courses.filter { summary in
            let course = summary.course
            if let selectedStars, course.ratingStarBucket != selectedStars {
                return false
            }
            return true
        }

        let loadedCategories = Array(
            Set(
                courses
                    .map { $0.course.category.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        if selectedCategory == nil || !loadedCategories.isEmpty {
            availableCategories = loadedCategories
        }
    }
}
