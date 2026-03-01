@testable import Runtime
import XCTest

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

final class RuntimePrintlnTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func capturePrintln(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(STDOUT_FILENO)
        fflush(stdout)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        block()
        fflush(stdout)
        dup2(savedFD, STDOUT_FILENO)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func testPrintlnNilPrintsZero() {
        let output = capturePrintln { kk_println_any(nil) }
        XCTAssertEqual(output, "0")
    }

    func testPrintlnNullSentinelPrintsNull() {
        let sentinel = UnsafeMutableRawPointer(bitPattern: Int(Int64.min))
        let output = capturePrintln { kk_println_any(sentinel) }
        XCTAssertEqual(output, "null")
    }

    func testPrintlnSmallIntPrintsValue() {
        let ptr = UnsafeMutableRawPointer(bitPattern: 42)
        let output = capturePrintln { kk_println_any(ptr) }
        XCTAssertEqual(output, "42")
    }
}
