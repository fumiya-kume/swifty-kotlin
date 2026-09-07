@testable import Runtime
import Foundation
import Testing

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeLateinitExceptionTests {
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

    private func kk_println_any(_ value: Int) {
        __kk_print_raw(makeRuntimeString(runtimeRenderAnyForPrint(value) + "\n"))
    }

    private func kk_println_any(_ value: UnsafeMutableRawPointer?) {
        kk_println_any(Int(bitPattern: value))
    }

    @Test func lateinitGetOrThrowReturnsInitializedValue() {
        var thrown = 0
        let initialized = kk_box_int(42)

        let result = kk_lateinit_get_or_throw(
            initialized,
            makeRuntimeString("name"),
            &thrown
        )

        #expect(result == initialized)
        #expect(thrown == 0)
    }

    @Test func lateinitGetOrThrowCreatesTypedException() throws {
        var thrown = 0

        let result = kk_lateinit_get_or_throw(
            runtimeNullSentinelInt,
            makeRuntimeString("name"),
            &thrown
        )

        #expect(result == runtimeNullSentinelInt)
        #expect(thrown != 0)

        let ptr = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        let throwable = try #require(tryCast(ptr, to: RuntimeThrowableBox.self))

        #expect(throwable.message == "lateinit property name has not been initialized")
        #expect(
            runtimeThrowableBoxHasExactType(
                throwable,
                RuntimeUninitializedPropertyAccessExceptionBox.self
            )
        )
    }

    @Test func lateinitExceptionPrintlnIncludesExceptionName() {
        var thrown = 0
        _ = kk_lateinit_get_or_throw(
            runtimeNullSentinelInt,
            makeRuntimeString("name"),
            &thrown
        )

        let rendered = capturePrintln {
            kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown))
        }

        // Kotlin renders a Throwable as "<qualified class name>: <message>", so a
        // stdlib exception keeps its `kotlin.` package prefix (verified against
        // kotlinc by Scripts/diff_cases/lateinit_exception_println.kt).
        #expect(
            rendered
                == "kotlin.UninitializedPropertyAccessException: lateinit property name has not been initialized"
        )
    }

    @Test func lateinitExceptionMatchesExceptionHierarchyTokens() {
        var thrown = 0
        _ = kk_lateinit_get_or_throw(
            runtimeNullSentinelInt,
            makeRuntimeString("name"),
            &thrown
        )

        #expect(
            kk_op_is(thrown, nominalTypeToken(for: "kotlin.UninitializedPropertyAccessException")) == 1
        )
        #expect(
            kk_op_is(thrown, nominalTypeToken(for: "kotlin.RuntimeException")) == 1
        )
        #expect(
            kk_op_is(thrown, nominalTypeToken(for: "kotlin.Exception")) == 1
        )
        #expect(
            kk_op_is(thrown, nominalTypeToken(for: "kotlin.Throwable")) == 1
        )
    }
}
