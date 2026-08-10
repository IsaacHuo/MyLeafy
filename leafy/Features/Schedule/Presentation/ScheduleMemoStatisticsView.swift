import Charts
import SwiftData
import SwiftUI
import UIKit

struct ScheduleMemoStatisticsView: View {
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
                        "还没有记录日迹",
                        systemImage: "chart.bar.xaxis",
                        description: Text("写下第一条随记后，这里会逐渐形成你的记录频率和习惯。")
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
        .navigationTitle("记录日迹")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    generateShareImage(statistics)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonBorderShape(.circle)
                .disabled(statistics.memoCount == 0)
                .accessibilityLabel("导出记录日迹图片")
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
        .alert("无法生成图片", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
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
            .accessibilityLabel("上一年")

            Menu {
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        if year == selectedYear {
                            Label("\(year) 年", systemImage: "checkmark")
                        } else {
                            Text("\(year) 年")
                        }
                    }
                }
            } label: {
                Text("\(selectedYear) 年")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(minWidth: 116, minHeight: 44)
                    .background(AppTheme.softFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择统计年份")

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
            .accessibilityLabel("下一年")
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
            LeafySectionTitle("截至今天", subtitle: "当前校园身份下保存在本机的随记")
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppSpacing.compact
            ) {
                overviewMetric("总随记", value: statistics.memoCount, systemImage: "note.text")
                overviewMetric("记录天数", value: statistics.recordingDayCount, systemImage: "calendar")
                overviewMetric("连续记录", value: statistics.currentStreak, suffix: "天", systemImage: "flame")
                overviewMetric("最长连续", value: statistics.longestStreak, suffix: "天", systemImage: "trophy")
            }
        }
    }

    private func overviewMetric(
        _ title: String,
        value: Int,
        suffix: String = "",
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text("\(value)\(suffix)")
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
                        Text("全年记录频率")
                            .leafyHeadline()
                        Text("\(selectedYear) 年 1 月至 12 月")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Picker("统计指标", selection: $annualMetric) {
                        ForEach(ScheduleMemoAnnualMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Chart(statistics.selectedYearMonths) { month in
                    BarMark(
                        x: .value("月份", month.month),
                        y: .value(annualMetric.title, annualMetric.value(for: month))
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
                                Text("\(month)月")
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

                if let month = selectedMonth,
                   let detail = statistics.selectedYearMonths.first(where: { $0.month == month }) {
                    Text("\(month) 月 · \(detail.memoCount) 条随记 · 记录 \(detail.recordingDayCount) 天")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.numericText())
                } else {
                    Text("点按柱形查看当月记录情况。")
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
                    Text("近 30 天")
                        .leafyHeadline()
                    Text(recentSummary(statistics))
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                ScheduleMemoRecentHeatmap(
                    days: statistics.recent30Days,
                    themeColorPreference: themeColorPreference,
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
            LeafySectionTitle("记录习惯", subtitle: habitSummary(statistics))

            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("星期分布")
                        .leafyHeadline()
                    Chart(weekdayData(statistics)) { item in
                        BarMark(
                            x: .value("星期", item.name),
                            y: .value("随记", item.count)
                        )
                        .foregroundStyle(AppTheme.accent(for: themeColorPreference).opacity(0.72))
                        .cornerRadius(3)
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 128)
                }
            }

            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("时间段分布")
                        .leafyHeadline()
                    Chart(statistics.timePeriodDistribution) { item in
                        BarMark(
                            x: .value("随记", item.count),
                            y: .value("时间段", item.period.title)
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
                }
            }
        }
    }

    private func tagsSection(_ statistics: ScheduleMemoStatistics) -> some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text("常用标签")
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
                Text("记录里程碑")
                    .leafyHeadline()

                if let firstDate = statistics.firstRecordingDate {
                    milestoneRow("第一次记录", detail: milestoneDateText(firstDate), systemImage: "flag")
                }
                if let peakDate = statistics.peakDate {
                    milestoneRow(
                        "记录最多的一天",
                        detail: "\(milestoneDateText(peakDate)) · \(statistics.peakMemoCount) 条",
                        systemImage: "sparkles"
                    )
                }
                milestoneRow("最长连续记录", detail: "\(statistics.longestStreak) 天", systemImage: "flame")
                milestoneRow("有记录的月份", detail: "\(statistics.recordingMonthCount) 个月", systemImage: "calendar.badge.checkmark")
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
        Label("统计在本机完成，导出图片只包含汇总数字。", systemImage: "lock.shield")
            .microCaption()
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func recentSummary(_ statistics: ScheduleMemoStatistics) -> String {
        "记录了 \(statistics.recent30DayRecordingDayCount) 天，共 \(statistics.recent30DayMemoCount) 条随记"
    }

    private func recentComparison(_ statistics: ScheduleMemoStatistics) -> String {
        let difference = statistics.recent30DayMemoCount - statistics.previous30DayMemoCount
        if statistics.previous30DayMemoCount == 0 {
            return statistics.recent30DayMemoCount == 0 ? "前 30 天和最近 30 天都没有记录。" : "前 30 天暂无记录。"
        }
        if difference == 0 {
            return "与前 30 天的随记数量相同。"
        }
        return difference > 0 ? "比前 30 天多 \(difference) 条。" : "比前 30 天少 \(-difference) 条。"
    }

    private func habitSummary(_ statistics: ScheduleMemoStatistics) -> String {
        guard let weekdayIndex = statistics.weekdayDistribution.indices.max(by: {
            statistics.weekdayDistribution[$0] < statistics.weekdayDistribution[$1]
        }), statistics.weekdayDistribution[weekdayIndex] > 0 else {
            return "记录多一些后，这里会显示你的常用时间。"
        }
        let weekday = ScheduleMemoWeekday.names[weekdayIndex]
        let period = statistics.timePeriodDistribution.max(by: { $0.count < $1.count })?.period.title ?? ""
        return "你最常在\(weekday)的\(period)记录。"
    }

    private func weekdayData(_ statistics: ScheduleMemoStatistics) -> [ScheduleMemoNamedCount] {
        zip(ScheduleMemoWeekday.shortNames, statistics.weekdayDistribution).map {
            ScheduleMemoNamedCount(name: $0.0, count: $0.1)
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
            themeColorPreference: themeColorPreference
        )
        .frame(width: 360)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let image = renderer.uiImage else {
            shareErrorMessage = "请稍后重试，或先截图保存当前页面。"
            return
        }
        shareItem = ScheduleMemoStatisticsShareItem(image: image)
    }
}

private enum ScheduleMemoAnnualMetric: String, CaseIterable, Identifiable {
    case memoCount
    case recordingDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memoCount: return "随记数"
        case .recordingDays: return "记录天数"
        }
    }

    func value(for month: ScheduleMemoMonthStatistics) -> Int {
        switch self {
        case .memoCount: return month.memoCount
        case .recordingDays: return month.recordingDayCount
        }
    }
}

private struct ScheduleMemoNamedCount: Identifiable {
    let name: String
    let count: Int

    var id: String { name }
}

private enum ScheduleMemoWeekday {
    static let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    static let shortNames = ["一", "二", "三", "四", "五", "六", "日"]
}

private extension ScheduleMemoTimePeriod {
    var title: String {
        switch self {
        case .earlyMorning: return "清晨"
        case .morning: return "上午"
        case .afternoon: return "下午"
        case .evening: return "晚间"
        case .lateNight: return "深夜"
        }
    }
}

private struct ScheduleMemoRecentHeatmap: View {
    let days: [ScheduleMemoActivityDay]
    let themeColorPreference: AppThemeColorPreference
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
                ForEach(ScheduleMemoWeekday.shortNames, id: \.self) { weekday in
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
                        .accessibilityLabel("\(day.date.formatted(date: .long, time: .omitted))，\(day.count) 条随记")
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
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
            .navigationTitle("记录日迹图片")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showsSystemShare = true
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
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

    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 12)
    private let heatmapColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("记录日迹")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("\(statistics.selectedYear) 年 · MyLeafy")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent(for: themeColorPreference))
            }

            HStack(spacing: 8) {
                shareMetric("本年随记", selectedYearMemoCount)
                shareMetric("本年记录天数", selectedYearRecordingDayCount)
                shareMetric("历史最长连续", statistics.longestStreak, suffix: "天")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("全年频率")
                    .font(.headline)
                Chart(statistics.selectedYearMonths) { month in
                    BarMark(
                        x: .value("月份", month.month),
                        y: .value("随记", month.memoCount)
                    )
                    .foregroundStyle(AppTheme.accent(for: themeColorPreference).opacity(0.72))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: [1, 3, 5, 7, 9, 11]) { value in
                        AxisValueLabel {
                            if let month = value.as(Int.self) {
                                Text("\(month)月").font(.caption2)
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
                    Text("当前近 30 天")
                        .font(.headline)
                    Spacer()
                    Text("\(statistics.recent30DayMemoCount) 条 · \(statistics.recent30DayRecordingDayCount) 天")
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
                Text("图片只包含本机汇总统计，不包含随记正文和标签名称。")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)

            Text("生成于 \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
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

    private func shareMetric(_ title: String, _ value: Int, suffix: String = "") -> some View {
        VStack(spacing: 4) {
            Text("\(value)\(suffix)")
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
