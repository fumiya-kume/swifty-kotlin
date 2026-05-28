@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-021: Validates that `kotlin.text.titlecase` resolves through
/// Sema as a `Char` extension (Kotlin spec defines it as
/// `fun Char.titlecase(): String`). The related no-arg `titlecaseChar()`
/// overload returning `Char` is also exposed. Runtime link names involved:
/// `kk_char_titlecase` and `kk_char_titlecaseChar`.
final class CharTitlecaseFunctionTests: XCTestCase {
    func testTitlecaseResolvesOnCharLiteralReceiver() throws {
        let ctx = makeContextFromSource("""
        fun titlecaseOfLiteral(): String {
            return 'a'.titlecase()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected titlecase to type-check on a Char literal, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testTitlecaseResolvesOnCharParameterReceiver() throws {
        let ctx = makeContextFromSource("""
        fun toTitle(ch: Char): String {
            return ch.titlecase()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected titlecase to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testTitlecaseLinksToCorrectRuntimeSymbol() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let fq = ["kotlin", "text", "titlecase"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.charType
                && signature.parameterTypes.isEmpty
        }, "Char.titlecase() must be registered as a synthetic extension function")
        XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_char_titlecase")

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        XCTAssertEqual(
            signature.returnType,
            sema.types.stringType,
            "Char.titlecase() should return String per Kotlin spec"
        )
    }

    func testTitlecaseCharResolvesAndLinksToCharRuntimeSymbol() throws {
        let ctx = makeContextFromSource("""
        fun toTitleChar(ch: Char): Char {
            return ch.titlecaseChar()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected titlecaseChar to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let fq = ["kotlin", "text", "titlecaseChar"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.charType
                && signature.parameterTypes.isEmpty
        }, "Char.titlecaseChar() must be registered as a synthetic extension function")
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_char_titlecaseChar"
        )

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        XCTAssertEqual(
            signature.returnType,
            sema.types.charType,
            "Char.titlecaseChar() should return Char per Kotlin spec"
        )
    }
}
