import Foundation
import XCTest
@testable import Leafy

final class ScheduleMemoMarkdownTests: XCTestCase {
    func testScheduleRootTopBarUsesCompactAndAccessibleLayouts() {
        XCTAssertEqual(
            ScheduleRootTopBarLayout.resolve(viewportWidth: 320, usesAccessibilitySizes: false),
            .combinedActions
        )
        XCTAssertEqual(
            ScheduleRootTopBarLayout.resolve(viewportWidth: 390, usesAccessibilitySizes: false),
            .regular
        )
        XCTAssertEqual(
            ScheduleRootTopBarLayout.resolve(viewportWidth: 390, usesAccessibilitySizes: true),
            .stacked
        )
    }

    func testParserRecognizesFormattingAndInlineResources() {
        let imageID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let attachmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let source = """
        # 标题

        > 引用
        - 项目
        2. 编号
        - [x] 完成
        ---
        ```
        let value = 1
        ```
        \(ScheduleMemoInlineResourceReference(kind: .image, id: imageID).marker)
        \(ScheduleMemoInlineResourceReference(kind: .attachment, id: attachmentID).marker)
        """

        let blocks = ScheduleMemoMarkdownParser.blocks(in: source)

        XCTAssertEqual(blocks.count, 9)
        XCTAssertEqual(blocks[0].kind, .heading(level: 1, text: "标题"))
        XCTAssertEqual(blocks[1].kind, .quote("引用"))
        XCTAssertEqual(blocks[2].kind, .unorderedList("项目"))
        XCTAssertEqual(blocks[3].kind, .orderedList(number: 2, text: "编号"))
        XCTAssertEqual(blocks[4].kind, .task(isCompleted: true, text: "完成"))
        XCTAssertEqual(blocks[5].kind, .divider)
        XCTAssertEqual(blocks[6].kind, .code("let value = 1"))
        XCTAssertEqual(
            ScheduleMemoMarkdownParser.referencedResources(in: source),
            Set([
                .init(kind: .image, id: imageID),
                .init(kind: .attachment, id: attachmentID)
            ])
        )
    }

    func testPlainTextRemovesMarkdownSyntaxButKeepsMeaningfulLabels() {
        let source = """
        ## **学习记录**

        - [ ] 复习 [Swift](https://swift.org)
        ![图片](leafy-memo://image/11111111-1111-1111-1111-111111111111)
        """

        XCTAssertEqual(
            ScheduleMemoMarkdownParser.plainText(from: source),
            "学习记录 待办 复习 Swift"
        )
    }

    func testEditorMutationUsesUTF16SelectionAndPreservesChineseText() {
        let source = "今天学习 Swift"
        let selection = (source as NSString).range(of: "学习")

        let result = ScheduleMemoEditorMutation.applying(.bold, to: source, selection: selection)

        XCTAssertEqual(result.text, "今天**学习** Swift")
        XCTAssertEqual((result.text as NSString).substring(with: result.selection), "学习")
    }

    func testRemovingResourceOnlyRemovesItsMarkerLine() {
        let reference = ScheduleMemoInlineResourceReference(
            kind: .attachment,
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
        let source = "第一段\n\(reference.marker)\n第二段"

        XCTAssertEqual(
            ScheduleMemoMarkdownParser.removingResource(reference, from: source),
            "第一段\n第二段"
        )
    }

    func testSubmissionUsesMailtoAndDoesNotExposeLocalResourceIdentifiers() throws {
        let attachmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let source = """
        # 校园观察

        正文
        [附件](leafy-memo://attachment/\(attachmentID.uuidString.lowercased()))
        """
        let draft = ScheduleMemoSubmissionDraft.make(
            title: "校园观察",
            source: source,
            tags: ["校园"],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 60),
            attachmentNames: [attachmentID: "观察记录.md"]
        )

        let url = try XCTUnwrap(draft.mailtoURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, ScheduleMemoSubmissionDraft.recipient)
        XCTAssertEqual(query["subject"], "【MyLeafy 投稿】校园观察")
        XCTAssertEqual(query["body"], draft.body)
        XCTAssertTrue(draft.body.contains("观察记录.md"))
        XCTAssertFalse(draft.body.contains("leafy-memo://"))
        XCTAssertFalse(draft.body.contains(attachmentID.uuidString.lowercased()))
    }
}
