@testable import CompilerCore
import XCTest

final class CharIsUpperCaseFunctionTests: XCTestCase {
    func testCharIsUpperCaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun probe(ch: Char): Boolean {
            return ch.isUpperCase()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Char.isUpperCase() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testCharIsUpperCaseLinksToRuntimeStub() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fq = ["kotlin", "text", "isUpperCase"].map { ctx.interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        let charReceiverSymbol = candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == sema.types.charType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.booleanType
        }
        let symbol = try XCTUnwrap(charReceiverSymbol, "Char.isUpperCase synthetic stub should be registered")
        XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_char_isUpperCase")
    }

    func testCharIsUpperCaseResolvesAtCallSite() throws {
        let ctx = makeContextFromSource("""
        fun probe(ch: Char) {
            ch.isUpperCase()
        }
        """)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)

        let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "isUpperCase"
        }, "Expected member call to isUpperCase in AST")

        XCTAssertNotEqual(sema.bindings.exprTypes[callExpr], sema.types.errorType)
        XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.booleanType)

        let chosen = sema.bindings.callBinding(for: callExpr)?.chosenCallee
            ?? sema.bindings.identifierSymbol(for: callExpr)
        XCTAssertEqual(
            chosen.flatMap { sema.symbols.externalLinkName(for: $0) },
            "kk_char_isUpperCase"
        )
    }
}
