@testable import CompilerCore
import Foundation
import XCTest

final class DataClassComponentNTests: XCTestCase {
    // Regression test for the bug reported in PR #1281 follow-up:
    // specializeComponentReturnType was applied only to inferDestructuringDeclExpr
    // but NOT to inferForDestructuringExpr, so for-loop destructuring of generic
    // Pair/tuple types still returned the raw type-parameter instead of the
    // concrete substituted type.
    func testForLoopDestructuringPairSpecializesComponentReturnType() throws {
        let source = """
        fun demo() {
            val pairs: List<Pair<String, Int>> = listOf(Pair("a", 1), Pair("b", 2))
            for ((k, v) in pairs) {
                k.length + v
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected for-loop pair destructuring to compile without sema errors, got: "
                + ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: ", ")
        )
    }

    func testComponentNUsesOwnerVisibilityForPrivateDataClass() throws {
        let source = """
        package test

        private data class Secret(val value: Int)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "DataClassComponentN")
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let componentFQName = [
                interner.intern("test"),
                interner.intern("Secret"),
                interner.intern("component1"),
            ]

            let componentSymbolID = try XCTUnwrap(sema.symbols.lookupAll(fqName: componentFQName).first)
            let componentSymbol = try XCTUnwrap(sema.symbols.symbol(componentSymbolID))

            XCTAssertEqual(componentSymbol.visibility, .private)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
