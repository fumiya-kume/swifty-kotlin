import Foundation
@testable import Runtime
import XCTest

final class RuntimeAdvancedLoggingTests: IsolatedRuntimeXCTestCase {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    func testFileHandlerWritesLogLine() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let logger = kk_logger_getLogger(runtimeString("demo"))
        let handler = kk_file_handler_new(runtimeString(fileURL.path))
        _ = kk_logger_addHandler(logger, handler)
        _ = kk_logger_warning(logger, runtimeString("warn"))

        let text = try String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(text, "[WARNING] demo: warn")
    }
}
