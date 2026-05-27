@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-SYSTEM-FN-002: `fun getTimeMicros(): Long` in kotlin.system.
///
/// Verifies the function resolves cleanly when imported in a source file.
final class SystemGetTimeMicrosFunctionTests: XCTestCase {
    func testGetTimeMicrosFunctionResolvesInSource() throws {
        let source = """
        import kotlin.system.getTimeMicros

        fun now(): Long {
            return getTimeMicros()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected kotlin.system.getTimeMicros to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "system", "getTimeMicros"].map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: fq)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(
                links.contains("kk_system_getTimeMicros"),
                "kotlin.system.getTimeMicros must link to kk_system_getTimeMicros; got: \(links)"
            )
        }
    }
}
