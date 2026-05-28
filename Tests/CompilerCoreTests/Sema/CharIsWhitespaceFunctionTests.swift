@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-019: Validates that `Char.isWhitespace()` resolves through Sema
/// for plain Char receivers as well as literal / branch contexts. The runtime
/// link involved is `kk_char_isWhitespace` (see `Sources/Runtime/RuntimeChar.swift`).
final class CharIsWhitespaceFunctionTests: XCTestCase {
    func testCharIsWhitespaceResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun whitespaceCheck(ch: Char): Boolean {
            return ch.isWhitespace()
        }

        fun whitespaceCheckLiteral(): Boolean {
            return ' '.isWhitespace()
        }

        fun whitespaceCheckTab(): Boolean {
            return '\t'.isWhitespace()
        }

        fun whitespaceCheckNonWhitespace(): Boolean {
            return 'A'.isWhitespace()
        }

        fun whitespaceCheckIfBranch(ch: Char): Int {
            return if (ch.isWhitespace()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isWhitespace() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharIsWhitespaceResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "isWhitespace"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            XCTAssertEqual(
                sema.symbols.functionSignature(for: symbol)?.returnType,
                sema.types.booleanType,
                "Char.isWhitespace() should return Boolean"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_char_isWhitespace")
    }

    func testCharIsWhitespaceResolvesAtCallSite() throws {
        let ctx = makeContextFromSource("""
        fun probe(ch: Char) {
            ch.isWhitespace()
        }
        """)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)

        let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "isWhitespace"
        }, "Expected member call to isWhitespace in AST")

        XCTAssertNotEqual(sema.bindings.exprTypes[callExpr], sema.types.errorType)
        XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.booleanType)

        let chosen = sema.bindings.callBinding(for: callExpr)?.chosenCallee
            ?? sema.bindings.identifierSymbol(for: callExpr)
        XCTAssertEqual(
            chosen.flatMap { sema.symbols.externalLinkName(for: $0) },
            "kk_char_isWhitespace"
        )
    }
}
