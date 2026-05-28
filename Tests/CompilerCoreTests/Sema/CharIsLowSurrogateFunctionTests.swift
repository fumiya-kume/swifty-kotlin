@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-014: Validates that `Char.isLowSurrogate()` resolves through
/// Sema for plain Char receivers as well as literal / branch contexts. The
/// runtime link involved is `kk_char_isLowSurrogate` (see
/// `Sources/Runtime/RuntimeChar.swift`).
final class CharIsLowSurrogateFunctionTests: XCTestCase {
    func testCharIsLowSurrogateResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun lowSurrogateCheck(ch: Char): Boolean {
            return ch.isLowSurrogate()
        }

        fun lowSurrogateCheckLiteralLow(): Boolean {
            return '\\uDC00'.isLowSurrogate()
        }

        fun lowSurrogateCheckLiteralHigh(): Boolean {
            return '\\uD800'.isLowSurrogate()
        }

        fun lowSurrogateCheckLiteralPlain(): Boolean {
            return 'A'.isLowSurrogate()
        }

        fun lowSurrogateCheckIfBranch(ch: Char): Int {
            return if (ch.isLowSurrogate()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isLowSurrogate() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharIsLowSurrogateResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "isLowSurrogate"].map { ctx.interner.intern($0) }
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
                "Char.isLowSurrogate() should return Boolean"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_char_isLowSurrogate")
    }
}
