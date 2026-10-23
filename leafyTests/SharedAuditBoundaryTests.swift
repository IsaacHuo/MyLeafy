import XCTest
@testable import Leafy

@MainActor
final class SharedAuditBoundaryTests: XCTestCase {
    func testClearedAcademicProgressCannotBeRevivedByOldReporter() {
        let controller = AcademicOperationProgressController()
        let old = controller.reporter(for: .grades)
        old(.begin(.fetchingGrades))
        controller.clear()
        old(.fail(.fetchingGrades, "late"))
        XCTAssertNil(controller.progress)
        let replacement = controller.reporter(for: .grades)
        replacement(.begin(.processingGrades))
        old(.fail(.fetchingGrades, "late"))
        XCTAssertEqual(controller.progress?.currentStage, .processingGrades)
    }

    func testWrongOperationStageDoesNotReplaceCurrentProgress() {
        let controller = AcademicOperationProgressController()
        controller.record(.begin(.fetchingGrades), for: .grades)
        controller.record(.begin(.fetchingExams), for: .timetable)
        XCTAssertEqual(controller.progress?.kind, .grades)
        XCTAssertEqual(controller.progress?.currentStage, .fetchingGrades)
    }

    func testPostgraduateSourcesOnlyOpenAbsoluteHTTPLinks() {
        for link in [
            "javascript:alert(1)",
            "file:///private/document.pdf",
            "/relative/path",
            "https:/missing-host",
            "mailto:hello@example.com"
        ] {
            XCTAssertNil(source(link).sourceURL, link)
        }
        XCTAssertEqual(source("https://example.edu/admissions?q=2027").sourceURL?.host, "example.edu")
        XCTAssertEqual(source("http://example.edu/admissions").sourceURL?.scheme, "http")
    }

    private func source(_ url: String) -> PostgraduateSource {
        PostgraduateSource(id: UUID(), title: "Admission", summary: "", sourceURLString: url,
                           sourceKindRawValue: "admission_notice", trustLevelRawValue: "official", school: nil,
                           unit: nil, major: nil, examYear: nil, publishedAt: nil, verifiedAt: nil,
                           status: "published", createdAt: nil, updatedAt: nil)
    }
}
