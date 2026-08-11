import Foundation
import OSLog
import Supabase

// MARK: - Feedback and Catalog

extension CommunityService {
    func submitFeedback(issueType: String, body: String, contact: String?, deviceInfo: [String: String]) async throws {
        try await ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let trimmedBody = trimmedText(body) ?? ""
        guard !trimmedBody.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请先填写反馈内容。")
        }

        let currentProfile = try? await fetchCurrentProfile()
        let insert = FeedbackSubmissionInsert(
            userID: currentProfile?.id,
            issueType: trimmedText(issueType) ?? "问题反馈",
            body: trimmedBody,
            contact: trimmedText(contact),
            deviceInfo: deviceInfo
        )

        _ = try await client
            .from("feedback_submissions")
            .insert(insert)
            .execute()
    }

    func submitCatalogSuggestion(input: CatalogSuggestionInput) async throws {
        try await ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let name = trimmedText(input.name) ?? ""
        let unit = trimmedText(input.unit) ?? ""
        guard !name.isEmpty, !unit.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请填写名称和学院/单位。")
        }

        let teacherName: String?
        let category: String?
        let credit: Double?
        switch input.type {
        case .teacher:
            teacherName = nil
            category = nil
            credit = nil
        case .course:
            teacherName = trimmedText(input.teacherName)
            guard teacherName != nil else {
                throw CommunityServiceError.edgeFunctionRejected("请填写授课老师。")
            }
            category = trimmedText(input.category) ?? "公选课"
            credit = input.credit
            if let credit, credit < 0 {
                throw CommunityServiceError.edgeFunctionRejected("学分不能小于 0。")
            }
        case .dish:
            teacherName = nil
            category = nil
            credit = nil
        }

        if let initialStars = input.initialStars, !(1...5).contains(initialStars) {
            throw CommunityServiceError.edgeFunctionRejected("评分必须在 1 到 5 星之间。")
        }

        let currentProfile = try? await fetchCurrentProfile()
        let insert = CatalogSuggestionInsert(
            suggestionType: input.type.rawValue,
            userID: currentProfile?.id,
            name: name,
            unit: unit,
            teacherName: teacherName,
            category: category,
            credit: credit,
            initialStars: input.initialStars,
            note: trimmedText(input.note)
        )

        do {
            _ = try await client
                .from("catalog_suggestions")
                .insert(insert)
                .execute()
        } catch {
            if isDuplicateCatalogSuggestion(error) {
                return
            }
            throw error
        }
    }
}
