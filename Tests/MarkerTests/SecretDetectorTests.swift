import XCTest
@testable import Marker

/// Fixtures are assembled at runtime: a literal vendor-shaped key in the
/// source would trip GitHub's push protection, even a made-up one.
final class SecretDetectorTests: XCTestCase {
    private func key(_ prefix: String, _ body: String) -> String {
        prefix + body
    }

    func testVendorPrefixedKeys() {
        XCTAssertTrue(SecretDetector.looksSecret(key("sk-", "notreal01-" + String(repeating: "Ab1", count: 10))))
        XCTAssertTrue(SecretDetector.looksSecret(key("ghp" + "_", String(repeating: "Zz9", count: 12))))
        XCTAssertTrue(SecretDetector.looksSecret(key("xox" + "b-", "000000000000-" + String(repeating: "Qw2", count: 8))))
        XCTAssertTrue(SecretDetector.looksSecret(key("AKI" + "A", "EXAMPLEEXAMPLE12")))
        XCTAssertTrue(SecretDetector.looksSecret(key("AIz" + "a", "Sy" + String(repeating: "Xx3", count: 10))))
    }

    func testAssignmentsAndPEM() {
        XCTAssertTrue(SecretDetector.looksSecret("api_key = 8f4c2b19d77e4a51"))
        XCTAssertTrue(SecretDetector.looksSecret("Authorization: Bearer " + String(repeating: "Ey7", count: 8)))
        XCTAssertTrue(SecretDetector.looksSecret("password: hunter2hunter2"))
        XCTAssertTrue(SecretDetector.looksSecret("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNza..."))
    }

    func testUnprefixedHighEntropyTokens() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." + String(repeating: "Ab1", count: 12)
        XCTAssertTrue(SecretDetector.looksSecret(jwt))
        XCTAssertTrue(SecretDetector.looksSecret("d41d8cd98f00b204e9800998ecf8427e1a2b3c4d"), "long hex")
    }

    func testOrdinaryTextIsNotSecret() {
        XCTAssertFalse(SecretDetector.looksSecret("Select text. It's already copied."))
        XCTAssertFalse(SecretDetector.looksSecret("hello"))
        XCTAssertFalse(SecretDetector.looksSecret("Оформить таблицу по полям расчета"))
        XCTAssertFalse(SecretDetector.looksSecret("https://getmarkerapp.net/privacy/"), "plain URL")
        XCTAssertFalse(SecretDetector.looksSecret("/Users/looseconfetti/Dev/marker/Sources"), "file path")
        XCTAssertFalse(SecretDetector.looksSecret("supercalifragilisticexpialidocious"), "long lowercase word")
        XCTAssertFalse(SecretDetector.looksSecret("git commit --amend --no-edit"))
    }
}