import Combine
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import os

struct DishSectionView: View {
    @Environment(\.leafyDependencies) private var dependencies

    @Binding var selectedDish: DishRatingSummary?
    let refreshID: UUID
    let isActive: Bool
    let lifecycleStore: RatingCatalogSectionStore

    private let pageSize = 50

    @State private var search = ""
    @State private var selectedCanteen: String?
    @State private var selectedLocation: String?
    @State private var selectedStars: Int?
    @State private var isFilterExpanded = false
    @State private var dishes: [DishRatingSummary] = []
    @State private var filteredDishes: [DishRatingSummary] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestionSheet: CatalogSuggestionSheetContext?

    private var hasActiveFilters: Bool {
        selectedCanteen != nil ||
        selectedLocation != nil ||
        selectedStars != nil ||
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isActive {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    HStack(alignment: .top, spacing: 12) {
                        LeafySectionTitle("评菜", subtitle: "按食堂和餐厅筛选菜品，每个账号对每道菜保留一条星级评分。")
                        Spacer(minLength: 8)
                        CatalogSuggestionPromptButton(title: "缺菜品", systemName: "fork.knife.circle.fill") {
                            openDishSuggestion()
                        }
                    }

                    DishFilterToolbar(
                        search: $search,
                        selectedCanteen: $selectedCanteen,
                        selectedLocation: $selectedLocation,
                        selectedStars: $selectedStars,
                        isExpanded: $isFilterExpanded,
                        hasActiveFilters: hasActiveFilters,
                        clearFilters: clearFilters
                    )

                    dishContent
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: isActive) {
            guard isActive, lifecycleStore.beginInitialLoad() else { return }
            await loadDishes(reset: true)
        }
        .onChange(of: search) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await loadDishes(reset: true)
            }
        }
        .onChange(of: selectedCanteen) { _, canteen in
            if let currentLocation = selectedLocation,
               let canteen,
               !CampusDiningLocation.locations(for: canteen).contains(where: { $0.fullName == currentLocation }) {
                selectedLocation = nil
            }
            scheduleDishLoad(reset: true)
        }
        .onChange(of: selectedLocation) { _, _ in
            scheduleDishLoad(reset: true)
        }
        .onChange(of: selectedStars) { _, _ in
            updateDerivedDishState()
        }
        .onChange(of: refreshID) { _, _ in
            scheduleDishLoad(reset: true)
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
    private var dishContent: some View {
        if isLoading && dishes.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else if let errorMessage, dishes.isEmpty {
            TeacherSectionMessageCard(
                title: "评菜加载失败",
                message: errorMessage,
                actionTitle: "重试",
                action: { scheduleDishLoad(reset: true) }
            )
        } else if dishes.isEmpty {
            TeacherSectionMessageCard(
                title: emptyDishTitle,
                message: emptyDishMessage,
                actionTitle: "提交缺失菜品",
                action: openDishSuggestion
            )
        } else if filteredDishes.isEmpty {
            TeacherSectionMessageCard(
                title: "没有匹配的菜品",
                message: "换一个食堂、地点、星级或菜名关键词再试。提交新菜名前，也可以先搜索确认是否已经有人提交过。",
                actionTitle: "提交缺失菜品",
                action: openDishSuggestion
            )
        } else {
            if let errorMessage {
                Text(errorMessage)
                    .leafyBody()
                    .foregroundStyle(AppTheme.danger)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }

            ForEach(filteredDishes) { summary in
                Button {
                    selectedDish = summary
                } label: {
                    DishCard(summary: summary)
                }
                .buttonStyle(.plain)
            }

            if canLoadMore {
                RatingLoadMoreButton(isLoading: isLoadingMore) {
                    scheduleDishLoad(reset: false)
                }
            }
        }
    }

    private var emptyDishTitle: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedCanteen == nil &&
        selectedLocation == nil
            ? "暂无菜品库"
            : "没有找到菜品"
    }

    private var emptyDishMessage: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedCanteen == nil &&
        selectedLocation == nil
            ? "先提交常吃菜品，审核通过后这里会显示可评分的菜品列表。"
            : "提交新菜名前，建议先换个关键词或地点确认是否已经有人提交过。"
    }

    @MainActor
    private func loadDishes(reset: Bool) async {
        let signpostState = LeafyPerformanceSignposter.ratings.beginInterval("dishes-load")
        defer { LeafyPerformanceSignposter.ratings.endInterval("dishes-load", signpostState) }

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
            let demoDishes = ReviewDemoDataSeeder.dishRatingSummaries(
                search: search,
                canteen: selectedCanteen,
                location: selectedLocation,
                limit: pageSize,
                offset: reset ? 0 : dishes.count
            )
            if reset {
                dishes = demoDishes
            } else {
                let existingIDs = Set(dishes.map(\.id))
                dishes.append(contentsOf: demoDishes.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = demoDishes.count == pageSize
            errorMessage = nil
            updateDerivedDishState()
            return
        }

        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            let fetchedDishes = try await dependencies.communityRepository.fetchDishRatingSummaries(
                search: search,
                canteen: selectedCanteen,
                location: selectedLocation,
                limit: pageSize,
                offset: reset ? 0 : dishes.count
            )
            if reset {
                dishes = fetchedDishes
            } else {
                let existingIDs = Set(dishes.map(\.id))
                dishes.append(contentsOf: fetchedDishes.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = fetchedDishes.count == pageSize
            errorMessage = nil
        } catch {
            if reset {
                dishes = []
                canLoadMore = false
            }
            errorMessage = error.localizedDescription
        }
        updateDerivedDishState()
    }

    private func clearFilters() {
        searchTask?.cancel()
        search = ""
        selectedCanteen = nil
        selectedLocation = nil
        selectedStars = nil
        scheduleDishLoad(reset: true)
    }

    private func openDishSuggestion() {
        suggestionSheet = CatalogSuggestionSheetContext(
            type: .dish,
            initialName: search.trimmingCharacters(in: .whitespacesAndNewlines),
            initialCategory: nil,
            initialLocation: selectedLocation
        )
    }

    private func scheduleDishLoad(reset: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            await loadDishes(reset: reset)
        }
    }

    private func updateDerivedDishState() {
        filteredDishes = dishes.filter { summary in
            let dish = summary.dish
            if let selectedStars, dish.ratingStarBucket != selectedStars {
                return false
            }
            return true
        }
    }
}
