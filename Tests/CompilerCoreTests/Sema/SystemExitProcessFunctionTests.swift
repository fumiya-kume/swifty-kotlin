@testable import CompilerCore
import XCTest

/// STDLIB-SYSTEM-FN-001: `fun exitProcess(status: Int): Nothing` is resolvable
/// from `kotlin.system` and may appear in the body of a `Nothing`-returning function.
final class SystemExitProcessFunctionTests: XCTestCase {
    func testExitProcessFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.system.exitProcess

        fun fail(): Nothing {
            exitProcess(1)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
