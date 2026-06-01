@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-009: Validates that `Char.isJavaIdentifierPart()` resolves through
/// Sema for plain Char receivers as well as literal contexts. The runtime link is
/// `kk_char_isJavaIdentifierPart` (see `Sources/Runtime/RuntimeChar.swift`).
final class CharIsJavaIdentifierPartFunctionTests: XCTestCase {
    func testCharIsJavaIdentifierPartResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun identifierPartCheck(ch: Char): Boolean {
            return ch.isJavaIdentifierPart()
        }

        fun identifierPartLiteral(): Boolean {
            return 'A'.isJavaIdentifierPart()
        }

        fun identifierPartDigit(): Boolean {
            return '5'.isJavaIdentifierPart()
        }

        fun identifierPartUnderscore(): Boolean {
            return '_'.isJavaIdentifierPart()
        }

        fun identifierPartIfBranch(ch: Char): Int {
            return if (ch.isJavaIdentifierPart()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isJavaIdentifierPart() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharIsJavaIdentifierPartResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "isJavaIdentifierPart"].map { ctx.interner.intern($0) }
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
                "Char.isJavaIdentifierPart() should return Boolean"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_char_isJavaIdentifierPart")
    }
}
