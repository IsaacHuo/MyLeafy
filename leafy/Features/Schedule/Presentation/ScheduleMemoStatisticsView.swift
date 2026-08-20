import Charts
import SwiftData
import SwiftUI
import UIKit

struct ScheduleMemoStatisticsView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Query private var memos: [ScheduleMemo]
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int?
    @State private var selectedDate: Date?
    @State private var annualMetric: ScheduleMemoAnnualMetric = .memoCount
    @State private var shareItem: ScheduleMemoStatisticsShareItem?
    @State private var shareErrorMessage: String?

    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let years = memos.lazy
            .filter { !$0.isTrashed }
            .map { calendar.component(.year, from: $0.createdAt) }
        return Set(years).union([currentYear]).sorted()
    }

    var body: some View {
        let statistics = ScheduleMemoStatistics.snapshot(
            memos: memos,
            selectedYear: selectedYear
        )

        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.card) {
                yearSelector

                if statistics.memoCount == 0 {
                    ContentUnavailableView(
                        L10n.text("还没有记录日迹", language: leafyLanguage),
                        systemImage: "chart.bar.xaxis",
                        description: Text(L10n.text("写下第一条随记后，这里会逐渐形成你的记录频率和习惯。", language: leafyLanguage))
                    )
                    .padding(.vertical, 72)
                } else {
                    overviewSection(statistics)
                    annualFrequencySection(statistics)
                    recentActivitySection(statistics)
                    habitsSection(statistics)
                    if !statistics.topTags.isEmpty {
                        tagsSection(statistics)
                    }
                    milestonesSection(statistics)
                    privacyFooter
                }
            }
            .leafyAdaptiveContentWidth(maxWidth: 760)
            .padding(.vertical, AppSpacing.card)
        }
        .background(LeafyPageBackground())
        .navigationTitle(L10n.text("记录日迹", language: leafyLanguage))
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    generateShareImage(statistics)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(statistics.memoCount == 0)
                .accessibilityLabel(L10n.text("导出记录日迹图片", language: leafyLanguage))
            }
        }
        .onChange(of: selectedYear) { _, _ in
            selectedMonth = nil
        }
        .leafySheet(item: $shareItem) { item in
            ScheduleMemoStatisticsSharePreview(item: item)
        }
        .leafySheet(isPresented: Binding(
            get: { selectedDate != nil },
            set: { if !$0 { selectedDate = nil } }
        )) {
            NavigationStack {
                ScheduleMemoDayView(date: selectedDate ?? Date())
            }
        }
        .alert(L10n.text("无法生成图片", language: leafyLanguage), isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button(L10n.text("好", language: leafyLanguage), role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "")
        }
    }

    private var yearSelector: some View {
        HStack(spacing: AppSpacing.compact) {
            Button {
                guard let previousYear else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedYear = previousYear
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(previousYear == nil)
            .accessibilityLabel(L10n.text("上一年", language: leafyLanguage))

            Menu {
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        if year == selectedYear {
                            Label(L10n.text("%@ 年", language: leafyLanguage, String(year)), systemImage: "checkmark")
                        } else {
                            Text(L10n.text("%@ 年", language: leafyLanguage, String(year)))
                        }
                    }
                }
            } label: {
                Text(L10n.text("%@ 年", language: leafyLanguage, String(selectedYear)))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(minWidth: 116, minHeight: 44)
                    .background(AppTheme.softFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("选择统计年份", language: leafyLanguage))

            Button {
                guard let nextYear else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedYear = nextYear
                }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(nextYear == nil)
            .accessibilityLabel(L10n.text("下一年", language: leafyLanguage))
        }
        .frame(maxWidth: .infinity)
    }

    private var previousYear: Int? {
        availableYears.last(where: { $0 < selectedYear })
    }

    private var nextYear: Int? {
        availableYears.first(where: { $0 > selectedYear })
    }

    private func overviewSection(_ statistics: ScheduleMemoStatistics) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            LeafySectionTitle(
                L10n.text("截至今天", language: leafyLanguage),
                subtitle: L10n.text("当前校园身份下保存在本机的随记", language: leafyLanguage)
            )
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppSpacing.compact
            ) {
                overviewMetric(
                    L10n.text("总随记", language: leafyLanguage),
                    value: L10n.text("%d 条随记", language: leafyLanguage, statistics.memoCount),
                    systemImage: "note.text"
                )
                overviewMetric(
                    L10n.text("记录天数", language: leafyLanguage),
                    value: L10n.text("%d 天", language: leafyLanguage, statistics.recordingDayCount),
                    systemImage: "calendar"
                )
                overviewMetric(
                    L10n.text("连续记录", language: leafyLanguage),
                    value: L10n.text("%d 天", language: leafyLanguage, statistics.currentStreak),
                    systemImage: "flame"
                )
                overviewMetric(
                    L10n.text("最长连续", language: leafyLanguage),
                    value: L10n.text("%d 天", language: leafyLanguage, statistics.longestStreak),
                    systemImage: "trophy"
                )
            }
        }
    }

    private func overviewMetric(
        _ title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .leafyCardStyle()
    }

    private func annualFrequencySection(_ statistics: ScheduleMemoStatistics) -> some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("全年记录频率", language: leafyLanguage))
                            .leafyHeadline()
                        Text(L10n.text("%@ 年 1 月至 12 月", language: leafyLanguage, String(selectedYear)))
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Picker(L10n.text("统计指标", language: leafyLanguage), selection: $annualMetric) {
                        ForEach(ScheduleMemoAnnualMetric.allCases) { metric in
                            Text(metric.title(language: leafyLanguage)).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Chart(statistics.selectedYearMonths) { month in
                    BarMark(
                        x: .value(L10n.text("月份", language: leafyLanguage), month.month),
                        y: .value(annualMetric.title(language: leafyLanguage), annualMetric.value(for: month))
                    )
                    .foregroundStyle(
                        month.month == Calendar.current.component(.month, from: Date()) &&
                        selectedYear == Calendar.current.component(.year, from: Date())
                            ? AppTheme.accent(for: themeColorPreference)
                            : AppTheme.accent(for: themeColorPreference).opacity(0.58)
                    )
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: statistics.selectedYearMonths.map(\.month)) { value in
                        AxisValueLabel {
                            if let month = value.as(Int.self) {
                                Text(L10n.text("%d月", language: leafyLanguage, month))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 210)
                .chartXSelection(value: $selectedMonth)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.text("全年记录频率", language: leafyLanguage))
                .accessibilityValue(
                    ScheduleMemoStatisticsAccessibility.annualSummary(
                        selectedYear: statistics.selectedYear,
                        months: statistics.selectedYearMonths,
                        metric: annualMetric,
                        language: leafyLanguage
                    )
                )

                if let month = selectedMonth,
                   let detail = statistics.selectedYearMonths.first(where: { $0.month == month }) {
                    Text(ScheduleMemoStatisticsAccessibility.monthSummary(detail, language: leafyLanguage))
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.numericText())
                } else {
                    Text(L10n.text("点按柱形查看当月记录情况。", language: leafyLanguage))
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private func recentActivitySection(_ statistics: ScheduleMemoStatistics) -> some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("近 30 天", language: leafyLanguage))
                        .leafyHeadline()
                    Text(recentSummary(statistics))
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                ScheduleMemoRecentHeatmap(
                    days: statistics.recent30Days,
                    themeColorPreference: themeColorPreference,
                    language: leafyLanguage,
                    onSelectDate: { selectedDate = $0 }
                )

                Text(recentComparison(statistics))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func habitsSection(_ statistics: ScheduleMemoStatistics) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            LeafySectionTitle(
                L10n.text("记录习惯", language: leafyLanguage),
                subtitle: habitSummary(statistics)
            )

            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(L10n.text("星期分布", language: leafyLanguage))
                        .leafyHeadline()
                    Chart(weekdayData(statistics)) { item in
                        BarMark(
                            x: .value(L10n.text("星期", language: leafyLanguage), item.name),
                            y: .value(L10n.text("随记", language: leafyLanguage), item.count)
                        )
                        .foregroundStyle(AppTheme.accent(for: themeColorPreference).opacity(0.72))
                        .cornerRadius(3)
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 128)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.text("星期分布", language: leafyLanguage))
                    .accessibilityValue(
                        ScheduleMemoStatisticsAccessibility.weekdaySummary(
                            counts: statistics.weekdayDistribution,
                            language: leafyLanguage
                        )
                    )
                }
            }

            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(L10n.text("时间段分布", language: leafyLanguage))
                        .leafyHeadline()
                    Chart(statistics.timePeriodDistribution) { item in
                        BarMark(
                            x: .value(L10n.text("随记", language: leafyLanguage), item.count),
                            y: .value(L10n.text("时间段", language: leafyLanguage), item.period.title(language: leafyLanguage))
                        )
                        .foregroundStyle(AppTheme.accent(for: themeColorPreference).opacity(0.72))
                        .cornerRadius(3)
                        .annotation(position: .trailing) {
                            Text("\(item.count)")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 180)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.text("时间段分布", language: leafyLanguage))
                    .accessibilityValue(
                        ScheduleMemoStatisticsAccessibility.timePeriodSummary(
                            periods: statistics.timePeriodDistribution,
                            language: leafyLanguage
                        )
                    )
                }
            }
        }
    }

    private func tagsSection(_ statistics: ScheduleMemoStatistics) -> some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(L10n.text("常用标签", language: leafyLanguage))
                    .leafyHeadline()

                ForEach(statistics.topTags) { tag in
                    HStack(spacing: 10) {
                        Text("#\(tag.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.accent(for: themeColorPreference), in: Capsule())
                            .lineLimit(1)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(AppTheme.softFill)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(AppTheme.accent(for: themeColorPreference).opacity(0.42))
                                        .frame(width: proxy.size.width * tagRatio(tag, in: statistics.topTags))
                                }
                        }
                        .frame(height: 8)
                        Text("\(tag.count)")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func milestonesSection(_ statistics: ScheduleMemoStatistics) -> some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("记录里程碑", language: leafyLanguage))
                    .leafyHeadline()

                if let firstDate = statistics.firstRecordingDate {
                    milestoneRow(
                        L10n.text("第一次记录", language: leafyLanguage),
                        detail: milestoneDateText(firstDate),
                        systemImage: "flag"
                    )
                }
                if let peakDate = statistics.peakDate {
                    milestoneRow(
                        L10n.text("记录最多的一天", language: leafyLanguage),
                        detail: L10n.text(
                            "%@ · %d 条随记",
                            language: leafyLanguage,
                            milestoneDateText(peakDate),
                            statistics.peakMemoCount
                        ),
                        systemImage: "sparkles"
                    )
                }
                milestoneRow(
                    L10n.text("最长连续记录", language: leafyLanguage),
                    detail: L10n.text("%d 天", language: leafyLanguage, statistics.longestStreak),
                    systemImage: "flame"
                )
                milestoneRow(
                    L10n.text("有记录的月份", language: leafyLanguage),
                    detail: L10n.text("%d 个月", language: leafyLanguage, statistics.recordingMonthCount),
                    systemImage: "calendar.badge.checkmark"
                )
            }
        }
    }

    private func milestoneDateText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return "" }
        return "\(year)/\(month)/\(day)"
    }

    private func milestoneRow(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                .frame(width: 24)
            Text(title)
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var privacyFooter: some View {
        Label(
            L10n.text("统计在本机完成，导出图片只包含汇总数字。", language: leafyLanguage),
            systemImage: "lock.shield"
        )
            .microCaption()
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func recentSummary(_ statistics: ScheduleMemoStatistics) -> String {
        L10n.text(
            "记录了 %d 天，共 %d 条随记",
            language: leafyLanguage,
            statistics.recent30DayRecordingDayCount,
            statistics.recent30DayMemoCount
        )
    }

    private func recentComparison(_ statistics: ScheduleMemoStatistics) -> String {
        let difference = statistics.recent30DayMemoCount - statistics.previous30DayMemoCount
        if statistics.previous30DayMemoCount == 0 {
            return statistics.recent30DayMemoCount == 0
                ? L10n.text("前 30 天和最近 30 天都没有记录。", language: leafyLanguage)
                : L10n.text("前 30 天暂无记录。", language: leafyLanguage)
        }
        if difference == 0 {
            return L10n.text("与前 30 天的随记数量相同。", language: leafyLanguage)
        }
        return difference > 0
            ? L10n.text("比前 30 天多 %d 条。", language: leafyLanguage, difference)
            : L10n.text("比前 30 天少 %d 条。", language: leafyLanguage, -difference)
    }

    private func habitSummary(_ statistics: ScheduleMemoStatistics) -> String {
        guard let weekdayIndex = statistics.weekdayDistribution.indices.max(by: {
            statistics.weekdayDistribution[$0] < statistics.weekdayDistribution[$1]
        }), statistics.weekdayDistribution[weekdayIndex] > 0 else {
            return L10n.text("记录多一些后，这里会显示你的常用时间。", language: leafyLanguage)
        }
        let weekday = leafyLanguage.weekdayTitle(for: weekdayIndex + 1)
        let period = statistics.timePeriodDistribution.max(by: { $0.count < $1.count })?.period.title(language: leafyLanguage) ?? ""
        return L10n.text("你最常在%@的%@记录。", language: leafyLanguage, weekday, period)
    }

    private func weekdayData(_ statistics: ScheduleMemoStatistics) -> [ScheduleMemoNamedCount] {
        zip(ScheduleMemoWeekday.shortNames(language: leafyLanguage), statistics.weekdayDistribution).enumerated().map {
            ScheduleMemoNamedCount(id: "weekday-\($0.offset)", name: $0.element.0, count: $0.element.1)
        }
    }

    private func tagRatio(_ tag: ScheduleMemoFrequency, in tags: [ScheduleMemoFrequency]) -> CGFloat {
        guard let maximum = tags.map(\.count).max(), maximum > 0 else { return 0 }
        return CGFloat(tag.count) / CGFloat(maximum)
    }

    @MainActor
    private func generateShareImage(_ statistics: ScheduleMemoStatistics) {
        let content = ScheduleMemoStatisticsShareCard(
            statistics: statistics,
            generatedAt: Date(),
            themeColorPreference: themeColorPreference,
            language: leafyLanguage
        )
        .frame(width: 360)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let image = renderer.uiImage else {
            shareErrorMessage = L10n.text("请稍后重试，或先截图保存当前页面。", language: leafyLanguage)
            return
        }
        shareItem = ScheduleMemoStatisticsShareItem(image: image)
    }
}

enum ScheduleMemoAnnualMetric: String, CaseIterable, Identifiable {
    case memoCount
    case recordingDays

    var id: String { rawValue }

    fileprivate var localizationKey: String {
        switch self {
        case .memoCount: return "随记数"
        case .recordingDays: return "记录天数"
        }
    }

    func title(language: AppLanguagePreference) -> String {
        L10n.text(localizationKey, language: language)
    }

    func value(for month: ScheduleMemoMonthStatistics) -> Int {
        switch self {
        case .memoCount: return month.memoCount
        case .recordingDays: return month.recordingDayCount
        }
    }
}

private struct ScheduleMemoNamedCount: Identifiable {
    let id: String
    let name: String
    let count: Int
}

private enum ScheduleMemoWeekday {
    static func shortNames(language: AppLanguagePreference) -> [String] {
        (1...7).map { day in
            let title = language.weekdayTitle(for: day)
            return language.resolvedLocalization == .zhHans
                ? String(title.dropFirst())
                : String(title.prefix(1))
        }
    }
}

fileprivate extension ScheduleMemoTimePeriod {
    func title(language: AppLanguagePreference) -> String {
        switch self {
        case .earlyMorning: return L10n.text("清晨", language: language)
        case .morning: return L10n.text("上午", language: language)
        case .afternoon: return L10n.text("下午", language: language)
        case .evening: return L10n.text("晚间", language: language)
        case .lateNight: return L10n.text("深夜", language: language)
        }
    }
}

enum ScheduleMemoStatisticsAccessibility {
    static func annualSummary(
        selectedYear: Int,
        months: [ScheduleMemoMonthStatistics],
        metric: ScheduleMemoAnnualMetric,
        language: AppLanguagePreference
    ) -> String {
        let values = months.map { month in
            switch metric {
            case .memoCount:
                return L10n.text("%d 月 %d 条随记", language: language, month.month, month.memoCount)
            case .recordingDays:
                return L10n.text("%d 月记录 %d 天", language: language, month.month, month.recordingDayCount)
            }
        }
        return L10n.text(
            "%@ 年全年记录频率（%@）：%@",
            language: language,
            String(selectedYear),
            metric.title(language: language),
            values.joined(separator: L10n.text("、", language: language))
        )
    }

    static func monthSummary(
        _ month: ScheduleMemoMonthStatistics,
        language: AppLanguagePreference
    ) -> String {
        L10n.text(
            "%d 月 · %d 条随记 · 记录 %d 天",
            language: language,
            month.month,
            month.memoCount,
            month.recordingDayCount
        )
    }

    static func weekdaySummary(
        counts: [Int],
        language: AppLanguagePreference
    ) -> String {
        let values = counts.enumerated().map { index, count in
            L10n.text(
                "%@：%d 条随记",
                language: language,
                language.weekdayTitle(for: index + 1),
                count
            )
        }
        return L10n.text(
            "星期分布：%@",
            language: language,
            values.joined(separator: L10n.text("、", language: language))
        )
    }

    static func timePeriodSummary(
        periods: [ScheduleMemoTimePeriodFrequency],
        language: AppLanguagePreference
    ) -> String {
        let values = periods.map { period in
            L10n.text(
                "%@：%d 条随记",
                language: language,
                period.period.title(language: language),
                period.count
            )
        }
        return L10n.text(
            "时间段分布：%@",
            language: language,
            values.joined(separator: L10n.text("、", language: language))
        )
    }

    static func heatmapSummary(
        days: [ScheduleMemoActivityDay],
        language: AppLanguagePreference
    ) -> String {
        L10n.text(
            "近 30 天热力图：%d 条随记，%d 天有记录。",
            language: language,
            days.reduce(0) { $0 + $1.count },
            days.filter { $0.count > 0 }.count
        )
    }
}

private struct ScheduleMemoRecentHeatmap: View {
    let days: [ScheduleMemoActivityDay]
    let themeColorPreference: AppThemeColorPreference
    let language: AppLanguagePreference
    let onSelectDate: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var paddedDays: [ScheduleMemoActivityDay?] {
        guard let first = days.first else { return [] }
        let weekday = Calendar.current.component(.weekday, from: first.date)
        let leadingEmptyCount = (weekday + 5) % 7
        return Array(repeating: nil, count: leadingEmptyCount) + days.map(Optional.some)
    }

    var body: some View {
        VStack(spacing: 7) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(ScheduleMemoWeekday.shortNames(language: language).enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                ForEach(Array(paddedDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button {
                            onSelectDate(day.date)
                        } label: {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(activityColor(day.count))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    if Calendar.current.isDateInToday(day.date) {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(AppTheme.accent(for: themeColorPreference), lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            L10n.text(
                                "%@，%d 条随记",
                                language: language,
                                day.date.formatted(
                                    Date.FormatStyle.dateTime
                                        .year()
                                        .month(.wide)
                                        .day()
                                        .locale(language.locale)
                                ),
                                day.count
                            )
                        )
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("近 30 天", language: language))
        .accessibilityValue(
            ScheduleMemoStatisticsAccessibility.heatmapSummary(days: days, language: language)
        )
    }

    private func activityColor(_ count: Int) -> Color {
        switch count {
        case 0: return AppTheme.softFill
        case 1: return AppTheme.accent(for: themeColorPreference).opacity(0.28)
        case 2: return AppTheme.accent(for: themeColorPreference).opacity(0.5)
        case 3: return AppTheme.accent(for: themeColorPreference).opacity(0.72)
        default: return AppTheme.accent(for: themeColorPreference)
        }
    }
}

private struct ScheduleMemoStatisticsShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ScheduleMemoStatisticsSharePreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    let item: ScheduleMemoStatisticsShareItem
    @State private var showsSystemShare = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                Image(uiImage: item.image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(L10n.text("记录日迹图片", language: leafyLanguage))
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("完成", language: leafyLanguage)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showsSystemShare = true
                    } label: {
                        Label(L10n.text("分享", language: leafyLanguage), systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showsSystemShare) {
                LeafySystemShare(activityItems: [item.image])
            }
        }
    }
}

private struct ScheduleMemoStatisticsShareCard: View {
    let statistics: ScheduleMemoStatistics
    let generatedAt: Date
    let themeColorPreference: AppThemeColorPreference
    let language: AppLanguagePreference

    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 12)
    private let heatmapColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("记录日迹", language: language))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.text("%@ 年 · %@", language: language, String(statistics.selectedYear), AppBrand.displayName))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent(for: themeColorPreference))
            }

            HStack(spacing: 8) {
                shareMetric(
                    L10n.text("本年随记", language: language),
                    value: String(selectedYearMemoCount)
                )
                shareMetric(
                    L10n.text("本年记录天数", language: language),
                    value: L10n.text("%d 天", language: language, selectedYearRecordingDayCount)
                )
                shareMetric(
                    L10n.text("历史最长连续", language: language),
                    value: L10n.text("%d 天", language: language, statistics.longestStreak)
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("全年频率", language: language))
                    .font(.headline)
                Chart(statistics.selectedYearMonths) { month in
                    BarMark(
                        x: .value(L10n.text("月份", language: language), month.month),
                        y: .value(L10n.text("随记", language: language), month.memoCount)
                    )
                    .foregroundStyle(AppTheme.accent(for: themeColorPreference).opacity(0.72))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: [1, 3, 5, 7, 9, 11]) { value in
                        AxisValueLabel {
                            if let month = value.as(Int.self) {
                                Text(L10n.text("%d月", language: language, month)).font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 130)
            }
            .padding(14)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text("当前近 30 天", language: language))
                        .font(.headline)
                    Spacer()
                    Text(
                        L10n.text(
                            "%d 条 · %d 天",
                            language: language,
                            statistics.recent30DayMemoCount,
                            statistics.recent30DayRecordingDayCount
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                LazyVGrid(columns: heatmapColumns, spacing: 4) {
                    ForEach(statistics.recent30Days) { day in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(shareActivityColor(day.count))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(14)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                Text(L10n.text("图片只包含本机汇总统计，不包含随记正文和标签名称。", language: language))
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)

            Text(
                L10n.text(
                    "生成于 %@",
                    language: language,
                    generatedAt.formatted(
                        Date.FormatStyle.dateTime
                            .year()
                            .month(.abbreviated)
                            .day()
                            .hour()
                            .minute()
                            .locale(language.locale)
                    )
                )
            )
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(22)
        .background(Color(uiColor: .systemBackground))
    }

    private var selectedYearMemoCount: Int {
        statistics.selectedYearMonths.reduce(0) { $0 + $1.memoCount }
    }

    private var selectedYearRecordingDayCount: Int {
        statistics.selectedYearMonths.reduce(0) { $0 + $1.recordingDayCount }
    }

    private func shareMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }

    private func shareActivityColor(_ count: Int) -> Color {
        switch count {
        case 0: return AppTheme.softFill
        case 1: return AppTheme.accent(for: themeColorPreference).opacity(0.28)
        case 2: return AppTheme.accent(for: themeColorPreference).opacity(0.5)
        case 3: return AppTheme.accent(for: themeColorPreference).opacity(0.72)
        default: return AppTheme.accent(for: themeColorPreference)
        }
    }
}
