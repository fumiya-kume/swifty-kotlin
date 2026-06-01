@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-IO-PATH-FN-038: Path.useLines { block }
//
// Verifies that `kotlin.io.path.Path.useLines(charset?, block)` resolves against
// the synthetic `kotlin.io.path.useLines` stub so that user code calling
// `path.useLines { lines -> ... }` (with or without a charset argument)
// compiles and type-checks correctly.

final class PathUseLinesFunctionTests: XCTestCase {

    // MARK: - Default-charset variant resolves

    func testPathUseLinesDefaultResolvesAndInfersBlockReturnType() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines

        fun main() {
            val path = Path("/dev/null")
            val count: Int = path.useLines { lines ->
                lines.count()
            }
            println(count)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.useLines { } should resolve and infer block return type: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    // MARK: - Charset variant resolves

    func testPathUseLinesCharsetVariantResolves() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.text.Charsets

        fun firstLine(path: Path): String {
            return path.useLines(Charsets.UTF_8) { lines ->
                lines.firstOrNull() ?: ""
            }
        }

        fun main() {
            println(firstLine(Path("/dev/null")))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.useLines(charset) { } should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    // MARK: - Block return type propagates to call site

    func testPathUseLinesBlockReturnTypePropagates() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines

        fun lineCount(path: Path): Int {
            val n: Int = path.useLines { lines ->
                lines.count()
            }
            return n
        }

        fun main() {
            println(lineCount(Path("/dev/null")))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.useLines block return type should propagate to call site: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
