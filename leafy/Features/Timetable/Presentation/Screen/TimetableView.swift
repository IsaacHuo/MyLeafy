import SwiftData
import SwiftSoup
import SwiftUI
import OSLog
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

struct TimetableView: View {
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

    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var isFetching = false
    @State private var alertMessage = ""
    @State private var showAlert = false
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
    @State private var calendarYearConfigurations: [SemesterRuntimeConfig]
    @State private var calendarYearTimetable: CalendarYearTimetable
    @State private var calendarYearMenuModel: TimetableCalendarMenuModel
    @State private var timetableCourseWeekProjections: [UUID: TimetableCourseWeekProjection] = [:]
    @State private var timetableCellReminderProjections: [UUID: TimetableCellReminderProjection] = [:]
    @State private var currentWeek: Int
    @State private var scrollToWeek: Int?
    @State private var isAwayFromCurrentSchedule = false
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
    @State private var timetableAgendaItemCache = TimetableAgendaItemCache()
    @State private var isWeatherAdvicePresented = false
    @State private var cachedTimetableWeather: TimetableWeatherSnapshot?
    @State private var customCountdownEvents: [CustomScheduleEvent]
    @State private var cachedExamArrangements: [ExamArrangement]
    @State private var calendarEventSignature = AcademicCalendarEvents.displayEvents()
    @State private var timetableScheduleProjectionSnapshot: TimetableScheduleProjectionSnapshot
    @State private var timetableBackgroundImage: UIImage?
    @State private var timetableBackgroundLoadTask: Task<Void, Never>?
    @State private var timetableBackgroundConfiguration = TimetableBackgroundConfiguration.load()

    @AppStorage("hasSeenTimetableOnboarding") private var hasSeenTimetableOnboarding = false
    @AppStorage("timetableHidesWeekends") private var timetableHidesWeekends = false
    @AppStorage(TimetableCurrentTimeIndicatorPreference.isEnabledKey)
    private var timetableCurrentTimeIndicatorIsEnabled = TimetableCurrentTimeIndicatorPreference.defaultIsEnabled
    @AppStorage(TimetableCurrentTimeIndicatorPreference.thicknessKey)
    private var timetableCurrentTimeIndicatorThickness = TimetableCurrentTimeIndicatorPreference.defaultThickness

    private static let backgroundLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.isaachuo.leafy",
        category: "TimetableBackground"
    )
    private var totalWeeks: Int { calendarYearTimetable.weeks.count }
    private var timelineStartDate: Date {
        calendarYearTimetable.weeks.first?.weekStartDate ?? Calendar.current.startOfDay(for: Date())
    }
    private let totalClasses = 13
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
#if os(macOS)
        true
#else
        UIDevice.current.userInterfaceIdiom == .pad
#endif
    }
    private var showsToolbarRefreshButton: Bool {
#if os(macOS)
        true
#else
        UIDevice.current.userInterfaceIdiom == .pad
#endif
    }

    private static func makeCalendarYearTimetable(
        configurations: [SemesterRuntimeConfig] = SemesterConfig.timelineConfigurations,
        referenceDate: Date = Date()
    ) -> CalendarYearTimetable {
        CalendarYearTimetable(
            year: Calendar.current.component(.year, from: referenceDate),
            configurations: configurations,
            semanticEvents: configurations.flatMap(\.calendarEvents),
            referenceDate: referenceDate
        )
    }

    init() {
        let configurations = SemesterConfig.timelineConfigurations
        let timetable = Self.makeCalendarYearTimetable(configurations: configurations)
        let currentPage = timetable.pageIndex(containing: Date()) ?? 1
        let countdownEvents = CustomScheduleStore.load()
        let exams = SchoolDataCache.loadExamSchedule()

        _calendarYearConfigurations = State(initialValue: configurations)
        _calendarYearTimetable = State(initialValue: timetable)
        _calendarYearMenuModel = State(
            initialValue: TimetableCalendarMenuModel(
                timetable: timetable,
                configurations: configurations
            )
        )
        _currentWeek = State(initialValue: currentPage)
        _scrollToWeek = State(initialValue: currentPage)
        _customCountdownEvents = State(initialValue: countdownEvents)
        _cachedExamArrangements = State(initialValue: exams)
        _timetableScheduleProjectionSnapshot = State(
            initialValue: TimetableScheduleProjectionSnapshot.make(
                countdownEvents: countdownEvents,
                exams: exams,
                calendarYear: timetable
            )
        )
    }

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    private var visibleDays: [Int] {
        timetableGridSnapshot?.visibleDays ?? (timetableHidesWeekends ? Array(1...5) : Array(1...7))
    }

    private var currentCalendarPage: Int {
        calendarYearTimetable.pageIndex(containing: Date()) ?? 1
    }

    private var currentTimelineWeek: CalendarYearWeek? {
        calendarYearTimetable.week(atPageIndex: currentWeek)
    }

    private var selectedSemesterContext: (semesterID: String, week: Int)? {
        guard let currentTimelineWeek,
              case let .teaching(semesterID, weekNumber) = currentTimelineWeek.phase else { return nil }
        return (semesterID, weekNumber)
    }

    private var selectedSemesterCourses: [Course] {
        guard let selectedSemesterContext else { return [] }
        return courses.filter { $0.sourceSemesterID == selectedSemesterContext.semesterID }
    }

    private var selectedSemesterWeek: Int {
        selectedSemesterContext?.week ?? SemesterConfig.currentWeek()
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
            cellReminders: cellReminders,
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
                } else if isFetching && courses.isEmpty {
                    loadingState
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
        .onReceive(NotificationCenter.default.publisher(for: .customCountdownEventsDidChange)) { _ in
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
        .onReceive(NotificationCenter.default.publisher(for: .timetableBackgroundSettingsDidChange)) { _ in
            reloadTimetableBackground()
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
            TimetableCellReminderSheet(context: context)
                .presentationDetents([.medium, .large])
        }
        .leafySheet(item: $selectedCustomScheduleEditor, onDismiss: reloadCustomCountdownEvents) { presentation in
            CustomScheduleEditorSheet(presentation: presentation)
                .presentationDetents([.medium, .large])
        }
        .leafySheet(item: $selectedDaySummary) { selection in
            DayScheduleSummarySheet(
                selection: selection,
                courses: selection.semesterID.map { semesterID in
                    courses.filter { $0.sourceSemesterID == semesterID }
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
                model: calendarYearMenuModel,
                selectedPage: currentWeek,
                currentPage: currentCalendarPage,
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
            Button("确定", role: .cancel) {}
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
            networkManager: networkManager
        ) { _ in
            Task { await fetchAndParseTimetable(userInitiated: true) }
        }
    }

    private var onboardingAlertBinding: Binding<Bool> {
        Binding(
            get: { networkManager.hasCachedIdentity && isTimetableInteractivelyLaidOut && !hasSeenTimetableOnboarding },
            set: { if !$0 { hasSeenTimetableOnboarding = true } }
        )
    }

    private var onboardingMessage: String {
        if isCustomCampus {
            return "通用入口的课表、成绩和考试安排来自你手动导入的 CSV 文件；数据只保存在本机当前账号作用域内。"
        }
        return "课表、成绩和考试安排来自学校教务系统；课表和成绩缓存保存在本机，离线时仍可查看。社区资料和你主动发布的内容会保存到 \(AppBrand.displayName) 的社区服务。"
    }

    @MainActor
    private func initializeTimetableIfNeeded() async {
        guard !hasInitializedTimetable else { return }
        hasInitializedTimetable = true
        syncCalendarYearDataProjections()
        syncTimetableScheduleProjectionSnapshot()
        syncTimetableGridSnapshot()
        syncReturnButtonVisibility()

        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()
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
        syncReturnButtonVisibility()
    }

    private func handleFirstInteractiveLayout() {
        isTimetableInteractivelyLaidOut = true
        guard !hasRunDeferredInitialWork else { return }
        hasRunDeferredInitialWork = true
        Task { @MainActor in
            await Task.yield()
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
        syncReturnButtonVisibility(for: newValue)
    }

    private func handleWeekendVisibilityChange() {
        syncTimetableGridSnapshot()
        scrollToWeek = currentWeek
    }

    private func handleCoursesCountChange() {
        syncCalendarYearDataProjections()
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
        syncCalendarYearDataProjections()
        syncTimetableGridSnapshot()
        publishWidgetSnapshot()
        refreshScheduleReportNotifications()
    }

    private func handleTimetableGridInputChange() {
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
        customCountdownEvents = CustomScheduleStore.load()
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
        Task { @MainActor in
            try? await ScheduleReportNotificationManager.refreshIfEnabled(modelContext: modelContext)
        }
    }

    @MainActor
    private func applySemesterRuntimeConfig(_ config: SemesterRuntimeConfig) {
        _ = config
        guard calendarYearConfigurations != SemesterConfig.timelineConfigurations else { return }
        rebuildCalendarYearTimeline(positionsToToday: true)
        publishWidgetSnapshot()
    }

    @MainActor
    private func rebuildCalendarYearTimeline(positionsToToday: Bool) {
        calendarYearConfigurations = SemesterConfig.timelineConfigurations
        calendarYearTimetable = Self.makeCalendarYearTimetable(
            configurations: calendarYearConfigurations
        )
        calendarYearMenuModel = TimetableCalendarMenuModel(
            timetable: calendarYearTimetable,
            configurations: calendarYearConfigurations
        )
        calendarEventSignature = AcademicCalendarEvents.displayEvents()
        syncCalendarYearDataProjections()
        syncTimetableScheduleProjectionSnapshot()
        timetableGridSnapshotCache.invalidate()
        timetableGridSnapshot = nil
        syncTimetableGridSnapshot()

        let todayPage = currentCalendarPage
        if positionsToToday {
            currentWeek = todayPage
            scrollToWeek = todayPage
        } else {
            currentWeek = min(max(currentWeek, 1), totalWeeks)
        }
        syncReturnButtonVisibility(for: currentWeek)
    }

    private func courseIntersectsCurrentCalendarYear(_ course: Course) -> Bool {
        guard let config = calendarYearTimetable.configuration(semesterID: course.sourceSemesterID) else {
            return true
        }
        return course.weeks.contains { semesterWeek in
            guard let date = Calendar.current.date(
                byAdding: .day,
                value: (semesterWeek - 1) * 7 + (course.dayOfWeek - 1),
                to: config.semesterStartDate
            ) else { return false }
            return Calendar.current.component(.year, from: date) == calendarYearTimetable.year
        }
    }

    @MainActor
    private func syncCalendarYearDataProjections() {
        var courseProjections: [UUID: TimetableCourseWeekProjection] = [:]
        for course in courses {
            guard let config = calendarYearTimetable.configuration(semesterID: course.sourceSemesterID) else {
                continue
            }
            var displayWeeks: [Int] = []
            var semesterWeekByDisplayWeek: [Int: Int] = [:]
            for semesterWeek in course.weeks {
                guard let occurrenceDate = Calendar.current.date(
                    byAdding: .day,
                    value: (semesterWeek - 1) * 7 + (course.dayOfWeek - 1),
                    to: config.semesterStartDate
                ), isDateInDisplayedCalendarYear(occurrenceDate),
                   let displayWeek = calendarYearTimetable.pageIndex(containing: occurrenceDate) else {
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
                  let displayWeek = calendarYearTimetable.pageIndex(containing: date) else { continue }
            let weekday = Calendar.current.component(.weekday, from: date)
            reminderProjections[reminder.id] = TimetableCellReminderProjection(
                displayWeek: displayWeek,
                dayOfWeek: ((weekday + 5) % 7) + 1
            )
        }
        timetableCellReminderProjections = reminderProjections
    }

    private func reloadTimetableBackground() {
        timetableBackgroundLoadTask?.cancel()
        let configuration = TimetableBackgroundConfiguration.load()
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
#if os(iOS)
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
#else
        ToolbarItem(placement: .leafyLeading) {
            HStack(spacing: 8 * leafyControlScale) {
                quickAccessMenu
                timetableWeatherButton
            }
        }
#endif
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
            quickAccessPopoverContent
                .leafyModalSurface()
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("首页快捷入口")
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
            HStack(spacing: 10 * leafyControlScale) {
                Image(systemName: systemImage)
                    .font(.system(size: 12 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                    .frame(width: 22 * leafyControlScale)

                Text(title)
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
            }
            .padding(.horizontal, 18 * leafyControlScale)
            .padding(.vertical, 12 * leafyControlScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scheduleQuickAccessAction(_ action: TimetableQuickAccessAction) {
        pendingQuickAccessAction = action
        isQuickAccessPresented = false

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard pendingQuickAccessAction == action else { return }
            pendingQuickAccessAction = nil
            guard !isQuickAccessPresented else { return }
            performQuickAccessAction(action)
        }
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
                weatherTextLabel(cachedTimetableWeather.timetableCapsuleText)
            }
            .accessibilityLabel("天气建议，\(cachedTimetableWeather.timetableCapsuleText)")
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
            .font(.system(size: 17 * leafyControlScale, weight: .semibold))
            .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
    }

    private func weatherTextLabel(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
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
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }

    private func defaultSchedulePeriod(occupiedPeriods: Set<Int>) -> Int {
        let preferred = min(max(TimetablePeriodSchedule.defaultStudyPeriod(), 1), totalClasses)
        if !occupiedPeriods.contains(preferred) {
            return preferred
        }
        return (1...totalClasses).first { !occupiedPeriods.contains($0) } ?? preferred
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
        guard let week = calendarYearTimetable.week(atPageIndex: page) else { return "本周" }
        switch week.phase {
        case let .teaching(_, weekNumber):
            return L10n.text("第 %d 周", language: leafyLanguage, weekNumber)
        case let .vacation(_, category):
            return TimetableCalendarMenuModel.vacationTitle(category: category)
        case .unconfigured:
            return shortWeekDateRange(week)
        }
    }

    private var weekPickerAccessibilityLabel: String {
        guard let week = currentTimelineWeek else { return weekTitle(currentWeek) }
        switch week.phase {
        case let .teaching(semesterID, weekNumber):
            let startDate = calendarYearTimetable.configuration(semesterID: semesterID)?.semesterStartDate
            let academicYear = TimetableCalendarMenuModel.academicYearTitle(semesterID: semesterID)
            let semester = TimetableCalendarMenuModel.semesterSeasonTitle(
                semesterID: semesterID,
                semesterStartDate: startDate
            )
            return "\(academicYear)学年，\(semester)，第 \(weekNumber) 周"
        case let .vacation(_, category):
            return TimetableCalendarMenuModel.vacationTitle(category: category)
        case .unconfigured:
            return shortWeekDateRange(week)
        }
    }

    private func selectTimetableWeek(_ page: Int) {
        currentWeek = page
        scrollToWeek = page
        isWeekPickerPresented = false
        syncReturnButtonVisibility(for: page)
    }

    private func shortWeekDateRange(_ week: CalendarYearWeek) -> String {
        let start = DateFormatters.chineseDay.string(from: max(
            week.weekStartDate,
            Calendar.current.date(from: DateComponents(year: calendarYearTimetable.year, month: 1, day: 1)) ?? week.weekStartDate
        ))
        let end = DateFormatters.chineseDay.string(from: min(
            week.weekEndDate(),
            Calendar.current.date(from: DateComponents(year: calendarYearTimetable.year, month: 12, day: 31)) ?? week.weekEndDate()
        ))
        return "\(start)－\(end)"
    }

    private func returnToCurrentWeek() {
        let week = currentCalendarPage
        currentWeek = week
        isAwayFromCurrentSchedule = false
        scrollToWeek = week
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
                let metrics = layoutMetrics(for: geometry.size, dayCount: gridSnapshot.visibleDays.count)

                Group {
                    switch metrics.mode {
                    case .weekGrid:
                        TimetableScrollContainer(
                            axisWidth: axisWidth,
                            headerHeight: headerHeight,
                            totalWeeks: totalWeeks,
                            weekStride: metrics.weekStride,
                            dayColumnWidth: metrics.dayColumnWidth,
                            rowHeight: metrics.rowHeight,
                            rowSpacing: metrics.rowSpacing,
                            allowsVerticalScroll: metrics.allowsVerticalScroll,
                            currentWeek: $currentWeek,
                            scrollToWeek: $scrollToWeek,
                            isAwayFromCurrentWeek: $isAwayFromCurrentSchedule,
                            containerID: "continuous-timetable",
                            onFirstInteractiveLayout: {
                                handleFirstInteractiveLayout()
                            },
                            currentWeekProvider: {
                                currentCalendarPage
                            },
                            corner: {
                                cornerHeader
                                    .frame(width: axisWidth, height: headerHeight)
                            },
                            header: {
                                ZStack(alignment: .topLeading) {
                                    ForEach(renderedTimetableWeeks, id: \.self) { week in
                                        HStack(alignment: .top, spacing: metrics.daySpacing) {
                                            ForEach(gridSnapshot.visibleDays, id: \.self) { day in
                                                let metadata = dayMetadata(day: day, week: week)
                                                if isDateInDisplayedCalendarYear(metadata.date) {
                                                    dayHeader(metadata: metadata)
                                                        .frame(width: metrics.dayColumnWidth, height: headerHeight)
                                                } else {
                                                    Color.clear
                                                        .frame(width: metrics.dayColumnWidth, height: headerHeight)
                                                        .accessibilityHidden(true)
                                                }
                                            }
                                        }
                                        .offset(x: CGFloat(week - 1) * metrics.weekStride)
                                        .accessibilityHidden(week != currentWeek)
                                    }
                                }
                                .frame(width: timetableContentWidth(metrics: metrics), height: headerHeight, alignment: .topLeading)
                            },
                            axis: {
                                timeAxis(metrics: metrics)
                            },
                            body: {
                                ZStack(alignment: .topLeading) {
                                    ForEach(renderedTimetableWeeks, id: \.self) { week in
                                        HStack(alignment: .top, spacing: metrics.daySpacing) {
                                            ForEach(gridSnapshot.visibleDays, id: \.self) { day in
                                                let metadata = dayMetadata(day: day, week: week)
                                                if isDateInDisplayedCalendarYear(metadata.date) {
                                                    dayColumnBody(
                                                        day: day,
                                                        week: week,
                                                        width: metrics.dayColumnWidth,
                                                        metrics: metrics,
                                                        gridSnapshot: gridSnapshot,
                                                        metadata: metadata
                                                    )
                                                } else {
                                                    Color.clear
                                                        .frame(width: metrics.dayColumnWidth, height: metrics.gridHeight)
                                                        .accessibilityHidden(true)
                                                }
                                            }
                                        }
                                        .offset(x: CGFloat(week - 1) * metrics.weekStride)
                                        .accessibilityHidden(week != currentWeek)
                                    }

                                    if timetableCurrentTimeIndicatorIsEnabled {
                                        currentTimeIndicator(metrics: metrics, visibleDays: gridSnapshot.visibleDays)
                                    }
                                }
                                .frame(
                                    width: timetableContentWidth(metrics: metrics),
                                    height: metrics.gridHeight,
                                    alignment: .topLeading
                                )
                            }
                        )
                        .frame(width: metrics.containerWidth, height: metrics.containerHeight, alignment: .topLeading)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .transaction { transaction in
                            transaction.animation = nil
                        }

                    case .agendaList:
                        timetableAgendaList(gridSnapshot: gridSnapshot)
                            .onAppear {
                                handleFirstInteractiveLayout()
                                scrollToWeek = nil
                                syncReturnButtonVisibility(for: currentWeek)
                            }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
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

    private var cornerHeader: some View {
        Text(monthString())
            .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
            .foregroundStyle(AppTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
        .frame(width: axisWidth, height: headerHeight)
    }

    private func timeAxis(metrics: TimetableLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...totalClasses, id: \.self) { classIndex in
                let slot = TimetablePeriodSchedule.slot(for: classIndex)
                VStack(spacing: 0) {
                    if let startText = slot?.startText {
                        Text(startText)
                            .font(.system(size: 6.4 * leafyControlScale, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                    Text("\(classIndex)")
                        .font(.system(size: 15 * leafyControlScale, weight: .semibold))
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

    private func currentTimeIndicator(
        metrics: TimetableLayoutMetrics,
        visibleDays: [Int]
    ) -> some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            if currentWeek == currentCalendarPage,
               !visibleDays.isEmpty,
               let y = TimetableCurrentTimePosition.yPosition(for: context.date, metrics: metrics) {
                Rectangle()
                    .fill(AppTheme.accentEmphasis(for: themeColorPreference))
                    .frame(
                        width: TimetableCurrentTimeIndicatorGeometry.width(
                            visibleDayCount: visibleDays.count,
                            metrics: metrics
                        ),
                        height: CGFloat(
                            TimetableCurrentTimeIndicatorPreference.sanitizedThickness(
                                timetableCurrentTimeIndicatorThickness
                            )
                        )
                    )
                    .position(
                        x: TimetableCurrentTimeIndicatorGeometry.centerX(
                            page: currentCalendarPage,
                            visibleDayCount: visibleDays.count,
                            metrics: metrics
                        ),
                        y: y
                    )
                    .zIndex(10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: timetableContentWidth(metrics: metrics),
            height: metrics.gridHeight,
            alignment: .topLeading
        )
    }

    private func dayColumnBody(
        day: Int,
        week: Int,
        width: CGFloat,
        metrics: TimetableLayoutMetrics,
        gridSnapshot: TimetableGridSnapshot,
        metadata: TimetableDayMetadata
    ) -> some View {
        let layouts = gridSnapshot.layouts(day: day, week: week)
        let occupiedPeriods = gridSnapshot.occupiedPeriods(day: day, week: week)
        let reminders = gridSnapshot.cellReminders(week: week, day: day)
        let reminderPeriods = Set(reminders.flatMap { Array($0.displayPeriodRange) })
        let countdowns = metadata.countdowns
        let countdownPeriods = Set(countdowns.flatMap { Array($0.startPeriod...$0.endPeriod) })
        let exams = metadata.exams

        return ZStack(alignment: .topLeading) {
            timetableGridBackground(width: width, metrics: metrics)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        guard let period = (1...totalClasses).first(where: { candidate in
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

            if let accessiblePeriod = (1...totalClasses).first(where: {
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

            ForEach(reminders) { reminder in
                let geometry = scheduleBlockGeometry(
                    startDate: reminder.resolvedStartDate,
                    endDate: reminder.resolvedEndDate,
                    fallbackStartPeriod: reminder.displayStartPeriod,
                    fallbackEndPeriod: reminder.displayEndPeriod,
                    metrics: metrics
                )
                let blockWidth = max(width - metrics.cardInset * 2, 1)
                TimetableCellReminderBlockView(
                    renderValue: reminder,
                    height: geometry.height,
                    width: blockWidth
                )
                .position(
                    x: width * 0.5,
                    y: geometry.centerY
                )
                .zIndex(2)
                .onTapGesture {
                    guard let currentReminder = cellReminders.first(where: { $0.id == reminder.id }) else {
                        handleStaleTimetableSnapshot()
                        return
                    }
                    selectedCellReminderContext = TimetableCellReminderContext(
                        week: week,
                        day: day,
                        period: reminder.displayStartPeriod,
                        date: metadata.date,
                        occupiedPeriods: occupiedPeriods,
                        totalPeriods: totalClasses,
                        reminder: currentReminder
                    )
                }
            }

            ForEach(layouts) { layout in
                let blockHeight = heightForCourse(layout.course, metrics: metrics)
                let blockWidth = widthForLayout(layout, availableWidth: width, metrics: metrics)
                let noteText = gridSnapshot.note(for: layout.course, week: week)

                CourseBlockView(
                    renderValue: layout.course,
                    hasNote: noteText != nil,
                    noteText: noteText,
                    height: blockHeight,
                    width: blockWidth,
                    isCompact: true,
                    isTodayCourse: metadata.isToday,
                    backgroundPalette: timetableBackgroundCoursePalette,
                    courseCardOpacity: timetableBackgroundConfiguration.courseCardOpacity,
                    showsContextMenu: false
                )
                .position(
                    x: xOffsetForLayout(layout, availableWidth: width, metrics: metrics) + blockWidth * 0.5,
                    y: yOffset(for: layout.course, metrics: metrics) + blockHeight * 0.5
                )
                .onTapGesture {
                    guard let currentCourse = courses.first(where: { $0.id == layout.course.id }) else {
                        handleStaleTimetableSnapshot()
                        return
                    }
                    selectedCourseContext = SelectedCourseContext(
                        course: currentCourse,
                        week: layout.course.semesterWeek(for: week) ?? week,
                        day: day,
                        date: metadata.date
                    )
                }
                .onLongPressGesture {
                    courseNotePreview = CourseNotePreview(
                        courseName: layout.course.displayCourseName,
                        note: noteText
                    )
                }
            }

            ForEach(countdowns) { countdown in
                let geometry = scheduleBlockGeometry(
                    startDate: countdown.startsAt,
                    endDate: countdown.endsAt,
                    fallbackStartPeriod: countdown.startPeriod,
                    fallbackEndPeriod: countdown.endPeriod,
                    metrics: metrics
                )
                let blockWidth = max(width - metrics.cardInset * 2, 1)
                Button {
                    presentCustomScheduleEditor(for: countdown)
                } label: {
                    TimetableCountdownBlockView(
                        projection: countdown,
                        height: geometry.height,
                        width: blockWidth
                    )
                    .contentShape(
                        RoundedRectangle(cornerRadius: AppRadius.small * 0.68, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .position(
                    x: width * 0.5,
                    y: geometry.centerY
                )
                .zIndex(3)
            }

            ForEach(Array(exams.enumerated()), id: \.element.id) { index, projection in
                let blockHeight = examBlockHeight(metrics: metrics)
                let blockWidth = max(width - metrics.cardInset * 2, 1)
                TimetableExamBlockView(
                    projection: projection,
                    height: blockHeight,
                    width: blockWidth
                )
                .position(
                    x: width * 0.5,
                    y: examYPosition(for: projection.period, index: index, height: blockHeight, metrics: metrics)
                )
                .zIndex(4)
                .onTapGesture {
                    let context = teachingContext(for: week)
                    selectedDaySummary = TimetableDaySelection(
                        week: context?.week ?? week,
                        day: day,
                        date: metadata.date,
                        semesterID: context?.semesterID
                    )
                }
            }
        }
        .frame(width: width, height: metrics.gridHeight, alignment: .topLeading)
    }

    private func timetableAgendaList(gridSnapshot: TimetableGridSnapshot) -> some View {
        VStack(spacing: AppSpacing.compact) {
            timetableAgendaHeader

            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: AppSpacing.compact) {
                    ForEach(gridSnapshot.visibleDays, id: \.self) { day in
                        timetableAgendaDaySection(day: day, gridSnapshot: gridSnapshot)
                    }
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.bottom, AppSpacing.page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var timetableAgendaHeader: some View {
        HStack(spacing: AppSpacing.compact) {
            Button {
                moveAgendaWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16 * leafyControlScale, weight: .semibold))
                    .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一周")
            .disabled(currentWeek <= 1)

            VStack(spacing: 2 * leafyControlScale) {
                Text(weekTitle(currentWeek))
                    .font(.system(size: 17 * leafyControlScale, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(agendaWeekRangeText)
                    .font(.system(size: 11 * leafyControlScale, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)

            Button {
                moveAgendaWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16 * leafyControlScale, weight: .semibold))
                    .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一周")
            .disabled(currentWeek >= totalWeeks)
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.vertical, 8 * leafyControlScale)
        .background(AppTheme.cardBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.page)
    }

    private func timetableAgendaDaySection(day: Int, gridSnapshot: TimetableGridSnapshot) -> some View {
        let metadata = dayMetadata(day: day, week: currentWeek)
        let items = timetableAgendaItems(metadata: metadata, gridSnapshot: gridSnapshot)

        return VStack(alignment: .leading, spacing: 10 * leafyControlScale) {
            HStack(spacing: 8 * leafyControlScale) {
                VStack(alignment: .leading, spacing: 2 * leafyControlScale) {
                    Text(metadata.dayTitle)
                        .font(.system(size: 15 * leafyControlScale, weight: .bold))
                        .foregroundStyle(metadata.isToday ? AppTheme.accentEmphasis : AppTheme.primaryText)
                    Text(metadata.chineseDateText)
                        .font(.system(size: 11 * leafyControlScale, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                if let event = metadata.event {
                    Text(event.title)
                        .font(.system(size: 11 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(dayHeaderForeground(event: event, hasExam: false))
                        .lineLimit(1)
                }
            }

            if items.isEmpty {
                Text("当天没有课程安排")
                    .font(.system(size: 13 * leafyControlScale, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4 * leafyControlScale)
            } else {
                VStack(spacing: 8 * leafyControlScale) {
                    ForEach(items) { item in
                        timetableAgendaRow(item)
                    }
                }
            }
        }
        .padding(14 * leafyControlScale)
        .background(AppTheme.cardBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private func timetableAgendaRow(_ item: TimetableAgendaItem) -> some View {
        Button {
            handleAgendaItemTap(item)
        } label: {
            HStack(alignment: .top, spacing: 10 * leafyControlScale) {
                VStack(spacing: 2 * leafyControlScale) {
                    Text(item.periodText)
                        .font(.system(size: 13 * leafyControlScale, weight: .bold))
                        .foregroundStyle(item.tint)
                        .lineLimit(1)
                    Text(item.timeText)
                        .font(.system(size: 9.5 * leafyControlScale, weight: .medium))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 50 * leafyControlScale)

                VStack(alignment: .leading, spacing: 4 * leafyControlScale) {
                    Text(item.title)
                        .font(.system(size: 14.5 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(size: 12 * leafyControlScale, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: item.systemImage)
                    .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 24 * leafyControlScale, height: 24 * leafyControlScale)
            }
            .padding(10 * leafyControlScale)
            .background(item.tint.opacity(colorScheme == .dark ? 0.18 : 0.11), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(agendaTodayCourseStrokeColor(item), lineWidth: agendaTodayCourseStrokeWidth(item))
            )
            .shadow(
                color: agendaTodayCourseGlowColor(item),
                radius: agendaTodayCourseGlowRadius(item),
                y: 0
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [item.title, item.detail, item.periodText, item.timeText]
                .filter { !$0.isEmpty }
                .joined(separator: "，")
        )
    }

    private func isTodayCourseAgendaItem(_ item: TimetableAgendaItem) -> Bool {
        guard case .course = item.kind else { return false }
        return Calendar.current.isDateInToday(item.date)
    }

    private func agendaTodayCourseStrokeColor(_ item: TimetableAgendaItem) -> Color {
        guard isTodayCourseAgendaItem(item) else { return .clear }
        return AppTheme.accentEmphasis(for: themeColorPreference).opacity(colorScheme == .dark ? 0.92 : 0.78)
    }

    private func agendaTodayCourseStrokeWidth(_ item: TimetableAgendaItem) -> CGFloat {
        guard isTodayCourseAgendaItem(item) else { return 0 }
        return max(1.5, 1.7 * leafyControlScale)
    }

    private func agendaTodayCourseGlowColor(_ item: TimetableAgendaItem) -> Color {
        guard isTodayCourseAgendaItem(item) else { return .clear }
        return AppTheme.accent(for: themeColorPreference).opacity(colorScheme == .dark ? 0.24 : 0.16)
    }

    private func agendaTodayCourseGlowRadius(_ item: TimetableAgendaItem) -> CGFloat {
        isTodayCourseAgendaItem(item) ? 4 * leafyControlScale : 0
    }

    private func timetableAgendaItems(
        metadata: TimetableDayMetadata,
        gridSnapshot: TimetableGridSnapshot
    ) -> [TimetableAgendaItem] {
        timetableAgendaItemCache.items(
            metadata: metadata,
            gridSnapshot: gridSnapshot,
            totalClasses: totalClasses
        )
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
        guard let event = customCountdownEvents.first(where: { $0.id == projection.eventID }) else {
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

    private var agendaWeekRangeText: String {
        let start = dateFor(dayOfWeek: 1, in: currentWeek)
        let end = dateFor(dayOfWeek: 7, in: currentWeek)
        return "\(DateFormatters.chineseDay.string(from: start)) - \(DateFormatters.chineseDay.string(from: end))"
    }

    private func moveAgendaWeek(by delta: Int) {
        let nextWeek = min(max(currentWeek + delta, 1), totalWeeks)
        guard nextWeek != currentWeek else { return }
        currentWeek = nextWeek
        scrollToWeek = nextWeek
        syncReturnButtonVisibility(for: nextWeek)
    }

    private func scheduleBlockGeometry(
        startDate: Date?,
        endDate: Date?,
        fallbackStartPeriod: Int,
        fallbackEndPeriod: Int,
        metrics: TimetableLayoutMetrics
    ) -> TimetableScheduleBlockGeometry {
        TimetableScheduleBlockGeometry.make(
            startDate: startDate,
            endDate: endDate,
            fallbackStartPeriod: fallbackStartPeriod,
            fallbackEndPeriod: fallbackEndPeriod,
            metrics: metrics,
            minimumHeight: min(
                18 * leafyControlScale,
                max(metrics.rowHeight - metrics.cardInset * 2, 1)
            )
        )
    }

    private func examBlockHeight(metrics: TimetableLayoutMetrics) -> CGFloat {
        min(max(metrics.rowHeight * 0.52, 20 * leafyControlScale), metrics.rowHeight - metrics.cardInset * 2)
    }

    private func examYPosition(for period: Int, index: Int, height: CGFloat, metrics: TimetableLayoutMetrics) -> CGFloat {
        let base = yPosition(forClass: period, metrics: metrics) + metrics.cardInset + height * 0.5
        let stackedOffset = CGFloat(index % 2) * min(height * 0.38, 8 * leafyControlScale)
        return base + stackedOffset
    }

    private func dayHeader(metadata: TimetableDayMetadata) -> some View {
        return VStack(spacing: 1) {
            Text(metadata.dayTitle)
                .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
            Text(metadata.numericDateText)
                .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
            if let event = metadata.event {
                Text(event.title)
                    .font(.system(size: 8.5 * leafyControlScale, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
            if metadata.hasExam {
                Label("考试", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 8.5 * leafyControlScale, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .foregroundStyle(dayHeaderTextForeground(for: metadata))
        .frame(maxWidth: .infinity, minHeight: headerHeight)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(dayHeaderFill(today: metadata.isToday, event: metadata.event, hasExam: metadata.hasExam))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(metadata.isToday || metadata.event != nil || metadata.hasExam ? Color.clear : AppTheme.separator, lineWidth: 1)
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
            for classIndex in 1...totalClasses {
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

    private var renderedTimetableWeeks: [Int] {
        TimetableRenderedWeekWindow.pages(
            currentWeek: currentWeek,
            pendingWeek: scrollToWeek,
            totalWeeks: totalWeeks
        )
    }

    private func timetableContentWidth(metrics: TimetableLayoutMetrics) -> CGFloat {
        max(CGFloat(totalWeeks) * metrics.weekStride - metrics.weekSpacing, 1)
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

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.1)
            Text("正在同步课表")
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unauthenticatedState: some View {
        ContentUnavailableView(
            "需要重新登录",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("当前教务登录态不可用，请先连接校园网，再回到登录页重新登录。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(title: String, description: String) -> some View {
        ContentUnavailableView(
            L10n.text(title, language: leafyLanguage),
            systemImage: "calendar",
            description: Text(L10n.text(description, language: leafyLanguage))
        )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
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

    private func layoutsForDay(_ day: Int, week: Int) -> [TimetableGridCourseLayout] {
        currentTimetableGridSnapshot().layouts(day: day, week: week)
    }

    private func widthForLayout(
        _ layout: TimetableGridCourseLayout,
        availableWidth: CGFloat,
        metrics: TimetableLayoutMetrics
    ) -> CGFloat {
        let totalSpacing = CGFloat(max(layout.laneCount - 1, 0)) * metrics.laneSpacing
        let laneWidth = (availableWidth - totalSpacing - metrics.cardInset * 2) / CGFloat(layout.laneCount)
        return max(laneWidth, 1)
    }

    private func xOffsetForLayout(
        _ layout: TimetableGridCourseLayout,
        availableWidth: CGFloat,
        metrics: TimetableLayoutMetrics
    ) -> CGFloat {
        let laneWidth = widthForLayout(layout, availableWidth: availableWidth, metrics: metrics)
        return metrics.cardInset + CGFloat(layout.laneIndex) * (laneWidth + metrics.laneSpacing)
    }

    private func heightForCourse(_ course: TimetableCourseRenderValue, metrics: TimetableLayoutMetrics) -> CGFloat {
        let count = max(course.duration.count, 1)
        let rawHeight = CGFloat(count) * metrics.rowHeight + CGFloat(count - 1) * metrics.rowSpacing - metrics.cardInset * 2
        return max(rawHeight, metrics.rowHeight * 0.7)
    }

    private func yOffset(for course: TimetableCourseRenderValue, metrics: TimetableLayoutMetrics) -> CGFloat {
        guard let start = course.duration.min() else { return 0 }
        return yPosition(forClass: start, metrics: metrics) + metrics.cardInset
    }

    private func yPosition(forClass classIndex: Int, metrics: TimetableLayoutMetrics) -> CGFloat {
        CGFloat(max(classIndex - 1, 0)) * (metrics.rowHeight + metrics.rowSpacing)
    }

    private func syncReturnButtonVisibility(for visibleWeek: Int? = nil) {
        let week = visibleWeek ?? currentWeek
        isAwayFromCurrentSchedule = week != currentCalendarPage
    }

    private func isDateInDisplayedCalendarYear(_ date: Date) -> Bool {
        Calendar.current.component(.year, from: date) == calendarYearTimetable.year
    }

    private func teachingContext(for page: Int) -> (semesterID: String, week: Int)? {
        guard let timelineWeek = calendarYearTimetable.week(atPageIndex: page),
              case let .teaching(semesterID, weekNumber) = timelineWeek.phase else { return nil }
        return (semesterID, weekNumber)
    }

    private func dateFor(dayOfWeek: Int, in week: Int) -> Date {
        guard let timelineWeek = calendarYearTimetable.week(atPageIndex: week) else { return Date() }
        return Calendar.current.date(
            byAdding: .day,
            value: dayOfWeek - 1,
            to: timelineWeek.weekStartDate
        ) ?? timelineWeek.weekStartDate
    }

    private func monthString() -> String {
        let date = dateFor(dayOfWeek: 1, in: currentWeek)
        let month = Calendar.current.component(.month, from: date)
        return "\(month)月"
    }

    private func dayTitle(_ day: Int) -> String {
        leafyLanguage.weekdayTitle(for: day)
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
            countdownEvents: customCountdownEvents,
            exams: cachedExamArrangements,
            calendarYear: calendarYearTimetable
        )
    }

    private func persistParserDebugHTML(_ html: String) -> String {
        let title: String = {
            guard let document = try? SwiftSoup.parse(html) else { return L10n.text("无标题", language: leafyLanguage) }
            return ((try? document.title()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        let titlePart = title.isEmpty ? L10n.text("无标题", language: leafyLanguage) : title

        #if DEBUG
        let bodyPrefix: String = {
            guard let document = try? SwiftSoup.parse(html) else { return "" }
            let raw = ((try? document.body()?.text()) ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(raw.prefix(100))
        }()

        let filename = "last_timetable_parser_input.html"
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = caches.appendingPathComponent("leafy-debug", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(filename)
            try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let bodyPart = bodyPrefix.isEmpty ? "" : L10n.text("，正文前缀：%@", language: leafyLanguage, bodyPrefix)
        return L10n.text("调试文件：%@，标题：%@%@", language: leafyLanguage, filename, titlePart, bodyPart)
        #else
        return L10n.text("页面标题：%@。请确认校园网连接，或重新登录后重试。", language: leafyLanguage, titlePart)
        #endif
    }

    private func fetchAndParseTimetable(userInitiated: Bool) async {
        guard !isFetching else { return }
        if isCustomCampus {
            await MainActor.run {
                if userInitiated {
                    isTimetableProcessingPresented = true
                }
            }
            return
        }
        if ReviewDemoMode.isEnabled {
            await MainActor.run {
                ReviewDemoDataSeeder.seed(using: modelContext)
                lastSyncAt = TimetableCacheMetadata.lastSyncAt
                lastFailureMessage = nil
                syncReturnButtonVisibility()
                publishWidgetSnapshot()
            }
            return
        }

        if userInitiated,
           let request = await SchoolReauthentication.preflightRequest(
               networkManager: networkManager,
               context: .timetable(portal: networkManager.currentPortal)
           ) {
            await MainActor.run {
                reauthenticationRequest = request
            }
            return
        }

        guard networkManager.isLoggedIn else {
            if userInitiated, networkManager.hasCachedIdentity {
                reauthenticationRequest = SchoolReauthenticationRequest(
                    context: .timetable(portal: networkManager.currentPortal)
                )
            } else {
                alertMessage = networkManager.hasCachedIdentity
                    ? L10n.text("本地身份已识别，但刷新课表需要连接校园网并重新建立教务登录态。", language: leafyLanguage)
                    : L10n.text("请先连接校园网登录教务系统。", language: leafyLanguage)
                showAlert = true
            }
            return
        }
        await MainActor.run { isFetching = true }
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable(force: userInitiated)
        await MainActor.run {
            applySemesterRuntimeConfig(semesterConfig)
        }

        do {
            let refreshUseCase = TimetableRefreshUseCase(repository: dependencies.schoolTimetableRepository)
            let htmlData = try await refreshUseCase.fetchHTML()
            let parsedCourseRecords: [ParsedCourseRecord]

            do {
                parsedCourseRecords = try await TimetableRefreshUseCase.parseRecords(html: htmlData)
            } catch {
                let debugSummary = persistParserDebugHTML(htmlData)
                throw NSError(
                    domain: "leafy.timetable",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription)。\(debugSummary)"]
                )
            }

            try await MainActor.run {
                let newCourses = parsedCourseRecords.map {
                    $0.makeCourse(semesterID: semesterConfig.semesterID)
                }
                let sharedCourses = newCourses.map(SharedTimetableCourse.init(course:))

                for course in courses where
                    course.sourceSemesterID == semesterConfig.semesterID
                    || !courseIntersectsCurrentCalendarYear(course) {
                    modelContext.delete(course)
                }
                for course in newCourses {
                    modelContext.insert(course)
                }

                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    throw error
                }

                timetableGridSnapshotCache.invalidate()
                timetableGridSnapshot = nil
                TimetableCacheMetadata.lastSyncAt = Date()
                TimetableCacheMetadata.lastFailureMessage = nil
                TimetableCacheMetadata.lastSyncedSemesterID = semesterConfig.semesterID
                AppStoreReviewCoordinator.recordSuccessfulSync(kind: .timetable, date: Date())
                SchoolDataRefreshNotifier.post(.timetable)
                Task {
                    await TimetableSharingService.shared.publishExistingSnapshotIfNeeded(courses: sharedCourses)
                }
                lastSyncAt = TimetableCacheMetadata.lastSyncAt
                lastFailureMessage = nil
                isFetching = false
                syncReturnButtonVisibility()
                publishWidgetSnapshot()
            }
        } catch {
            await MainActor.run {
                isFetching = false
                TimetableCacheMetadata.lastFailureMessage = error.localizedDescription
                lastFailureMessage = error.localizedDescription
                publishWidgetSnapshot()
                if userInitiated, SchoolReauthentication.shouldPromptForUserInitiatedAccess(error) {
                    reauthenticationRequest = SchoolReauthenticationRequest(
                        context: .timetable(portal: networkManager.currentPortal)
                    )
                } else {
                    alertMessage = courses.isEmpty
                        ? L10n.text("获取课表失败：%@", language: leafyLanguage, error.localizedDescription)
                        : L10n.text("获取课表失败，已继续显示本地缓存：%@", language: leafyLanguage, error.localizedDescription)
                    showAlert = true
                }
            }
        }
    }

    private func publishWidgetSnapshot() {
        LeafyWidgetSnapshotBuilder.publish(
            courses: courses.filter { $0.sourceSemesterID == SemesterConfig.currentSemesterID },
            notes: courseNotes,
            occurrenceNotes: occurrenceNotes,
            reminders: courseReminderSettings,
            cellReminders: cellReminders,
            isAuthenticated: networkManager.hasCachedIdentity || ReviewDemoMode.isEnabled
        )
    }

    private func openCourseFromDeepLink(id: UUID) {
        guard let course = courses.first(where: { $0.id == id }) else {
            return
        }

        guard let config = calendarYearTimetable.configuration(semesterID: course.sourceSemesterID) else { return }
        let preferredSemesterWeek = SemesterConfig.currentWeek(config: config)
        let semesterWeek = course.weeks.contains(preferredSemesterWeek)
            ? preferredSemesterWeek
            : course.weeks.sorted().first ?? preferredSemesterWeek
        guard let weekStart = Calendar.current.date(
            byAdding: .day,
            value: (semesterWeek - 1) * 7,
            to: config.semesterStartDate
        ), let targetPage = calendarYearTimetable.pageIndex(containing: weekStart) else { return }
        currentWeek = targetPage
        scrollToWeek = targetPage
        selectedCourseContext = SelectedCourseContext(
            course: course,
            week: semesterWeek,
            day: course.dayOfWeek,
            date: Calendar.current.date(
                byAdding: .day,
                value: course.dayOfWeek - 1,
                to: weekStart
            ) ?? weekStart
        )
    }

}

private struct TimetableWeekPickerPanel: View {
    let model: TimetableCalendarMenuModel
    let selectedPage: Int
    let currentPage: Int
    let onSelect: (Int) -> Void

    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.leafyLanguage) private var leafyLanguage

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 64), spacing: AppSpacing.compact),
        count: 4
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.card) {
                    ForEach(model.academicYears) { academicYear in
                        academicYearSection(academicYear)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("年度视图")
                            .leafyHeadline()

                        TimetableTimeScopeView(
                            snapshot: TimetableTimeScopeSnapshot.make(
                                currentWeek: SemesterConfig.currentWeek(),
                                referenceDate: Date(),
                                language: leafyLanguage
                            ),
                            presentation: .embedded
                        )
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("选择周次")
            .leafyInlineNavigationTitle()
        }
    }

    @ViewBuilder
    private func academicYearSection(_ academicYear: TimetableCalendarMenuAcademicYear) -> some View {
        let visibleStages = academicYear.stages.filter { stage in
            guard case let .semester(semester) = stage else { return true }
            return semester.title != "春季学期"
        }

        if !visibleStages.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text("\(academicYear.academicYear)学年")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)

                ForEach(visibleStages) { stage in
                    switch stage {
                    case let .semester(semester):
                        semesterSection(semester)
                    case let .vacation(vacation):
                        vacationButton(vacation)
                    }
                }
            }
        }
    }

    private func semesterSection(_ semester: TimetableCalendarMenuSemester) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(spacing: AppSpacing.compact) {
                Text(semester.title)
                    .leafyHeadline()
                if semester.semesterID == model.currentSemesterID {
                    Text("当前学期")
                        .microCaption()
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                }
            }

            LazyVGrid(columns: columns, spacing: AppSpacing.compact) {
                ForEach(semester.weeks) { week in
                    weekButton(week, semester: semester)
                }
            }
        }
        .padding(16)
        .leafyCardStyle()
    }

    private func weekButton(
        _ week: TimetableCalendarMenuWeek,
        semester: TimetableCalendarMenuSemester
    ) -> some View {
        let isSelected = week.page == selectedPage
        let isCurrent = week.page == currentPage
        let tint = AppTheme.accent(for: themeColorPreference)

        return Button {
            onSelect(week.page)
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

    private func vacationButton(_ vacation: TimetableCalendarMenuVacation) -> some View {
        let isSelected = vacation.page == selectedPage
        let isCurrent = vacation.page == currentPage
        let tint = AppTheme.accent(for: themeColorPreference)

        return Button {
            onSelect(vacation.page)
        } label: {
            HStack {
                Label(vacation.title, systemImage: "sun.max")
                    .leafyBody()
                Spacer()
                if isCurrent {
                    Text("本周")
                        .microCaption()
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 14)
            .foregroundStyle(isSelected ? Color.white : AppTheme.primaryText)
            .background(
                isSelected ? tint : AppTheme.fill,
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(vacation.title)\(isCurrent ? "，本周" : "")\(isSelected ? "，已选择" : "")")
        .accessibilityHint("跳转到\(vacation.title)")
    }
}
