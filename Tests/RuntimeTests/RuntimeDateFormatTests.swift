import Foundation
@testable import Runtime
import XCTest

final class RuntimeDateFormatTests: IsolatedRuntimeXCTestCase {
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

    func testDateFormatFormatsEpochMillis() {
        let fmt = kk_dateformat_ofPattern(runtimeString("yyyy-MM-dd"), runtimeString("en_US"))
        XCTAssertEqual(stringValue(kk_dateformat_format(fmt, 0)), "1970-01-01")
    }
}
