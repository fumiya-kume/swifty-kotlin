@testable import CompilerCore
import XCTest

/// STDLIB-IO-FN-003: Validates that `InputStream.buffered(bufferSize)` resolves
/// through Sema for the `java.io.InputStream` receiver and produces a
/// `java.io.BufferedInputStream` value that can be used as an `InputStream`
/// (closing, reading, .use {} etc.).
///
/// The runtime link names exercised here are `kk_input_stream_buffered_default`
/// (zero-arg overload) and `kk_input_stream_buffered` (bufferSize overload).
final class InputStreamBufferedFunctionTests: XCTestCase {

    // MARK: - Zero-arg overload

    func testInputStreamBufferedNoArgsResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.BufferedInputStream
        import java.io.File
        import java.io.InputStream

        fun open(file: File): BufferedInputStream {
            val raw: InputStream = file.inputStream()
            return raw.buffered()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected InputStream.buffered() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - bufferSize overload

    func testInputStreamBufferedWithBufferSizeResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.BufferedInputStream
        import java.io.File
        import java.io.InputStream

        fun openWithSize(file: File): BufferedInputStream {
            val raw: InputStream = file.inputStream()
            return raw.buffered(8 * 1024)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected InputStream.buffered(bufferSize) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Returned BufferedInputStream usable as InputStream

    func testBufferedInputStreamFlowsThroughInputStreamSurface() throws {
        // BufferedInputStream extends InputStream, so all read/skip/available/close
        // methods on InputStream remain callable via the buffered handle, and
        // .use { } works because InputStream is a Closeable subtype.
        let ctx = makeContextFromSource("""
        import java.io.BufferedInputStream
        import java.io.File
        import java.io.InputStream

        fun consume(file: File): Int {
            val buffered: BufferedInputStream = file.inputStream().buffered()
            val byte: Int = buffered.read()
            val remaining: Int = buffered.available()
            buffered.close()
            return byte + remaining
        }

        fun useIt(file: File): Int {
            return file.inputStream().buffered(4096).use { stream ->
                stream.read()
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected BufferedInputStream to be usable as an InputStream, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
