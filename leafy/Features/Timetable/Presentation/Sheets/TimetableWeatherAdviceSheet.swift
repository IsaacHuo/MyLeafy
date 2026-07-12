import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
        case .permissionRequired:
            permissionCard(
                title: "开启当前位置天气",
                detail: "允许 MyLeafy 使用当前位置后，可以根据今天后续课程给出带伞、加衣或防晒建议。",
                primaryTitle: "允许定位"
            ) {
                Task { await loadWeather(requestsPermissionIfNeeded: true) }
            }
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
            weatherHeader(snapshot)
            hourlyForecastSection(snapshot.upcomingHourlyForecast())
            suggestionsSection(summary.suggestions)

            if !summary.scheduleItems.isEmpty {
                scheduleSection(summary.scheduleItems)
            }

            attributionFooter(snapshot.attribution)
        }
    }

    private func weatherHeader(_ snapshot: TimetableWeatherSnapshot) -> some View {
        HStack(alignment: .center, spacing: 18 * leafyControlScale) {
            Image(systemName: snapshot.symbolName.isEmpty ? "cloud.sun" : snapshot.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 52 * leafyControlScale, weight: .medium))
                .frame(width: 64 * leafyControlScale, height: 64 * leafyControlScale)

            VStack(alignment: .leading, spacing: 3 * leafyControlScale) {
                Text("\(Int(snapshot.temperature.rounded()))°")
                    .font(.system(size: 42 * leafyControlScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Text(snapshot.condition)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.secondaryText)
                Text("更新于 \(DateFormatters.headerWithTime.string(from: snapshot.observedAt))")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private func hourlyForecastSection(_ hours: [TimetableHourlyWeather]) -> some View {
        return VStack(alignment: .leading, spacing: 14 * leafyControlScale) {
            Text("未来 12 小时")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            if !hours.isEmpty {
                VStack(alignment: .leading, spacing: 14 * leafyControlScale) {
                    Chart(hours, id: \.date) { hour in
                        LineMark(
                            x: .value("时间", hour.date),
                            y: .value("温度", hour.temperature)
                        )
                        .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("时间", hour.date),
                            y: .value("温度", hour.temperature)
                        )
                        .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(AppTheme.separator.opacity(0.7))
                            AxisValueLabel {
                                if let temperature = value.as(Double.self) {
                                    Text("\(Int(temperature.rounded()))°")
                                }
                            }
                        }
                    }
                    .frame(height: 116 * leafyControlScale)
                    .accessibilityLabel("未来 12 小时温度趋势")

                    Chart(hours, id: \.date) { hour in
                        BarMark(
                            x: .value("时间", hour.date),
                            y: .value("降水概率", hour.precipitationChance)
                        )
                        .foregroundStyle(AppTheme.accent(for: themeColorPreference).opacity(0.65))
                        .cornerRadius(3)
                    }
                    .chartYScale(domain: 0...1)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                            AxisGridLine().foregroundStyle(AppTheme.separator.opacity(0.7))
                            AxisValueLabel {
                                if let chance = value.as(Double.self) {
                                    Text(chance.formatted(.percent.precision(.fractionLength(0))))
                                }
                            }
                        }
                    }
                    .frame(height: 76 * leafyControlScale)
                    .accessibilityLabel("未来 12 小时降水概率")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10 * leafyControlScale) {
                        ForEach(hours, id: \.date) { hour in
                            TimetableHourlyWeatherCard(hour: hour)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("暂无逐小时预报")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private func suggestionsSection(_ suggestions: [TimetableWeatherSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 12 * leafyControlScale) {
            Text("今天建议")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            VStack(spacing: 10 * leafyControlScale) {
                ForEach(suggestions) { suggestion in
                    WeatherSuggestionRow(suggestion: suggestion)
                }
            }
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
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
        HStack(spacing: 8 * leafyControlScale) {
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
            loadState = .permissionRequired
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
            loadState = .permissionRequired
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

private struct TimetableHourlyWeatherCard: View {
    @Environment(\.leafyControlScale) private var leafyControlScale

    let hour: TimetableHourlyWeather

    var body: some View {
        VStack(spacing: 6 * leafyControlScale) {
            Text(hour.date.formatted(.dateTime.hour()))
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Image(systemName: hour.symbolName.isEmpty ? "cloud.sun" : hour.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 22 * leafyControlScale))
            Text("\(Int(hour.temperature.rounded()))°")
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)
            Label(
                hour.precipitationChance.formatted(.percent.precision(.fractionLength(0))),
                systemImage: "drop.fill"
            )
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(width: 64 * leafyControlScale)
        .padding(.vertical, 10 * leafyControlScale)
        .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private enum TimetableWeatherAdviceLoadState: Equatable {
    case idle
    case loading
    case permissionRequired
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
