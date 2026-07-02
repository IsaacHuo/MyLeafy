import SwiftUI

struct AcademicHubView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @Binding private var selectedTab: AcademicPrimaryTab
    private let showsSidebar: Bool
    @State private var selectedTeacher: TeacherRatingSummary?
    @State private var selectedCourse: CourseRatingSummary?
    @State private var selectedDish: DishRatingSummary?
    @State private var teacherRefreshID = UUID()
    @State private var courseRefreshID = UUID()
    @State private var dishRefreshID = UUID()
    @State private var navigationPath: [AcademicNavigationItem] = []
    @State private var isHandlingExternalRoute = false

    init(
        selectedTab: Binding<AcademicPrimaryTab> = .constant(.cultivation),
        showsSidebar: Bool = true
    ) {
        _selectedTab = selectedTab
        self.showsSidebar = showsSidebar
    }

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    private var isMedicalEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.medicalServices)
    }

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    private var campusID: CampusID {
        ActiveCampusContext.descriptor.id
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    if showsSidebar {
                        academicSidebar
                    }

                    ScrollView(showsIndicators: false) {
                        Color.clear
                            .frame(height: 0)
                            .id("academic-content-top")

                        selectedAcademicContent
                            .leafyAdaptiveContentWidth(
                                maxWidth: 760, horizontalPadding: AppSpacing.page
                            )
                            .padding(.bottom, AppSpacing.card)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, -AppSpacing.micro)
                }
                .onChange(of: selectedTab) { _, _ in
                    if isHandlingExternalRoute {
                        isHandlingExternalRoute = false
                        return
                    }
                    navigationPath.removeAll()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo("academic-content-top", anchor: .top)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LeafyPageBackground())
            .tint(AppTheme.accent(for: themeColorPreference))
            .navigationTitle("")
            .leafyInlineNavigationTitle()
            .leafyNavigationBarVisible()
            .sheet(item: $selectedTeacher) { teacher in
                TeacherDetailSheet(summary: teacher) { updatedSummary in
                    selectedTeacher = updatedSummary
                    teacherRefreshID = UUID()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedCourse) { course in
                CourseRatingDetailSheet(summary: course) { updatedSummary in
                    selectedCourse = updatedSummary
                    courseRefreshID = UUID()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedDish) { dish in
                DishDetailSheet(summary: dish) { updatedSummary in
                    selectedDish = updatedSummary
                    dishRefreshID = UUID()
                }
                .presentationDetents([.medium, .large])
            }
            .navigationDestination(for: AcademicNavigationItem.self) { item in
                academicDestination(for: item.route)
                    .id(item.id)
            }
            .onChange(of: appNavigation.requestedAcademicRoute) { _, route in
                handleAcademicRouteRequest(route)
            }
            .onChange(of: appNavigation.requestedAcademicDetailRoute) { _, route in
                handleAcademicDetailRouteRequest(route)
            }
            .onChange(of: appNavigation.requestedClassroomLookup) { _, request in
                handleClassroomLookupRequest(request)
            }
            .onAppear {
                sanitizeSelectedTab()
                handleAcademicRouteRequest(appNavigation.requestedAcademicRoute)
                handleAcademicDetailRouteRequest(appNavigation.requestedAcademicDetailRoute)
                handleClassroomLookupRequest(appNavigation.requestedClassroomLookup)
            }
        }
    }

    private var visibleAcademicTabs: [AcademicPrimaryTab] {
        AcademicPrimaryTab.visibleCases(
            isCustomCampus: isCustomCampus,
            isCommunityEnabled: isCommunityEnabled,
            isMedicalEnabled: isMedicalEnabled,
            campusID: campusID
        )
    }

    @ViewBuilder
    private func academicDestination(for route: AcademicDetailRoute) -> some View {
        AcademicRouteDestinationView(route: route, openRoute: openRoute)
            .leafyNavigationBarVisible()
    }

    @ViewBuilder
    private var selectedAcademicContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            switch selectedTab {
            case .cultivation:
                TeachingCultivationSectionView(openRoute: openRoute)
            case .schedule:
                ScheduleSectionView(openRoute: openRoute)
            case .classrooms:
                ClassroomsSectionView(openRoute: openRoute)
            case .learning:
                LearningWorkspaceView(openRoute: openRoute)
            case .sports:
                SportsSectionView(openRoute: openRoute)
            case .career:
                CareerPlanningSectionView()
            case .postgraduate:
                PostgraduateInfoSectionView()
            case .ratings:
                if isCommunityEnabled {
                    RatingSectionContainerView(
                        selectedTeacher: $selectedTeacher,
                        selectedCourse: $selectedCourse,
                        selectedDish: $selectedDish,
                        teacherRefreshID: teacherRefreshID,
                        courseRefreshID: courseRefreshID,
                        dishRefreshID: dishRefreshID
                    )
                } else {
                    AcademicDetailCard {
                        ContentUnavailableView(
                            "当前入口暂未开放社区评分",
                            systemImage: "star.bubble",
                            description: Text("评教、评课和评菜属于学校社区能力，需要先进入对应学校社区。")
                        )
                    }
                }
            case .medical:
                MedicalMattersSectionView(openRoute: openRoute)
            case .weekendTravel:
                WeekendTravelSectionView()
            }
        }
    }

    private var academicSidebar: some View {
        VStack(spacing: 4 * leafyControlScale) {
            ForEach(visibleAcademicTabs) { tab in
                Button {
                    selectAcademicTab(tab)
                } label: {
                    AcademicSidebarTabItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        language: leafyLanguage,
                        themeColorPreference: themeColorPreference
                    )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .accessibilityLabel(tab.title(language: leafyLanguage))
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(8 * leafyControlScale)
        .frame(width: academicSidebarWidth, alignment: .top)
        .leafyGlassSurface(
            in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous),
            fallbackFill: Color(uiColor: .systemBackground).opacity(0.9)
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, -(AppSpacing.micro / 15))
        .accessibilityElement(children: .contain)
    }

    private var academicSidebarWidth: CGFloat {
        78 * leafyControlScale
    }

    @MainActor
    private func openRoute(_ route: AcademicDetailRoute) {
        guard
            CampusAcademicVisibility.isRouteVisible(
                route,
                isCustomCampus: isCustomCampus,
                isCommunityEnabled: isCommunityEnabled,
                isMedicalEnabled: isMedicalEnabled
            )
        else {
            sanitizeSelectedTab()
            return
        }
        navigationPath.append(AcademicNavigationItem(route: route))
    }

    @MainActor
    private func selectAcademicTab(_ tab: AcademicPrimaryTab) {
        guard tab.isVisible(
            isCustomCampus: isCustomCampus,
            isCommunityEnabled: isCommunityEnabled,
            isMedicalEnabled: isMedicalEnabled,
            campusID: campusID
        )
        else {
            sanitizeSelectedTab()
            return
        }

        navigationPath.removeAll()
        selectedTab = tab
    }

    @MainActor
    private func handleAcademicRouteRequest(_ route: AcademicRoute?) {
        guard let route else { return }
        let target = AcademicRouteResolver.target(for: route)
        guard
            target.tab.isVisible(
                isCustomCampus: isCustomCampus,
                isCommunityEnabled: isCommunityEnabled,
                isMedicalEnabled: isMedicalEnabled,
                campusID: campusID)
        else {
            appNavigation.requestedAcademicRoute = nil
            sanitizeSelectedTab()
            return
        }

        navigationPath.removeAll()
        let changesSelectedTab = selectedTab != target.tab
        isHandlingExternalRoute = changesSelectedTab
        selectedTab = target.tab
        openRoute(target.detailRoute)
        if !changesSelectedTab {
            isHandlingExternalRoute = false
        }

        appNavigation.requestedAcademicRoute = nil
    }

    @MainActor
    private func handleAcademicDetailRouteRequest(_ route: AcademicDetailRoute?) {
        guard let route else { return }
        guard
            route.tab.isVisible(
                isCustomCampus: isCustomCampus,
                isCommunityEnabled: isCommunityEnabled,
                isMedicalEnabled: isMedicalEnabled,
                campusID: campusID),
            CampusAcademicVisibility.isRouteVisible(
                route,
                isCustomCampus: isCustomCampus,
                isCommunityEnabled: isCommunityEnabled,
                isMedicalEnabled: isMedicalEnabled
            )
        else {
            appNavigation.requestedAcademicDetailRoute = nil
            sanitizeSelectedTab()
            return
        }

        navigationPath.removeAll()
        let changesSelectedTab = selectedTab != route.tab
        isHandlingExternalRoute = changesSelectedTab
        selectedTab = route.tab
        openRoute(route)
        if !changesSelectedTab {
            isHandlingExternalRoute = false
        }

        appNavigation.requestedAcademicDetailRoute = nil
    }

    @MainActor
    private func handleClassroomLookupRequest(_ request: ClassroomLookupRequest?) {
        guard let request else { return }
        guard
            AcademicPrimaryTab.classrooms.isVisible(
                isCustomCampus: isCustomCampus,
                isCommunityEnabled: isCommunityEnabled,
                isMedicalEnabled: isMedicalEnabled,
                campusID: campusID)
        else {
            appNavigation.requestedClassroomLookup = nil
            sanitizeSelectedTab()
            return
        }
        navigationPath.removeAll()
        selectedTab = .classrooms
        openRoute(.classroomLookup(building: request.building, room: request.room))
        appNavigation.requestedClassroomLookup = nil
    }

    @MainActor
    private func sanitizeSelectedTab() {
        guard
            !selectedTab.isVisible(
                isCustomCampus: isCustomCampus,
                isCommunityEnabled: isCommunityEnabled,
                isMedicalEnabled: isMedicalEnabled,
                campusID: campusID)
        else { return }
        selectedTab = .cultivation
        navigationPath.removeAll()
    }
}

private struct AcademicSidebarTabItem: View {
    @Environment(\.leafyControlScale) private var leafyControlScale

    let tab: AcademicPrimaryTab
    let isSelected: Bool
    let language: AppLanguagePreference
    let themeColorPreference: AppThemeColorPreference

    var body: some View {
        VStack(spacing: 4 * leafyControlScale) {
            Image(systemName: tab.icon)
                .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? AppTheme.textOnAccent(for: themeColorPreference)
                        : AppTheme.accent(for: themeColorPreference)
                )
                .frame(width: 28 * leafyControlScale, height: 28 * leafyControlScale)
                .background(
                    isSelected
                        ? AppTheme.accent(for: themeColorPreference)
                        : AppTheme.accent(for: themeColorPreference).opacity(0.12),
                    in: Circle()
                )

            Text(tab.title(language: language))
                .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54 * leafyControlScale)
        .background(
            isSelected ? AppTheme.accent(for: themeColorPreference).opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }
}
