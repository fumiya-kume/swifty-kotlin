@testable import CompilerCore
import XCTest

/// STDLIB-IO-FN-004: Validates that `buffered()` and `buffered(bufferSize)` resolve
/// through Sema for the `java.io.OutputStream` receiver. The runtime is wired through
/// `kk_output_stream_buffered` and `kk_output_stream_buffered_sized`, both of which
/// return the same underlying OutputStream handle since `RuntimeOutputStreamBox`
/// already streams through an OS-level FileHandle.
///
/// Runtime link names involved:
///   - `kk_output_stream_buffered`
///   - `kk_output_stream_buffered_sized`
final class OutputStreamBufferedFunctionTests: XCTestCase {
    func testOutputStreamBufferedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import java.io.OutputStream

        fun useDefault(file: File) {
            val sink: OutputStream = file.outputStream()
            val buffered = sink.buffered()
            buffered.write(0x41)
            buffered.flush()
            buffered.close()
        }

        fun useSized(file: File) {
            val sink = file.outputStream()
            val buffered = sink.buffered(8192)
            buffered.write(0x42)
            buffered.flush()
            buffered.close()
        }

        fun chained(file: File) {
            file.outputStream().buffered().use { stream ->
                stream.write(0x43)
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected OutputStream.buffered() and buffered(bufferSize) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
