import CoreGraphics
import XCTest
@testable import Marker

final class CGEventKeySynthesizerTests: XCTestCase {
    func testRecognizesOnlyEventsTaggedByMarker() throws {
        let event = try XCTUnwrap(
            CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(8),
                keyDown: true
            )
        )

        XCTAssertFalse(CGEventKeySynthesizer.isMarkerSynthetic(event))

        event.setIntegerValueField(
            .eventSourceUserData,
            value: CGEventKeySynthesizer.syntheticEventTag
        )

        XCTAssertTrue(CGEventKeySynthesizer.isMarkerSynthetic(event))
    }
}
