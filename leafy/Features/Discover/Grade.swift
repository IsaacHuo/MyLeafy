import Foundation
import SwiftData

@Model
final class Grade {
    var id: UUID
    var term: String
    var courseName: String
    var credit: String
    var score: String
    var type: String // Display text; original portal fields remain separate.
    var courseCode: String?
    var courseAttribute: String?
    var courseCategory: String?
    var examNature: String?
    
    init(id: UUID = UUID(), term: String, courseName: String, credit: String, score: String, type: String, courseCode: String? = nil, courseAttribute: String? = nil, courseCategory: String? = nil, examNature: String? = nil) {
        self.id = id
        self.term = term
        self.courseName = courseName
        self.credit = credit
        self.score = score
        self.type = type
        self.courseCode = courseCode
        self.courseAttribute = courseAttribute
        self.courseCategory = courseCategory
        self.examNature = examNature
    }
}