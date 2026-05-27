@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-107: Validates that `Sequence<T>.single` resolves through Sema
/// and gets wired to the runtime entry point `kk_sequence_single`. The synthetic
/// surface signature is `single(): T` and the call is marked as throwing because
/// the operation panics when the sequence is empty or contains more than one
/// element.
final class SequenceSingleFunctionTests: XCTestCase {
    func testSequenceSingleResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun onlyInt(): Int {
            return sequenceOf(42).single()
        }

        fun onlyString(): String {
            return sequenceOf("only").single()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.single to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSequenceSingleLinksToRuntimeEntryPoint() throws {
        let source = """
        fun probe(): Int {
            return sequenceOf(7).single()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Sequence.single surface to resolve cleanly, got: \(diagnosticSummary)"
        )

        let sema = try XCTUnwrap(ctx.sema)
        let memberFQName = ["kotlin", "sequences", "Sequence", "single"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_sequence_single"),
            "Expected Sequence.single to link to kk_sequence_single, got: \(links)"
        )
    }

    func testSequenceSingleReturnsElementType() throws {
        let source = """
        fun probe(values: Sequence<String>): String {
            return values.single()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence<String>.single to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "single"
        }, "Expected single member call")
        XCTAssertEqual(sema.bindings.exprType(for: callExpr), sema.types.stringType)
    }
}
