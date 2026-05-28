@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-006: Validates that `Char.isHighSurrogate()` resolves through
/// Sema for plain Char receivers as well as literal / branch contexts. The runtime
/// link involved is `kk_char_isHighSurrogate` (see `Sources/Runtime/RuntimeChar.swift`).
final class CharIsHighSurrogateFunctionTests: XCTestCase {
    func testCharIsHighSurrogateResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun highSurrogateCheck(ch: Char): Boolean {
            return ch.isHighSurrogate()
        }

        fun highSurrogateCheckLiteral(): Boolean {
            return 'A'.isHighSurrogate()
        }

        fun highSurrogateCheckBoundary(): Boolean {
            return '\\uD800'.isHighSurrogate()
        }

        fun highSurrogateCheckIfBranch(ch: Char): Int {
            return if (ch.isHighSurrogate()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isHighSurrogate() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharIsHighSurrogateResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "isHighSurrogate"].map { ctx.interner.intern($0) }
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
                "Char.isHighSurrogate() should return Boolean"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_char_isHighSurrogate")
    }
}
