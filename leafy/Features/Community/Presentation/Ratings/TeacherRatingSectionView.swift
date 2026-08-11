import Combine
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import os

struct TeacherSectionView: View {
    @Environment(\.leafyDependencies) private var dependencies

    @Binding var selectedTeacher: TeacherRatingSummary?
    let refreshID: UUID
    let isActive: Bool
    let lifecycleStore: RatingCatalogSectionStore

    private let pageSize = 50
    private let visibleLoadMoreCount = 20

    @State private var search = ""
    @State private var selectedUnit: String?
    @State private var selectedStars: Int?
    @State private var isFilterExpanded = false
    @State private var teachers: [TeacherRatingSummary] = []
    @State private var filteredTeachers: [TeacherRatingSummary] = []
    @State private var availableUnits: [String] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var sourceOffset = 0
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestionSheet: CatalogSuggestionSheetContext?

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
                        search: $search,
                        selectedUnit: $selectedUnit,
                        selectedStars: $selectedStars,
                        isExpanded: $isFilterExpanded,
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
            guard isActive, lifecycleStore.beginInitialLoad() else { return }
            await loadTeachers(reset: true)
        }
        .onChange(of: search) { _, _ in
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
        }
        .leafySheet(item: $suggestionSheet) { context in
            CatalogSuggestionSheet(context: context)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var teacherContent: some View {
        if isLoading && teachers.isEmpty {
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
            ? "先在 Supabase 的 teachers 表导入 name,unit CSV，导入后这里会显示真实老师列表。"
            : "换一个姓名或学院关键词再试。"
    }

    @MainActor
    private func loadTeachers(reset: Bool) async {
        let signpostState = LeafyPerformanceSignposter.ratings.beginInterval("teachers-load")
        defer { LeafyPerformanceSignposter.ratings.endInterval("teachers-load", signpostState) }

        if reset {
            isLoading = true
        } else {
            guard !isLoadingMore, canLoadMore else { return }
            isLoadingMore = true
        }
        defer {
            if reset {
                isLoading = false
            } else {
                isLoadingMore = false
            }
        }

        if ReviewDemoMode.isEnabled {
            let demoTeachers = ReviewDemoDataSeeder.teacherSummaries(search: search)
            teachers = reset ? demoTeachers : teachers
            sourceOffset = demoTeachers.count
            canLoadMore = false
            errorMessage = nil
            updateDerivedTeacherState()
            return
        }

        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            if reset {
                let fetchedTeachers = try await dependencies.communityRepository.fetchTeacherRatingSummaries(
                    search: search,
                    limit: pageSize,
                    offset: 0
                )
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
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if reset {
                teachers = []
                sourceOffset = 0
                canLoadMore = false
            }
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
