@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-016: Validates that `kotlin.text.isTitleCase` resolves
/// through Sema as a Char extension (Kotlin spec defines it as
/// `fun Char.isTitleCase(): Boolean`). The runtime link name involved is
/// `kk_char_isTitleCase`.
final class CharIsTitleCaseFunctionTests: XCTestCase {
    func testIsTitleCaseResolvesOnCharLiteralReceiver() throws {
        let ctx = makeContextFromSource("""
        fun isTitleOfLiteral(): Boolean {
            return 'A'.isTitleCase()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isTitleCase to type-check on a Char literal, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIsTitleCaseResolvesOnCharParameterReceiver() throws {
        let ctx = makeContextFromSource("""
        fun isTitle(ch: Char): Boolean {
            return ch.isTitleCase()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isTitleCase to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIsTitleCaseLinksToCorrectRuntimeSymbol() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fq = ["kotlin", "text", "isTitleCase"].map { ctx.interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        let charReceiverSymbol = candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == sema.types.charType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.booleanType
        }
        let symbol = try XCTUnwrap(
            charReceiverSymbol,
            "Char.isTitleCase() synthetic stub should be registered"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_char_isTitleCase")
    }
}
