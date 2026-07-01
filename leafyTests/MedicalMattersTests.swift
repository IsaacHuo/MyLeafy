import XCTest
@testable import Leafy

final class MedicalMattersTests: XCTestCase {
    func testMedicalPolicySnapshotKeepsCoreRatesAndSources() {
        let snapshot = MedicalPolicySnapshot.current

        XCTAssertEqual(snapshot.policyUpdatedAt, "2024-05-23")
        XCTAssertEqual(snapshot.hospitalInfoUpdatedAt, "2026-06-01")
        XCTAssertEqual(snapshot.reimbursementRates.first(where: { $0.id == "clinic-campus" })?.rate, 90)
        XCTAssertEqual(snapshot.reimbursementRates.first(where: { $0.id == "clinic-contract" })?.rate, 80)
        XCTAssertEqual(snapshot.reimbursementRates.first(where: { $0.id == "clinic-specialist" })?.rate, 70)
        XCTAssertEqual(snapshot.reimbursementRates.first(where: { $0.id == "inpatient" })?.rate, 95)
        XCTAssertFalse(snapshot.scenarioAdvices.isEmpty)
        XCTAssertFalse(snapshot.advice(for: .contractOutpatient).materials.isEmpty)
    }

    func testMedicalLedgerEstimationAndDeadlineStates() {
        let estimate = MedicalLedgerCalculator.estimatedReimbursement(totalExpense: 123.45, scenario: .campusClinic)
        XCTAssertEqual(try XCTUnwrap(estimate), 111.11, accuracy: 0.001)
        XCTAssertNil(MedicalLedgerCalculator.estimatedReimbursement(totalExpense: 123.45, scenario: .emergency))

        let calendar = Calendar(identifier: .gregorian)
        let now = try! XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25)))
        let dueSoon = try! XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))
        let overdue = try! XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20)))

        XCTAssertEqual(
            MedicalLedgerCalculator.deadlineState(deadline: dueSoon, status: .readyToSubmit, now: now, calendar: calendar),
            .dueSoon(days: 7)
        )
        XCTAssertEqual(
            MedicalLedgerCalculator.deadlineState(deadline: overdue, status: .submitted, now: now, calendar: calendar),
            .overdue(days: 5)
        )
        XCTAssertEqual(
            MedicalLedgerCalculator.deadlineState(deadline: overdue, status: .reimbursed, now: now, calendar: calendar),
            .closed
        )
    }

    func testMedicalLedgerExportIncludesManifestCSVAndPhotos() throws {
        let entry = MedicalLedgerEntry(
            visitDate: Date(timeIntervalSince1970: 1_782_345_600),
            hospitalName: "北医三院",
            department: "内科",
            diagnosisNote: "急诊",
            scenarioRawValue: MedicalLedgerScenario.contractOutpatient.rawValue,
            totalExpense: 200,
            statusRawValue: MedicalLedgerStatus.readyToSubmit.rawValue,
            materialChecklistRawValue: MedicalLedgerMaterial.encode([.invoice, .referral])
        )
        let photo = MedicalLedgerPhoto(
            entryID: entry.id.uuidString,
            originalFilename: "receipt.jpg",
            localFilename: "local-receipt.jpg"
        )

        let csvData = MedicalLedgerExporter.makeCSVData(entries: [entry])
        let csv = try XCTUnwrap(String(data: csvData, encoding: .utf8))
        XCTAssertTrue(csv.contains("北医三院"))
        XCTAssertTrue(csv.contains("预计报销"))

        let manifestData = try MedicalLedgerExporter.makeManifestData(entries: [entry], photos: [photo])
        let manifest = try JSONDecoder.leafyISO8601.decode(MedicalLedgerExporter.ExportManifest.self, from: manifestData)
        XCTAssertEqual(manifest.entries.first?.estimatedReimbursement, 160)
        XCTAssertEqual(manifest.photos.first?.archivePath, "photos/\(entry.id.uuidString)/local-receipt.jpg")

        let zipData = try MedicalLedgerExporter.makeZipData(entries: [entry], photos: [photo]) { requestedPhoto in
            requestedPhoto.id == photo.id ? Data("image-data".utf8) : nil
        }
        let zipText = try XCTUnwrap(String(data: zipData, encoding: .isoLatin1))
        XCTAssertTrue(zipText.contains("medical-ledger.csv"))
        XCTAssertTrue(zipText.contains("manifest.json"))
        XCTAssertTrue(zipText.contains("photos/\(entry.id.uuidString)/local-receipt.jpg"))
    }

    func testCRC32UsesStandardChecksum() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xcbf43926)
    }
}

private extension JSONDecoder {
    static var leafyISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
