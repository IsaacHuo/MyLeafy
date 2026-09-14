import Foundation
import XCTest
@testable import Leafy

final class TimetableTeacherParserTests: XCTestCase {
    func testCompleteTableKeepsTeachersPerWeekAndCountsEveryOccurrence() throws {
        let records = try HTMLParser.parseTimetableRecords(
            html: TimetableTeacherParserFixtures.completeTableHTML(
                entries: TimetableTeacherParserFixtures.segmentedSchedule
            )
        )

        XCTAssertEqual(records.count, 7)
        XCTAssertEqual(records.reduce(0) { $0 + $1.weeks.count }, 32)

        assertSegmentedTeacherWeeks(in: records, courseName: "课程甲", dayOfWeek: 1)
        assertSegmentedTeacherWeeks(in: records, courseName: "课程甲", dayOfWeek: 2)
        assertSegmentedTeacherWeeks(in: records, courseName: "课程乙", dayOfWeek: 3)
    }

    func testIndependentContentKeepsTeachersPerWeekAndMatchesTablePath() throws {
        let entries = TimetableTeacherParserFixtures.segmentedSchedule
        let tableRecords = try HTMLParser.parseTimetableRecords(
            html: TimetableTeacherParserFixtures.completeTableHTML(entries: entries)
        )
        let contentRecords = try HTMLParser.parseTimetableRecords(
            html: TimetableTeacherParserFixtures.independentContentHTML(entries: entries)
        )

        XCTAssertEqual(recordSignatures(contentRecords), recordSignatures(tableRecords))
        XCTAssertEqual(contentRecords.reduce(0) { $0 + $1.weeks.count }, 32)
        assertSegmentedTeacherWeeks(in: contentRecords, courseName: "课程甲", dayOfWeek: 1)
        assertSegmentedTeacherWeeks(in: contentRecords, courseName: "课程乙", dayOfWeek: 3)
    }

    func testSameTeacherAdjacentPeriodsMergeAndExactDuplicatesAreRemoved() throws {
        let entries = [
            TimetableTeacherParserFixtures.Entry(
                courseName: "连续课程", teacher: "教师甲", weeks: "2-3周",
                dayOfWeek: 1, periodIndex: 1, room: "二教101"
            ),
            TimetableTeacherParserFixtures.Entry(
                courseName: "连续课程", teacher: "教师甲", weeks: "2-3周",
                dayOfWeek: 1, periodIndex: 1, room: "二教101"
            ),
            TimetableTeacherParserFixtures.Entry(
                courseName: "连续课程", teacher: "教师甲", weeks: "2-3周",
                dayOfWeek: 1, periodIndex: 2, room: "二教101"
            )
        ]

        let records = try HTMLParser.parseTimetableRecords(
            html: TimetableTeacherParserFixtures.independentContentHTML(entries: entries)
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.teacher, "教师甲")
        XCTAssertEqual(records.first?.weeks, [2, 3])
        XCTAssertEqual(records.first?.duration, [1, 2, 3, 4])
    }

    func testDifferentTeachersWithSamePlacementAreKeptSeparate() throws {
        let entries = [
            TimetableTeacherParserFixtures.Entry(
                courseName: "换师课程", teacher: "教师甲", weeks: "2周",
                dayOfWeek: 1, periodIndex: 1, room: "二教101"
            ),
            TimetableTeacherParserFixtures.Entry(
                courseName: "换师课程", teacher: "教师乙", weeks: "2周",
                dayOfWeek: 1, periodIndex: 1, room: "二教101"
            )
        ]

        let records = try HTMLParser.parseTimetableRecords(
            html: TimetableTeacherParserFixtures.independentContentHTML(entries: entries)
        )

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.teacher)), Set(["教师甲", "教师乙"]))
        XCTAssertTrue(records.allSatisfy { $0.weeks == [2] && $0.duration == [1, 2] })
    }

    func testDifferentPeriodsWithEqualDurationSumAreNotConsideredDuplicates() throws {
        let entries = [
            TimetableTeacherParserFixtures.Entry(
                courseName: "节次课程", teacher: "教师甲", weeks: "2周",
                dayOfWeek: 1, periodIndex: 1, room: "二教101", explicitDuration: "第3节"
            ),
            TimetableTeacherParserFixtures.Entry(
                courseName: "节次课程", teacher: "教师甲", weeks: "2周",
                dayOfWeek: 1, periodIndex: 1, room: "二教101", explicitDuration: "第1-2节"
            )
        ]

        let records = try HTMLParser.parseTimetableRecords(
            html: TimetableTeacherParserFixtures.independentContentHTML(entries: entries)
        )

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.duration).sorted { $0.lexicographicallyPrecedes($1) }, [[1, 2], [3]])
        XCTAssertTrue(records.allSatisfy { $0.courseName == "节次课程" && $0.teacher == "教师甲" })
    }

    func testAdjacentPeriodsWithDifferentTeachersStaySeparateInBothHTMLPaths() throws {
        let entries = [
            TimetableTeacherParserFixtures.Entry(courseName: "连续换师课程", teacher: "教师甲", weeks: "2周",
                dayOfWeek: 1, periodIndex: 1, room: "二教101"),
            TimetableTeacherParserFixtures.Entry(courseName: "连续换师课程", teacher: "教师乙", weeks: "2周",
                dayOfWeek: 1, periodIndex: 2, room: "二教101")
        ]
        for html in [TimetableTeacherParserFixtures.completeTableHTML(entries: entries),
                     TimetableTeacherParserFixtures.independentContentHTML(entries: entries)] {
            let records = try HTMLParser.parseTimetableRecords(html: html)
            XCTAssertEqual(records.count, 2)
            XCTAssertEqual(records.first { $0.teacher == "教师甲" }?.duration, [1, 2])
            XCTAssertEqual(records.first { $0.teacher == "教师乙" }?.duration, [3, 4])
        }
    }

    private func assertSegmentedTeacherWeeks(
        in records: [ParsedCourseRecord],
        courseName: String,
        dayOfWeek: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let courseRecords = records.filter {
            $0.courseName == courseName && $0.dayOfWeek == dayOfWeek
        }
        XCTAssertEqual(courseRecords.count, courseName == "课程甲" ? 2 : 3, file: file, line: line)

        let weeksByTeacher = Dictionary(uniqueKeysWithValues: courseRecords.map { ($0.teacher, $0.weeks) })
        if courseName == "课程甲" {
            XCTAssertEqual(weeksByTeacher["教师甲"], Array(2...9), file: file, line: line)
            XCTAssertEqual(weeksByTeacher["教师乙"], Array(11...14), file: file, line: line)
        } else {
            XCTAssertEqual(weeksByTeacher["教师甲"], [2, 3], file: file, line: line)
            XCTAssertEqual(weeksByTeacher["教师乙"], [6, 7], file: file, line: line)
            XCTAssertEqual(weeksByTeacher["教师丙"], Array(8...11), file: file, line: line)
        }
    }

    private func recordSignatures(_ records: [ParsedCourseRecord]) -> [String] {
        records.map {
            [
                $0.courseName, $0.teacher, $0.classInfo, String($0.dayOfWeek),
                $0.duration.map(String.init).joined(separator: ","), $0.room, $0.location,
                $0.weeks.map(String.init).joined(separator: ",")
            ].joined(separator: "|")
        }.sorted()
    }
}

/// Reusable synthetic timetable markup for parser regressions. It contains no user data.
enum TimetableTeacherParserFixtures {
    struct Entry {
        let courseName: String
        let teacher: String
        let weeks: String
        let dayOfWeek: Int
        let periodIndex: Int
        let room: String
        let explicitDuration: String?

        init(
            courseName: String,
            teacher: String,
            weeks: String,
            dayOfWeek: Int,
            periodIndex: Int,
            room: String,
            explicitDuration: String? = nil
        ) {
            self.courseName = courseName
            self.teacher = teacher
            self.weeks = weeks
            self.dayOfWeek = dayOfWeek
            self.periodIndex = periodIndex
            self.room = room
            self.explicitDuration = explicitDuration
        }
    }

    static let segmentedSchedule: [Entry] = [
        Entry(courseName: "课程甲", teacher: "教师甲", weeks: "2-9周", dayOfWeek: 1, periodIndex: 1, room: "二教101"),
        Entry(courseName: "课程甲", teacher: "教师乙", weeks: "11-14周", dayOfWeek: 1, periodIndex: 1, room: "二教101"),
        Entry(courseName: "课程甲", teacher: "教师甲", weeks: "2-9周", dayOfWeek: 2, periodIndex: 2, room: "二教101"),
        Entry(courseName: "课程甲", teacher: "教师乙", weeks: "11-14周", dayOfWeek: 2, periodIndex: 2, room: "二教101"),
        Entry(courseName: "课程乙", teacher: "教师甲", weeks: "2-3周", dayOfWeek: 3, periodIndex: 3, room: "二教101"),
        Entry(courseName: "课程乙", teacher: "教师乙", weeks: "6-7周", dayOfWeek: 3, periodIndex: 3, room: "二教101"),
        Entry(courseName: "课程乙", teacher: "教师丙", weeks: "8-11周", dayOfWeek: 3, periodIndex: 3, room: "二教101")
    ]

    static func completeTableHTML(entries: [Entry]) -> String {
        let headings = ["", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
        let periodLabels = ["12节", "34节", "5节", "67节", "89节", "1011节", "12节"]
        let rows = periodLabels.enumerated().map { row, label in
            let cells = (1...7).map { day in
                let content = entries
                    .filter { $0.dayOfWeek == day && $0.periodIndex == row + 1 }
                    .map { markup(for: $0) }
                    .joined(separator: "<hr>")
                let body = content.isEmpty ? "&nbsp;" : content
                let rowID = String(format: "%032d", row + 1)
                return "<td><div id='" + rowID + "-" + String(day) + "-random' class='kbcontent1'>"
                    + body
                    + "</div><div id='" + rowID + "-" + String(day) + "-detail' style='display: none;' class='kbcontent'>"
                    + body
                    + "</div></td>"
            }.joined()
            return "<tr><th>\(label)&nbsp;</th>\(cells)</tr>"
        }.joined()

        return """
        <html><body>
          <table id="kbtable"><tbody>
            <tr>\(headings.map { "<th>\($0)</th>" }.joined())</tr>
            \(rows)
            <tr><th>实验实习安排:</th><td colspan="7">匿名实践安排</td></tr>
          </tbody></table>
        </body></html>
        """
    }

    static func independentContentHTML(entries: [Entry]) -> String {
        let contents = entries.map { entry in
            "<div id=\"kbcontent_\(entry.dayOfWeek)_\(entry.periodIndex)\" class=\"kbcontent\">\(markup(for: entry))</div>"
        }.joined()
        return "<html><body>\(contents)</body></html>"
    }

    private static func markup(for entry: Entry) -> String {
        let duration = entry.explicitDuration.map { "\($0)<br>" } ?? ""
        return "\(entry.courseName)<br><font title=\"老师\">\(entry.teacher)</font><br>"
            + "<font title=\"周次(节次)\">\(entry.weeks)</font><br>\(duration)"
            + "<font title=\"教室\">\(entry.room)</font><br>"
    }
}
