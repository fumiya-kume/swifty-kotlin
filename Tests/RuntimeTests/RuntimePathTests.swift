@testable import Runtime
import XCTest

final class RuntimePathTests: XCTestCase {
    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
                Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
            }
        }
    }

    private func extractStringRaw(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func makePathRaw(_ value: String) -> Int {
        kk_path_new(makeStringRaw(value))
    }

    func testPathInvariantSeparatorsPathRewritesBackslashes() {
        XCTAssertEqual(
            extractStringRaw(kk_path_invariantSeparatorsPath(makePathRaw(#"C:\tmp\archive.tar.gz"#))),
            "C:/tmp/archive.tar.gz"
        )
        XCTAssertEqual(
            extractStringRaw(kk_path_invariantSeparatorsPath(makePathRaw("/tmp/archive.tar.gz"))),
            "/tmp/archive.tar.gz"
        )
    }

    func testPathInvariantSeparatorsPathStringRewritesBackslashes() {
        XCTAssertEqual(
            extractStringRaw(kk_path_invariantSeparatorsPathString(makePathRaw(#"C:\tmp\archive.tar.gz"#))),
            "C:/tmp/archive.tar.gz"
        )
    }

    func testPathNameReturnsLastComponent() {
        XCTAssertEqual(
            extractStringRaw(kk_path_name(makePathRaw("/tmp/archive.tar.gz"))),
            "archive.tar.gz"
        )
    }

    func testPathNameWithoutExtensionReturnsLastComponentStem() {
        XCTAssertEqual(
            extractStringRaw(kk_path_nameWithoutExtension(makePathRaw("/tmp/archive.tar.gz"))),
            "archive.tar"
        )
        XCTAssertEqual(
            extractStringRaw(kk_path_nameWithoutExtension(makePathRaw("/tmp/README"))),
            "README"
        )
        XCTAssertEqual(
            extractStringRaw(kk_path_nameWithoutExtension(makePathRaw("/tmp/.gitignore"))),
            ""
        )
    }

    func testPathFactoryWriteTextAndAppendTextRoundTrip() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = kk_path_get(makeStringRaw(fileURL.path))
        XCTAssertEqual(extractStringRaw(kk_path_toString(pathRaw)), fileURL.path)

        var thrown = 0
        XCTAssertEqual(kk_path_writeText(pathRaw, makeStringRaw("alpha"), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha")

        let appendedPathRaw = kk_path_appendText_default(pathRaw, makeStringRaw("\nbeta"), &thrown)
        XCTAssertEqual(extractStringRaw(kk_path_toString(appendedPathRaw)), fileURL.path)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha\nbeta")
    }

    func testPathDeleteIfExistsRemovesExistingFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "data".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = makePathRaw(fileURL.path)

        XCTAssertEqual(kk_unbox_bool(kk_path_deleteIfExists(pathRaw)), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(kk_unbox_bool(kk_path_deleteIfExists(pathRaw)), 0)
    }
}
