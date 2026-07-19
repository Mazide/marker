import XCTest
@testable import Marker

final class URLCommandTests: XCTestCase {
    private func parse(_ string: String) -> URLCommand? {
        URLCommand.parse(URL(string: string)!)
    }

    func testShow() {
        XCTAssertEqual(parse("marker://show"), .show)
    }

    func testSearchWithQuery() {
        XCTAssertEqual(parse("marker://search?q=invoice"), .search(query: "invoice"))
        XCTAssertEqual(
            parse("marker://search?q=two%20words"), .search(query: "two words"))
    }

    func testSearchWithoutQueryOpensEmptySearch() {
        XCTAssertEqual(parse("marker://search"), .search(query: ""))
    }

    func testCopyDefaultsToNewest() {
        XCTAssertEqual(parse("marker://copy"), .copy(position: 1))
    }

    func testCopyWithPosition() {
        XCTAssertEqual(parse("marker://copy?position=3"), .copy(position: 3))
    }

    func testCopyRejectsBadPositions() {
        XCTAssertNil(parse("marker://copy?position=0"))
        XCTAssertNil(parse("marker://copy?position=-2"))
        XCTAssertNil(parse("marker://copy?position=abc"))
    }

    func testAdd() {
        XCTAssertEqual(parse("marker://add?text=hello"), .add(text: "hello"))
    }

    func testAddRejectsEmptyText() {
        XCTAssertNil(parse("marker://add"))
        XCTAssertNil(parse("marker://add?text="))
        XCTAssertNil(parse("marker://add?text=%20%20"))
    }

    func testUnknownHostAndForeignSchemeRejected() {
        XCTAssertNil(parse("marker://selfdestruct"))
        XCTAssertNil(parse("other://show"))
    }
}
