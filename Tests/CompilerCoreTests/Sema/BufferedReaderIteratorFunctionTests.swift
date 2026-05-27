@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-IO-FN-022: BufferedReader.iterator()
//
// Verifies that `kotlin.io.BufferedReader.iterator()` is resolved by Sema so
// that user code calling `reader.iterator()` (or iterating with `for-in`) compiles
// against our synthetic `java.io.BufferedReader` declarations.

final class BufferedReaderIteratorFunctionTests: XCTestCase {

    // MARK: - Direct iterator() call resolves and types as Iterator<String>

    func testBufferedReaderIteratorCallResolves() throws {
        let source = """
        import java.io.File

        fun main() {
            val reader = File("/dev/null").bufferedReader()
            val iter = reader.iterator()
            if (iter.hasNext()) {
                val first: String = iter.next()
                println(first)
            }
            reader.close()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "BufferedReader.iterator() should resolve to Iterator<String>: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    // MARK: - Iterator chained with hasNext/next is well-typed

    func testBufferedReaderIteratorElementsAreStrings() throws {
        let source = """
        import java.io.File

        fun firstLine(file: File): String? {
            val reader = file.bufferedReader()
            val iter = reader.iterator()
            val result: String? = if (iter.hasNext()) iter.next() else null
            reader.close()
            return result
        }

        fun main() {
            println(firstLine(File("/dev/null")))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "iter.next() on BufferedReader iterator should type as String: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    // MARK: - Used within Closeable.use { } block

    func testBufferedReaderIteratorWorksInsideUseBlock() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/dev/null").bufferedReader().use { reader ->
                val iter = reader.iterator()
                while (iter.hasNext()) {
                    println(iter.next())
                }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "BufferedReader.iterator() should resolve inside Closeable.use { } block: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
