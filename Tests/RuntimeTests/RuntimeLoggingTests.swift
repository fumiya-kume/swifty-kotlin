import Foundation
@testable import Runtime
import XCTest

final class RuntimeLoggingTests: IsolatedRuntimeXCTestCase {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func captureStdout(_ body: () -> Void) -> String {
        let pipe = Pipe()
        let saved = dup(STDOUT_FILENO)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        body()
        fflush(nil)
        dup2(saved, STDOUT_FILENO)
        close(saved)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testLoggerInfoPrintsExpectedPrefix() {
        let logger = kk_logger_getLogger(runtimeString("demo-info"))
        let output = captureStdout {
            _ = kk_logger_info(logger, runtimeString("hello"))
        }
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "[INFO] demo-info: hello")
    }

    func testGetLoggerReturnsSameLoggerForSameName() {
        let first = kk_logger_getLogger(runtimeString("demo-singleton"))
        let second = kk_logger_getLogger(runtimeString("demo-singleton"))
        XCTAssertEqual(first, second)
    }

    func testLoggerSupportsExtendedLevelsAndThrowableFormatting() {
        let logger = kk_logger_getLogger(runtimeString("demo-levels"))
        let throwable = runtimeAllocateThrowable(message: "IllegalStateException: boom")
        let output = captureStdout {
            _ = kk_logger_log(logger, kk_logging_level_config(), runtimeString("cfg"))
            _ = kk_logger_log(logger, kk_logging_level_fine(), runtimeString("fine"))
            _ = kk_logger_log(logger, kk_logging_level_finer(), runtimeString("finer"))
            _ = kk_logger_log(logger, kk_logging_level_finest(), runtimeString("finest"))
            _ = kk_logger_log_throwable(logger, kk_logging_level_severe(), runtimeString("failed"), throwable)
        }
        XCTAssertEqual(
            output.split(separator: "\n").map(String.init),
            [
                "[CONFIG] demo-levels: cfg",
                "[FINE] demo-levels: fine",
                "[FINER] demo-levels: finer",
                "[FINEST] demo-levels: finest",
                "[SEVERE] demo-levels: failed | IllegalStateException: boom",
            ]
        )
    }
}
