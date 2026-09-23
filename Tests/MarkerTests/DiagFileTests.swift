import Foundation
import XCTest
@testable import Marker

final class DiagFileTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_725_000_000.125)
    private let fixedSessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let metadata = DiagnosticLogMetadata(
        appVersion: "2.4.0",
        appBuild: "240",
        operatingSystem: "macOS 15.1",
        architecture: "arm64"
    )

    func testEnablingCreatesPrivateSelfDescribingLog() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }

        try fixture.log.setEnabled(true)

        XCTAssertTrue(fixture.log.enabled)
        let contents = try String(contentsOf: fixture.liveURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("# Marker diagnostic log"))
        XCTAssertTrue(contents.contains("# format=1"))
        XCTAssertTrue(contents.contains("# session=\(fixedSessionID.uuidString)"))
        XCTAssertTrue(contents.contains("# app_version=2.4.0"))
        XCTAssertTrue(contents.contains("# app_build=240"))
        XCTAssertTrue(contents.contains("# macOS=macOS 15.1"))
        XCTAssertTrue(contents.contains("# architecture=arm64"))
        XCTAssertTrue(contents.contains("Clipboard and selection contents are not recorded"))
        XCTAssertEqual(try permissions(at: fixture.liveURL), 0o600)
    }

    func testDisabledLogDoesNotCreateFileUntilEnabled() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }

        fixture.log.append("paste.request trigger=hotkey")
        try fixture.log.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.liveURL.path))

        try fixture.log.setEnabled(true)
        fixture.log.append("paste.request trigger=hotkey")
        try fixture.log.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.liveURL.path))
    }

    func testInitializationHardensAnExistingLegacyLogWhileDisabled() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let liveURL = root.appendingPathComponent("logs/Marker.log")
        try FileManager.default.createDirectory(
            at: liveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(
            atPath: liveURL.path,
            contents: Data("legacy diagnostic".utf8),
            attributes: [.posixPermissions: NSNumber(value: Int16(0o644))]
        ))

        _ = makeLog(fileURL: liveURL)

        XCTAssertEqual(try permissions(at: liveURL), 0o600)
        XCTAssertEqual(try String(contentsOf: liveURL, encoding: .utf8), "legacy diagnostic")
    }

    func testAppendIsOrderedAndEscapesMultilineOrControlText() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        try fixture.log.setEnabled(true)

        fixture.log.append("event=first")
        fixture.log.append("event=second\nforged-header\u{0}\tend")
        fixture.log.append("event=third")
        try fixture.log.flush()

        let contents = try String(contentsOf: fixture.liveURL, encoding: .utf8)
        let first = try XCTUnwrap(contents.range(of: "event=first"))
        let second = try XCTUnwrap(contents.range(of: "event=second\\nforged-header� end"))
        let third = try XCTUnwrap(contents.range(of: "event=third"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
        XCTAssertLessThan(second.lowerBound, third.lowerBound)
        XCTAssertFalse(contents.contains("event=second\nforged-header"))
        XCTAssertFalse(contents.unicodeScalars.contains("\u{0}"))
    }

    func testAppendRedactsTheCurrentUsersHomeDirectory() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        try fixture.log.setEnabled(true)
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        fixture.log.append("history.error path=\(home)/Library/private.db")
        try fixture.log.flush()

        let contents = try String(contentsOf: fixture.liveURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("path=<home>/Library/private.db"))
        XCTAssertFalse(contents.contains("path=\(home)/Library/private.db"))
    }

    func testConcurrentAppendsProduceCompleteSingleLineRecords() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        try fixture.log.setEnabled(true)

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            fixture.log.append("concurrent.event id=\(index)")
        }
        try fixture.log.flush()

        let contents = try String(contentsOf: fixture.liveURL, encoding: .utf8)
        let eventLines = contents.split(separator: "\n").filter {
            $0.contains("concurrent.event id=")
        }
        XCTAssertEqual(eventLines.count, 200)
        for index in 0 ..< 200 {
            XCTAssertEqual(
                eventLines.filter { $0.hasSuffix("concurrent.event id=\(index)") }.count,
                1
            )
        }
    }

    func testExportFlushesQueuedRecordsAndCreatesPrivateStandaloneCopy() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        try fixture.log.setEnabled(true)

        for index in 0 ..< 50 {
            fixture.log.append("capture.decision index=\(index)")
        }
        let exportURL = fixture.root.appendingPathComponent("exports/Marker-diagnostics.log")

        try fixture.log.export(to: exportURL)

        let contents = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("# Marker diagnostic export"))
        XCTAssertTrue(contents.contains("# exported="))
        XCTAssertTrue(contents.contains("# section=current"))
        XCTAssertTrue(contents.contains("capture.decision index=0"))
        XCTAssertTrue(contents.contains("capture.decision index=49"))
        XCTAssertEqual(try permissions(at: exportURL), 0o600)
    }

    func testExportIncludesFreshSnapshotWithRecordingDisabledWithoutCreatingLiveLog() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let exportURL = fixture.root.appendingPathComponent("report.txt")

        try fixture.log.export(
            to: exportURL,
            snapshot: "middle_click=true middle_click_tap=disabled\nforged-header"
        )

        let contents = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("# recording_enabled=false"))
        XCTAssertTrue(contents.contains("# section=export_snapshot"))
        XCTAssertTrue(contents.contains("middle_click=true middle_click_tap=disabled\\nforged-header"))
        XCTAssertFalse(contents.contains("\nforged-header"))
        XCTAssertTrue(contents.contains("# log_state=no_recorded_events"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.liveURL.path))
        XCTAssertFalse(fixture.log.enabled)
        XCTAssertEqual(try permissions(at: exportURL), 0o600)
    }

    func testRotationKeepsOnlyCurrentAndOnePreviousFile() throws {
        let fixture = makeFixture(maximumFileSize: 700)
        defer { fixture.remove() }
        try fixture.log.setEnabled(true)

        for index in 0 ..< 80 {
            fixture.log.append("paste.decision index=\(index) detail=\(String(repeating: "x", count: 70))")
        }
        try fixture.log.flush()

        let previousURL = fixture.root.appendingPathComponent("logs/Marker.previous.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.liveURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousURL.path))
        XCTAssertEqual(try permissions(at: fixture.liveURL), 0o600)
        XCTAssertEqual(try permissions(at: previousURL), 0o600)

        let logFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.liveURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(Set(logFiles.map(\.lastPathComponent)), ["Marker.log", "Marker.previous.log"])

        let exportURL = fixture.root.appendingPathComponent("Marker-export.log")
        try fixture.log.export(to: exportURL)
        let exported = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(exported.contains("# section=previous"))
        XCTAssertTrue(exported.contains("# section=current"))
        XCTAssertTrue(exported.contains("# continued_after_rotation=true"))
        XCTAssertTrue(exported.contains("paste.decision index=79"))
    }

    func testEnableFailureIsReturnedAndLeavesRecordingDisabled() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockingFile = root.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockingFile)
        let log = makeLog(fileURL: blockingFile.appendingPathComponent("Marker.log"))

        XCTAssertThrowsError(try log.setEnabled(true)) { error in
            XCTAssertTrue(error is DiagnosticLogError)
            XCTAssertTrue(error.localizedDescription.contains("Could not enable"))
        }
        XCTAssertFalse(log.enabled)
        XCTAssertNotNil(log.lastErrorDescription)
    }

    func testExportFailureIsReturned() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        try fixture.log.setEnabled(true)
        let blockingFile = fixture.root.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockingFile)

        XCTAssertThrowsError(
            try fixture.log.export(to: blockingFile.appendingPathComponent("Marker-export.log"))
        ) { error in
            XCTAssertTrue(error is DiagnosticLogError)
            XCTAssertTrue(error.localizedDescription.contains("Could not export"))
        }
        XCTAssertNotNil(fixture.log.lastErrorDescription)
    }

    private func makeFixture(maximumFileSize: UInt64 = 5_000_000) -> Fixture {
        let root = temporaryRoot()
        let liveURL = root.appendingPathComponent("logs/Marker.log")
        return Fixture(
            root: root,
            liveURL: liveURL,
            log: makeLog(fileURL: liveURL, maximumFileSize: maximumFileSize)
        )
    }

    private func makeLog(
        fileURL: URL,
        maximumFileSize: UInt64 = 5_000_000
    ) -> DiagFile {
        DiagFile(
            fileURL: fileURL,
            enabled: false,
            maximumFileSize: maximumFileSize,
            now: { [fixedDate] in fixedDate },
            sessionID: { [fixedSessionID] in fixedSessionID },
            metadata: metadata
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagFileTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    private struct Fixture {
        let root: URL
        let liveURL: URL
        let log: DiagFile

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
