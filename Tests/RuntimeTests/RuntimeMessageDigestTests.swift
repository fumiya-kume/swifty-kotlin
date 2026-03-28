import Foundation
@testable import Runtime
import XCTest

final class RuntimeMessageDigestTests: IsolatedRuntimeXCTestCase {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    func testSHA256DigestOfAbcHasExpectedLength() {
        let digest = kk_message_digest_getInstance(runtimeString("SHA-256"), nil)
        let data = registerRuntimeObject(RuntimeListBox(elements: Array("abc".utf8).map { Int($0) }))
        let out = kk_message_digest_digest(digest, data, nil)
        XCTAssertEqual(runtimeListBox(from: out)?.elements.count, 32)
    }
}
