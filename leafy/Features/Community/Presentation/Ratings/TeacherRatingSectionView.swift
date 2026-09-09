import Combine
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import os

nonisolated enum TeacherRatingRouteResolver {
    static func exactMatch(
        named name: String,
        in summaries: [TeacherRatingSummary]
    ) -> TeacherRatingSummary? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = summaries.filter {
            $0.teacher.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

struct TeacherSectionView: View {
    @Environment(\.leafyDependencies) private var dependencies

    @Binding var selectedTeacher: TeacherRatingSummary?
    @Binding var requestedTeacherName: String?
    let refreshID: UUID
    let isActive: Bool
    @Bindable var store: TeacherRatingCatalogStore

    private let pageSize = 50
    private let visibleLoadMoreCount = 20

    private var search: String {
        get { store.search }
        nonmutating set { store.search = newValue }
    }
    private var selectedUnit: String? {
        get { store.selectedUnit }
        nonmutating set { store.selectedUnit = newValue }
    }
    private var selectedStars: Int? {
        get { store.selectedStars }
        nonmutating set { store.selectedStars = newValue }
    }
    private var isFilterExpanded: Bool {
        get { store.isFilterExpanded }
        nonmutating set { store.isFilterExpanded = newValue }
    }
    private var teachers: [TeacherRatingSummary] {
        get { store.teachers }
        nonmutating set { store.teachers = newValue }
    }
    private var filteredTeachers: [TeacherRatingSummary] {
        get { store.filteredTeachers }
        nonmutating set { store.filteredTeachers = newValue }
    }
    private var availableUnits: [String] {
        get { store.availableUnits }
        nonmutating set { store.availableUnits = newValue }
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
    private var sourceOffset: Int {
        get { store.sourceOffset }
        nonmutating set { store.sourceOffset = newValue }
    }
    private var errorMessage: String? {
        get { store.errorMessage }
        nonmutating set { store.errorMessage = newValue }
    }
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestionSheet: CatalogSuggestionSheetContext?
    @State private var isApplyingRequestedTeacher = false

    private var hasActiveFilters: Bool {
        selectedUnit != nil || selectedStars != nil || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isActive {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    HStack(alignment: .top, spacing: 12) {
                        LeafySectionTitle("评教", subtitle: "按老师打星评分，结果只统计星级。")
                        Spacer(minLength: 8)
                        CatalogSuggestionPromptButton(title: "缺老师", systemName: "person.badge.plus") {
                            openTeacherSuggestion()
                        }
                    }

                    TeacherFilterToolbar(
                        search: $store.search,
                        selectedUnit: $store.selectedUnit,
                        selectedStars: $store.selectedStars,
                        isExpanded: $store.isFilterExpanded,
                        availableUnits: availableUnits,
                        hasActiveFilters: hasActiveFilters,
                        clearFilters: clearFilters
                    )

                    teacherContent
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: isActive) {
            guard isActive, !store.load.hasLoaded else { return }
            await loadTeachers(reset: true)
        }
        .onChange(of: search) { _, _ in
            guard !isApplyingRequestedTeacher else { return }
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await loadTeachers(reset: true)
            }
        }
        .onChange(of: refreshID) { _, _ in
            scheduleTeacherLoad(reset: true)
        }
        .onChange(of: selectedUnit) { _, _ in
            updateDerivedTeacherState()
        }
        .onChange(of: selectedStars) { _, _ in
            updateDerivedTeacherState()
        }
        .onDisappear {
            searchTask?.cancel()
            store.load.cancel()
            isLoading = false
            isLoadingMore = false
        }
        .task(id: requestedTeacherName) {
            guard let requestedTeacherName else { return }
            await openRequestedTeacher(named: requestedTeacherName)
        }
        .leafySheet(item: $suggestionSheet) { context in
            CatalogSuggestionSheet(context: context)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var teacherContent: some View {
        if (isLoading || (!store.load.hasLoaded && errorMessage == nil)) && teachers.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else if let errorMessage, teachers.isEmpty {
            TeacherSectionMessageCard(
                title: "评教加载失败",
                message: errorMessage,
                actionTitle: "重试",
                action: { scheduleTeacherLoad(reset: true) }
            )
        } else if teachers.isEmpty {
            TeacherSectionMessageCard(
                title: emptyTeacherTitle,
                message: emptyTeacherMessage,
                actionTitle: "提交缺失老师",
                action: openTeacherSuggestion
            )
        } else if filteredTeachers.isEmpty {
            if hasActiveFilters {
                TeacherSectionMessageCard(
                    title: "没有匹配的老师",
                    message: "换一个学院、星级或关键词再试。",
                    actionTitle: "提交缺失老师",
                    action: openTeacherSuggestion
                )
            } else {
                TeacherSectionMessageCard(
                    title: "没有匹配的老师",
                    message: "换一个学院、星级或关键词再试。",
                    actionTitle: "提交缺失老师",
                    action: openTeacherSuggestion
                )
            }
            if canLoadMore {
                RatingLoadMoreButton(isLoading: isLoadingMore) {
                    scheduleTeacherLoad(reset: false)
                }
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

            ForEach(filteredTeachers) { summary in
                Button {
                    selectedTeacher = summary
                } label: {
                    TeacherCard(summary: summary)
                }
                .buttonStyle(.plain)
            }

            if canLoadMore {
                RatingLoadMoreButton(isLoading: isLoadingMore) {
                    scheduleTeacherLoad(reset: false)
                }
            }
        }
    }

    private var emptyTeacherTitle: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "暂无教师名录" : "未找到教师"
    }

    private var emptyTeacherMessage: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "当前学校暂未收录教师，可以提交缺失老师。"
            : "换一个姓名或学院关键词再试。"
    }

    @MainActor
    private func loadTeachers(reset: Bool) async {
        let signpostState = LeafyPerformanceSignposter.ratings.beginInterval("teachers-load")
        defer { LeafyPerformanceSignposter.ratings.endInterval("teachers-load", signpostState) }

        guard reset || (!isLoading && !isLoadingMore && canLoadMore) else { return }
        let loadID = store.load.begin()
        let requestSearch = search
        isLoading = reset
        isLoadingMore = !reset
        defer {
            if store.load.isCurrent(loadID) {
                isLoading = false
                isLoadingMore = false
            }
        }

        if ReviewDemoMode.isEnabled {
            let demoTeachers = ReviewDemoDataSeeder.teacherSummaries(search: search)
            teachers = reset ? demoTeachers : teachers
            sourceOffset = demoTeachers.count
            canLoadMore = false
            store.load.complete(loadID)
            errorMessage = nil
            updateDerivedTeacherState()
            return
        }

        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch else { return }
            if reset {
                let fetchedTeachers = try await dependencies.communityRepository.fetchTeacherRatingSummaries(
                    search: search,
                    limit: pageSize,
                    offset: 0
                )
                guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch else { return }
                teachers = fetchedTeachers
                sourceOffset = fetchedTeachers.count
                canLoadMore = fetchedTeachers.count == pageSize
            } else {
                let visibleIDsBeforeLoad = Set(filteredTeachers.map(\.id))
                var newlyVisibleCount = 0

                while canLoadMore && newlyVisibleCount < visibleLoadMoreCount {
                    try Task.checkCancellation()
                    let fetchedTeachers = try await dependencies.communityRepository.fetchTeacherRatingSummaries(
                        search: search,
                        limit: pageSize,
                        offset: sourceOffset
                    )
                guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch else { return }
                    sourceOffset += fetchedTeachers.count

                    let existingIDs = Set(teachers.map(\.id))
                    teachers.append(contentsOf: fetchedTeachers.filter { !existingIDs.contains($0.id) })
                    canLoadMore = fetchedTeachers.count == pageSize
                    updateDerivedTeacherState()
                    newlyVisibleCount = filteredTeachers.reduce(into: 0) { count, teacher in
                        if !visibleIDsBeforeLoad.contains(teacher.id) {
                            count += 1
                        }
                    }
                }
            }
            store.load.complete(loadID)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch else { return }
            errorMessage = error.localizedDescription
        }
        updateDerivedTeacherState()
    }

    private func clearFilters() {
        searchTask?.cancel()
        search = ""
        selectedUnit = nil
        selectedStars = nil
        scheduleTeacherLoad(reset: true)
    }

    private func openTeacherSuggestion() {
        suggestionSheet = CatalogSuggestionSheetContext(
            type: .teacher,
            initialName: search.trimmingCharacters(in: .whitespacesAndNewlines),
            initialCategory: nil,
            initialLocation: nil
        )
    }

    private func scheduleTeacherLoad(reset: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            await loadTeachers(reset: reset)
        }
    }

    @MainActor
    private func openRequestedTeacher(named name: String) async {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            requestedTeacherName = nil
            return
        }

        searchTask?.cancel()
        isApplyingRequestedTeacher = true
        search = normalizedName
        await loadTeachers(reset: true)
        isApplyingRequestedTeacher = false

        if let exactMatch = TeacherRatingRouteResolver.exactMatch(named: normalizedName, in: teachers) {
            selectedTeacher = exactMatch
        }
        requestedTeacherName = nil
    }

    private func updateDerivedTeacherState() {
        filteredTeachers = teachers.filter { summary in
            let teacher = summary.teacher
            if let selectedUnit, teacher.unit != selectedUnit {
                return false
            }
            if let selectedStars, teacher.ratingStarBucket != selectedStars {
                return false
            }
            return true
        }

        availableUnits = Array(
            Set(
                teachers
                    .map { $0.teacher.unit.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
