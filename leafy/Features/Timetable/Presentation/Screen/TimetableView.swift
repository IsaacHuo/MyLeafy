import SwiftData
import SwiftSoup
import SwiftUI
import OSLog
import UIKit

private struct CourseNotePreview: Identifiable {
    let id = UUID()
    let courseName: String
    let note: String?

    var message: String {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty
            ? "\(courseName) 暂无备注。"
            : trimmed
    }
}

private enum TimetableQuickAccessAction: Equatable, Sendable {
    case processTimetable
    case shareTimetable
    case emptyClassroom
    case addSchedule
    case exportTimetable
}

private struct TimetableZoomDayRenderPayload: Identifiable {
    let preparedDay: TimetableZoomPreparedDay
    let metadata: TimetableDayMetadata?
    let occupiedPeriods: Set<Int>
    let reminders: [TimetableCellReminderRenderValue]
    let reminderPeriods: Set<Int>
    let countdownPeriods: Set<Int>
    let conflictContent: TimetableConflictDayContent

    var id: Date { preparedDay.id }
}

struct TimetableView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.leafyDependencies) private var dependencies
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @Query private var courses: [Course]
    @Query private var cellReminders: [TimetableCellReminder]
    @Query private var courseNotes: [CourseNote]
    @Query private var occurrenceNotes: [CourseOccurrenceNote]
    @Query private var courseReminderSettings: [CourseReminderSetting]

    @ObservedObject private var networkManager = ActiveCampusContext.networkManager
    @State private var isFetching = false
    @State private var progressController = AcademicOperationProgressController()
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var emptyResultIdentity: CampusIdentity?
    @State private var requiresPeriodConfiguration = false
    @State private var reauthenticationRequest: SchoolReauthenticationRequest?
    @State private var selectedCourseContext: SelectedCourseContext?
    @State private var selectedCellReminderContext: TimetableCellReminderContext?
    @State private var selectedCustomScheduleEditor: CustomScheduleEditorPresentation?
    @State private var courseNotePreview: CourseNotePreview?
    @State private var isExportSheetPresented = false
    @State private var isTimetableProcessingPresented = false
    @State private var isQuickAccessPresented = false
    @State private var isWeekPickerPresented = false
    @State private var pendingQuickAccessAction: TimetableQuickAccessAction?
    @State private var academicYearConfigurations: [SemesterRuntimeConfig]
    @State private var academicYearTimetable: AcademicYearTimetable
    @State private var academicYearMenuModel: TimetableCalendarMenuModel
    @State private var timetableCourseWeekProjections: [UUID: TimetableCourseWeekProjection] = [:]
    @State private var timetableCellReminderProjections: [UUID: TimetableCellReminderProjection] = [:]
    @State private var currentWeek: Int
    @State private var isAwayFromCurrentSchedule = false
    @State private var selectedConflictSelection: TimetableConflictSelection?
    @State private var pendingConflictItem: TimetableAgendaItem?
    @State private var conflictDayCache = TimetableConflictDayCache()
    @State private var selectedDaySummary: TimetableDaySelection?
    @State private var lastSyncAt = TimetableCacheMetadata.lastSyncAt
    @State private var lastFailureMessage = TimetableCacheMetadata.lastFailureMessage
    @State private var isTimetableInteractivelyLaidOut = false
    @State private var hasInitializedTimetable = false
    @State private var hasPerformedInitialAppearance = false
    @State private var hasRunDeferredInitialWork = false
    @State private var timetableGridSnapshot: TimetableGridSnapshot?
    @State private var timetableGridSnapshotCache = TimetableGridSnapshotCache()
    @State private var timetableLayoutMetricsCache = TimetableLayoutMetricsCache()
    @State private var timetableDayMetadataCache = TimetableDayMetadataCache()
    @State private var isWeatherAdvicePresented = false
    @State private var cachedTimetableWeather: TimetableWeatherSnapshot?
    @State private var customScheduleEvents: [CustomScheduleEvent]
    @State private var cachedExamArrangements: [ExamArrangement]
    @State private var calendarEventSignature = AcademicCalendarEvents.displayEvents()
    @State private var timetableScheduleProjectionSnapshot: TimetableScheduleProjectionSnapshot
    @State private var timetableBackgroundImage: UIImage?
    @State private var timetableBackgroundLoadTask: Task<Void, Never>?
    @State private var timetableBackgroundConfiguration = TimetableBackgroundConfiguration.load()
    @GestureState private var isTimetablePagingDragActive = false
    @GestureState private var isTimetableMagnificationActive = false
    @State private var continuousViewport: TimetableContinuousViewportController
    @State private var continuousRenderWindow: TimetableZoomRenderWindow
    @State private var continuousDayPayloads: [TimetableZoomDayRenderPayload] = []
    @State private var hasDeferredContinuousPayloadRefresh = false
    @State private var settledDisplayMode = TimetableDisplayMode.week
    @State private var timetableViewportSize: CGSize = .zero

    @AppStorage("hasSeenTimetableOnboarding") private var hasSeenTimetableOnboarding = false
    @AppStorage("timetableHidesWeekends") private var timetableHidesWeekends = false
    @AppStorage(TimetableCurrentTimeIndicatorPreference.isEnabledKey)
    private var timetableCurrentTimeIndicatorIsEnabled = TimetableCurrentTimeIndicatorPreference.defaultIsEnabled
    @AppStorage(TimetableCurrentTimeIndicatorPreference.thicknessKey)
    private var timetableCurrentTimeIndicatorThickness = TimetableCurrentTimeIndicatorPreference.defaultThickness
    @AppStorage(TimetableCurrentTimeIndicatorPreference.transparencyKey)
    private var timetableCurrentTimeIndicatorTransparency = TimetableCurrentTimeIndicatorPreference.defaultTransparency

    private static let backgroundLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.isaachuo.leafy",
        category: "TimetableBackground"
    )
    private static let dataLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.isaachuo.leafy",
        category: "TimetableData"
    )
    private var totalWeeks: Int { academicYearTimetable.weeks.count }
    private var timelineStartDate: Date {
        academicYearTimetable.weeks.first?.weekStartDate ?? UserTimetableSettings.calendar.startOfDay(for: Date())
    }
    private var totalClasses: Int { TimetablePeriodSchedule.slots.count }
    private var overviewRowSpacing: CGFloat { 1.5 * leafyControlScale }
    private var overviewCardInset: CGFloat { 1.5 * leafyControlScale }
    private var overviewMinimumRowHeight: CGFloat { 26 * leafyControlScale }
    private var overviewBottomClearance: CGFloat { 16 * leafyControlScale }
    private var axisWidth: CGFloat { 34 * leafyControlScale }
    private var headerHeight: CGFloat { 52 * leafyControlScale }
    private var timetableHorizontalPadding: CGFloat { 4 * leafyControlScale }
    private var timetableDaySpacing: CGFloat { 5 * leafyControlScale }
    private var timetableWeekSpacing: CGFloat { 6 * leafyControlScale }
    private var allowsTimetableAgendaFallback: Bool {
        horizontalSizeClass == .regular
    }
    private var showsToolbarRefreshButton: Bool {
        horizontalSizeClass == .regular
    }

    private static func makeAcademicYearTimetable(
        configurations: [SemesterRuntimeConfig] = [SemesterConfig.current],
        referenceDate: Date = Date()
    ) -> AcademicYearTimetable {
        AcademicYearTimetable(container: configurations.first ?? SemesterConfig.current)
    }

    init() {
        let configurations = [SemesterConfig.current]
        let timetable = Self.makeAcademicYearTimetable(configurations: configurations)
        let currentPage = timetable.pageIndex(containing: Date()) ?? SemesterConfig.currentWeek()
        let calendar = UserTimetableSettings.calendar
        let today = calendar.startOfDay(for: Date())
        let academicEnd = calendar.date(byAdding: .day, value: -1, to: timetable.endDate)
            ?? timetable.endDate
        let initialWeekStart = timetable.week(atPageIndex: currentPage)?.weekStartDate
            ?? today
        let continuousViewport = TimetableContinuousViewportController(
            weekStartDate: initialWeekStart,
            centerDate: today,
            rangeStart: timetable.startDate,
            rangeEnd: academicEnd,
            calendar: calendar
        )
        let continuousRenderWindow = TimetableZoomRenderWindow.make(
            weekStartDate: initialWeekStart,
            academicYear: timetable,
            calendar: calendar
        )
        let countdownEvents = CustomScheduleStore.load()
        let exams = SchoolDataCache.loadExamSchedule()

        _academicYearConfigurations = State(initialValue: configurations)
        _academicYearTimetable = State(initialValue: timetable)
        _academicYearMenuModel = State(
            initialValue: TimetableCalendarMenuModel(
                timetable: timetable,
                configurations: configurations
            )
        )
        _currentWeek = State(initialValue: currentPage)
        _continuousViewport = State(initialValue: continuousViewport)
        _continuousRenderWindow = State(initialValue: continuousRenderWindow)
        _customScheduleEvents = State(initialValue: countdownEvents)
        _cachedExamArrangements = State(initialValue: exams)
        _timetableScheduleProjectionSnapshot = State(
            initialValue: TimetableScheduleProjectionSnapshot.make(
                countdownEvents: countdownEvents,
                exams: exams,
                academicYear: timetable
            )
        )
    }

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    private var currentAcademicYearPage: Int {
        academicYearTimetable.pageIndex(containing: Date()) ?? SemesterConfig.currentWeek()
    }

    private var currentTimelineWeek: AcademicYearWeek? {
        academicYearTimetable.week(atPageIndex: currentWeek)
    }

    private var selectedTimelineDate: Date {
        currentTimelineWeek?.referenceDate ?? Date()
    }

    private var selectedTimeScopeSnapshot: TimetableTimeScopeSnapshot {
        let referenceDate = Date()
        let config = TimetableTimeScopeConfigurationResolver.configuration(
            for: referenceDate,
            configurations: academicYearConfigurations
        ) ?? SemesterConfig.current
        let displayedMonthDate = referenceDate < config.semesterStartDate
            ? config.semesterStartDate
            : referenceDate
        let days = UserTimetableSettings.calendar.dateComponents(
            [.day],
            from: UserTimetableSettings.calendar.startOfDay(for: config.semesterStartDate),
            to: UserTimetableSettings.calendar.startOfDay(for: referenceDate)
        ).day ?? 0
        return TimetableTimeScopeSnapshot.make(
            currentWeek: min(20, max(1, days / 7 + 1)),
            referenceDate: referenceDate,
            displayedMonthDate: displayedMonthDate,
            language: leafyLanguage,
            semesterConfig: config,
            configurations: academicYearConfigurations
        )
    }

    private var selectedSemesterContext: (semesterID: String, week: Int)? {
        guard let currentTimelineWeek,
              case let .teaching(semesterID, weekNumber) = currentTimelineWeek.phase else { return nil }
        return (semesterID, weekNumber)
    }

    private var selectedSemesterCourses: [Course] {
        return courses
    }

    private var selectedSemesterWeek: Int {
        selectedSemesterContext?.week ?? SemesterConfig.currentWeek()
    }

    private var displayMode: TimetableDisplayMode {
        settledDisplayMode
    }

    private var viewportVerticalOffsetBinding: Binding<CGFloat> {
        Binding(
            get: { continuousViewport.verticalOffset },
            set: { continuousViewport.verticalOffset = max($0, 0) }
        )
    }

    private var usesCustomTimetableBackground: Bool {
        guard timetableBackgroundConfiguration.usesCustomBackground else { return false }
        if timetableBackgroundConfiguration.kind == .photo {
            return timetableBackgroundImage != nil
        }
        return true
    }

    private var timetableBackgroundCoursePalette: [Color]? {
        guard usesCustomTimetableBackground else { return nil }
        return timetableBackgroundConfiguration.coursePalette(colorScheme: colorScheme)
    }

    private var timetableRenderInput: TimetableRenderInput {
        TimetableRenderInput(
            courses: courses,
            notes: courseNotes,
            occurrenceNotes: occurrenceNotes,
            cellReminders: cellReminders.filter { reminder in
                reminder.startsAt.map(academicYearTimetable.contains) ?? true
            },
            hidesWeekends: timetableHidesWeekends,
            courseWeekProjections: timetableCourseWeekProjections,
            cellReminderProjections: timetableCellReminderProjections
        )
    }

    var body: some View {
        rootAlerts
    }

    private var rootNavigation: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.compact) {
                if !networkManager.hasCachedIdentity {
                    unauthenticatedState
                        .padding(.horizontal, AppSpacing.page)
                } else if isCustomCampus && courses.isEmpty {
                    customCampusEmptyState
                        .padding(.horizontal, AppSpacing.page)
                } else {
                    timetableContent
                }
            }
            .padding(.top, AppSpacing.micro)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(timetablePageBackground)
            .tint(AppTheme.accent(for: themeColorPreference))
            .navigationTitle("")
            .leafyInlineNavigationTitle()
            .toolbar {
                leadingToolbarItems

                ToolbarItemGroup(placement: .leafyTrailing) {
                    if isAwayFromCurrentSchedule {
                        toolbarReturnButton
                            .transition(returnButtonTransition)
                    }
                    toolbarWeekMenu
                    if showsToolbarRefreshButton {
                        toolbarRefreshButton
                    }
                }
            }
            .navigationDestination(isPresented: $isTimetableProcessingPresented) {
                TimetableProcessingView()
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isAwayFromCurrentSchedule)
        }
    }

    private var rootLifecycle: some View {
        rootBackgroundLifecycle
    }

    private var rootBaseLifecycle: some View {
        rootDataLifecycle
            .onChange(of: appNavigation.requestedTimetableCourseID) { _, requestedID in
                handleTimetableCourseDeepLink(requestedID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .customScheduleEventsDidChange)) { _ in
                reloadCustomCountdownEvents()
            }
            .onReceive(NotificationCenter.default.publisher(for: .schoolExamScheduleDidChange)) { _ in
                reloadExamArrangements()
            }
            .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { notification in
                handleSchoolDataRefresh(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .semesterRuntimeConfigDidChange)) { _ in
                applySemesterRuntimeConfig(SemesterConfig.current)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nationalCalendarRuntimeConfigDidChange)) { _ in
                handleNationalCalendarRuntimeConfigChange()
            }
    }

    private var rootPresentationLifecycle: some View {
        rootNavigation
            .task {
                await initializeTimetableIfNeeded()
                await maintainTimetableWeatherPreview()
            }
            .onAppear(perform: handleAppear)
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: currentWeek) { _, newValue in
                handleCurrentWeekChange(newValue)
            }
            .onChange(of: continuousViewport.windowRevision) { _, _ in
                handleContinuousWindowRevision()
            }
            .onChange(of: continuousViewport.phase) { _, phase in
                guard phase == .idle else { return }
                settledDisplayMode = continuousViewport.isThreeDay ? .threeDay : .week
                if hasDeferredContinuousPayloadRefresh {
                    refreshContinuousDayPayloads()
                }
                syncReturnButtonVisibility(for: currentWeek)
            }
            .onChange(of: isTimetablePagingDragActive) { _, isActive in
                if !isActive { continuousViewport.cancelPaging(reducesMotion: accessibilityReduceMotion) }
            }
            .onChange(of: isTimetableMagnificationActive) { _, isActive in
                if !isActive { continuousViewport.cancelMagnification() }
            }
            .onChange(of: timetableHidesWeekends) { _, _ in
                handleWeekendVisibilityChange()
            }
    }

    private var rootDataLifecycle: some View {
        rootPresentationLifecycle
            .onChange(of: courses.count) { _, _ in
                handleCoursesCountChange()
            }
            .onChange(of: courseNotes.count) { _, _ in
                handleCourseNotesCountChange()
            }
            .onChange(of: occurrenceNotes.count) { _, _ in
                handleCourseNotesCountChange()
            }
            .onChange(of: courseReminderSettings.count) { _, _ in
                handleCourseReminderSettingsCountChange()
            }
            .onChange(of: cellReminders.count) { _, _ in
                handleCellRemindersCountChange()
            }
            .onChange(of: timetableRenderInput.signature) { _, _ in
                handleTimetableGridInputChange()
            }
    }

    private var rootBackgroundLifecycle: some View {
        rootBaseLifecycle
            .onReceive(NotificationCenter.default
                .publisher(for: .timetableBackgroundSettingsDidChange)) { notification in
                    let configuration = notification.userInfo?[TimetableBackgroundStore.configurationUserInfoKey]
                        as? TimetableBackgroundConfiguration
                    reloadTimetableBackground(configuration: configuration)
            }
    }

    private var timetablePageBackground: some View {
        ZStack {
            LeafyPageBackground()

            if usesCustomTimetableBackground {
                TimetableBackgroundLayer(
                    configuration: timetableBackgroundConfiguration,
                    image: timetableBackgroundImage
                )
                .ignoresSafeArea()
            }
        }
    }

    private var rootSheets: some View {
        rootLifecycle
            .leafySheet(item: $selectedCourseContext) { context in
                CourseDetailSheet(context: context)
                    .presentationDetents([.medium, .large])
            }
            .leafySheet(item: $selectedCellReminderContext) { context in
                CustomScheduleEditorSheet(presentation: .timetable(context))
                    .presentationDetents([.medium, .large])
            }
            .leafySheet(item: $selectedCustomScheduleEditor, onDismiss: reloadCustomCountdownEvents) { presentation in
                CustomScheduleEditorSheet(presentation: presentation)
                    .presentationDetents([.medium, .large])
            }
            .leafySheet(item: $selectedConflictSelection, onDismiss: {
                if let item = pendingConflictItem {
                    pendingConflictItem = nil
                    handleConflictItemTap(item)
                }
            }) { selection in
                TimetableConflictListSheet(selection: selection) { item in
                    pendingConflictItem = item
                    selectedConflictSelection = nil
                }
                .presentationDetents([.medium, .large])
            }
            .leafySheet(item: $selectedDaySummary) { selection in
                DayScheduleSummarySheet(
                    selection: selection,
                    courses: selection.semesterID.map { semesterID in
                        courses
                    } ?? [],
                    exams: cachedExamArrangements,
                    lastSyncAt: lastSyncAt,
                    lastFailureMessage: lastFailureMessage
                )
                .presentationDetents([.medium, .large])
            }
            .leafySheet(isPresented: $isExportSheetPresented) {
                TimetableExportSheet(
                    currentWeek: selectedSemesterWeek,
                    courses: selectedSemesterCourses,
                    courseNotes: courseNotes,
                    occurrenceNotes: occurrenceNotes,
                    cellReminders: cellReminders,
                    exams: cachedExamArrangements,
                    lastSyncAt: lastSyncAt,
                    lastFailureMessage: lastFailureMessage,
                    includesWeekendsByDefault: !timetableHidesWeekends
                )
                .presentationDetents([.large])
            }
            .leafySheet(isPresented: $isWeatherAdvicePresented, onDismiss: {
                Task { await refreshTimetableWeatherPreview() }
            }) {
                TimetableWeatherAdviceSheet(
                    currentWeek: selectedSemesterWeek,
                    courses: selectedSemesterCourses,
                    cellReminders: cellReminders,
                    exams: cachedExamArrangements,
                    weatherPreview: $cachedTimetableWeather
                )
                .presentationDetents([.medium, .large])
            }
            .popover(isPresented: $isWeekPickerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                TimetableWeekPickerPanel(
                    model: academicYearMenuModel,
                    selectedDate: selectedTimelineDate,
                    referenceDate: Date(),
                    overviewSnapshot: selectedTimeScopeSnapshot,
                    onSelect: selectTimetableWeek
                )
                .frame(idealWidth: 420, idealHeight: 520)
                .leafyModalSurface()
                .presentationDetents([.medium, .large])
                .presentationCompactAdaptation(.sheet)
            }
    }

    private var rootAlerts: some View {
        rootSheets
            .alert("提示", isPresented: $showAlert) {
                if requiresPeriodConfiguration {
                    Button("补全课表作息") {
                        appNavigation.openProfileRoute(.timetableSettings); requiresPeriodConfiguration = false }
                }
                if emptyResultIdentity != nil {
                    Button("清空学校课程", role: .destructive) { clearConfirmedEmptyTimetable() }
                }
                Button("保留当前数据", role: .cancel) { emptyResultIdentity = nil }
            } message: {
                Text(alertMessage)
            }
            .alert("欢迎使用 \(AppBrand.displayName)", isPresented: onboardingAlertBinding) {
                Button("知道了", role: .cancel) {
                    hasSeenTimetableOnboarding = true
                }
            } message: {
                Text(onboardingMessage)
            }
            .alert(item: $courseNotePreview) { preview in
                Alert(
                    title: Text("课程备注"),
                    message: Text(preview.message),
                    dismissButton: .default(Text("知道了"))
                )
            }
            .schoolReauthenticationSheet(
                request: $reauthenticationRequest,
                networkManager: networkManager,
                operationKind: .timetable,
                progressController: progressController
            ) { _ in
                Task {
                    await fetchAndParseTimetable(
                        userInitiated: true,
                        allowsAutomaticRecovery: false
                    )
                }
            }
            .academicOperationProgress(progressController)
    }

    private var onboardingAlertBinding: Binding<Bool> {
        Binding(
            get: { networkManager.hasCachedIdentity && isTimetableInteractivelyLaidOut && !hasSeenTimetableOnboarding },
            set: { if !$0 { hasSeenTimetableOnboarding = true } }
        )
    }

    private var onboardingMessage: String {
        if isCustomCampus {
            return "可从时间视图设置学期和第一周的星期一。课表固定为 20 周，成绩和考试可手动导入；在我的页可选择开启 iCloud 同步。"
        }
        return "可从时间视图调整学期和第一周的星期一。课表固定为 20 周；刷新会替换课程，保留你写的备注和个人日程。离线时仍可查看，在我的页可选择开启 iCloud 同步。"
    }

    @MainActor
    private func initializeTimetableIfNeeded() async {
        guard !hasInitializedTimetable else { return }
        let scope = CampusOperationScope()
        hasInitializedTimetable = true
        do {
            try TimetableLocalDataSemesterMigration.migrateIfNeeded(
                courses: courses,
                courseNotes: courseNotes,
                occurrenceNotes: occurrenceNotes,
                reminderSettings: courseReminderSettings,
                cellReminders: cellReminders,
                modelContext: modelContext
            )
            try TimetableSingleContainerMigration.run(context: modelContext)
        } catch {
            Self.dataLogger
                .error("Failed to migrate historical timetable data: \(error.localizedDescription, privacy: .public)")
        }
        syncAcademicYearDataProjections()
        syncTimetableScheduleProjectionSnapshot()
        syncTimetableGridSnapshot()
        syncReturnButtonVisibility()

        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()
        guard scope.isCurrent, !Task.isCancelled else { return }
        applySemesterRuntimeConfig(semesterConfig)
        await refreshTimetableWeatherPreview()
    }

    private func handleAppear() {
        guard !hasPerformedInitialAppearance else {
            syncReturnButtonVisibility()
            return
        }
        hasPerformedInitialAppearance = true
        reloadTimetableBackground()
        refreshContinuousDayPayloads()
        syncReturnButtonVisibility()
    }

    private func handleFirstInteractiveLayout() {
        isTimetableInteractivelyLaidOut = true
        guard !hasRunDeferredInitialWork else { return }
        hasRunDeferredInitialWork = true
        let scope = CampusOperationScope()
        Task { @MainActor in
            await Task.yield()
            guard scope.isCurrent, !Task.isCancelled else { return }
            publishWidgetSnapshot()
            refreshScheduleReportNotifications()
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        reloadExamArrangements()
        if !isWeatherAdvicePresented {
            Task { await refreshTimetableWeatherPreview() }
        }
        syncReturnButtonVisibility()
        publishWidgetSnapshot()
    }

    private func handleCurrentWeekChange(_ newValue: Int) {
        if continuousViewport.phase == .idle,
           let weekStart = academicYearTimetable.week(atPageIndex: newValue)?.weekStartDate,
           !UserTimetableSettings.calendar.isDate(weekStart, inSameDayAs: continuousViewport.weekStartDate) {
            continuousViewport.positionOnWeek(
                weekStart,
                centersToday: newValue == currentAcademicYearPage
            )
        }
        syncReturnButtonVisibility(for: newValue)
    }

    private func handleContinuousWindowRevision() {
        continuousRenderWindow = TimetableZoomRenderWindow.make(
            weekStartDate: continuousViewport.weekStartDate,
            academicYear: academicYearTimetable
        )
        if let page = academicYearTimetable.pageIndex(containing: continuousViewport.centerDate),
           page != currentWeek {
            currentWeek = page
        }
        refreshContinuousDayPayloads(forNewWindow: true)
        syncReturnButtonVisibility(for: currentWeek)
    }

    private func refreshContinuousDayPayloads(forNewWindow: Bool = false) {
        guard forNewWindow || continuousViewport.phase == .idle else {
            hasDeferredContinuousPayloadRefresh = true
            return
        }
        let signpostState = LeafyPerformanceSignposter.timetable.beginInterval("zoom-window-prepare")
        defer {
            LeafyPerformanceSignposter.timetable.endInterval("zoom-window-prepare", signpostState)
        }
        let snapshot = currentTimetableGridSnapshot()
        continuousDayPayloads = continuousRenderWindow.days.map { preparedDay in
            guard let week = preparedDay.academicWeek else {
                return TimetableZoomDayRenderPayload(
                    preparedDay: preparedDay,
                    metadata: nil,
                    occupiedPeriods: [],
                    reminders: [],
                    reminderPeriods: [],
                    countdownPeriods: [],
                    conflictContent: .empty
                )
            }
            let metadata = dayMetadata(day: preparedDay.dayOfWeek, week: week)
            let reminders = snapshot.cellReminders(week: week, day: preparedDay.dayOfWeek)
            return TimetableZoomDayRenderPayload(
                preparedDay: preparedDay,
                metadata: metadata,
                occupiedPeriods: snapshot.occupiedPeriods(day: preparedDay.dayOfWeek, week: week),
                reminders: reminders,
                reminderPeriods: Set(reminders.flatMap { Array($0.displayPeriodRange) }),
                countdownPeriods: Set(metadata.countdowns.flatMap { Array($0.startPeriod ... $0.endPeriod) }),
                conflictContent: conflictDayCache.content(
                    metadata: metadata,
                    snapshot: snapshot,
                    totalClasses: totalClasses
                )
            )
        }
        hasDeferredContinuousPayloadRefresh = false
    }

    private func handleWeekendVisibilityChange() {
        syncTimetableGridSnapshot()
    }

    private func handleCoursesCountChange() {
        syncAcademicYearDataProjections()
        syncTimetableGridSnapshot()
        if courses.isEmpty {
            isTimetableInteractivelyLaidOut = false
        }
        syncReturnButtonVisibility()
        publishWidgetSnapshot()
        refreshScheduleReportNotifications()
    }

    private func handleCourseNotesCountChange() {
        syncTimetableGridSnapshot()
        publishWidgetSnapshot()
    }

    private func handleCourseReminderSettingsCountChange() {
        publishWidgetSnapshot()
    }

    private func handleCellRemindersCountChange() {
        syncAcademicYearDataProjections()
        syncTimetableGridSnapshot()
        publishWidgetSnapshot()
        refreshScheduleReportNotifications()
    }

    private func handleTimetableGridInputChange() {
        syncAcademicYearDataProjections()
        syncTimetableGridSnapshot()
    }

    private func handleNationalCalendarRuntimeConfigChange() {
        calendarEventSignature = AcademicCalendarEvents.displayEvents()
        syncTimetableScheduleProjectionSnapshot()
        publishWidgetSnapshot()
        refreshScheduleReportNotifications()
    }

    private func handleSchoolDataRefresh(_ notification: Notification) {
        let event = notification.object as? SchoolDataRefreshEvent
        guard event?.contains(.timetable) == true || event?.contains(.exams) == true else { return }

        if event?.contains(.timetable) == true {
            lastSyncAt = TimetableCacheMetadata.lastSyncAt
            lastFailureMessage = TimetableCacheMetadata.lastFailureMessage
            syncTimetableGridSnapshot()
            syncReturnButtonVisibility()
        }
        if event?.contains(.exams) == true {
            reloadExamArrangements()
        }
        refreshScheduleReportNotifications()
        publishWidgetSnapshot()
    }

    private func reloadCustomCountdownEvents() {
        customScheduleEvents = CustomScheduleStore.load()
        syncTimetableScheduleProjectionSnapshot()
        refreshScheduleReportNotifications()
    }

    private func reloadExamArrangements() {
        cachedExamArrangements = SchoolDataCache.loadExamSchedule()
        syncTimetableScheduleProjectionSnapshot()
        refreshScheduleReportNotifications()
    }

    @MainActor
    private func refreshTimetableWeatherPreview() async {
        let weatherService = dependencies.timetableWeatherService
        guard weatherService.authorizationState() == .authorized else {
            cachedTimetableWeather = nil
            return
        }

        if let cached = weatherService.cachedWeather(maxAge: 30 * 60) {
            cachedTimetableWeather = cached
            return
        }

        cachedTimetableWeather = nil
        do {
            cachedTimetableWeather = try await weatherService.fetchCurrentWeather(
                requestsPermissionIfNeeded: false
            )
        } catch {
            cachedTimetableWeather = nil
        }
    }

    private func maintainTimetableWeatherPreview() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(30 * 60))
            } catch {
                return
            }

            if !isWeatherAdvicePresented {
                await refreshTimetableWeatherPreview()
            }
        }
    }

    private func refreshScheduleReportNotifications() {
        let scope = CampusOperationScope()
        Task { @MainActor in
            guard scope.isCurrent, !Task.isCancelled else { return }
            try? await ScheduleReportNotificationManager.refreshIfEnabled(modelContext: modelContext)
        }
    }

    @MainActor
    private func applySemesterRuntimeConfig(_ config: SemesterRuntimeConfig) {
        _ = config
        rebuildAcademicYearTimeline(referenceDate: Date(), positionsToReferenceDate: false)
        publishWidgetSnapshot()
    }

    @MainActor
    private func rebuildAcademicYearTimeline(
        referenceDate: Date,
        positionsToReferenceDate: Bool
    ) {
        academicYearConfigurations = [SemesterConfig.current]
        academicYearTimetable = Self.makeAcademicYearTimetable(
            configurations: academicYearConfigurations,
            referenceDate: referenceDate
        )
        academicYearMenuModel = TimetableCalendarMenuModel(
            timetable: academicYearTimetable,
            configurations: academicYearConfigurations,
            referenceDate: Date()
        )
        calendarEventSignature = AcademicCalendarEvents.displayEvents()
        syncAcademicYearDataProjections()
        syncTimetableScheduleProjectionSnapshot()
        timetableGridSnapshotCache.invalidate()
        timetableGridSnapshot = nil
        syncTimetableGridSnapshot()

        let referencePage = academicYearTimetable.pageIndex(containing: referenceDate) ?? SemesterConfig
            .currentWeek(date: referenceDate)
        if positionsToReferenceDate {
            currentWeek = referencePage
        } else {
            currentWeek = min(max(currentWeek, 1), totalWeeks)
        }
        let calendar = UserTimetableSettings.calendar
        let academicEnd = calendar.date(byAdding: .day, value: -1, to: academicYearTimetable.endDate)
            ?? academicYearTimetable.endDate
        continuousViewport.updateBounds(
            rangeStart: academicYearTimetable.startDate,
            rangeEnd: academicEnd
        )
        if let weekStart = academicYearTimetable.week(atPageIndex: currentWeek)?.weekStartDate {
            continuousViewport.positionOnWeek(
                weekStart,
                centersToday: referencePage == currentAcademicYearPage
            )
        }
        continuousRenderWindow = TimetableZoomRenderWindow.make(
            weekStartDate: continuousViewport.weekStartDate,
            academicYear: academicYearTimetable,
            calendar: calendar
        )
        syncReturnButtonVisibility(for: currentWeek)
    }

    @MainActor
    private func syncAcademicYearDataProjections() {
        var courseProjections: [UUID: TimetableCourseWeekProjection] = [:]
        for course in courses {
            guard let config = academicYearTimetable.configuration(semesterID: course.sourceSemesterID) else {
                continue
            }
            var displayWeeks: [Int] = []
            var semesterWeekByDisplayWeek: [Int: Int] = [:]
            for semesterWeek in course.weeks {
                guard let occurrenceDate = UserTimetableSettings.calendar.date(
                          byAdding: .day,
                          value: (semesterWeek - 1) * 7 + (course.dayOfWeek - 1),
                          to: config.semesterStartDate
                      ), isDateInDisplayedAcademicYear(occurrenceDate),
                      let displayWeek = academicYearTimetable.pageIndex(containing: occurrenceDate) else {
                    continue
                }
                displayWeeks.append(displayWeek)
                semesterWeekByDisplayWeek[displayWeek] = semesterWeek
            }
            courseProjections[course.id] = TimetableCourseWeekProjection(
                displayWeeks: Array(Set(displayWeeks)).sorted(),
                semesterWeekByDisplayWeek: semesterWeekByDisplayWeek
            )
        }
        timetableCourseWeekProjections = courseProjections

        var reminderProjections: [UUID: TimetableCellReminderProjection] = [:]
        for reminder in cellReminders {
            guard let date = reminder.startsAt ?? reminder.resolvedStartDate,
                  let displayWeek = academicYearTimetable.pageIndex(containing: date) else { continue }
            let weekday = UserTimetableSettings.calendar.component(.weekday, from: date)
            reminderProjections[reminder.id] = TimetableCellReminderProjection(
                displayWeek: displayWeek,
                dayOfWeek: ((weekday + 5) % 7) + 1
            )
        }
        timetableCellReminderProjections = reminderProjections
    }

    private func reloadTimetableBackground(configuration suppliedConfiguration: TimetableBackgroundConfiguration? =
        nil) {
        timetableBackgroundLoadTask?.cancel()
        let configuration = suppliedConfiguration ?? TimetableBackgroundConfiguration.load()
        let previousConfiguration = timetableBackgroundConfiguration
        timetableBackgroundConfiguration = configuration

        guard configuration.usesCustomBackground, configuration.kind == .photo else {
            timetableBackgroundImage = nil
            return
        }

        let filename = configuration.filename
        if previousConfiguration.kind == .photo,
           previousConfiguration.filename == filename,
           timetableBackgroundImage != nil {
            return
        }
        timetableBackgroundLoadTask = Task {
            let image = await TimetableBackgroundStore.image(filename: filename)
            guard !Task.isCancelled,
                  filename == TimetableBackgroundConfiguration.load().filename
            else {
                return
            }
            timetableBackgroundImage = image
            if image == nil {
                Self.backgroundLogger.error(
                    "Configured timetable background image could not be loaded; filename=\(filename, privacy: .private(mask: .hash))"
                )
            }
        }
    }

    private func handleTimetableCourseDeepLink(_ requestedID: UUID?) {
        guard let requestedID else { return }
        openCourseFromDeepLink(id: requestedID)
        appNavigation.requestedTimetableCourseID = nil
    }

    @ToolbarContentBuilder
    private var leadingToolbarItems: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .leafyLeading) {
                quickAccessMenu
            }
            ToolbarSpacer(.fixed, placement: .leafyLeading)
            ToolbarItem(placement: .leafyLeading) {
                timetableWeatherButton
            }
        } else {
            ToolbarItem(placement: .leafyLeading) {
                HStack(spacing: 8 * leafyControlScale) {
                    quickAccessMenu
                    timetableWeatherButton
                }
            }
        }
    }

    private var quickAccessMenu: some View {
        Button {
            isQuickAccessPresented.toggle()
        } label: {
            toolbarIconLabel(systemName: "slider.horizontal.3")
                .frame(
                    width: LeafyRootChromeMetrics.controlDiameter,
                    height: LeafyRootChromeMetrics.controlDiameter
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: $isQuickAccessPresented,
            attachmentAnchor: .point(.bottomLeading),
            arrowEdge: .top
        ) {
            quickAccessPopoverPresentation
                .presentationCompactAdaptation(.popover)
                .onDisappear(perform: completeQuickAccessDismissal)
        }
        .accessibilityLabel("首页快捷入口")
    }

    @ViewBuilder
    private var quickAccessPopoverPresentation: some View {
        if #available(iOS 26.0, *) {
            quickAccessPopoverContent
        } else {
            quickAccessPopoverContent
                .presentationBackground(AppTheme.topBarMaterial)
        }
    }

    private var quickAccessPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCustomCampus {
                quickAccessPopoverButton(
                    "课表处理",
                    systemImage: "slider.horizontal.3",
                    action: .processTimetable
                )
            } else {
                quickAccessPopoverButton(
                    "共享课表",
                    systemImage: "person.2.fill",
                    action: .shareTimetable
                )
            }

            if !isCustomCampus {
                quickAccessPopoverButton(
                    "空闲教室",
                    systemImage: "building.2.crop.circle",
                    action: .emptyClassroom
                )
            }

            quickAccessPopoverButton(
                "添加日程",
                systemImage: "calendar.badge.plus",
                action: .addSchedule
            )

            quickAccessPopoverButton(
                "导出课表",
                systemImage: "square.and.arrow.up",
                action: .exportTimetable
            )
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func quickAccessPopoverButton(
        _ title: String,
        systemImage: String,
        action: TimetableQuickAccessAction
    ) -> some View {
        Button {
            scheduleQuickAccessAction(action)
        } label: {
            HStack(spacing: 8 * leafyControlScale) {
                Image(systemName: systemImage)
                    .font(.system(size: 12 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                    .frame(width: 22 * leafyControlScale)

                Text(title)
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
            }
            .frame(minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12 * leafyControlScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func scheduleQuickAccessAction(_ action: TimetableQuickAccessAction) {
        pendingQuickAccessAction = action
        isQuickAccessPresented = false
    }

    private func completeQuickAccessDismissal() {
        guard !isQuickAccessPresented, let action = pendingQuickAccessAction else { return }
        pendingQuickAccessAction = nil
        performQuickAccessAction(action)
    }

    private func performQuickAccessAction(_ action: TimetableQuickAccessAction) {
        switch action {
        case .processTimetable:
            isTimetableProcessingPresented = true
        case .shareTimetable:
            appNavigation.openTimetableSharing()
        case .emptyClassroom:
            appNavigation.openAcademicRoute(.emptyClassroom)
        case .addSchedule:
            presentFreeScheduleSheet()
        case .exportTimetable:
            isExportSheetPresented = true
        }
    }

    @ViewBuilder
    private var timetableWeatherButton: some View {
        if let cachedTimetableWeather {
            Button {
                isWeatherAdvicePresented = true
            } label: {
                weatherCapsuleLabel(cachedTimetableWeather)
            }
            .accessibilityLabel(
                L10n.text(
                    "天气建议，体感温度 %@",
                    language: leafyLanguage,
                    cachedTimetableWeather.timetableCapsuleText(language: leafyLanguage)
                )
            )
        } else {
            Button {
                isWeatherAdvicePresented = true
            } label: {
                toolbarIconLabel(systemName: "cloud.sun")
            }
            .accessibilityLabel("天气建议")
        }
    }

    private func toolbarIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(
                size: LeafyRootChromeMetrics.iconPointSize * leafyControlScale,
                weight: .semibold
            ))
            .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
    }

    private func weatherCapsuleLabel(_ weather: TimetableWeatherSnapshot) -> some View {
        HStack(spacing: 6 * leafyControlScale) {
            Image(systemName: weather.symbolName.isEmpty ? "cloud.sun" : weather.symbolName)
                .font(.system(size: 13 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))

            Text("\(Int(weather.apparentTemperature.rounded()))°C")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private func presentFreeScheduleSheet() {
        let week = currentWeek
        let day = defaultScheduleDay
        let occupiedPeriods = currentTimetableGridSnapshot().occupiedPeriods(day: day, week: week)
        let period = defaultSchedulePeriod(occupiedPeriods: occupiedPeriods)
        selectedCellReminderContext = TimetableCellReminderContext(
            week: week,
            day: day,
            period: period,
            date: dayMetadata(day: day, week: week).date,
            occupiedPeriods: occupiedPeriods,
            totalPeriods: totalClasses,
            reminder: nil,
            allowsDateSelection: true
        )
    }

    private var defaultScheduleDay: Int {
        let weekday = UserTimetableSettings.calendar.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }

    private func defaultSchedulePeriod(occupiedPeriods: Set<Int>) -> Int {
        let preferred = min(max(TimetablePeriodSchedule.defaultStudyPeriod(), 1), totalClasses)
        if !occupiedPeriods.contains(preferred) {
            return preferred
        }
        return (1 ... totalClasses).first { !occupiedPeriods.contains($0) } ?? preferred
    }

    private var toolbarReturnButton: some View {
        Button("回到") {
            returnToCurrentWeek()
        }
        .frame(minWidth: 44, minHeight: 44)
        .tint(AppTheme.accentEmphasis(for: themeColorPreference))
        .accessibilityLabel("回到本周")
        .accessibilityHint("返回当前日期所在周")
    }

    private var toolbarWeekMenu: some View {
        Button {
            isWeekPickerPresented = true
        } label: {
            Text(weekTitle(currentWeek))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
        }
        .accessibilityLabel(weekPickerAccessibilityLabel)
        .accessibilityHint("选择要查看的教学周或假期")
    }

    private func weekTitle(_ page: Int) -> String {
        guard let week = academicYearTimetable.week(atPageIndex: page) else { return "本周" }
        switch week.phase {
        case let .teaching(_, weekNumber):
            return L10n.text("第 %d 周", language: leafyLanguage, weekNumber)
        case let .vacation(_, category):
            return TimetableCalendarMenuModel.vacationTitle(category: category, language: leafyLanguage)
        case .unconfigured:
            return shortWeekDateRange(week)
        }
    }

    private var weekPickerAccessibilityLabel: String {
        guard let week = currentTimelineWeek else { return weekTitle(currentWeek) }
        switch week.phase {
        case let .teaching(semesterID, weekNumber):
            let startDate = academicYearTimetable.configuration(semesterID: semesterID)?.semesterStartDate
            let academicYear = TimetableCalendarMenuModel.academicYearTitle(semesterID: semesterID)
            let semester = TimetableCalendarMenuModel.semesterSeasonTitle(
                semesterID: semesterID,
                semesterStartDate: startDate
            )
            return "\(academicYear)学年，\(semester)，第 \(weekNumber) 周"
        case let .vacation(_, category):
            return TimetableCalendarMenuModel.vacationTitle(category: category, language: leafyLanguage)
        case .unconfigured:
            return shortWeekDateRange(week)
        }
    }

    @MainActor
    private func selectTimetableWeek(_ date: Date) {
        if !academicYearTimetable.contains(date) {
            rebuildAcademicYearTimeline(referenceDate: date, positionsToReferenceDate: false)
        }
        guard let page = academicYearTimetable.pageIndex(containing: date) else { return }
        currentWeek = page
        isWeekPickerPresented = false
        syncReturnButtonVisibility(for: page)
    }

    private func shortWeekDateRange(_ week: AcademicYearWeek) -> String {
        let start = TimetableClock.formatter(DateFormatters.chineseDay).string(from: max(
            week.weekStartDate,
            academicYearTimetable.startDate
        ))
        let end = TimetableClock.formatter(DateFormatters.chineseDay).string(from: min(
            week.weekEndDate(),
            UserTimetableSettings.calendar.date(byAdding: .day, value: -1, to: academicYearTimetable.endDate)
                ?? week.weekEndDate()
        ))
        return "\(start)－\(end)"
    }

    private func returnToCurrentWeek() {
        if !academicYearTimetable.contains(Date()) {
            rebuildAcademicYearTimeline(referenceDate: Date(), positionsToReferenceDate: true)
            return
        }
        let week = currentAcademicYearPage
        continuousViewport.returnToToday()
        currentWeek = week
        isAwayFromCurrentSchedule = false
    }

    private var returnButtonTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.92)),
            removal: .opacity
                .combined(with: .scale(scale: 0.92))
        )
    }

    @ViewBuilder
    private var toolbarRefreshButton: some View {
        if isFetching {
            ProgressView()
        } else {
            Button {
                if isCustomCampus {
                    isTimetableProcessingPresented = true
                } else {
                    Task { await fetchAndParseTimetable(userInitiated: true) }
                }
            } label: {
                Image(systemName: isCustomCampus ? "slider.horizontal.3" : "arrow.clockwise")
            }
            .accessibilityLabel(isCustomCampus ? "课表处理" : "刷新")
        }
    }

    private var timetableContent: some View {
        VStack(spacing: AppSpacing.card) {
            GeometryReader { geometry in
                let gridSnapshot = currentTimetableGridSnapshot()
                let dayCount = timetableHidesWeekends ? 5 : 7
                let metrics = layoutMetrics(for: geometry.size, dayCount: dayCount)
                continuousTimetable(gridSnapshot: gridSnapshot, metrics: metrics)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .onAppear { timetableViewportSize = geometry.size }
                    .onChange(of: geometry.size) { _, size in
                        guard size.width > 0, size.height > 0 else { return }
                        continuousViewport.resizeViewport()
                        timetableViewportSize = size
                    }
            }
        }
        .simultaneousGesture(timetableMagnificationGesture)
        .simultaneousGesture(timetableHorizontalPagingGesture)
        .accessibilityValue(displayMode == .threeDay ? "三日放大视图" : "一周课表视图")
        .accessibilityActions {
            if !isCustomCampus {
                Button("刷新课表") {
                    Task { await refreshTimetableFromGesture() }
                }
                .disabled(!canRefreshTimetable)
            }
        }
        .accessibilityZoomAction { action in
            switch action.direction {
            case .zoomIn:
                continuousViewport.setZoomTarget(
                    1,
                    centersToday: currentWeek == currentAcademicYearPage,
                    reducesMotion: accessibilityReduceMotion
                )
            case .zoomOut:
                continuousViewport.setZoomTarget(
                    0,
                    centersToday: currentWeek == currentAcademicYearPage,
                    reducesMotion: accessibilityReduceMotion
                )
            }
        }
    }

    private var timetableMagnificationGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.04)
            .updating($isTimetableMagnificationActive) { _, isActive, _ in isActive = true }
            .onChanged { value in
                if continuousViewport.phase != .pinching {
                    continuousViewport.beginMagnification(
                        centersToday: currentWeek == currentAcademicYearPage
                    )
                }
                var transaction = Transaction(animation: nil)
                transaction.isContinuous = true
                withTransaction(transaction) {
                    continuousViewport.updateMagnification(value.magnification)
                }
            }
            .onEnded { value in
                continuousViewport.endMagnification(
                    magnification: value.magnification,
                    velocity: value.velocity,
                    reducesMotion: accessibilityReduceMotion
                )
            }
    }

    private var timetableHorizontalPagingGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($isTimetablePagingDragActive) { _, isActive, _ in isActive = true }
            .onChanged { value in
                if continuousViewport.phase != .paging {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                }
                var transaction = Transaction(animation: nil)
                transaction.isContinuous = true
                withTransaction(transaction) {
                    if continuousViewport.phase != .paging {
                        guard continuousViewport.beginPaging(viewportWidth: continuousContentViewportWidth)
                        else { return }
                    }
                    continuousViewport.updatePaging(translation: value.translation.width)
                }
            }
            .onEnded { value in
                guard continuousViewport.phase == .paging else { return }
                let estimatedVelocity = (
                    value.predictedEndTranslation.width - value.translation.width
                ) / 0.16
                continuousViewport.endPaging(
                    predictedTranslation: value.predictedEndTranslation.width,
                    velocity: estimatedVelocity,
                    viewportWidth: continuousContentViewportWidth,
                    reducesMotion: accessibilityReduceMotion
                )
            }
    }

    private var continuousContentViewportWidth: CGFloat {
        max(
            timetableViewportSize.width
                - timetableHorizontalPadding * 2
                - axisWidth
                - AppSpacing.micro,
            1
        )
    }

    private func continuousTimetable(
        gridSnapshot: TimetableGridSnapshot,
        metrics: TimetableLayoutMetrics
    ) -> some View {
        let viewportWidth = max(metrics.containerWidth - axisWidth - AppSpacing.micro, 1)
        let now = Date()
        let currentTimeY = TimetableCurrentTimePosition.yPosition(for: now, metrics: metrics)
        let todayOrdinal = continuousRenderWindow.days.first { preparedDay in
            UserTimetableSettings.calendar.isDate(preparedDay.date, inSameDayAs: now)
        }?.ordinal

        return TimetableScrollContainer(
            axisWidth: axisWidth,
            headerHeight: headerHeight,
            totalWeeks: 1,
            weekStride: viewportWidth,
            dayColumnWidth: viewportWidth,
            rowHeight: metrics.rowHeight,
            rowSpacing: metrics.rowSpacing,
            allowsVerticalScroll: metrics.allowsVerticalScroll,
            currentWeek: .constant(1),
            scrollToWeek: .constant(nil),
            isAwayFromCurrentWeek: .constant(false),
            verticalOffset: viewportVerticalOffsetBinding,
            containerID: "continuous-zoom-timetable",
            isRefreshEnabled: canRefreshTimetable,
            onRefresh: isCustomCampus ? nil : { await refreshTimetableFromGesture() },
            onFirstInteractiveLayout: handleFirstInteractiveLayout,
            currentWeekProvider: { 1 },
            corner: {
                TimetableContinuousCenterDateReader(controller: continuousViewport) { centerDate in
                    continuousCornerHeader(date: centerDate)
                }
            },
            header: {
                TimetableContinuousViewportReader(
                    controller: continuousViewport,
                    viewportWidth: viewportWidth,
                    hidesWeekends: timetableHidesWeekends,
                    gutter: metrics.daySpacing
                ) { visualState in
                    TimetableContinuousColumnsLayout(geometry: visualState.geometry) {
                        ForEach(continuousDayPayloads) { payload in
                            if let metadata = payload.metadata {
                                dayHeader(metadata: metadata)
                                    .frame(maxWidth: .infinity, minHeight: headerHeight)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: headerHeight)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(width: viewportWidth, height: headerHeight, alignment: .topLeading)
                    .clipped()
                }
            },
            axis: {
                timeAxis(metrics: metrics)
            },
            body: {
                TimetableContinuousViewportReader(
                    controller: continuousViewport,
                    viewportWidth: viewportWidth,
                    hidesWeekends: timetableHidesWeekends,
                    gutter: metrics.daySpacing
                ) { visualState in
                    let currentTimeXRange = visualState.geometry.currentTimeIndicatorXRange(
                        todayOrdinal: todayOrdinal
                    )
                    ZStack {
                        TimetableContinuousColumnsLayout(geometry: visualState.geometry) {
                            ForEach(continuousDayPayloads) { payload in
                                continuousDayColumn(
                                    payload,
                                    metrics: metrics,
                                    gridSnapshot: gridSnapshot,
                                    isInteractionActive: visualState.isInteractionActive
                                )
                            }
                        }

                        if timetableCurrentTimeIndicatorIsEnabled,
                           let y = currentTimeY,
                           let xRange = currentTimeXRange {
                            Rectangle()
                                .fill(AppTheme.accentEmphasis(for: themeColorPreference))
                                .opacity(
                                    1 - TimetableCurrentTimeIndicatorPreference.sanitizedTransparency(
                                        timetableCurrentTimeIndicatorTransparency
                                    )
                                )
                                .frame(
                                    width: xRange.upperBound - xRange.lowerBound,
                                    height: CGFloat(
                                        TimetableCurrentTimeIndicatorPreference.sanitizedThickness(
                                            timetableCurrentTimeIndicatorThickness
                                        )
                                    )
                                )
                                .position(x: (xRange.lowerBound + xRange.upperBound) * 0.5, y: y)
                                .zIndex(10)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }

                        if visualState.isInteractionActive {
                            Color.clear
                                .contentShape(Rectangle())
                                .allowsHitTesting(true)
                        }
                    }
                    .frame(width: viewportWidth, height: metrics.gridHeight, alignment: .topLeading)
                    .clipped()
                }
            }
        )
        .frame(width: metrics.containerWidth, height: metrics.containerHeight, alignment: .topLeading)
        .padding(.horizontal, metrics.horizontalPadding)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private func continuousDayColumn(
        _ payload: TimetableZoomDayRenderPayload,
        metrics: TimetableLayoutMetrics,
        gridSnapshot: TimetableGridSnapshot,
        isInteractionActive: Bool
    ) -> some View {
        GeometryReader { proxy in
            if let week = payload.preparedDay.academicWeek,
               let metadata = payload.metadata {
                ZStack(alignment: .topLeading) {
                    dayColumnBody(
                        day: payload.preparedDay.dayOfWeek,
                        week: week,
                        width: proxy.size.width,
                        metrics: metrics,
                        gridSnapshot: gridSnapshot,
                        metadata: metadata,
                        preparedPayload: payload
                    )
                }
                .allowsHitTesting(!isInteractionActive)
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: metrics.gridHeight)
    }

    private func continuousCornerHeader(date: Date) -> some View {
        Text(TimetableClock.formatter(DateFormatters.shortMonth(language: leafyLanguage)).string(from: date))
            .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
            .foregroundStyle(AppTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: axisWidth, height: headerHeight)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
    }

    private func layoutMetrics(for size: CGSize, dayCount: Int) -> TimetableLayoutMetrics {
        timetableLayoutMetricsCache.metrics(
            size: size,
            dayCount: dayCount,
            totalClasses: totalClasses,
            axisWidth: axisWidth,
            headerHeight: headerHeight,
            horizontalPadding: timetableHorizontalPadding,
            daySpacing: timetableDaySpacing,
            weekSpacing: timetableWeekSpacing,
            rowSpacing: overviewRowSpacing,
            minimumRowHeight: overviewMinimumRowHeight,
            cardInset: overviewCardInset,
            laneSpacing: 2 * leafyControlScale,
            bottomClearance: overviewBottomClearance,
            controlScale: leafyControlScale,
            interPaneSpacing: AppSpacing.micro,
            allowsAgendaList: allowsTimetableAgendaFallback
        )
    }

    private func timeAxis(metrics: TimetableLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1 ... totalClasses, id: \.self) { classIndex in
                let slot = TimetablePeriodSchedule.slot(for: classIndex)
                VStack(spacing: 0) {
                    Text("\(classIndex)")
                        .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                    if let startText = slot?.startText {
                        Text(startText)
                            .font(.system(size: 6.4 * leafyControlScale, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                    if let endText = slot?.endText {
                        Text(endText)
                            .font(.system(size: 6.4 * leafyControlScale, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: axisWidth, height: metrics.rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(AppTheme.cardBackground.opacity(0.52))
                )
                .position(
                    x: axisWidth * 0.5,
                    y: yPosition(forClass: classIndex, metrics: metrics) + metrics.rowHeight * 0.5
                )
            }
        }
        .frame(width: axisWidth, height: metrics.gridHeight, alignment: .topLeading)
    }

    private func dayColumnBody(
        day: Int,
        week: Int,
        width: CGFloat,
        metrics: TimetableLayoutMetrics,
        gridSnapshot: TimetableGridSnapshot,
        metadata: TimetableDayMetadata,
        preparedPayload: TimetableZoomDayRenderPayload? = nil
    ) -> some View {
        let occupiedPeriods = preparedPayload?.occupiedPeriods
            ?? gridSnapshot.occupiedPeriods(day: day, week: week)
        let reminders = preparedPayload?.reminders
            ?? gridSnapshot.cellReminders(week: week, day: day)
        let reminderPeriods = preparedPayload?.reminderPeriods
            ?? Set(reminders.flatMap { Array($0.displayPeriodRange) })
        let countdowns = metadata.countdowns
        let countdownPeriods = preparedPayload?.countdownPeriods
            ?? Set(countdowns.flatMap { Array($0.startPeriod ... $0.endPeriod) })

        return ZStack(alignment: .topLeading) {
            timetableGridBackground(width: width, metrics: metrics)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        guard let period = (1 ... totalClasses).first(where: { candidate in
                                  let minY = yPosition(forClass: candidate, metrics: metrics)
                                  return value.location.y >= minY && value.location.y <= minY + metrics.rowHeight
                              }),
                              !occupiedPeriods.contains(period),
                              !reminderPeriods.contains(period),
                              !countdownPeriods.contains(period) else { return }

                        selectedCellReminderContext = TimetableCellReminderContext(
                            week: week,
                            day: day,
                            period: period,
                            date: metadata.date,
                            occupiedPeriods: occupiedPeriods,
                            totalPeriods: totalClasses,
                            reminder: nil
                        )
                    }
                )
                .accessibilityHidden(true)

            if let accessiblePeriod = (1 ... totalClasses).first(where: {
                !occupiedPeriods.contains($0)
                    && !reminderPeriods.contains($0)
                    && !countdownPeriods.contains($0)
            }) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("\(metadata.dayTitle)添加日程")
                    .accessibilityHint("添加第 \(accessiblePeriod) 节日程")
                    .accessibilityAction {
                        selectedCellReminderContext = TimetableCellReminderContext(
                            week: week,
                            day: day,
                            period: accessiblePeriod,
                            date: metadata.date,
                            occupiedPeriods: occupiedPeriods,
                            totalPeriods: totalClasses,
                            reminder: nil
                        )
                    }
            }

            let content = preparedPayload?.conflictContent
                ?? conflictDayCache.content(metadata: metadata, snapshot: gridSnapshot, totalClasses: totalClasses)
            ForEach(content.layout.blocks) { block in
                if let item = content.items[block.id] {
                    let rects = TimetableConflictGeometry.rects(
                        segments: block.segments,
                        width: width,
                        metrics: metrics
                    )
                    TimetableConflictBlockView(
                        item: item,
                        rects: rects,
                        width: width,
                        height: metrics.gridHeight,
                        background: conflictBlockBackground(item),
                        isTodayCourse: metadata.isToday && isCourseConflictItem(item)
                    )
                    .onTapGesture { handleConflictItemTap(item.agenda) }
                    .onLongPressGesture {
                        if case .course(let course) = item.agenda.kind {
                            courseNotePreview = CourseNotePreview(courseName: course.displayCourseName, note: item.note)
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                }
            }
            ForEach(content.layout.groups) { group in
                let segment = TimetableConflictSegment(start: group.start, end: group.end, leading: 0, trailing: 1)
                if let rect = TimetableConflictGeometry.rects(segments: [segment], width: width, metrics: metrics)
                    .first {
                    Button {
                        let items = group.itemIDs.compactMap { content.items[$0] }.sorted {
                            if $0.interval.start != $1.interval.start { return $0.interval.start < $1.interval.start }
                            return $0.id < $1.id
                        }
                        selectedConflictSelection = TimetableConflictSelection(
                            id: group.id,
                            date: metadata.date,
                            items: items
                        )
                    } label: {
                        Text(L10n.text("%d 项安排", language: leafyLanguage, group.itemIDs.count))
                            .font(.system(size: 10.5 * leafyControlScale, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .frame(width: rect.width, height: rect.height)
                            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.accent, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityHint(L10n.text("查看这个时段的全部安排", language: leafyLanguage))
                }
            }
        }
        .frame(width: width, height: metrics.gridHeight, alignment: .topLeading)
    }

    private func isCourseConflictItem(_ item: TimetableConflictDisplayItem) -> Bool {
        if case .course = item.agenda.kind { return true }
        return false
    }

    private func conflictBlockBackground(_ item: TimetableConflictDisplayItem) -> Color {
        if case .exam = item.agenda.kind {
            return colorScheme == .dark ? AppTheme.warning.opacity(0.28) : AppTheme.warning.opacity(0.20)
        }
        if case .course(let course) = item.agenda.kind,
           let palette = timetableBackgroundCoursePalette, !palette.isEmpty {
            return AppTheme.courseCardColor(for: course.displayCourseName + course.teacher, colors: palette)
                .opacity(timetableBackgroundConfiguration.courseCardOpacity)
        }
        if colorScheme == .dark { return AppTheme.accent(for: themeColorPreference).opacity(0.3) }
        let key: String
        if case .course(let course) = item.agenda.kind { key = course.displayCourseName + course.teacher }
        else { key = item.id + item.agenda.title }
        return AppTheme.courseCardColor(for: key, themeColorPreferenceRaw: themeColorPreference.rawValue).opacity(0.9)
    }

    private func handleConflictItemTap(_ item: TimetableAgendaItem) {
        if case .course(let value) = item.kind {
            guard let current = courses.first(where: { $0.id == value.id }) else {
                handleStaleTimetableSnapshot()
                return
            }
            selectedCourseContext = SelectedCourseContext(
                course: current,
                week: value.semesterWeek(for: item.week) ?? item.week,
                day: item.day,
                date: item.date
            )
        } else {
            handleAgendaItemTap(item)
        }
    }

    private func handleAgendaItemTap(_ item: TimetableAgendaItem) {
        switch item.kind {
        case .course(let course):
            guard let currentCourse = courses.first(where: { $0.id == course.id }) else {
                handleStaleTimetableSnapshot()
                return
            }
            selectedCourseContext = SelectedCourseContext(
                course: currentCourse,
                week: item.week,
                day: item.day,
                date: item.date
            )
        case .cellReminder(let reminder, let period):
            guard let currentReminder = cellReminders.first(where: { $0.id == reminder.id }) else {
                handleStaleTimetableSnapshot()
                return
            }
            selectedCellReminderContext = TimetableCellReminderContext(
                week: item.week,
                day: item.day,
                period: period,
                date: item.date,
                occupiedPeriods: currentTimetableGridSnapshot().occupiedPeriods(day: item.day, week: item.week),
                totalPeriods: totalClasses,
                reminder: currentReminder
            )
        case .countdown(let projection):
            presentCustomScheduleEditor(for: projection)
        case .exam:
            let context = teachingContext(for: item.week)
            selectedDaySummary = TimetableDaySelection(
                week: context?.week ?? item.week,
                day: item.day,
                date: item.date,
                semesterID: context?.semesterID
            )
        }
    }

    private func presentCustomScheduleEditor(for projection: TimetableCountdownProjection) {
        guard let event = customScheduleEvents.first(where: { $0.id == projection.eventID }) else {
            alertMessage = "该日程已更新，请刷新课表后重试。"
            showAlert = true
            return
        }

        let context = TimetableCellReminderContext(
            week: projection.week,
            day: projection.dayOfWeek,
            period: projection.period,
            date: event.startsAt,
            occupiedPeriods: currentTimetableGridSnapshot().occupiedPeriods(
                day: projection.dayOfWeek,
                week: projection.week
            ),
            totalPeriods: totalClasses,
            reminder: nil,
            allowsDateSelection: true
        )
        selectedCustomScheduleEditor = .importantDate(
            event,
            defaultContext: context,
            allowsModeSelection: false
        )
    }

    private func dayHeader(metadata: TimetableDayMetadata) -> some View {
        let annotation = [
            metadata.event?.displayTitle(language: leafyLanguage),
            metadata.hasExam ? L10n.text("考试", language: leafyLanguage) : nil
        ].compactMap { $0 }.joined(separator: " · ")

        return VStack(spacing: 0) {
            Text(metadata.dayTitle)
                .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                .frame(height: 18 * leafyControlScale)
            Text(metadata.numericDateText)
                .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(height: 14 * leafyControlScale)
        }
        .frame(maxWidth: .infinity)
        .frame(height: headerHeight, alignment: .center)
        .overlay(alignment: .bottom) {
            if !annotation.isEmpty {
                Text(annotation)
                    .font(.system(size: 7.5 * leafyControlScale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
                    .frame(height: 8 * leafyControlScale)
                    .padding(.horizontal, 2 * leafyControlScale)
                    .padding(.bottom, leafyControlScale)
            }
        }
        .foregroundStyle(dayHeaderTextForeground(for: metadata))
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(dayHeaderFill(today: metadata.isToday, event: metadata.event, hasExam: metadata.hasExam))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(
                    metadata.isToday || metadata.event != nil || metadata.hasExam ? Color.clear : AppTheme.separator,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }

    private func dayHeaderFill(today: Bool, event: SchoolCalendarEvent?, hasExam: Bool) -> Color {
        if today { return AppTheme.accent }
        if hasExam { return AppTheme.warning.opacity(colorScheme == .dark ? 0.26 : 0.20) }
        guard let event else { return AppTheme.cardBackground }

        switch event.academicCategory {
        case .winterBreak:
            return Color.cyan.opacity(colorScheme == .dark ? 0.24 : 0.18)
        case .summerBreak:
            return Color.yellow.opacity(colorScheme == .dark ? 0.24 : 0.20)
        case .importantDate, .semesterEnd:
            return AppTheme.fill.opacity(0.82)
        case .publicHoliday, nil:
            break
        }

        switch event.kind {
        case .holiday:
            return colorScheme == .dark ? AppTheme.accent.opacity(0.26) : AppTheme.accentSoft.opacity(0.72)
        case .closure:
            return AppTheme.warning.opacity(0.24)
        case .solarTerm:
            return solarTermFill(for: event)
        }
    }

    private func dayHeaderForeground(event: SchoolCalendarEvent?, hasExam: Bool) -> Color {
        if hasExam { return AppTheme.warning }
        guard let event else { return AppTheme.primaryText }
        switch event.academicCategory {
        case .winterBreak:
            return Color.cyan.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .summerBreak:
            return Color.yellow.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .importantDate, .semesterEnd:
            return AppTheme.secondaryText
        case .publicHoliday, nil:
            break
        }
        switch event.kind {
        case .holiday:
            return AppTheme.accentEmphasis
        case .closure:
            return AppTheme.warning
        case .solarTerm:
            return solarTermForeground(for: event)
        }
    }

    private func dayHeaderTextForeground(for metadata: TimetableDayMetadata) -> Color {
        if metadata.isToday { return AppTheme.textOnAccent }
        if metadata.event != nil { return .black }
        if metadata.hasExam { return AppTheme.warning }
        return AppTheme.primaryText
    }

    private func solarTermFill(for event: SchoolCalendarEvent) -> Color {
        switch event.solarTermSeason {
        case .spring:
            return Color.green.opacity(colorScheme == .dark ? 0.22 : 0.18)
        case .summer:
            return Color.yellow.opacity(colorScheme == .dark ? 0.24 : 0.24)
        case .autumn:
            return Color.orange.opacity(colorScheme == .dark ? 0.24 : 0.20)
        case .winter:
            return Color.cyan.opacity(colorScheme == .dark ? 0.24 : 0.18)
        case nil:
            return AppTheme.fill.opacity(0.82)
        }
    }

    private func solarTermForeground(for event: SchoolCalendarEvent) -> Color {
        switch event.solarTermSeason {
        case .spring:
            return Color.green.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .summer:
            return Color.yellow.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .autumn:
            return Color.orange.opacity(colorScheme == .dark ? 0.92 : 0.82)
        case .winter:
            return Color.cyan.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case nil:
            return AppTheme.secondaryText
        }
    }

    private func timetableGridBackground(width: CGFloat, metrics: TimetableLayoutMetrics) -> some View {
        Canvas { context, _ in
            for classIndex in 1 ... totalClasses {
                let isBreakBoundary = classIndex == 5 || classIndex == 9
                let rect = CGRect(
                    x: 0,
                    y: yPosition(forClass: classIndex, metrics: metrics),
                    width: width,
                    height: metrics.rowHeight
                )
                context.opacity = isBreakBoundary ? 1 : 0.72
                context.fill(
                    Path(roundedRect: rect, cornerRadius: AppRadius.small),
                    with: .color(backgroundFillColor(for: classIndex))
                )
            }
        }
        .frame(width: width, height: metrics.gridHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func backgroundFillColor(for classIndex: Int) -> Color {
        if classIndex == 5 || classIndex == 9 {
            if usesCustomTimetableBackground {
                return colorScheme == .dark ? AppTheme.accent.opacity(0.22) : AppTheme.accentSoft.opacity(0.46)
            }
            return colorScheme == .dark ? AppTheme.accent.opacity(0.18) : AppTheme.accentSoft.opacity(0.38)
        }
        return AppTheme.cardBackground.opacity(usesCustomTimetableBackground ? 0.48 : 0.36)
    }

    private var unauthenticatedState: some View {
        ContentUnavailableView(
            "需要重新登录",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("当前教务登录态不可用，请先连接校园网，再回到登录页重新登录。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customCampusEmptyState: some View {
        ContentUnavailableView {
            Label("暂无课表", systemImage: "calendar")
        } description: {
            Text("添加课程或导入文件后显示。")
        } actions: {
            Button {
                isTimetableProcessingPresented = true
            } label: {
                Label("课表处理", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: themeColorPreference))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func yPosition(forClass classIndex: Int, metrics: TimetableLayoutMetrics) -> CGFloat {
        CGFloat(max(classIndex - 1, 0)) * (metrics.rowHeight + metrics.rowSpacing)
    }

    private func syncReturnButtonVisibility(for visibleWeek: Int? = nil) {
        if displayMode == .threeDay {
            isAwayFromCurrentSchedule = !UserTimetableSettings.calendar.isDate(
                continuousViewport.centerDate,
                inSameDayAs: Date()
            )
            return
        }
        let week = visibleWeek ?? currentWeek
        isAwayFromCurrentSchedule = !academicYearTimetable.contains(Date())
            || week != currentAcademicYearPage
    }

    private func isDateInDisplayedAcademicYear(_ date: Date) -> Bool {
        academicYearTimetable.contains(date)
    }

    private func teachingContext(for page: Int) -> (semesterID: String, week: Int)? {
        guard let timelineWeek = academicYearTimetable.week(atPageIndex: page),
              case let .teaching(semesterID, weekNumber) = timelineWeek.phase else { return nil }
        return (semesterID, weekNumber)
    }

    private func dayMetadata(day: Int, week: Int) -> TimetableDayMetadata {
        timetableDayMetadataCache.metadata(
            day: day,
            week: week,
            timelineStartDate: timelineStartDate,
            calendarEvents: calendarEventSignature,
            scheduleSnapshot: timetableScheduleProjectionSnapshot,
            language: leafyLanguage
        )
    }

    private func currentTimetableGridSnapshot() -> TimetableGridSnapshot {
        if let timetableGridSnapshot {
            return timetableGridSnapshot
        }

        return timetableGridSnapshotCache.snapshot(
            input: timetableRenderInput,
            totalWeeks: totalWeeks
        )
    }

    private func syncTimetableGridSnapshot() {
        let snapshot = timetableGridSnapshotCache.snapshot(
            input: timetableRenderInput,
            totalWeeks: totalWeeks
        )
        guard timetableGridSnapshot?.signature != snapshot.signature ||
            timetableGridSnapshot?.totalWeeks != snapshot.totalWeeks
        else { return }
        timetableGridSnapshot = snapshot
        refreshContinuousDayPayloads()
    }

    private func handleStaleTimetableSnapshot() {
        timetableGridSnapshotCache.invalidate()
        timetableGridSnapshot = nil
        alertMessage = L10n.text("课表已更新，请重试。", language: leafyLanguage)
        showAlert = true
        Task { @MainActor in
            await Task.yield()
            syncTimetableGridSnapshot()
        }
    }

    private func syncTimetableScheduleProjectionSnapshot() {
        timetableScheduleProjectionSnapshot = TimetableScheduleProjectionSnapshot.make(
            countdownEvents: customScheduleEvents,
            exams: cachedExamArrangements,
            academicYear: academicYearTimetable
        )
        refreshContinuousDayPayloads()
    }

    private func persistParserDebugHTML(_ html: String) -> String {
        let filename = "last_timetable_parser_input.html"
        _ = networkManager.persistDebugHTML(html, filename: filename)
        return networkManager.pageDebugSummary(html: html, responseURL: nil, snapshotName: filename)
    }

    private var canRefreshTimetable: Bool {
        !isCustomCampus && !isFetching && !progressController.isActive
            && reauthenticationRequest == nil && !continuousViewport.isInteractionActive
    }

    @MainActor
    private func refreshTimetableFromGesture() async {
        guard canRefreshTimetable else { return }
        await fetchAndParseTimetable(userInitiated: true)
    }

    @MainActor
    private func fetchAndParseTimetable(
        userInitiated: Bool,
        allowsAutomaticRecovery: Bool = true
    ) async {
        let scope = CampusOperationScope()
        guard !isFetching, !Task.isCancelled else { return }
        if isCustomCampus {
            await MainActor.run {
                if userInitiated {
                    isTimetableProcessingPresented = true
                }
            }
            return
        }
        if ReviewDemoMode.isEnabled {
            isFetching = true
            defer { isFetching = false }
            do {
                let saved = try ReviewDemoDataSeeder.refreshTimetable(using: modelContext)
                let reminderWarning = await saved.reminders.restore()
                try scope.check()
                TimetableCacheMetadata.lastSyncAt = Date()
                TimetableCacheMetadata.lastFailureMessage = reminderWarning
                TimetableCacheMetadata.lastSyncedSemesterID = SemesterConfig.currentSemesterID
                lastSyncAt = TimetableCacheMetadata.lastSyncAt
                lastFailureMessage = reminderWarning
                timetableGridSnapshotCache.invalidate()
                timetableGridSnapshot = nil
                syncReturnButtonVisibility()
                publishWidgetSnapshot()
                if userInitiated && !Task.isCancelled {
                    alertMessage = reminderWarning ?? L10n.text("同步完成，已加载示例课表。", language: leafyLanguage)
                    showAlert = true
                }
            } catch {
                guard !scope.wasCancelled(error) else { return }
                alertMessage = error.localizedDescription
                showAlert = true
            }
            return
        }

        let progressReporter: AcademicOperationProgressReporter? = userInitiated
            ? progressController.reporter(for: .timetable)
            : nil
        if userInitiated {
            progressController.begin(.timetable)
        }

        if userInitiated,
           let request = SchoolReauthentication.preflightRequest(
               networkManager: networkManager,
               context: .timetable(portal: networkManager.currentPortal),
               allowsAutomaticAttempt: allowsAutomaticRecovery
           ) {
            await MainActor.run {
                reauthenticationRequest = request
            }
            return
        }

        guard networkManager.isLoggedIn else {
            if userInitiated, networkManager.hasCachedIdentity {
                reauthenticationRequest = SchoolReauthenticationRequest(
                    context: .timetable(portal: networkManager.currentPortal),
                    allowsAutomaticAttempt: allowsAutomaticRecovery
                )
            } else {
                progressController.clear()
                alertMessage = networkManager.hasCachedIdentity
                    ? L10n.text("本地身份已识别，但刷新课表需要连接校园网并重新建立教务登录态。", language: leafyLanguage)
                    : L10n.text("请先连接校园网登录教务系统。", language: leafyLanguage)
                showAlert = true
            }
            return
        }
        isFetching = true
        defer { isFetching = false }
        progressReporter?(.begin(.refreshingSemester))
        let semesterConfig = SemesterConfig.current
        do {
            try scope.check()
            applySemesterRuntimeConfig(semesterConfig)
            let refreshUseCase = TimetableRefreshUseCase(repository: dependencies.schoolTimetableRepository)
            progressReporter?(.begin(.fetchingTimetable))
            let document = try await refreshUseCase.fetchDocument()
            try scope.check()
            let parsedCourseRecords: [ParsedCourseRecord]

            do {
                progressReporter?(.begin(.processingTimetable))
                parsedCourseRecords = try await TimetableRefreshUseCase.parseRecords(html: document.html)
            } catch {
                let debugSummary = persistParserDebugHTML(document.html)
                throw NSError(
                    domain: "leafy.timetable",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription)。\(debugSummary)"]
                )
            }

            try scope.check()
            let (saved, refreshSummary) = try await MainActor.run {
                try scope.check()
                progressReporter?(.begin(.savingTimetable))
                let refreshSummary = TimetableRefreshSummary.compare(
                    records: parsedCourseRecords,
                    existingCourses: courses,
                    semesterID: document.sourceSemesterID
                )
                let saved = try refreshUseCase.persist(
                    records: parsedCourseRecords,
                    existingCourses: courses,
                    modelContext: modelContext,
                    semesterID: document.sourceSemesterID
                )
                return (saved, refreshSummary)
            }
            let reminderWarning = await saved.reminders.restore()
            try scope.check()
            await MainActor.run {
                guard scope.isCurrent, !Task.isCancelled else { return }
                let sharedCourses = saved.sharedCourses

                timetableGridSnapshotCache.invalidate()
                timetableGridSnapshot = nil
                TimetableCacheMetadata.lastSyncAt = Date()
                TimetableCacheMetadata.lastFailureMessage = reminderWarning
                TimetableCacheMetadata.lastSyncedSemesterID = document.sourceSemesterID
                AppStoreReviewCoordinator.recordSuccessfulSync(kind: .timetable, date: Date())
                SchoolDataRefreshNotifier.post(.timetable)
                Task {
                    guard scope.isCurrent, !Task.isCancelled else { return }
                    await TimetableSharingService.shared.publishExistingSnapshotIfNeeded(courses: sharedCourses)
                }
                lastSyncAt = TimetableCacheMetadata.lastSyncAt
                lastFailureMessage = reminderWarning
                isFetching = false
                progressController.completeCurrentStep()
                progressController.clear()
                syncReturnButtonVisibility()
                publishWidgetSnapshot()
                if userInitiated && !Task.isCancelled {
                    alertMessage = reminderWarning ?? timetableRefreshMessage(for: refreshSummary)
                    showAlert = true
                }
            }
        } catch {
            if scope.wasCancelled(error) {
                progressController.clear()
                return
            }
            await MainActor.run {
                isFetching = false
                requiresPeriodConfiguration = error is TimetableConfigurationRequired
                emptyResultIdentity = error is TimetableEmptyResult ? ActiveCampusContext.identity : nil
                TimetableCacheMetadata.lastFailureMessage = error.localizedDescription
                lastFailureMessage = error.localizedDescription
                publishWidgetSnapshot()
                if userInitiated, SchoolReauthentication.shouldPromptForUserInitiatedAccess(error) {
                    reauthenticationRequest = SchoolReauthenticationRequest(
                        context: .timetable(portal: networkManager.currentPortal),
                        allowsAutomaticAttempt: allowsAutomaticRecovery
                    )
                } else {
                    progressController.clear()
                    alertMessage = courses.isEmpty
                        ? L10n.text("获取课表失败：%@", language: leafyLanguage, error.localizedDescription)
                        : L10n.text("获取课表失败，已继续显示本地缓存：%@", language: leafyLanguage, error.localizedDescription)
                    showAlert = true
                }
            }
        }
    }

    private func clearConfirmedEmptyTimetable() {
        guard let identity = emptyResultIdentity, identity == ActiveCampusContext.identity else { return }
        emptyResultIdentity = nil
        let scope = CampusOperationScope()
        do {
            let saved = try TimetableRefreshUseCase().persist(records: [], existingCourses: courses,
                                                              modelContext: modelContext, allowsEmpty: true)
            Task { @MainActor in
                guard scope.isCurrent, !Task.isCancelled else { return }
                _ = await saved.reminders.restore()
                guard scope.isCurrent, !Task.isCancelled else { return }
                TimetableCacheMetadata.lastSyncAt = Date()
                SchoolDataRefreshNotifier.post(.timetable)
                publishWidgetSnapshot()
                _ = await TimetableSharingService.shared.publishExistingSnapshotIfNeeded(courses: [])
            }
        } catch { alertMessage = error.localizedDescription; showAlert = true }
    }

    private func timetableRefreshMessage(for summary: TimetableRefreshSummary) -> String {
        if summary.scheduleCount == 0 {
            return L10n.text("同步完成，学校当前没有返回课程安排。", language: leafyLanguage)
        }
        if !summary.hasChanges {
            return L10n.text(
                "同步完成，课表已是最新，共 %d 门课程、%d 条安排。",
                language: leafyLanguage,
                summary.courseCount,
                summary.scheduleCount
            )
        }
        return L10n.text(
            "同步完成，获取到 %d 门课程、%d 条安排。",
            language: leafyLanguage,
            summary.courseCount,
            summary.scheduleCount
        )
    }

    private func publishWidgetSnapshot() {
        LeafyWidgetSnapshotBuilder.publish(
            from: modelContext,
            isAuthenticated: networkManager.hasCachedIdentity || ReviewDemoMode.isEnabled
        )
    }

    private func openCourseFromDeepLink(id: UUID) {
        guard let course = courses.first(where: { $0.id == id }) else {
            return
        }

        guard let config = academicYearTimetable.configuration(semesterID: course.sourceSemesterID) else { return }
        let preferredSemesterWeek = SemesterConfig.currentWeek(config: config)
        let semesterWeek = course.weeks.contains(preferredSemesterWeek)
            ? preferredSemesterWeek
            : course.weeks.sorted().first ?? preferredSemesterWeek
        guard let weekStart = UserTimetableSettings.calendar.date(
            byAdding: .day,
            value: (semesterWeek - 1) * 7,
            to: config.semesterStartDate
        ), let targetPage = academicYearTimetable.pageIndex(containing: weekStart) else { return }
        currentWeek = targetPage
        selectedCourseContext = SelectedCourseContext(
            course: course,
            week: semesterWeek,
            day: course.dayOfWeek,
            date: UserTimetableSettings.calendar.date(
                byAdding: .day,
                value: course.dayOfWeek - 1,
                to: weekStart
            ) ?? weekStart
        )
    }
}

private struct TimetableWeekPickerPanel: View {
    let model: TimetableCalendarMenuModel
    let selectedDate: Date
    let referenceDate: Date
    let overviewSnapshot: TimetableTimeScopeSnapshot
    let onSelect: (Date) -> Void

    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.leafyLanguage) private var leafyLanguage
    @State private var expandedSemesterIDs: Set<String>

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 64), spacing: AppSpacing.compact),
        count: 4
    )

    init(
        model: TimetableCalendarMenuModel,
        selectedDate: Date,
        referenceDate: Date,
        overviewSnapshot: TimetableTimeScopeSnapshot,
        onSelect: @escaping (Date) -> Void
    ) {
        self.model = model
        self.selectedDate = selectedDate
        self.referenceDate = referenceDate
        self.overviewSnapshot = overviewSnapshot
        self.onSelect = onSelect
        _expandedSemesterIDs = State(initialValue: model.defaultExpandedSemesterIDs)
    }

    private var visibleAcademicYears: [TimetableCalendarMenuAcademicYear] {
        model.timeViewAcademicYears
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.card) {
                    TimetableConfigurationLink()
                    ForEach(visibleAcademicYears) { academicYear in
                        primaryAcademicYearSection(academicYear)
                    }

                    if let message = model.unavailableFutureConfigurationMessage {
                        Label(message, systemImage: "calendar.badge.exclamationmark")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 16)
                            .leafyCardStyle()
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("年度视图")
                            .leafyHeadline()

                        TimetableTimeScopeView(
                            snapshot: overviewSnapshot,
                            presentation: .embedded
                        )
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("时间视图")
            .leafyInlineNavigationTitle()
            .onChange(of: model.academicYears.flatMap(\.semesters).map(\.semesterID)) { _, _ in
                expandedSemesterIDs = model.defaultExpandedSemesterIDs
            }
        }
    }

    private func primaryAcademicYearSection(_ academicYear: TimetableCalendarMenuAcademicYear) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.micro) {
            ForEach(academicYear.semesters) { semester in
                semesterSection(semester)
            }
        }
    }

    private func semesterSection(_ semester: TimetableCalendarMenuSemester) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSemesterIDs.contains(semester.semesterID) },
                set: { isExpanded in
                    if isExpanded {
                        expandedSemesterIDs.insert(semester.semesterID)
                    } else {
                        expandedSemesterIDs.remove(semester.semesterID)
                    }
                }
            )
        ) {
            LazyVGrid(columns: columns, spacing: AppSpacing.compact) {
                ForEach(semester.weeks) { week in
                    weekButton(week, semester: semester)
                }
            }
            .padding(.top, AppSpacing.compact)
        } label: {
            HStack(spacing: AppSpacing.compact) {
                Text(semester.title)
                    .leafyHeadline()
                if semester.semesterID == model.currentSemesterID {
                    Text("当前学期")
                        .microCaption()
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                }
                Spacer(minLength: AppSpacing.compact)
                Text(semesterRangeText(semester))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .leafyCardStyle()
    }

    private func semesterRangeText(_ semester: TimetableCalendarMenuSemester) -> String {
        let formatter = TimetableClock.formatter(DateFormatters.monthYear(language: leafyLanguage))
        formatter.calendar = Calendar(identifier: .gregorian)
        let start = formatter.string(from: semester.startDate)
        guard let endDate = semester.endDate else {
            return L10n.text("%@起", language: leafyLanguage, start)
        }
        return L10n.text("%@到%@", language: leafyLanguage, start, formatter.string(from: endDate))
    }

    private func weekButton(
        _ week: TimetableCalendarMenuWeek,
        semester: TimetableCalendarMenuSemester
    ) -> some View {
        let isSelected = isSameWeek(week.targetDate, selectedDate)
        let isCurrent = isSameWeek(week.targetDate, referenceDate)
        let tint = AppTheme.accent(for: themeColorPreference)

        return Button {
            onSelect(week.targetDate)
        } label: {
            Text("第 \(week.weekNumber) 周")
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isSelected ? Color.white : AppTheme.primaryText)
                .background(
                    isSelected ? tint : AppTheme.fill,
                    in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                )
                .overlay {
                    if isCurrent && !isSelected {
                        RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                            .stroke(tint, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(semester.title)，第 \(week.weekNumber) 周\(isCurrent ? "，本周" : "")\(isSelected ? "，已选择" : "")"
        )
        .accessibilityHint("跳转到这一周")
    }

    private func isSameWeek(_ lhs: Date, _ rhs: Date) -> Bool {
        guard let lhsInterval = UserTimetableSettings.calendar.dateInterval(of: .weekOfYear, for: lhs),
              let rhsInterval = UserTimetableSettings.calendar.dateInterval(of: .weekOfYear, for: rhs) else {
            return UserTimetableSettings.calendar.isDate(lhs, inSameDayAs: rhs)
        }
        return lhsInterval.start == rhsInterval.start
    }
}
