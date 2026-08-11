import Combine
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import os

struct TeacherDetailSheet: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var summary: TeacherRatingSummary
    @State private var selectedStars: Int
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    let onUpdate: (TeacherRatingSummary) -> Void

    private var teacher: TeacherProfile {
        summary.teacher
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(termsChecker: dependencies.communityRepository)
    }

    init(summary: TeacherRatingSummary, onUpdate: @escaping (TeacherRatingSummary) -> Void) {
        _summary = State(initialValue: summary)
        _selectedStars = State(initialValue: summary.myRating?.stars ?? 0)
        self.onUpdate = onUpdate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    TeacherCard(summary: summary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评分分布")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        ForEach((1...5).reversed(), id: \.self) { stars in
                            TeacherRatingDistributionRow(
                                stars: stars,
                                count: teacher.ratingCountsByStars[stars] ?? 0,
                                total: teacher.ratingCount
                            )
                        }
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("我的评分")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        TeacherStarPicker(selection: $selectedStars)
                            .frame(maxWidth: .infinity, alignment: .center)

                        if let myRating = summary.myRating {
                            Text("当前已评 \(myRating.stars) 星，可直接修改。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Text("每位老师每个账号只保留一条评分记录。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        Button {
                            Task { await submitRating() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(summary.myRating == nil ? "提交评分" : "更新评分")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                Capsule()
                                    .fill(selectedStars == 0 ? AppTheme.tertiaryText : AppTheme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedStars == 0 || isSaving)
                    }
                    .padding(18)
                    .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(teacher.name)
            .leafyInlineNavigationTitle()
            .leafyOperationAlert($operationAlert)
        }
    }

    @MainActor
    private func submitRating() async {
        guard selectedStars > 0 else { return }

        isSaving = true
        defer { isSaving = false }

        if ReviewDemoMode.isEnabled {
            let updatedSummary = ReviewDemoDataSeeder.updatedTeacherSummary(teacherID: teacher.id, stars: selectedStars)
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存。", language: leafyLanguage))
            return
        }

        switch await communityAccessGate.evaluate(.rating) {
        case .allowed:
            break
        case .requiresProfileCompletion, .requiresTermsAcceptance:
            break
        case .failed(let message):
            errorMessage = message
            return
        }

        do {
            let updatedSummary = try await dependencies.communityActivityRepository.submitTeacherRating(
                teacherID: teacher.id,
                stars: selectedStars
            )
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存。", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CourseRatingDetailSheet: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var summary: CourseRatingSummary
    @State private var selectedStars: Int
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    let onUpdate: (CourseRatingSummary) -> Void

    private var course: CourseProfile {
        summary.course
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(termsChecker: dependencies.communityRepository)
    }

    init(summary: CourseRatingSummary, onUpdate: @escaping (CourseRatingSummary) -> Void) {
        _summary = State(initialValue: summary)
        _selectedStars = State(initialValue: summary.myRating?.stars ?? 0)
        self.onUpdate = onUpdate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    CourseCard(summary: summary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评分分布")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        ForEach((1...5).reversed(), id: \.self) { stars in
                            CourseRatingDistributionRow(
                                stars: stars,
                                count: course.ratingCountsByStars[stars] ?? 0,
                                total: course.ratingCount
                            )
                        }
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("我的评分")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        CourseStarPicker(selection: $selectedStars)
                            .frame(maxWidth: .infinity, alignment: .center)

                        if let myRating = summary.myRating {
                            Text("当前已评 \(myRating.stars) 星，可直接修改。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Text("每门课程每个账号只保留一条评分记录。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        Button {
                            Task { await submitRating() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(summary.myRating == nil ? "提交评分" : "更新评分")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                Capsule()
                                    .fill(selectedStars == 0 ? AppTheme.tertiaryText : AppTheme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedStars == 0 || isSaving)
                    }
                    .padding(18)
                    .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(course.name)
            .leafyInlineNavigationTitle()
            .leafyOperationAlert($operationAlert)
        }
    }

    @MainActor
    private func submitRating() async {
        guard selectedStars > 0 else { return }

        isSaving = true
        defer { isSaving = false }

        if ReviewDemoMode.isEnabled {
            let updatedSummary = ReviewDemoDataSeeder.updatedCourseSummary(courseID: course.id, stars: selectedStars)
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存。", language: leafyLanguage))
            return
        }

        switch await communityAccessGate.evaluate(.rating) {
        case .allowed:
            break
        case .requiresProfileCompletion, .requiresTermsAcceptance:
            break
        case .failed(let message):
            errorMessage = message
            return
        }

        do {
            let updatedSummary = try await dependencies.communityActivityRepository.submitCourseRating(
                courseID: course.id,
                stars: selectedStars
            )
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存。", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DishDetailSheet: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var summary: DishRatingSummary
    @State private var selectedStars: Int
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    let onUpdate: (DishRatingSummary) -> Void

    private var dish: DishProfile {
        summary.dish
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(termsChecker: dependencies.communityRepository)
    }

    init(summary: DishRatingSummary, onUpdate: @escaping (DishRatingSummary) -> Void) {
        _summary = State(initialValue: summary)
        _selectedStars = State(initialValue: summary.myRating?.stars ?? 0)
        self.onUpdate = onUpdate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    DishCard(summary: summary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评分分布")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        ForEach((1...5).reversed(), id: \.self) { stars in
                            DishRatingDistributionRow(
                                stars: stars,
                                count: dish.ratingCountsByStars[stars] ?? 0,
                                total: dish.ratingCount
                            )
                        }
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("我的评分")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        DishStarPicker(selection: $selectedStars)
                            .frame(maxWidth: .infinity, alignment: .center)

                        if let myRating = summary.myRating {
                            Text("当前已评 \(myRating.stars) 星，可直接修改。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Text("每道菜每个账号只保留一条评分记录。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        Button {
                            Task { await submitRating() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(summary.myRating == nil ? "提交评分" : "更新评分")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                Capsule()
                                    .fill(selectedStars == 0 ? AppTheme.tertiaryText : AppTheme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedStars == 0 || isSaving)
                    }
                    .padding(18)
                    .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(dish.name)
            .leafyInlineNavigationTitle()
            .leafyOperationAlert($operationAlert)
        }
    }

    @MainActor
    private func submitRating() async {
        guard selectedStars > 0 else { return }

        isSaving = true
        defer { isSaving = false }

        if ReviewDemoMode.isEnabled {
            let updatedSummary = ReviewDemoDataSeeder.updatedDishSummary(dishID: dish.id, stars: selectedStars)
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存。", language: leafyLanguage))
            return
        }

        switch await communityAccessGate.evaluate(.rating) {
        case .allowed:
            break
        case .requiresProfileCompletion, .requiresTermsAcceptance:
            break
        case .failed(let message):
            errorMessage = message
            return
        }

        do {
            let updatedSummary = try await dependencies.communityActivityRepository.submitDishRating(
                dishID: dish.id,
                stars: selectedStars
            )
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存。", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TeacherRatingDistributionRow: View {
    let stars: Int
    let count: Int
    let total: Int

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Text("\(stars)")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.yellow)
            }
            .frame(width: 34, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.fill)
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: max(4, proxy.size.width * progress))
                        .opacity(count == 0 ? 0 : 1)
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

struct CourseRatingDistributionRow: View {
    let stars: Int
    let count: Int
    let total: Int

    var body: some View {
        TeacherRatingDistributionRow(stars: stars, count: count, total: total)
    }
}

struct DishRatingDistributionRow: View {
    let stars: Int
    let count: Int
    let total: Int

    var body: some View {
        TeacherRatingDistributionRow(stars: stars, count: count, total: total)
    }
}

struct TeacherStarPicker: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { stars in
                Button {
                    selection = stars
                } label: {
                    Image(systemName: stars <= selection ? "star.fill" : "star")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(stars <= selection ? .yellow : AppTheme.tertiaryText)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(stars) 星")
            }
        }
    }
}

struct CourseStarPicker: View {
    @Binding var selection: Int

    var body: some View {
        TeacherStarPicker(selection: $selection)
    }
}

struct DishStarPicker: View {
    @Binding var selection: Int

    var body: some View {
        TeacherStarPicker(selection: $selection)
    }
}

struct CommunityMockPost: Identifiable {
    let id: Int
    let author: String
    let title: String
    let body: String
    let timestamp: String
    let likes: Int
    let comments: Int
    let tag: String
    let avatarColor: Color
    let photoLabels: [String]
    let mockComments: [String]

    static let samples: [CommunityMockPost] = [
        CommunityMockPost(
            id: 1,
            author: "匿名同学",
            title: "食堂晚饭有没有稳定不踩雷的窗口？",
            body: "最近想固定一个晚饭窗口，不想每天随机试错。有没有那种价格稳定、出餐快、晚上也不容易翻车的推荐？",
            timestamp: "今天 18:42",
            likes: 23,
            comments: 8,
            tag: "食堂",
            avatarColor: AppTheme.featureTints[0],
            photoLabels: ["晚饭", "北林", "推荐"],
            mockComments: ["一食堂二层的烤盘饭比较稳。", "三食堂窗口更新快，晚上选择多。"]
        ),
        CommunityMockPost(
            id: 2,
            author: "林学 23 级",
            title: "图书馆闭馆前一小时人会突然少很多吗？",
            body: "想找一个相对安静的时间段复习，白天人流太大。有人长期蹲馆的话，可以说一下晚上座位变化吗？",
            timestamp: "昨天 21:15",
            likes: 16,
            comments: 5,
            tag: "自习",
            avatarColor: AppTheme.featureTints[2],
            photoLabels: [],
            mockComments: ["九点以后会明显松一点。", "考试周不一定，平时是这样的。"]
        )
    ]
}
