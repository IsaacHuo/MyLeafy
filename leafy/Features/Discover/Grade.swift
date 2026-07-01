import Foundation
import SwiftData

@Model
final class Grade {
    var id: UUID
    var term: String
    var courseName: String
    var credit: String
    var score: String
    var type: String // 例如 必修/选修
    
    init(id: UUID = UUID(), term: String, courseName: String, credit: String, score: String, type: String) {
        self.id = id
        self.term = term
        self.courseName = courseName
        self.credit = credit
        self.score = score
        self.type = type
    }
}