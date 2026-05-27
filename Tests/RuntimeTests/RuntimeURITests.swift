import Foundation
@testable import Runtime
import XCTest

final class RuntimeURITests: XCTestCase {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    func testURIParsesAndNormalizesComponents() {
        var thrown = 0
        let uriRaw = kk_uri_new(runtimeString("https://example.com/base/../path?q=1#frag"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_uri_scheme(uriRaw)), "https")
        XCTAssertEqual(stringValue(kk_uri_authority(uriRaw)), "example.com")
        XCTAssertEqual(stringValue(kk_uri_query(uriRaw)), "q=1")
        XCTAssertEqual(stringValue(kk_uri_fragment(uriRaw)), "frag")
        let normalized = kk_uri_normalize(uriRaw)
        XCTAssertEqual(stringValue(kk_uri_path(normalized)), "/path")
    }

    func testURIToPathExtractsFilePath() {
        var thrown = 0
        let uriRaw = kk_uri_new(runtimeString("file:///tmp/archive.tar.gz"), &thrown)
        XCTAssertEqual(thrown, 0)
        let pathRaw = kk_uri_toPath(uriRaw)
        XCTAssertEqual(stringValue(kk_path_pathString(pathRaw)), "/tmp/archive.tar.gz")
    }

    func testURIToPathDecodesPercentEncodedPath() {
        var thrown = 0
        let uriRaw = kk_uri_new(runtimeString("file:///tmp/hello%20world.txt"), &thrown)
        XCTAssertEqual(thrown, 0)
        let pathRaw = kk_uri_toPath(uriRaw)
        XCTAssertEqual(stringValue(kk_path_pathString(pathRaw)), "/tmp/hello world.txt")
    }

    func testURIToPathRoundTripsThroughPathToUri() {
        let absolute = "/tmp/example/file.kt"
        let pathRaw = kk_path_new(runtimeString(absolute))
        let uriRaw = kk_path_toUri(pathRaw)
        let restoredPathRaw = kk_uri_toPath(uriRaw)
        XCTAssertEqual(stringValue(kk_path_pathString(restoredPathRaw)), absolute)
    }
}
