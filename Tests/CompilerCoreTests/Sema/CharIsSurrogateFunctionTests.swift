@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-015: Validates that `Char.isSurrogate()` resolves through
/// Sema for plain Char receivers as well as literal / branch contexts. The
/// runtime link involved is `kk_char_isSurrogate` (see
/// `Sources/Runtime/RuntimeChar.swift`), which returns true for the entire
/// surrogate range `[0xD800, 0xDFFF]`.
final class CharIsSurrogateFunctionTests: XCTestCase {
    func testCharIsSurrogateResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun surrogateCheck(ch: Char): Boolean {
            return ch.isSurrogate()
        }

        fun surrogateCheckHighLiteral(): Boolean {
            return '\\uD800'.isSurrogate()
        }

        fun surrogateCheckLowLiteral(): Boolean {
            return '\\uDFFF'.isSurrogate()
        }

        fun surrogateCheckNonSurrogate(): Boolean {
            return 'A'.isSurrogate()
        }

        fun surrogateCheckIfBranch(ch: Char): Int {
            return if (ch.isSurrogate()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isSurrogate() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharIsSurrogateResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "isSurrogate"].map { ctx.interner.intern($0) }
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
                "Char.isSurrogate() should return Boolean"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_char_isSurrogate")
    }
}
