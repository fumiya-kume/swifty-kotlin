@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-008: Validates that `Char.isIdentifierIgnorable()` resolves
/// through Sema for plain Char receivers as well as literal and branch contexts.
/// The runtime link involved is `kk_char_isIdentifierIgnorable` (see
/// `Sources/Runtime/RuntimeChar.swift`).
final class CharIsIdentifierIgnorableFunctionTests: XCTestCase {
    func testCharIsIdentifierIgnorableResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun ignorableCheck(ch: Char): Boolean {
            return ch.isIdentifierIgnorable()
        }

        fun ignorableCheckLiteral(): Boolean {
            return '\\u0001'.isIdentifierIgnorable()
        }

        fun ignorableCheckIfBranch(ch: Char): Int {
            return if (ch.isIdentifierIgnorable()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isIdentifierIgnorable() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharIsIdentifierIgnorableResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "isIdentifierIgnorable"].map { ctx.interner.intern($0) }
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
                "Char.isIdentifierIgnorable() should return Boolean"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_char_isIdentifierIgnorable")
    }
}
