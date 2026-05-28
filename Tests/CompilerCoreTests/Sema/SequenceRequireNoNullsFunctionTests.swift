@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-SEQ-FN-098: `Sequence<T?>.requireNoNulls()` の Sema サーフェスを検証する。
/// Runtime (`kk_sequence_requireNoNulls`)、Sema 合成スタブ、CallLowerer の
/// ディスパッチは既に揃っており、ここでは `Sequence<Int?>` から
/// `Sequence<Int>` への nullable 剥がしが Sema で正しく推論されること、
/// および `kotlin.sequences.Sequence.requireNoNulls` の external link name が
/// `kk_sequence_requireNoNulls` であることを保証する。
final class SequenceRequireNoNullsFunctionTests: XCTestCase {
    func testSequenceRequireNoNullsStripsNullabilityAndResolvesRuntimeLink() throws {
        let source = """
        fun probe(values: Sequence<Int?>) {
            val result: Sequence<Int> = values.requireNoNulls()
            println(result.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected requireNoNulls to type-check cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "requireNoNulls"
            }, "Expected requireNoNulls member call in AST")

            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("requireNoNulls"),
            ]
            XCTAssertTrue(
                sema.symbols.lookupAll(fqName: fqName).contains { candidate in
                    sema.symbols.externalLinkName(for: candidate) == "kk_sequence_requireNoNulls"
                },
                "Expected Sequence.requireNoNulls synthetic member to link to kk_sequence_requireNoNulls"
            )

            // 結果型が Sequence<Int>（non-null 要素）に解決されることを軽く確認しておく。
            // 厳密な要素型までは依存せず、エクスプレッション型が存在することを assert する。
            XCTAssertNotNil(
                sema.bindings.exprType(for: callExpr),
                "Expected requireNoNulls call to have an inferred expression type"
            )
        }
    }
}
