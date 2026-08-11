import Combine
import QuickLook
import SwiftUI
import os
import SwiftData
import UniformTypeIdentifiers
import UIKit

enum RatingSectionMode: String, CaseIterable, Identifiable {
    case teachers = "老师"
    case courses = "课程"
    case dishes = "菜品"

    var id: String { rawValue }
}

struct RatingSectionContainerView: View {
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @Binding var selectedTeacher: TeacherRatingSummary?
    @Binding var selectedCourse: CourseRatingSummary?
    @Binding var selectedDish: DishRatingSummary?
    let teacherRefreshID: UUID
    let courseRefreshID: UUID
    let dishRefreshID: UUID

    @State private var mode: RatingSectionMode = .teachers
    @State private var workspace = RatingCatalogWorkspace()

    private var shouldShowRatingSections: Bool {
        if ActiveCampusContext.descriptor.id == .bjfu && ActiveCampusContext.identity?.isCustom != true {
            return true
        }
        return sessionManager.hasApprovedCommunityAccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            if shouldShowRatingSections {
                Picker("评教评课评菜", selection: $mode) {
                    ForEach(RatingSectionMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                ZStack(alignment: .topLeading) {
                    TeacherSectionView(
                        selectedTeacher: $selectedTeacher,
                        refreshID: teacherRefreshID,
                        isActive: mode == .teachers,
                        lifecycleStore: workspace.teachers
                    )
                    .opacity(mode == .teachers ? 1 : 0)
                    .allowsHitTesting(mode == .teachers)
                    .accessibilityHidden(mode != .teachers)

                    CourseSectionView(
                        selectedCourse: $selectedCourse,
                        refreshID: courseRefreshID,
                        isActive: mode == .courses,
                        lifecycleStore: workspace.courses
                    )
                    .opacity(mode == .courses ? 1 : 0)
                    .allowsHitTesting(mode == .courses)
                    .accessibilityHidden(mode != .courses)

                    DishSectionView(
                        selectedDish: $selectedDish,
                        refreshID: dishRefreshID,
                        isActive: mode == .dishes,
                        lifecycleStore: workspace.dishes
                    )
                    .opacity(mode == .dishes ? 1 : 0)
                    .allowsHitTesting(mode == .dishes)
                    .accessibilityHidden(mode != .dishes)
                }
                .animation(.easeInOut(duration: 0.18), value: mode)
            } else {
                RatingCommunityAccessStatusCard(
                    status: sessionManager.communityAccessStatus,
                    profile: sessionManager.profile
                )
            }
        }
        .task {
            CommunitySessionManager.shared.startBootstrapIfNeeded()
            await CommunitySessionManager.shared.restoreProfileIfPossible()
        }
    }
}

struct RatingCommunityAccessStatusCard: View {
    let status: CommunityAccessStatus
    let profile: CommunityProfile?

    private var title: String {
        switch status {
        case .pending:
            return "学校申请正在审核中"
        case .rejected:
            return "学校申请未通过"
        case .approved:
            return "正在进入学校社区"
        case .general:
            return "当前为通用模式"
        }
    }

    private var detail: String {
        switch status {
        case .pending:
            let school = profile?.communitySchoolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return school.isEmpty
                ? "审核通过后会开放对应学校的评教、评课和评菜。"
                : "\(school) 的申请审核通过后，会开放对应学校的评教、评课和评菜。"
        case .rejected:
            return "学校申请未通过。当前处于通用模式，社区功能暂不可用。"
        case .approved:
            return "评教、评课和评菜会按学校社区分别展示。"
        case .general:
            return "评教、评课和评菜属于学校社区能力，请先在社区页提交学校申请。"
        }
    }

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                ContentUnavailableView(
                    title,
                    systemImage: "star.bubble",
                    description: Text(detail)
                )

                if status == .rejected,
                   let reason = profile?.communityRejectionReason?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reason.isEmpty {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

nonisolated struct CampusDiningLocation: Identifiable, Hashable, Sendable {
    let canteen: String
    let floor: String
    let name: String

    var id: String { fullName }
    var fullName: String { "\(canteen) · \(floor) · \(name)" }
    var displayName: String { "\(floor) · \(name)" }

    static let east = "东区食堂"
    static let west = "西区食堂"
    static let canteens = [east, west]

    static let all: [CampusDiningLocation] = [
        CampusDiningLocation(canteen: east, floor: "一层", name: "学一食堂"),
        CampusDiningLocation(canteen: east, floor: "一层", name: "学三食堂"),
        CampusDiningLocation(canteen: east, floor: "一层", name: "烘焙坊"),
        CampusDiningLocation(canteen: east, floor: "二层", name: "教工餐厅"),
        CampusDiningLocation(canteen: east, floor: "二层", name: "学四食堂"),
        CampusDiningLocation(canteen: east, floor: "三层", name: "楸木园餐厅"),
        CampusDiningLocation(canteen: east, floor: "三层", name: "林园餐厅"),
        CampusDiningLocation(canteen: west, floor: "B1层", name: "小食光餐厅"),
        CampusDiningLocation(canteen: west, floor: "一层", name: "学二食堂"),
        CampusDiningLocation(canteen: west, floor: "二层", name: "齐芳阁餐厅"),
        CampusDiningLocation(canteen: west, floor: "三层", name: "林汇园餐厅")
    ]

    static func locations(for canteen: String) -> [CampusDiningLocation] {
        all.filter { $0.canteen == canteen }
    }

    static func location(for fullName: String) -> CampusDiningLocation? {
        all.first { $0.fullName == fullName }
    }

    static func displayName(for fullName: String) -> String? {
        location(for: fullName)?.displayName
    }
}

struct CommunitySectionView: View {
    @Binding var selectedPost: CommunityMockPost?

    private let posts = CommunityMockPost.samples

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("社区", subtitle: "当前阶段使用 Mock 数据，验证信息架构、帖子流与详情交互。")

            ForEach(posts) { post in
                Button {
                    selectedPost = post
                } label: {
                    CommunityPostCard(post: post)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
