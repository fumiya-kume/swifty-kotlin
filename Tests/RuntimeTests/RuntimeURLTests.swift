import Foundation
@testable import Runtime
import XCTest

final class RuntimeURLTests: XCTestCase {
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

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    func testURLParsesResolvesAndConvertsToURI() {
        var thrown = 0
        let base = kk_url_new(runtimeString("https://example.com/base/index.html?x=1#frag"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_url_protocol(base)), "https")
        XCTAssertEqual(stringValue(kk_url_host(base)), "example.com")
        XCTAssertEqual(kk_url_port(base), -1)
        XCTAssertEqual(stringValue(kk_url_path(base)), "/base/index.html")
        XCTAssertEqual(stringValue(kk_url_query(base)), "x=1")
        XCTAssertEqual(stringValue(kk_url_fragment(base)), "frag")

        let child = kk_url_new_relative(base, runtimeString("../child?q=a%20b#next"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_url_toExternalForm(child)), "https://example.com/child?q=a%20b#next")

        let uri = kk_url_toURI(child, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_uri_toString(uri)), "https://example.com/child?q=a%20b#next")
    }

    func testURLEqualitySameFileAndEncodingHelpers() {
        var thrown = 0
        let lhs = kk_url_new(runtimeString("https://example.com/a%20b?q=1#top"), &thrown)
        XCTAssertEqual(thrown, 0)
        let rhs = kk_url_new(runtimeString("https://example.com/a%20b?q=1#top"), &thrown)
        XCTAssertEqual(thrown, 0)
        let otherFragment = kk_url_new(runtimeString("https://example.com/a%20b?q=1#bottom"), &thrown)
        XCTAssertEqual(thrown, 0)

        XCTAssertTrue(boolValue(kk_url_equals(lhs, rhs)))
        XCTAssertEqual(kk_url_hashCode(lhs), kk_url_hashCode(rhs))
        XCTAssertTrue(boolValue(kk_url_sameFile(lhs, otherFragment)))

        XCTAssertEqual(stringValue(kk_url_encode(runtimeString("a b+c"))), "a%20b%2Bc")
        XCTAssertEqual(stringValue(kk_url_decode(runtimeString("a%20b%2Bc"))), "a b+c")
    }

    func testURLReadBytesReturnsSignedByteValues() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0, 127, 128, 255]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let urlRaw = kk_url_new(runtimeString(fileURL.absoluteString), &thrown)
        let bytesRaw = kk_url_readBytes(urlRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeListBox(from: bytesRaw)?.elements, [0, 127, -128, -1])
    }
}
