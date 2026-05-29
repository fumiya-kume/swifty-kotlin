@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-007: Validates that `kotlin.text.isISOControl` resolves
/// through Sema as a Char extension (Kotlin spec defines it as
/// `fun Char.isISOControl(): Boolean`). The runtime link name involved is
/// `kk_char_isISOControl` (see `Sources/Runtime/RuntimeChar.swift`).
final class CharIsISOControlFunctionTests: XCTestCase {
    func testIsISOControlResolvesOnCharLiteralReceiver() throws {
        let ctx = makeContextFromSource("""
        fun isControlOfLiteral(): Boolean {
            return '\\u0000'.isISOControl()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isISOControl to type-check on a Char literal, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIsISOControlResolvesOnCharParameterReceiver() throws {
        let ctx = makeContextFromSource("""
        fun isControl(ch: Char): Boolean {
            return ch.isISOControl()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isISOControl to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIsISOControlResolvesInBranch() throws {
        let ctx = makeContextFromSource("""
        fun controlClassify(ch: Char): Int {
            return if (ch.isISOControl()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isISOControl to type-check in an if-branch, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIsISOControlLinksToRuntimeStub() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fq = ["kotlin", "text", "isISOControl"].map { ctx.interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        let charReceiverSymbol = candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == sema.types.charType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.booleanType
        }
        let symbol = try XCTUnwrap(charReceiverSymbol, "Char.isISOControl synthetic stub should be registered")
        XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_char_isISOControl")
    }

    func testIsISOControlResolvesAtCallSite() throws {
        let ctx = makeContextFromSource("""
        fun probe(ch: Char) {
            ch.isISOControl()
        }
        """)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)

        let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "isISOControl"
        }, "Expected member call to isISOControl in AST")

        XCTAssertNotEqual(sema.bindings.exprTypes[callExpr], sema.types.errorType)
        XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.booleanType)

        let chosen = sema.bindings.callBinding(for: callExpr)?.chosenCallee
            ?? sema.bindings.identifierSymbol(for: callExpr)
        XCTAssertEqual(
            chosen.flatMap { sema.symbols.externalLinkName(for: $0) },
            "kk_char_isISOControl"
        )
    }
}
