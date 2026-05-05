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

    func testPathInvariantSeparatorsPathStringRewritesBackslashes() {
        XCTAssertEqual(
            extractStringRaw(kk_path_invariantSeparatorsPathString(makePathRaw(#"C:\tmp\archive.tar.gz"#))),
            "C:/tmp/archive.tar.gz"
        )
    }
}
