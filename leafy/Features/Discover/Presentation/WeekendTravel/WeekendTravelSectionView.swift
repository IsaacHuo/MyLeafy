import MapKit
import SwiftUI

struct WeekendTravelSectionView: View {
    @State private var selectedDestinationID = ""
    @State private var mapPosition = MapCameraPosition.region(Self.mapRegion)

    private var currentMonth: Int {
        Calendar.current.component(.month, from: Date())
    }

    private var recommendations: [WeekendDestination] {
        WeekendTravelRecommendationEngine.recommend(currentMonth: currentMonth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.micro) {
            LeafySectionTitle(
                "周末去哪",
                subtitle: "从北林出发，先看北京周边的高铁圈层，再滑出适合周末的推荐城市。"
            )

            weekendMapCard
            recommendationCarousel
        }
        .task(id: recommendations.map(\.id)) {
            syncSelectedDestination()
        }
    }

    private var weekendMapCard: some View {
        AcademicDetailCard {
            weekendMap
        }
    }

    private var weekendMap: some View {
        ZStack {
            Map(position: $mapPosition) {
                ForEach(recommendations) { destination in
                    Annotation("", coordinate: destination.coordinate.clLocationCoordinate) {
                        WeekendTravelMapMarker(isSelected: destination.id == selectedDestinationID)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .allowsHitTesting(false)
            .frame(height: 250)

            WeekendTravelMapOverlay()
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private var recommendationCarousel: some View {
        VStack(alignment: .leading, spacing: 4) {
            AcademicDetailSectionHeader(title: "推荐城市")

            if recommendations.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView(
                        "暂无可用周末建议",
                        systemImage: "map",
                        description: Text("当前没有合适的目的地，可以稍后再试。")
                    )
                }
            } else {
                TabView(selection: $selectedDestinationID) {
                    ForEach(recommendations) { destination in
                        WeekendDestinationCard(destination: destination)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.horizontal, 6)
                            .tag(destination.id)
                    }
                }
                .frame(height: 372)
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }

    private func syncSelectedDestination() {
        guard let firstID = recommendations.first?.id else {
            selectedDestinationID = ""
            return
        }

        guard recommendations.contains(where: { $0.id == selectedDestinationID }) else {
            selectedDestinationID = firstID
            return
        }
    }

    private static let mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 10.0)
    )
}

private struct WeekendDestinationCard: View {
    let destination: WeekendDestination

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .top, spacing: AppSpacing.compact) {
                    LeafyIconBadge(systemName: "tram.fill", tint: AppTheme.accentSecondary)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(destination.cityName)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        Text(destination.tagline)
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: AppSpacing.compact)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppSpacing.compact),
                        GridItem(.flexible(), spacing: AppSpacing.compact)
                    ],
                    spacing: AppSpacing.compact
                ) {
                    WeekendMetricTile(title: "路程", value: "\(destination.distanceKilometers) 公里")
                    WeekendMetricTile(title: "交通", value: destination.travelTimeText)
                    WeekendMetricTile(title: "预算", value: destination.budgetText)
                    WeekendMetricTile(title: "季节", value: destination.seasonText)
                }

                Text(destination.suggestedPace)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(destination.highlightRail, id: \.self) { highlight in
                            Text(highlight)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .foregroundStyle(AppTheme.accentEmphasis)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    AppTheme.accent.opacity(0.1),
                                    in: Capsule()
                                )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .leafyTransparentHorizontalScrollRail()
            }
        }
    }
}

private struct WeekendMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.tertiaryText)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            AppTheme.accent.opacity(0.08),
            in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
        )
    }
}

private struct WeekendTravelMapMarker: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: isSelected ? 9 : 7, height: isSelected ? 9 : 7)

            if isSelected {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 18, height: 18)
            }
        }
        .shadow(color: .black.opacity(isSelected ? 0.18 : 0.12), radius: 4, x: 0, y: 2)
    }
}

private struct WeekendTravelMapOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let outerRadius = diameter * 0.39
            let middleRadius = diameter * 0.28
            let innerRadius = diameter * 0.18

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                func circleRect(radius: CGFloat) -> CGRect {
                    CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                }

                context.stroke(
                    Path(ellipseIn: circleRect(radius: outerRadius)),
                    with: .color(AppTheme.accent.opacity(0.48)),
                    lineWidth: 2
                )
                context.stroke(
                    Path(ellipseIn: circleRect(radius: middleRadius)),
                    with: .color(AppTheme.accent.opacity(0.34)),
                    lineWidth: 2
                )
                context.stroke(
                    Path(ellipseIn: circleRect(radius: innerRadius)),
                    with: .color(AppTheme.accent.opacity(0.22)),
                    lineWidth: 2
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
                    with: .color(AppTheme.accent)
                )
            }
            .opacity(0.85)
        }
    }
}

private extension CampusCoordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
