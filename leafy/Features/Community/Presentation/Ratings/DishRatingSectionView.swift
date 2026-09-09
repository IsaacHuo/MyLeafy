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
    @Bindable var store: DishRatingCatalogStore

    private let pageSize = 50

    private var search: String {
        get { store.search }
        nonmutating set { store.search = newValue }
    }
    private var selectedCanteen: String? {
        get { store.selectedCanteen }
        nonmutating set { store.selectedCanteen = newValue }
    }
    private var selectedLocation: String? {
        get { store.selectedLocation }
        nonmutating set { store.selectedLocation = newValue }
    }
    private var selectedStars: Int? {
        get { store.selectedStars }
        nonmutating set { store.selectedStars = newValue }
    }
    private var isFilterExpanded: Bool {
        get { store.isFilterExpanded }
        nonmutating set { store.isFilterExpanded = newValue }
    }
    private var dishes: [DishRatingSummary] {
        get { store.dishes }
        nonmutating set { store.dishes = newValue }
    }
    private var filteredDishes: [DishRatingSummary] {
        get { store.filteredDishes }
        nonmutating set { store.filteredDishes = newValue }
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
                        search: $store.search,
                        selectedCanteen: $store.selectedCanteen,
                        selectedLocation: $store.selectedLocation,
                        selectedStars: $store.selectedStars,
                        isExpanded: $store.isFilterExpanded,
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
            guard isActive, !store.load.hasLoaded else { return }
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
    private var dishContent: some View {
        if (isLoading || (!store.load.hasLoaded && errorMessage == nil)) && dishes.isEmpty {
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

        guard reset || (!isLoading && !isLoadingMore && canLoadMore) else { return }
        let loadID = store.load.begin()
        let requestSearch = search
        let requestSelectedCanteen = selectedCanteen
        let requestSelectedLocation = selectedLocation
        isLoading = reset
        isLoadingMore = !reset
        defer {
            if store.load.isCurrent(loadID) {
                isLoading = false
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
            store.load.complete(loadID)
            errorMessage = nil
            updateDerivedDishState()
            return
        }

        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch, selectedCanteen == requestSelectedCanteen, selectedLocation == requestSelectedLocation else { return }
            let fetchedDishes = try await dependencies.communityRepository.fetchDishRatingSummaries(
                search: search,
                canteen: selectedCanteen,
                location: selectedLocation,
                limit: pageSize,
                offset: reset ? 0 : dishes.count
            )
                guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch, selectedCanteen == requestSelectedCanteen, selectedLocation == requestSelectedLocation else { return }
            if reset {
                dishes = fetchedDishes
            } else {
                let existingIDs = Set(dishes.map(\.id))
                dishes.append(contentsOf: fetchedDishes.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = fetchedDishes.count == pageSize
            store.load.complete(loadID)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, store.load.isCurrent(loadID), search == requestSearch, selectedCanteen == requestSelectedCanteen, selectedLocation == requestSelectedLocation else { return }
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
