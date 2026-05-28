@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-012: Validates that `Char.isLetterOrDigit()` resolves through Sema
/// and links to the runtime helper `kk_char_isLetterOrDigit`.
final class CharIsLetterOrDigitFunctionTests: XCTestCase {
    func testCharIsLetterOrDigitResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun probe(ch: Char): Boolean {
            return ch.isLetterOrDigit()
        }

        fun probeLiteralLetter(): Boolean {
            return 'a'.isLetterOrDigit()
        }

        fun probeLiteralDigit(): Boolean {
            return '7'.isLetterOrDigit()
        }

        fun probeLiteralNonLetterOrDigit(): Boolean {
            return '!'.isLetterOrDigit()
        }

        fun probeInBranch(ch: Char): Int {
            return if (ch.isLetterOrDigit()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isLetterOrDigit() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharIsLetterOrDigitStubHasCorrectExternalLink() throws {
        var capturedSema: SemaModule?
        var capturedInterner: StringInterner?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            capturedSema = try XCTUnwrap(ctx.sema)
            capturedInterner = ctx.interner
        }
        let sema = try XCTUnwrap(capturedSema)
        let interner = try XCTUnwrap(capturedInterner)

        let fq = ["kotlin", "text", "isLetterOrDigit"].map { interner.intern($0) }
        let sym = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            },
            "Expected synthetic kotlin.text.isLetterOrDigit extension on Char"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: sym),
            "kk_char_isLetterOrDigit"
        )
    }

    func testCharIsLetterOrDigitReturnsBoolean() throws {
        var capturedSema: SemaModule?
        var capturedInterner: StringInterner?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            capturedSema = try XCTUnwrap(ctx.sema)
            capturedInterner = ctx.interner
        }
        let sema = try XCTUnwrap(capturedSema)
        let interner = try XCTUnwrap(capturedInterner)

        let fq = ["kotlin", "text", "isLetterOrDigit"].map { interner.intern($0) }
        let sym = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            },
            "Expected synthetic kotlin.text.isLetterOrDigit extension on Char"
        )
        XCTAssertEqual(
            sema.symbols.functionSignature(for: sym)?.returnType,
            sema.types.booleanType,
            "Char.isLetterOrDigit() should return Boolean"
        )
    }
}
