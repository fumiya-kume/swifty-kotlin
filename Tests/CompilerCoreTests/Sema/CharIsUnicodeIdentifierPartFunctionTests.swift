@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-017: Validates that `Char.isUnicodeIdentifierPart` resolves
/// through Sema for plain Char receivers and literal contexts. The runtime link
/// involved is `kk_char_isUnicodeIdentifierPart`
/// (see `Sources/Runtime/RuntimeChar.swift`).
final class CharIsUnicodeIdentifierPartFunctionTests: XCTestCase {
    func testCharIsUnicodeIdentifierPartResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun identifierPartCheck(ch: Char): Boolean {
            return ch.isUnicodeIdentifierPart()
        }

        fun identifierPartCheckLiteral(): Boolean {
            return 'a'.isUnicodeIdentifierPart()
        }

        fun identifierPartCheckIfBranch(ch: Char): Int {
            return if (ch.isUnicodeIdentifierPart()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isUnicodeIdentifierPart() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharIsUnicodeIdentifierPartResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "isUnicodeIdentifierPart"].map { ctx.interner.intern($0) }
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
                "Char.isUnicodeIdentifierPart() should return Boolean"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_char_isUnicodeIdentifierPart")
    }
}
