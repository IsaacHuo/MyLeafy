import Foundation
import SwiftSoup

nonisolated struct ClassroomAvailabilityMatrix: Sendable {
    struct Row: Sendable {
        let room: EmptyClassroom
        let slots: [ClassroomUsageSlot]
    }
    let periods: [Int]
    let rows: [Row]

    func availableRooms(start: Int? = nil, end: Int? = nil) throws -> [EmptyClassroom] {
        let lower = start ?? periods.min() ?? 1
        let upper = end ?? periods.max() ?? 12
        guard lower >= 1, upper <= 12, lower <= upper else {
            throw SchoolNetworkError.classroomDataUnavailable("请选择有效的起止节次。")
        }
        let requested = Set(lower...upper)
        guard requested.isSubset(of: Set(periods)) else {
            throw SchoolNetworkError.classroomDataUnavailable("学校结果缺少所选节次。")
        }
        return try rows.compactMap { row in
            let slots = row.slots.filter { requested.contains($0.period) }
            guard !slots.contains(where: { $0.status == .unknown }) else {
                throw SchoolNetworkError.classroomDataUnavailable("学校结果包含无法识别的占用状态。")
            }
            return slots.allSatisfy { $0.status == .available } ? row.room : nil
        }
    }

    func usage(for target: ClassroomIdentity) throws -> [ClassroomUsageSlot] {
        guard let row = rows.first(where: { $0.room.identity == target }), Set(periods) == Set(1...12) else {
            throw SchoolNetworkError.classroomDataUnavailable("学校结果未包含所选教室的完整节次。")
        }
        guard !row.slots.contains(where: { $0.status == .unknown }) else {
            throw SchoolNetworkError.classroomDataUnavailable("学校结果包含无法识别的占用状态。")
        }
        return row.slots
    }
}

extension HTMLParser {
    nonisolated static func parseClassroomAvailability(html: String) throws -> ClassroomAvailabilityMatrix {
        let document = try SwiftSoup.parse(html)
        guard let table = try document.select("#dataList").first(),
              try table.select("th").text().contains("星期") else {
            throw HTMLParserError.tableNotFound("教室占用矩阵")
        }
        let columns = try table.select("tr td[tdvalue]").array().map { cell -> [Int] in
            let value = try cell.attr("tdvalue").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count % 2 == 0, value.allSatisfy(\.isNumber) else {
                throw HTMLParserError.tableRowsUnparseable("教室节次")
            }
            let characters = Array(value)
            return try stride(from: 0, to: characters.count, by: 2).map { index in
                guard let period = Int(String(characters[index...index + 1])), (1...12).contains(period) else {
                    throw HTMLParserError.tableRowsUnparseable("教室节次")
                }
                return period
            }
        }
        let periods = columns.flatMap { $0 }
        guard !periods.isEmpty, Set(periods).count == periods.count else {
            throw HTMLParserError.tableRowsUnparseable("教室节次")
        }
        var rows: [(weight: Int, row: ClassroomAvailabilityMatrix.Row)] = []
        for row in try table.select("tr[jsbh]").array() {
            let cells = try row.select("td").array()
            guard cells.count == columns.count + 1 else {
                throw HTMLParserError.tableRowsUnparseable("教室占用行")
            }
            // The portal also lists laboratories and sports fields outside our classroom catalog.
            guard let room = try parseClassroomRow(cells[0].text()) else { continue }
            var slots: [ClassroomUsageSlot] = []
            for (index, column) in columns.enumerated() {
                let text = try cells[index + 1].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let symbol = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
                let knownOccupied = ["◆", "L", "G", "K", "Κ", "X", "J"]
                let status: ClassroomUsageStatus = text.isEmpty ? .available
                    : (knownOccupied.contains(symbol) ? .occupied : .unknown)
                slots += column.map { ClassroomUsageSlot(period: $0, status: status) }
            }
            rows.append((room.weight, .init(room: room.room, slots: slots.sorted { $0.period < $1.period })))
        }
        // A recognized matrix with no room rows is a verified empty result. Other tables are errors.
        if try table.select("tr[jsbh]").isEmpty(),
           try table.select("tr").array().contains(where: { row in
               let text = try row.text()
               return try row.select("td").count > 1 && row.select("td[tdvalue]").isEmpty()
                   && !text.contains("暂无") && !text.contains("无数据") && !text.contains("符号说明")
           }) {
            throw HTMLParserError.tableRowsUnparseable("教室占用矩阵")
        }
        return ClassroomAvailabilityMatrix(periods: periods, rows: rows.sorted {
            $0.weight == $1.weight ? $0.row.room.room < $1.row.room.room : $0.weight > $1.weight
        }.map(\.row))
    }
}
