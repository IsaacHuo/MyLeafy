import Foundation
import OSLog
import Supabase

// MARK: - Ratings

extension CommunityService {
    func fetchTeacherRatingSummaries(
        search: String = "",
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [TeacherRatingSummary] {
        let client = try LeafySupabase.shared.requireClient()
        let normalizedSearch = trimmedText(search)?.lowercased()
        let cappedLimit = max(1, min(limit, 100))
        let safeOffset = max(offset, 0)
        let rangeEnd = safeOffset + cappedLimit - 1

        let teachers: [TeacherProfile]
        if let normalizedSearch {
            teachers = try await client
                .from("teachers")
                .select()
                .ilike("search_text", pattern: "%\(normalizedSearch)%")
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .order("id", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        } else {
            teachers = try await client
                .from("teachers")
                .select()
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .order("id", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        }

        let ratings = try await fetchMyTeacherRatings(teacherIDs: teachers.map(\.id))
        let ratingMap = LeafyFirstValueMap.build(ratings.map { ($0.teacherID, $0) })

        return teachers.map { teacher in
            TeacherRatingSummary(teacher: teacher, myRating: ratingMap[teacher.id])
        }
    }

    func fetchTeacherRatingSummary(teacherID: Int64) async throws -> TeacherRatingSummary {
        let client = try LeafySupabase.shared.requireClient()
        let teachers: [TeacherProfile] = try await client
            .from("teachers")
            .select()
            .eq("id", value: Int(teacherID))
            .limit(1)
            .execute()
            .value

        guard let teacher = teachers.first else {
            throw CommunityServiceError.edgeFunctionRejected("没有找到这位老师。")
        }

        let rating = try await fetchMyTeacherRatings(teacherIDs: [teacherID]).first
        return TeacherRatingSummary(teacher: teacher, myRating: rating)
    }

    func submitTeacherRating(teacherID: Int64, stars: Int) async throws -> TeacherRatingSummary {
        guard (1...5).contains(stars) else {
            throw CommunityServiceError.edgeFunctionRejected("评分必须在 1 到 5 星之间。")
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let existingRating = try await fetchMyTeacherRatings(teacherIDs: [teacherID]).first
        if existingRating == nil {
            let insert = TeacherRatingInsert(
                teacherID: teacherID,
                userID: currentProfile.id,
                stars: stars
            )

            do {
                _ = try await client
                    .from("teacher_ratings")
                    .insert(insert)
                    .execute()
            } catch {
                let update = TeacherRatingStarsUpdate(stars: stars)
                _ = try await client
                    .from("teacher_ratings")
                    .update(update)
                    .eq("teacher_id", value: Int(teacherID))
                    .eq("user_id", value: currentProfile.id.uuidString)
                    .execute()
            }
        } else {
            let update = TeacherRatingStarsUpdate(stars: stars)
            _ = try await client
                .from("teacher_ratings")
                .update(update)
                .eq("teacher_id", value: Int(teacherID))
                .eq("user_id", value: currentProfile.id.uuidString)
                .execute()
        }

        return try await fetchTeacherRatingSummary(teacherID: teacherID)
    }

    func fetchCourseRatingSummaries(
        search: String = "",
        category: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [CourseRatingSummary] {
        let client = try LeafySupabase.shared.requireClient()
        let normalizedSearch = trimmedText(search)?.lowercased()
        let normalizedCategory = trimmedText(category)
        let cappedLimit = max(1, min(limit, 100))
        let safeOffset = max(offset, 0)
        let rangeEnd = safeOffset + cappedLimit - 1

        let courses: [CourseProfile]
        switch (normalizedSearch, normalizedCategory) {
        case let (search?, category?):
            courses = try await client
                .from("course_catalog")
                .select()
                .eq("status", value: "published")
                .eq("category", value: category)
                .ilike("search_text", pattern: "%\(search)%")
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        case let (search?, nil):
            courses = try await client
                .from("course_catalog")
                .select()
                .eq("status", value: "published")
                .ilike("search_text", pattern: "%\(search)%")
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        case let (nil, category?):
            courses = try await client
                .from("course_catalog")
                .select()
                .eq("status", value: "published")
                .eq("category", value: category)
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        case (nil, nil):
            courses = try await client
                .from("course_catalog")
                .select()
                .eq("status", value: "published")
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        }

        let ratings = try await fetchMyCourseRatings(courseIDs: courses.map(\.id))
        let ratingMap = LeafyFirstValueMap.build(ratings.map { ($0.courseID, $0) })

        return courses.map { course in
            CourseRatingSummary(course: course, myRating: ratingMap[course.id])
        }
    }

    func fetchCourseRatingSummary(courseID: Int64) async throws -> CourseRatingSummary {
        let client = try LeafySupabase.shared.requireClient()
        let courses: [CourseProfile] = try await client
            .from("course_catalog")
            .select()
            .eq("id", value: Int(courseID))
            .eq("status", value: "published")
            .limit(1)
            .execute()
            .value

        guard let course = courses.first else {
            throw CommunityServiceError.edgeFunctionRejected("没有找到这门课程。")
        }

        let rating = try await fetchMyCourseRatings(courseIDs: [courseID]).first
        return CourseRatingSummary(course: course, myRating: rating)
    }

    func submitCourseRating(courseID: Int64, stars: Int) async throws -> CourseRatingSummary {
        guard (1...5).contains(stars) else {
            throw CommunityServiceError.edgeFunctionRejected("评分必须在 1 到 5 星之间。")
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let existingRating = try await fetchMyCourseRatings(courseIDs: [courseID]).first
        if existingRating == nil {
            let insert = CourseRatingInsert(
                courseID: courseID,
                userID: currentProfile.id,
                stars: stars
            )

            do {
                _ = try await client
                    .from("course_ratings")
                    .insert(insert)
                    .execute()
            } catch {
                let update = TeacherRatingStarsUpdate(stars: stars)
                _ = try await client
                    .from("course_ratings")
                    .update(update)
                    .eq("course_id", value: Int(courseID))
                    .eq("user_id", value: currentProfile.id.uuidString)
                    .execute()
            }
        } else {
            let update = TeacherRatingStarsUpdate(stars: stars)
            _ = try await client
                .from("course_ratings")
                .update(update)
                .eq("course_id", value: Int(courseID))
                .eq("user_id", value: currentProfile.id.uuidString)
                .execute()
        }

        return try await fetchCourseRatingSummary(courseID: courseID)
    }

    func fetchDishRatingSummaries(
        search: String = "",
        canteen: String? = nil,
        location: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [DishRatingSummary] {
        let client = try LeafySupabase.shared.requireClient()
        let normalizedSearch = trimmedText(search)?.lowercased()
        let normalizedCanteen = trimmedText(canteen)
        let normalizedLocation = trimmedText(location)
        let cappedLimit = max(1, min(limit, 100))
        let safeOffset = max(offset, 0)
        let rangeEnd = safeOffset + cappedLimit - 1

        var query = client
            .from("dish_catalog")
            .select()
            .eq("status", value: "published")

        if let normalizedLocation {
            query = query.eq("location", value: normalizedLocation)
        } else if let normalizedCanteen {
            query = query.ilike("location", pattern: "\(normalizedCanteen)%")
        }

        if let normalizedSearch {
            query = query.ilike("search_text", pattern: "%\(normalizedSearch)%")
        }

        let dishes: [DishProfile] = try await query
            .order("rating_average", ascending: false)
            .order("rating_count", ascending: false)
            .order("name", ascending: true)
            .range(from: safeOffset, to: rangeEnd)
            .execute()
            .value

        let ratings = try await fetchMyDishRatings(dishIDs: dishes.map(\.id))
        let ratingMap = LeafyFirstValueMap.build(ratings.map { ($0.dishID, $0) })

        return dishes.map { dish in
            DishRatingSummary(dish: dish, myRating: ratingMap[dish.id])
        }
    }

    func fetchDishRatingSummary(dishID: Int64) async throws -> DishRatingSummary {
        let client = try LeafySupabase.shared.requireClient()
        let dishes: [DishProfile] = try await client
            .from("dish_catalog")
            .select()
            .eq("id", value: Int(dishID))
            .eq("status", value: "published")
            .limit(1)
            .execute()
            .value

        guard let dish = dishes.first else {
            throw CommunityServiceError.edgeFunctionRejected("没有找到这个菜品。")
        }

        let rating = try await fetchMyDishRatings(dishIDs: [dishID]).first
        return DishRatingSummary(dish: dish, myRating: rating)
    }

    func submitDishRating(dishID: Int64, stars: Int) async throws -> DishRatingSummary {
        guard (1...5).contains(stars) else {
            throw CommunityServiceError.edgeFunctionRejected("评分必须在 1 到 5 星之间。")
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let existingRating = try await fetchMyDishRatings(dishIDs: [dishID]).first
        if existingRating == nil {
            let insert = DishRatingInsert(
                dishID: dishID,
                userID: currentProfile.id,
                stars: stars
            )

            do {
                _ = try await client
                    .from("dish_ratings")
                    .insert(insert)
                    .execute()
            } catch {
                let update = TeacherRatingStarsUpdate(stars: stars)
                _ = try await client
                    .from("dish_ratings")
                    .update(update)
                    .eq("dish_id", value: Int(dishID))
                    .eq("user_id", value: currentProfile.id.uuidString)
                    .execute()
            }
        } else {
            let update = TeacherRatingStarsUpdate(stars: stars)
            _ = try await client
                .from("dish_ratings")
                .update(update)
                .eq("dish_id", value: Int(dishID))
                .eq("user_id", value: currentProfile.id.uuidString)
                .execute()
        }

        return try await fetchDishRatingSummary(dishID: dishID)
    }

    func fetchMyTeacherRatings(teacherIDs: [Int64]) async throws -> [TeacherRating] {
        guard !teacherIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil,
              let currentProfile = try await fetchCurrentProfile() else {
            return []
        }

        return try await client
            .from("teacher_ratings")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .in("teacher_id", values: teacherIDs.map { Int($0) })
            .execute()
            .value
    }

    func fetchMyDishRatings(dishIDs: [Int64]) async throws -> [DishRating] {
        guard !dishIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil,
              let currentProfile = try await fetchCurrentProfile() else {
            return []
        }

        return try await client
            .from("dish_ratings")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .in("dish_id", values: dishIDs.map { Int($0) })
            .execute()
            .value
    }

    func fetchMyCourseRatings(courseIDs: [Int64]) async throws -> [CourseRating] {
        guard !courseIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil,
              let currentProfile = try await fetchCurrentProfile() else {
            return []
        }

        return try await client
            .from("course_ratings")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .in("course_id", values: courseIDs.map { Int($0) })
            .execute()
            .value
    }
}
