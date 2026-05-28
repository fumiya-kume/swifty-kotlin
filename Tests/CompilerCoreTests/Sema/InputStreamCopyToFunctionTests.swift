@testable import CompilerCore
import XCTest

/// STDLIB-IO-FN-013: Validates that `InputStream.copyTo(out, bufferSize)` resolves
/// through Sema for the `java.io.InputStream` receiver and produces a `Long` value.
///
/// Kotlin signature:
///   public fun InputStream.copyTo(
///       out: OutputStream,
///       bufferSize: Int = DEFAULT_BUFFER_SIZE
///   ): Long
///
/// The runtime link name exercised here is `kk_input_stream_copyTo`.
final class InputStreamCopyToFunctionTests: XCTestCase {

    // MARK: - Default bufferSize overload

    func testInputStreamCopyToWithDefaultBufferSizeResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import java.io.InputStream
        import java.io.OutputStream

        fun copy(src: File, dst: File): Long {
            val input: InputStream = src.inputStream()
            val output: OutputStream = dst.outputStream()
            return input.copyTo(output)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected InputStream.copyTo(out) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Explicit bufferSize overload

    func testInputStreamCopyToWithExplicitBufferSizeResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import java.io.InputStream
        import java.io.OutputStream

        fun copyWithBuffer(src: File, dst: File): Long {
            val input: InputStream = src.inputStream()
            val output: OutputStream = dst.outputStream()
            return input.copyTo(output, 4096)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected InputStream.copyTo(out, bufferSize) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Return type is Long

    func testInputStreamCopyToReturnTypeIsLong() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import java.io.InputStream
        import java.io.OutputStream

        fun countBytes(src: File, dst: File): Long {
            val input: InputStream = src.inputStream()
            val output: OutputStream = dst.outputStream()
            val bytesCopied: Long = input.copyTo(output)
            return bytesCopied
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected InputStream.copyTo return type Long to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
