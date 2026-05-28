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

    func testPathStringReturnsRawPathString() {
        XCTAssertEqual(
            extractStringRaw(kk_path_pathString(makePathRaw(#"C:\tmp\archive.tar.gz"#))),
            #"C:\tmp\archive.tar.gz"#
        )
        XCTAssertEqual(
            extractStringRaw(kk_path_pathString(makePathRaw("/tmp/archive.tar.gz"))),
            "/tmp/archive.tar.gz"
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

    func testPathWriteLinesIterableWritesLinesToFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = makePathRaw(fileURL.path)
        let linesRaw = registerRuntimeObject(RuntimeListBox(elements: [
            makeStringRaw("hello"),
            makeStringRaw("world"),
        ]))
        var thrown = 0
        let returnedRaw = kk_path_writeLines_iterable(pathRaw, linesRaw, 0, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returnedRaw, pathRaw)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "hello\nworld\n")
    }

    func testPathWriteLinesIterableOverwritesExistingContent() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "old content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = makePathRaw(fileURL.path)
        let linesRaw = registerRuntimeObject(RuntimeListBox(elements: [
            makeStringRaw("new line"),
        ]))
        var thrown = 0
        kk_path_writeLines_iterable(pathRaw, linesRaw, 0, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "new line\n")
    }

    func testPathWriteLinesSequenceWritesLinesToFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = makePathRaw(fileURL.path)
        let elements = [makeStringRaw("alpha"), makeStringRaw("beta")]
        let seqRaw = registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: elements)]))
        var thrown = 0
        let returnedRaw = kk_path_writeLines_sequence(pathRaw, seqRaw, 0, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returnedRaw, pathRaw)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha\nbeta\n")
    }

    func testPathWriteLinesSequenceOverwritesExistingContent() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "stale".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = makePathRaw(fileURL.path)
        let elements = [makeStringRaw("fresh")]
        let seqRaw = registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: elements)]))
        var thrown = 0
        kk_path_writeLines_sequence(pathRaw, seqRaw, 0, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "fresh\n")
    }

    func testPathDeleteIfExistsRemovesExistingFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "data".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = makePathRaw(fileURL.path)

        XCTAssertEqual(kk_unbox_bool(kk_path_deleteIfExists(pathRaw)), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(kk_unbox_bool(kk_path_deleteIfExists(pathRaw)), 0)
    }

    func testPathGetLastModifiedTimeReturnsModificationMillisForExistingFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "data".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let expectedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: expectedDate], ofItemAtPath: fileURL.path)

        let pathRaw = makePathRaw(fileURL.path)
        var thrown = 0
        let fileTimeRaw = kk_path_getLastModifiedTime(pathRaw, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(fileTimeRaw, 0)

        let actualMillis = kk_fileTime_toMillis(fileTimeRaw)
        XCTAssertEqual(actualMillis, Int(expectedDate.timeIntervalSince1970 * 1000))
    }

    func testPathGetLastModifiedTimeReportsIOExceptionForMissingFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let pathRaw = makePathRaw(fileURL.path)
        var thrown = 0
        _ = kk_path_getLastModifiedTime(pathRaw, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "missing file should populate outThrown with an IOException")
    }

    // MARK: - STDLIB-IO-PATH-FN-039: Path.walk

    func testPathWalkReturnsRootFileAsOnlyElement() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "data".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = makePathRaw(fileURL.path)
        let seqRaw = kk_path_walk(pathRaw, 0)

        let elements = runtimeSequenceSourceElements(from: seqRaw)
        XCTAssertNotNil(elements)
        XCTAssertEqual(elements?.count, 1)
        // Extract path string via public kk_path_toString
        let firstPathStr = extractStringRaw(kk_path_toString(elements![0]))
        XCTAssertEqual(firstPathStr, fileURL.path)
    }

    func testPathWalkIncludesRootDirectoryAndDescendants() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: false)
        let subDir = tmpDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: false)
        let file1 = tmpDir.appendingPathComponent("a.txt")
        let file2 = subDir.appendingPathComponent("b.txt")
        try "a".write(to: file1, atomically: true, encoding: .utf8)
        try "b".write(to: file2, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let pathRaw = makePathRaw(tmpDir.path)
        let seqRaw = kk_path_walk(pathRaw, 0)

        let elements = runtimeSequenceSourceElements(from: seqRaw)
        XCTAssertNotNil(elements)
        // Should include: tmpDir, sub/, a.txt, sub/b.txt (depth-first order)
        XCTAssertGreaterThanOrEqual(elements?.count ?? 0, 4)
        // Root is always first
        let firstPathStr = extractStringRaw(kk_path_toString(elements![0]))
        XCTAssertEqual(firstPathStr, tmpDir.path)
        // All paths should start with the root directory
        for elemRaw in elements! {
            let p = extractStringRaw(kk_path_toString(elemRaw))
            XCTAssertTrue(p.hasPrefix(tmpDir.path), "Expected \(p) to start with \(tmpDir.path)")
        }
    }

    func testPathWalkOnNonexistentDirectoryReturnsOnlyRoot() {
        let nonExistent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let pathRaw = makePathRaw(nonExistent)
        let seqRaw = kk_path_walk(pathRaw, 0)

        let elements = runtimeSequenceSourceElements(from: seqRaw)
        XCTAssertNotNil(elements)
        // Non-existent path: root is included, but enumerator yields nothing
        XCTAssertEqual(elements?.count, 1)
    }
}
