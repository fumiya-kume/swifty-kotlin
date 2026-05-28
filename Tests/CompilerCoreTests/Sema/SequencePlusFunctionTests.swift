@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-SEQ-FN-087: `kotlin.sequences.Sequence<T>.plus` の Sema 解決を検証する。
final class SequencePlusFunctionTests: XCTestCase {
    func testSequencePlusMemberCallResolvesToRuntimeABI() throws {
        let source = """
        fun probe(values: Sequence<Int>) {
            val combined: Sequence<Int> = values.plus(sequenceOf(3, 4))
            println(combined)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected Sequence.plus member call to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "plus"
            }, "Expected Sequence.plus member call")

            let memberFQName = [
                "kotlin", "sequences", "Sequence", "plus",
            ].map(ctx.interner.intern)
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(
                links.contains("kk_sequence_plus"),
                "Expected Sequence.plus to link to kk_sequence_plus, got: \(links)"
            )

            // 戻り型は Sequence<Int> (= レシーバ) のまま保たれる。
            let callType = try XCTUnwrap(sema.bindings.exprType(for: callExpr))
            guard case .classType(let classType) = sema.types.kind(of: callType) else {
                return XCTFail("Expected plus() result to be a class type, got: \(sema.types.kind(of: callType))")
            }
            let sequencesFQ = ["kotlin", "sequences", "Sequence"].map(ctx.interner.intern)
            let classSymbol = try XCTUnwrap(sema.symbols.symbol(classType.classSymbol))
            XCTAssertEqual(
                classSymbol.fqName,
                sequencesFQ,
                "Expected receiver to be kotlin.sequences.Sequence"
            )
            XCTAssertEqual(classType.args.count, 1, "Expected Sequence<T> to be parameterized with one argument")
            switch classType.args[0] {
            case .out(let elementType), .invariant(let elementType):
                XCTAssertEqual(elementType, sema.types.intType)
            default:
                XCTFail("Expected covariant or invariant element type, got: \(classType.args[0])")
            }
        }
    }

    func testSequencePlusOperatorResolvesToRuntimeABI() throws {
        let source = """
        fun probe(values: Sequence<Int>): Sequence<Int> {
            return values + sequenceOf(3, 4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected Sequence + Sequence operator to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = [
                "kotlin", "sequences", "Sequence", "plus",
            ].map(ctx.interner.intern)
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(
                links.contains("kk_sequence_plus"),
                "Expected Sequence + Sequence operator to resolve to kk_sequence_plus, got: \(links)"
            )
        }
    }
}
