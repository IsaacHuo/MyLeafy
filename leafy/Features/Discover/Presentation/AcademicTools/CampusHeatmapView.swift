import MapKit
import SwiftUI

struct CampusHeatmapView: View {
    @Environment(\.leafyDependencies) private var dependencies

    @State private var usesCustomFilter = false
    @State private var selectedDate = Date()
    @State private var startPeriod = min(max(TimetablePeriodSchedule.defaultStudyPeriod(), 1), 12)
    @State private var endPeriod = min(max(TimetablePeriodSchedule.defaultStudyPeriod(), 1), 12)
    @State private var data = CampusHeatmapData()
    @State private var errorMessage: String?
    @State private var didLoadInitialData = false
    @State private var mapPosition = MapCameraPosition.region(Self.defaultRegion)
    @State private var selectedBuilding: CampusHeatmapBuildingSummary?

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    private var safeStartPeriod: Int {
        min(max(startPeriod, 1), 12)
    }

    private var safeEndPeriodRange: ClosedRange<Int> {
        safeStartPeriod...12
    }

    private var heatmapRequest: CampusHeatmapRequest {
        CampusHeatmapRequest(
            date: selectedDate,
            startPeriod: startPeriod,
            endPeriod: endPeriod
        )
    }

    private var querySummary: String {
        "\(DateFormatters.header.string(from: selectedDate)) \(periodRangeText)"
    }

    private var periodRangeText: String {
        if safeStartPeriod == endPeriod {
            return periodDisplayText(safeStartPeriod)
        }
        return "第 \(safeStartPeriod)-\(endPeriod) 节"
    }

    var body: some View {
        AcademicDetailScrollContainer {
            if isCustomCampus {
                AcademicDetailCard {
                    ContentUnavailableView(
                        "暂无校园热力图",
                        systemImage: "map",
                        description: Text("通用入口暂未接入全校教室目录。")
                    )
                }
            } else {
                queryModeControl
                if usesCustomFilter {
                    queryControls
                }
                if let errorMessage {
                    AcademicDetailCard {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.warning)
                    }
                }
                mapCard
                heatRankingSection
                if data.unmatchedAvailableRoomCount > 0 {
                    unmatchedRoomsSection
                }
                AcademicDetailFooterText(text: "校园热力图仅表示教学楼教室占用估算，不展示课程明细，也不代表食堂、宿舍或真实校园人流。")
            }
        }
        .navigationTitle("校园热力图")
        .leafyInlineNavigationTitle()
        .task {
            normalizePeriods()
            guard !isCustomCampus, !didLoadInitialData else { return }
            didLoadInitialData = true
            await loadHeatmap()
        }
        .onChange(of: usesCustomFilter) { _, enabled in
            if !enabled {
                resetToCurrentQuery()
            }
            normalizePeriods()
            Task { await loadHeatmap() }
        }
        .onChange(of: startPeriod) { _, newValue in
            normalizePeriods(startingAt: newValue)
            if usesCustomFilter {
                Task { await loadHeatmap() }
            }
        }
        .onChange(of: endPeriod) { _, _ in
            normalizePeriods()
            if usesCustomFilter {
                Task { await loadHeatmap() }
            }
        }
        .onChange(of: selectedDate) { _, _ in
            if usesCustomFilter {
                Task { await loadHeatmap() }
            }
        }
        .sheet(item: $selectedBuilding) { building in
            CampusFloorCongestionSheet(building: building)
        }
    }

    private var queryModeControl: some View {
        AcademicDetailCard {
            Picker("时间", selection: $usesCustomFilter) {
                Text("当前").tag(false)
                Text("自定义").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private var queryControls: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                DatePicker("日期", selection: $selectedDate, displayedComponents: .date)

                Picker("开始节次", selection: $startPeriod) {
                    ForEach(1...12, id: \.self) { period in
                        Text(periodDisplayText(period)).tag(period)
                    }
                }

                Picker("结束节次", selection: $endPeriod) {
                    ForEach(safeEndPeriodRange, id: \.self) { period in
                        Text(periodDisplayText(period)).tag(period)
                    }
                }
            }
        }
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "教学楼拥挤度")
            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(querySummary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)

                    Map(position: $mapPosition) {
                        ForEach(data.mappedBuildings.filter { $0.building != "学研B座" }) { building in
                            if let coordinate = coordinate(for: building) {
                                Annotation(building.building, coordinate: coordinate) {
                                    Button {
                                        selectedBuilding = building
                                    } label: {
                                        CampusHeatBubble(summary: building)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                            .stroke(AppTheme.separator, lineWidth: 1)
                    )

                    heatLegend
                }
            }
        }
    }

    private var heatRankingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "最拥挤教学楼")
            AcademicDetailCard {
                if data.buildings.isEmpty {
                    ContentUnavailableView(
                        "暂无拥挤度数据",
                        systemImage: "map",
                        description: Text("当前条件没有可用的内置占用快照。")
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(data.hottestBuildings.enumerated()), id: \.element.id) { index, building in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            heatRankingRow(building)
                        }
                    }
                }
            }
        }
    }

    private var unmatchedRoomsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "未纳入统计")
            AcademicDetailCard {
                Text("有 \(data.unmatchedAvailableRoomCount) 间教室未匹配到当前教学楼目录，已排除在占用率之外。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var heatLegend: some View {
        HStack(spacing: 12) {
            ForEach(CampusHeatLevel.allCases) { level in
                HStack(spacing: 5) {
                    Circle()
                        .fill(level.color)
                        .frame(width: 8, height: 8)
                    Text(level.title)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heatRankingRow(_ building: CampusHeatmapBuildingSummary) -> some View {
        Button {
            selectedBuilding = building
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(CampusHeatLevel.level(for: building.occupancyRatio).color.opacity(0.18))
                    Text("\(Int((building.occupancyRatio * 100).rounded()))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CampusHeatLevel.level(for: building.occupancyRatio).color)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(building.building)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                    Text("\(building.occupiedRooms) 间占用 / \(building.totalRooms) 间教室，\(building.availableRooms) 间空闲")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Text(CampusHeatLevel.level(for: building.occupancyRatio).title)
                    .microCaption()
                    .fontWeight(.semibold)
                    .foregroundStyle(CampusHeatLevel.level(for: building.occupancyRatio).color)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }

    private func loadHeatmap() async {
        let outcome = await dependencies.campusHeatmapService.load(heatmapRequest)

        await MainActor.run {
            data = outcome.data
            errorMessage = outcome.errorMessage
        }
    }

    private func normalizePeriods(startingAt proposedStart: Int? = nil) {
        let normalizedStart = min(max(proposedStart ?? startPeriod, 1), 12)
        if startPeriod != normalizedStart {
            startPeriod = normalizedStart
        }
        endPeriod = min(max(endPeriod, normalizedStart), 12)
    }

    private func resetToCurrentQuery() {
        let currentPeriod = min(max(TimetablePeriodSchedule.defaultStudyPeriod(), 1), 12)
        selectedDate = Date()
        startPeriod = currentPeriod
        endPeriod = currentPeriod
    }

    private func coordinate(for summary: CampusHeatmapBuildingSummary) -> CLLocationCoordinate2D? {
        guard let coordinate = ClassroomCatalog.coordinate(for: summary.building) else { return nil }
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func periodDisplayText(_ period: Int) -> String {
        guard let slot = TimetablePeriodSchedule.slot(for: period) else {
            return "第 \(period) 节"
        }
        return "第 \(period) 节 \(slot.startText)-\(slot.endText)"
    }

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude: ClassroomCatalog.mapCenterCoordinate.latitude,
            longitude: ClassroomCatalog.mapCenterCoordinate.longitude
        ),
        span: MKCoordinateSpan(latitudeDelta: 0.0062, longitudeDelta: 0.0082)
    )
}

private struct CampusHeatBubble: View {
    let summary: CampusHeatmapBuildingSummary

    private var level: CampusHeatLevel {
        CampusHeatLevel.level(for: summary.occupancyRatio)
    }

    private var diameter: CGFloat {
        24 + CGFloat(summary.occupancyRatio) * 18
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(level.color.opacity(0.72))
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.82), lineWidth: 2)
                    )
                    .shadow(color: level.color.opacity(0.32), radius: 6, x: 0, y: 3)

                Text("\(Int((summary.occupancyRatio * 100).rounded()))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(summary.building)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.building) 占用率 \(Int((summary.occupancyRatio * 100).rounded()))%")
    }
}

private struct CampusFloorCongestionSheet: View {
    let building: CampusHeatmapBuildingSummary

    var body: some View {
        NavigationStack {
            AcademicDetailScrollContainer {
                AcademicDetailCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(building.building)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)

                        Text("\(building.occupiedRooms) 间占用 / \(building.totalRooms) 间教室，\(building.availableRooms) 间空闲")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    AcademicDetailSectionHeader(title: "楼层拥挤度")
                    AcademicDetailCard {
                        if building.floors.isEmpty {
                            ContentUnavailableView(
                                "暂无楼层数据",
                                systemImage: "square.stack.3d.up",
                                description: Text("当前教学楼目录暂时无法按楼层拆分。")
                            )
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(building.floors.enumerated()), id: \.element.id) { index, floor in
                                    if index > 0 {
                                        AcademicDetailDivider()
                                    }
                                    floorRow(floor)
                                }
                            }
                        }
                    }
                }

                AcademicDetailFooterText(text: "楼层拥挤度来自匿名教室占用快照，仅展示聚合结果。")
            }
            .navigationTitle("楼层情况")
            .leafyInlineNavigationTitle()
        }
        .presentationDetents([.medium, .large])
    }

    private func floorRow(_ floor: CampusHeatmapFloorSummary) -> some View {
        let level = CampusHeatLevel.level(for: floor.occupancyRatio)

        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(level.color.opacity(0.18))
                Text("\(Int((floor.occupancyRatio * 100).rounded()))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(level.color)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(floor.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text("\(floor.occupiedRooms) 间占用 / \(floor.totalRooms) 间教室，\(floor.availableRooms) 间空闲")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Text(level.title)
                .microCaption()
                .fontWeight(.semibold)
                .foregroundStyle(level.color)
        }
        .padding(.vertical, 8)
    }
}

private enum CampusHeatLevel: CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { title }

    var title: String {
        switch self {
        case .low:
            return "舒适"
        case .medium:
            return "拥挤"
        case .high:
            return "非常拥挤"
        }
    }

    var color: Color {
        switch self {
        case .low:
            return AppTheme.accent
        case .medium:
            return AppTheme.warning
        case .high:
            return AppTheme.danger
        }
    }

    static func level(for ratio: Double) -> CampusHeatLevel {
        if ratio >= 0.72 {
            return .high
        }
        if ratio >= 0.45 {
            return .medium
        }
        return .low
    }
}
