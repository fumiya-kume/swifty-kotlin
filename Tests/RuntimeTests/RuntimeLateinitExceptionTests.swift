@testable import Runtime
import XCTest

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

final class RuntimeLateinitExceptionTests: IsolatedRuntimeXCTestCase {
    private func makeRuntimeString(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func capturePrintln(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(STDOUT_FILENO)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        block()
        fflush(nil)
        dup2(savedFD, STDOUT_FILENO)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func nominalTypeToken(for fqName: String) -> Int {
        let nominalBase: Int64 = 6
        let payloadShift: Int64 = 9
        let typeID = runtimeStableNominalTypeID(fqName: fqName)
        return Int(nominalBase | (typeID << payloadShift))
    }

    func testLateinitGetOrThrowReturnsInitializedValue() {
        var thrown = 0
        let initialized = kk_box_int(42)

        let result = kk_lateinit_get_or_throw(
            initialized,
            makeRuntimeString("name"),
            &thrown
        )

        XCTAssertEqual(result, initialized)
        XCTAssertEqual(thrown, 0)
    }

    func testLateinitGetOrThrowCreatesTypedException() {
        var thrown = 0

        let result = kk_lateinit_get_or_throw(
            runtimeNullSentinelInt,
            makeRuntimeString("name"),
            &thrown
        )

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)

        guard let ptr = UnsafeMutableRawPointer(bitPattern: thrown),
              let throwable = tryCast(ptr, to: RuntimeThrowableBox.self)
        else {
            XCTFail("Expected a RuntimeThrowableBox-compatible exception")
            return
        }

        XCTAssertEqual(
            throwable.message,
            "lateinit property name has not been initialized"
        )
        XCTAssertTrue(throwable is RuntimeUninitializedPropertyAccessExceptionBox)
    }

    func testLateinitExceptionPrintlnIncludesExceptionName() {
        var thrown = 0
        _ = kk_lateinit_get_or_throw(
            runtimeNullSentinelInt,
            makeRuntimeString("name"),
            &thrown
        )

        let rendered = capturePrintln {
            kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown))
        }

        XCTAssertEqual(
            rendered,
            "Throwable(UninitializedPropertyAccessException: lateinit property name has not been initialized)"
        )
    }

    func testLateinitExceptionMatchesExceptionHierarchyTokens() {
        var thrown = 0
        _ = kk_lateinit_get_or_throw(
            runtimeNullSentinelInt,
            makeRuntimeString("name"),
            &thrown
        )

        XCTAssertEqual(
            kk_op_is(thrown, nominalTypeToken(for: "kotlin.UninitializedPropertyAccessException")),
            1
        )
        XCTAssertEqual(
            kk_op_is(thrown, nominalTypeToken(for: "kotlin.RuntimeException")),
            1
        )
        XCTAssertEqual(
            kk_op_is(thrown, nominalTypeToken(for: "kotlin.Exception")),
            1
        )
        XCTAssertEqual(
            kk_op_is(thrown, nominalTypeToken(for: "kotlin.Throwable")),
            1
        )
    }
}
