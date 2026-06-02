@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-010: Validates that `Char.isJavaIdentifierStart()` resolves
/// through Sema for plain Char receivers as well as literal and branch contexts.
/// The runtime link involved is `kk_char_isJavaIdentifierStart` (see
/// `Sources/Runtime/RuntimeChar.swift`).
final class CharIsJavaIdentifierStartFunctionTests: XCTestCase {
    func testCharIsJavaIdentifierStartResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun javaIdentStartCheck(ch: Char): Boolean {
            return ch.isJavaIdentifierStart()
        }

        fun javaIdentStartCheckLetter(): Boolean {
            return 'A'.isJavaIdentifierStart()
        }

        fun javaIdentStartCheckUnderscore(): Boolean {
            return '_'.isJavaIdentifierStart()
        }

        fun javaIdentStartCheckIfBranch(ch: Char): Int {
            return if (ch.isJavaIdentifierStart()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isJavaIdentifierStart() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharIsJavaIdentifierStartResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "isJavaIdentifierStart"].map { ctx.interner.intern($0) }
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
                "Char.isJavaIdentifierStart() should return Boolean"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_char_isJavaIdentifierStart")
    }
}
