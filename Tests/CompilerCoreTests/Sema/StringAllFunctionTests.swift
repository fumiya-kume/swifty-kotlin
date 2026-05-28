@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-001: Validates that `CharSequence.all(predicate)` resolves
/// through Sema for String receivers and lowers to the runtime helper
/// `kk_string_all`. The synthetic surface signature is
/// `String.all(predicate: (Char) -> Boolean): Boolean`.
final class StringAllFunctionTests: XCTestCase {
    private func allMemberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { continue }
            results.append(exprID)
        }
        return results
    }

    /// Sema should accept `String.all { predicate }` with a `(Char) -> Boolean`
    /// lambda and resolve the result type to `Boolean`.
    func testStringAllResolvesAndReturnsBoolean() throws {
        let source = """
        fun allDigits(value: String): Boolean {
            return value.all { c -> c.isDigit() }
        }

        fun allUppercase(): Boolean {
            return "HELLO".all { it.isUpperCase() }
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
                "Expected String.all to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "all", in: ast, interner: ctx.interner)
            XCTAssertEqual(callIDs.count, 2, "Expected two String.all call sites")
            for callID in callIDs {
                let exprType = try XCTUnwrap(sema.bindings.exprType(for: callID))
                XCTAssertEqual(
                    exprType,
                    sema.types.booleanType,
                    "String.all should be typed as Boolean"
                )
            }
        }
    }

    /// Sema should expose `String.all` as a synthetic extension function whose
    /// external link name is `kk_string_all`.
    func testStringAllLinksToRuntimeHelper() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "all"].map { ctx.interner.intern($0) }
            let stringReceiverSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    guard signature.receiverType == sema.types.stringType,
                          signature.parameterTypes.count == 1
                    else { return false }
                    return signature.returnType == sema.types.booleanType
                },
                "Expected String.all synthetic to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: stringReceiverSymbol),
                "kk_string_all"
            )
        }
    }

    /// Lowering should emit a `kk_string_all` call site for each invocation in
    /// the source program and propagate the throw flag so that thrown
    /// exceptions from the predicate can bubble up.
    func testStringAllLowersToRuntimeHelper() throws {
        let source = """
        fun main() {
            val numeric = "123"
            numeric.all { it.isDigit() }
            val letters = "abc"
            letters.all { it.isLetter() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            let allFlags = try XCTUnwrap(
                throwFlags["kk_string_all"],
                "Expected kk_string_all call sites to appear in main()"
            )
            XCTAssertEqual(allFlags.count, 2, "Expected two kk_string_all invocations")
        }
    }
}
