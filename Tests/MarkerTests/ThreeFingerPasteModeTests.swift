import XCTest
@testable import Marker

final class ThreeFingerPasteModeTests: XCTestCase {
    func testStoredDoubleTapRemainsDoubleTap() {
        XCTAssertEqual(
            ThreeFingerPasteMode.fromStoredValue("doubleTap", legacyClickEnabled: false),
            .doubleTap
        )
    }

    func testCurrentStoredValueWinsOverLegacyToggle() {
        XCTAssertEqual(
            ThreeFingerPasteMode.fromStoredValue("off", legacyClickEnabled: true),
            .off
        )
        XCTAssertEqual(
            ThreeFingerPasteMode.fromStoredValue("click", legacyClickEnabled: false),
            .click
        )
    }

    func testLegacyToggleStillMigratesWhenNoModeWasStored() {
        XCTAssertEqual(
            ThreeFingerPasteMode.fromStoredValue(nil, legacyClickEnabled: true),
            .click
        )
        XCTAssertEqual(
            ThreeFingerPasteMode.fromStoredValue(nil, legacyClickEnabled: false),
            .off
        )
    }
}
