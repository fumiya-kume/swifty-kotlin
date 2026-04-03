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

    private func stringValue(
        _ raw: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let value = extractString(from: ptr)
        else {
            XCTFail("Invalid runtime string handle: \(raw)", file: file, line: line)
            return ""
        }
        return value
    }

    private func expectedPattern(
        _ pattern: String,
        locale: String,
        timeZone: String = "UTC",
        epochMillis: Int
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: normalizeLocaleIdentifier(locale))
        formatter.dateFormat = pattern
        formatter.timeZone = TimeZone(identifier: timeZone)
        return formatter.string(from: Date(timeIntervalSince1970: Double(epochMillis) / 1000.0))
    }

    private func expectedStyles(
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        locale: String,
        timeZone: String = "UTC",
        epochMillis: Int
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: normalizeLocaleIdentifier(locale))
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatter.timeZone = TimeZone(identifier: timeZone)
        return formatter.string(from: Date(timeIntervalSince1970: Double(epochMillis) / 1000.0))
    }

    func testDateFormatFormatsEpochMillis() {
        let fmt = kk_dateformat_ofPattern(runtimeString("yyyy-MM-dd"), runtimeString("en_US"))
        XCTAssertEqual(stringValue(kk_dateformat_format(fmt, 0)), "1970-01-01")
    }

    func testDateFormatFormatsPatternWithTimeZone() {
        let epochMillis = 0
        let fmt = kk_dateformat_ofPatternWithTimeZone(
            runtimeString("yyyy-MM-dd HH:mm zzz"),
            runtimeString("en_US"),
            runtimeString("Asia/Tokyo")
        )
        XCTAssertEqual(
            stringValue(kk_dateformat_format(fmt, epochMillis)),
            expectedPattern("yyyy-MM-dd HH:mm zzz", locale: "en_US", timeZone: "Asia/Tokyo", epochMillis: epochMillis)
        )
    }

    func testDateFormatDateInstanceUsesLocaleFormatting() {
        let epochMillis = 0
        let fmt = kk_dateformat_getDateInstance(runtimeString("ja_JP"))
        XCTAssertEqual(
            stringValue(kk_dateformat_format(fmt, epochMillis)),
            expectedStyles(dateStyle: .medium, timeStyle: .none, locale: "ja_JP", epochMillis: epochMillis)
        )
    }

    func testDateFormatTimeInstanceUsesLocaleFormatting() {
        let epochMillis = 0
        let fmt = kk_dateformat_getTimeInstance(runtimeString("en_US"))
        XCTAssertEqual(
            stringValue(kk_dateformat_format(fmt, epochMillis)),
            expectedStyles(dateStyle: .none, timeStyle: .medium, locale: "en_US", epochMillis: epochMillis)
        )
    }

    func testDateFormatDateTimeInstanceUsesTimeZone() {
        let epochMillis = 0
        let fmt = kk_dateformat_getDateTimeInstanceWithTimeZone(
            runtimeString("en_US"),
            runtimeString("Asia/Tokyo")
        )
        XCTAssertEqual(
            stringValue(kk_dateformat_format(fmt, epochMillis)),
            expectedStyles(dateStyle: .medium, timeStyle: .medium, locale: "en_US", timeZone: "Asia/Tokyo", epochMillis: epochMillis)
        )
    }
}
