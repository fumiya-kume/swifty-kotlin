@testable import CompilerCore
import Foundation
import XCTest

final class FileFingerprintTests: XCTestCase {
    // MARK: - Init

    func testInitStoresProperties() {
        let fp = FileFingerprint(path: "/tmp/a.kt", contentHash: "abc123", mtimeNanos: 999)
        XCTAssertEqual(fp.path, "/tmp/a.kt")
        XCTAssertEqual(fp.contentHash, "abc123")
        XCTAssertEqual(fp.mtimeNanos, 999)
    }

    // MARK: - Compute from file contents

    func testComputeFromContentsProducesConsistentHash() {
        let data = Data("fun main() {}".utf8)
        let fp1 = FileFingerprint.compute(for: "/fake/path.kt", contents: data)
        let fp2 = FileFingerprint.compute(for: "/fake/path.kt", contents: data)
        XCTAssertEqual(fp1.contentHash, fp2.contentHash)
        XCTAssertEqual(fp1.path, "/fake/path.kt")
    }

    func testComputeFromContentsDifferentContentsDifferentHash() {
        let data1 = Data("fun main() {}".utf8)
        let data2 = Data("fun main() { println() }".utf8)
        let fp1 = FileFingerprint.compute(for: "/a.kt", contents: data1)
        let fp2 = FileFingerprint.compute(for: "/a.kt", contents: data2)
        XCTAssertNotEqual(fp1.contentHash, fp2.contentHash)
    }

    func testComputeFromContentsEmptyData() {
        let data = Data()
        let fp = FileFingerprint.compute(for: "/empty.kt", contents: data)
        // SHA-256 of empty input is a well-known constant
        XCTAssertEqual(fp.contentHash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    // MARK: - Compute from file path

    func testComputeFromPathReturnsNilForNonExistentFile() {
        let fp = FileFingerprint.compute(for: "/nonexistent/path/that/does/not/exist.kt")
        XCTAssertNil(fp)
    }

    func testComputeFromPathReturnsValidFingerprintForExistingFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt")
        try "hello world".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fp = FileFingerprint.compute(for: tempURL.path)
        XCTAssertNotNil(fp)
        XCTAssertEqual(fp?.path, tempURL.path)
        XCTAssertFalse(try XCTUnwrap(fp?.contentHash.isEmpty))
        XCTAssertTrue(try XCTUnwrap(fp?.mtimeNanos) > 0)
    }

    // MARK: - contentChanged

    func testContentChangedReturnsTrueForDifferentHashes() {
        let fp1 = FileFingerprint(path: "/a.kt", contentHash: "aaa", mtimeNanos: 100)
        let fp2 = FileFingerprint(path: "/a.kt", contentHash: "bbb", mtimeNanos: 100)
        XCTAssertTrue(fp1.contentChanged(from: fp2))
    }

    func testContentChangedReturnsFalseForSameHash() {
        let fp1 = FileFingerprint(path: "/a.kt", contentHash: "same", mtimeNanos: 100)
        let fp2 = FileFingerprint(path: "/a.kt", contentHash: "same", mtimeNanos: 200)
        XCTAssertFalse(fp1.contentChanged(from: fp2))
    }

    // MARK: - mtimeUnchanged

    func testMtimeUnchangedReturnsTrueForSamePathAndMtime() {
        let fp1 = FileFingerprint(path: "/a.kt", contentHash: "x", mtimeNanos: 100)
        let fp2 = FileFingerprint(path: "/a.kt", contentHash: "y", mtimeNanos: 100)
        XCTAssertTrue(fp1.mtimeUnchanged(from: fp2))
    }

    func testMtimeUnchangedReturnsFalseForDifferentMtime() {
        let fp1 = FileFingerprint(path: "/a.kt", contentHash: "x", mtimeNanos: 100)
        let fp2 = FileFingerprint(path: "/a.kt", contentHash: "x", mtimeNanos: 200)
        XCTAssertFalse(fp1.mtimeUnchanged(from: fp2))
    }

    func testMtimeUnchangedReturnsFalseForDifferentPath() {
        let fp1 = FileFingerprint(path: "/a.kt", contentHash: "x", mtimeNanos: 100)
        let fp2 = FileFingerprint(path: "/b.kt", contentHash: "x", mtimeNanos: 100)
        XCTAssertFalse(fp1.mtimeUnchanged(from: fp2))
    }

    // MARK: - Equatable

    func testEquatable() {
        let fp1 = FileFingerprint(path: "/a.kt", contentHash: "abc", mtimeNanos: 100)
        let fp2 = FileFingerprint(path: "/a.kt", contentHash: "abc", mtimeNanos: 100)
        let fp3 = FileFingerprint(path: "/a.kt", contentHash: "xyz", mtimeNanos: 100)
        XCTAssertEqual(fp1, fp2)
        XCTAssertNotEqual(fp1, fp3)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let fp = FileFingerprint(path: "/test.kt", contentHash: "deadbeef", mtimeNanos: 42)
        let encoder = JSONEncoder()
        let data = try encoder.encode(fp)
        let decoder = JSONDecoder()
        let restored = try decoder.decode(FileFingerprint.self, from: data)
        XCTAssertEqual(fp, restored)
    }

    // MARK: - SHA-256 correctness

    func testSHA256KnownVector() {
        // "abc" -> ba7816bf 8f01cfea 414140de 5dae2223 b00361a3 96177a9c b410ff61 f20015ad
        let data = Data("abc".utf8)
        let fp = FileFingerprint.compute(for: "/test.kt", contents: data)
        XCTAssertEqual(fp.contentHash, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
