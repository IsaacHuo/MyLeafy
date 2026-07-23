import XCTest
@testable import Leafy

final class FitnessTestShareTests: XCTestCase {
    func testSnapshotIncludesAllItemsAndIgnoresPageFilter() {
        let height = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            item: .height,
            value: 175.5,
            testedAt: Date(timeIntervalSince1970: 100),
            note: "晨起测量"
        )
        let weight = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            item: .weight,
            value: 62.5,
            testedAt: Date(timeIntervalSince1970: 200)
        )

        let snapshot = FitnessTestShareSnapshot(records: [height, weight])

        XCTAssertEqual(snapshot.recordCount, 2)
        XCTAssertEqual(snapshot.itemCount, 2)
        XCTAssertEqual(snapshot.groups.map(\.item), [.height, .weight])
        XCTAssertEqual(snapshot.latestTestDate, weight.testedAt)
    }

    func testSnapshotGroupsRecordsNewestFirstAndPreservesUnitsAndNotes() {
        let older = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            item: .run800m,
            value: 230,
            testedAt: Date(timeIntervalSince1970: 100),
            note: "  第一次测试  "
        )
        let newer = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            item: .run800m,
            value: 214,
            testedAt: Date(timeIntervalSince1970: 200),
            note: "复测"
        )

        let snapshot = FitnessTestShareSnapshot(records: [older, newer])
        let group = snapshot.groups.first

        XCTAssertEqual(group?.item, .run800m)
        XCTAssertEqual(group?.records.map(\.id), [newer.id, older.id])
        XCTAssertEqual(group?.records.map(\.displayValue), ["3分34秒", "3分50秒"])
        XCTAssertEqual(group?.records.map(\.note), ["复测", "第一次测试"])
    }

    func testEmptySnapshotHasNoGroups() {
        let snapshot = FitnessTestShareSnapshot(records: [])

        XCTAssertEqual(snapshot.recordCount, 0)
        XCTAssertEqual(snapshot.itemCount, 0)
        XCTAssertNil(snapshot.latestTestDate)
        XCTAssertTrue(snapshot.groups.isEmpty)
    }

    private func record(
        id: UUID,
        item: FitnessTestItem,
        value: Double,
        testedAt: Date,
        note: String = ""
    ) -> FitnessTestRecord {
        FitnessTestRecord(
            id: id,
            testedAt: testedAt,
            itemRawValue: item.rawValue,
            value: value,
            unitRawValue: item.defaultUnit.rawValue,
            note: note,
            createdAt: testedAt,
            updatedAt: testedAt
        )
    }
}
