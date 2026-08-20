import SwiftUI
import Charts
import UIKit

struct TimetableWeatherAdviceSheet: View {
    let currentWeek: Int
    let courses: [Course]
    let cellReminders: [TimetableCellReminder]
    let exams: [ExamArrangement]
    @Binding var weatherPreview: TimetableWeatherSnapshot?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyDependencies) private var dependencies
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var loadState: TimetableWeatherAdviceLoadState = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("天气建议")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                if case .loaded = loadState {
                    ToolbarItem(placement: .leafyTrailing) {
                        Button("刷新") {
                            Task { await loadWeather(requestsPermissionIfNeeded: false) }
                        }
                    }
                }
            }
            .task {
                await loadInitialState()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await loadInitialState() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            loadingCard
        case .permissionDenied:
            permissionCard(
                title: "定位权限未开启",
                detail: "请在系统设置中允许 MyLeafy 使用位置，然后回到这里刷新天气。",
                primaryTitle: "打开设置"
            ) {
                openAppSettings()
            }
        case .failed:
            failedCard
        case .loaded(let snapshot, let summary):
            loadedContent(snapshot: snapshot, summary: summary)
        }
    }

    private var loadingCard: some View {
        VStack(spacing: 14 * leafyControlScale) {
            ProgressView()
            Text("正在读取天气")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(24 * leafyControlScale)
        .leafyCardStyle()
    }

    private func permissionCard(
        title: String,
        detail: String,
        primaryTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16 * leafyControlScale) {
            HStack(alignment: .top, spacing: 12 * leafyControlScale) {
                LeafyIconBadge(systemName: "location")

                VStack(alignment: .leading, spacing: 5 * leafyControlScale) {
                    Text(title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(detail)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Button(action: action) {
                Label(primaryTitle, systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: themeColorPreference))
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 16 * leafyControlScale) {
            HStack(alignment: .top, spacing: 12 * leafyControlScale) {
                LeafyIconBadge(systemName: "cloud.slash", tint: AppTheme.tertiaryText)

                VStack(alignment: .leading, spacing: 5 * leafyControlScale) {
                    Text("天气暂不可用")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text("可以稍后重试。若刚启用 WeatherKit，请确认开发者后台已同时开启 capability 和 App Service。")
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Button {
                Task { await loadWeather(requestsPermissionIfNeeded: false) }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent(for: themeColorPreference))
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private func loadedContent(
        snapshot: TimetableWeatherSnapshot,
        summary: TimetableWeatherAdviceSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            weatherSummaryCard(snapshot: snapshot, suggestions: summary.suggestions)
            hourlyForecastSection(snapshot.upcomingHourlyForecast())

            if !summary.scheduleItems.isEmpty {
                scheduleSection(summary.scheduleItems)
            }

            attributionFooter(snapshot.attribution)
        }
    }

    private func weatherSummaryCard(
        snapshot: TimetableWeatherSnapshot,
        suggestions: [TimetableWeatherSuggestion]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16 * leafyControlScale) {
            HStack(alignment: .center, spacing: 10 * leafyControlScale) {
                Image(systemName: snapshot.symbolName.isEmpty ? "cloud.sun" : snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 25 * leafyControlScale, weight: .medium))
                    .frame(width: 32 * leafyControlScale, height: 32 * leafyControlScale)

                Text("\(Int(snapshot.temperature.rounded()))°")
                    .font(.system(size: 26 * leafyControlScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                Text(snapshot.localizedCondition(language: leafyLanguage))
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(snapshot.observedAt.formatted(date: .omitted, time: .shortened)) 更新")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)
            }

            if !suggestions.isEmpty {
                Divider()

                Text("今天建议")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                VStack(spacing: 10 * leafyControlScale) {
                    ForEach(suggestions) { suggestion in
                        WeatherSuggestionRow(suggestion: suggestion)
                    }
                }
            }
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private func hourlyForecastSection(_ hours: [TimetableHourlyWeather]) -> some View {
        VStack(alignment: .leading, spacing: 12 * leafyControlScale) {
            Text("未来 12 小时")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            if !hours.isEmpty {
                temperatureChartCard(hours)
                precipitationChartCard(hours)
            } else {
                Text("暂无逐小时预报")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16 * leafyControlScale)
                    .background(
                        AppTheme.softFill,
                        in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    )
            }
        }
    }

    private func temperatureChartCard(_ hours: [TimetableHourlyWeather]) -> some View {
        let axis = temperatureAxis(for: hours)

        return VStack(alignment: .leading, spacing: 8 * leafyControlScale) {
            Text("气温")
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            Chart(hours, id: \.date) { hour in
                LineMark(
                    x: .value("时间", hour.date),
                    y: .value("温度", hour.temperature)
                )
                .foregroundStyle(AppTheme.warning)
                .interpolationMethod(.catmullRom)

                if hour.date != hours.first?.date, hour.date != hours.last?.date {
                    PointMark(
                        x: .value("时间", hour.date),
                        y: .value("温度", hour.temperature)
                    )
                    .foregroundStyle(AppTheme.warning)
                }
            }
            .chartYScale(domain: axis.domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.separator.opacity(0.45))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.hour()))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: axis.values) { value in
                    AxisGridLine().foregroundStyle(AppTheme.separator.opacity(0.55))
                    AxisValueLabel {
                        if let temperature = value.as(Double.self) {
                            Text("\(Int(temperature.rounded()))°")
                        }
                    }
                }
            }
            .frame(height: 120 * leafyControlScale)
            .accessibilityLabel("未来 12 小时气温趋势")
        }
        .padding(14 * leafyControlScale)
        .background(
            AppTheme.warning.opacity(colorScheme == .dark ? 0.18 : 0.12),
            in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.warning.opacity(0.2), lineWidth: 1)
        )
    }

    private func precipitationChartCard(_ hours: [TimetableHourlyWeather]) -> some View {
        VStack(alignment: .leading, spacing: 8 * leafyControlScale) {
            Text("降水概率")
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            Chart(hours, id: \.date) { hour in
                BarMark(
                    x: .value("时间", hour.date),
                    y: .value("降水概率", hour.precipitationChance)
                )
                .foregroundStyle(Color.blue.opacity(0.72))
                .cornerRadius(3)
            }
            .chartYScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.separator.opacity(0.45))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.hour()))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                    AxisGridLine().foregroundStyle(AppTheme.separator.opacity(0.55))
                    AxisValueLabel {
                        if let chance = value.as(Double.self) {
                            Text(chance.formatted(.percent.precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .frame(height: 104 * leafyControlScale)
            .accessibilityLabel("未来 12 小时降水概率")
        }
        .padding(14 * leafyControlScale)
        .background(
            Color.blue.opacity(colorScheme == .dark ? 0.16 : 0.09),
            in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
    }

    private func scheduleSection(_ items: [TimetableWeatherScheduleItem]) -> some View {
        VStack(alignment: .leading, spacing: 12 * leafyControlScale) {
            Text("后续安排")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            VStack(spacing: 8 * leafyControlScale) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10 * leafyControlScale) {
                        Image(systemName: iconName(for: item.kind))
                            .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                            .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                            .frame(width: 22 * leafyControlScale)

                        VStack(alignment: .leading, spacing: 2 * leafyControlScale) {
                            Text(item.displayTitle)
                                .leafySubheadline()
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)
                            Text(item.timeText)
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4 * leafyControlScale)
                }
            }
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private func attributionFooter(_ attribution: TimetableWeatherAttribution) -> some View {
        HStack(alignment: .bottom, spacing: 8 * leafyControlScale) {
            if let markURL = colorScheme == .dark
                ? attribution.combinedMarkDarkURL
                : attribution.combinedMarkLightURL {
                AsyncImage(url: markURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Text("数据来源：\(attribution.serviceName)")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: 110 * leafyControlScale, maxHeight: 18 * leafyControlScale, alignment: .leading)
            } else {
                Text("数据来源：\(attribution.serviceName)")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Link("法律信息", destination: attribution.legalPageURL)
                .microCaption()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4 * leafyControlScale)
    }

    private func temperatureAxis(for hours: [TimetableHourlyWeather]) -> (
        domain: ClosedRange<Double>,
        values: [Double]
    ) {
        let temperatures = hours.map(\.temperature)
        let lowerBound = min(-10, floor((temperatures.min() ?? -10) / 10) * 10)
        let upperBound = max(40, ceil((temperatures.max() ?? 40) / 10) * 10)
        return (
            domain: lowerBound...upperBound,
            values: Array(stride(from: lowerBound, through: upperBound, by: 10))
        )
    }

    @MainActor
    private func loadInitialState() async {
        switch dependencies.timetableWeatherService.authorizationState() {
        case .authorized:
            if let cached = dependencies.timetableWeatherService.cachedWeather(maxAge: 30 * 60) {
                apply(snapshot: cached)
            } else {
                await loadWeather(requestsPermissionIfNeeded: false)
            }
        case .notDetermined:
            await loadWeather(requestsPermissionIfNeeded: true)
        case .denied:
            loadState = .permissionDenied
        case .unavailable:
            loadState = .failed
        }
    }

    @MainActor
    private func loadWeather(requestsPermissionIfNeeded: Bool) async {
        loadState = .loading
        do {
            let snapshot = try await dependencies.timetableWeatherService.fetchCurrentWeather(
                requestsPermissionIfNeeded: requestsPermissionIfNeeded
            )
            apply(snapshot: snapshot)
        } catch TimetableWeatherServiceError.permissionRequired {
            if requestsPermissionIfNeeded {
                loadState = .failed
            } else {
                await loadWeather(requestsPermissionIfNeeded: true)
            }
        } catch TimetableWeatherServiceError.permissionDenied {
            loadState = .permissionDenied
        } catch {
            loadState = .failed
        }
    }

    @MainActor
    private func apply(snapshot: TimetableWeatherSnapshot) {
        let scheduleItems = TimetableWeatherAdviceBuilder.scheduleItems(
            courses: courses,
            cellReminders: cellReminders,
            exams: exams,
            currentWeek: currentWeek
        )
        let summary = TimetableWeatherAdviceBuilder.makeSummary(
            snapshot: snapshot,
            scheduleItems: scheduleItems
        )
        weatherPreview = snapshot
        loadState = .loaded(snapshot, summary)
    }

    private func iconName(for kind: TimetableWeatherScheduleItemKind) -> String {
        switch kind {
        case .course:
            return "book.closed"
        case .reminder:
            return "calendar.badge.clock"
        case .exam:
            return "pencil.and.list.clipboard"
        }
    }

    private func openAppSettings() {
        LeafySystemSettings.openApplicationSettings()
    }
}

private enum TimetableWeatherAdviceLoadState: Equatable {
    case idle
    case loading
    case permissionDenied
    case failed
    case loaded(TimetableWeatherSnapshot, TimetableWeatherAdviceSummary)
}

private struct WeatherSuggestionRow: View {
    @Environment(\.leafyControlScale) private var leafyControlScale

    let suggestion: TimetableWeatherSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 11 * leafyControlScale) {
            Image(systemName: suggestion.systemImage)
                .font(.system(size: 16 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24 * leafyControlScale, height: 24 * leafyControlScale)

            VStack(alignment: .leading, spacing: 3 * leafyControlScale) {
                Text(suggestion.title)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(suggestion.detail)
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
    }
}
