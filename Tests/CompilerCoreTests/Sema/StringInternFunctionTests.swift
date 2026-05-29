@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-026: Validates that `String.intern()` is exposed as a
/// synthetic kotlin.text extension and resolves through Sema.
final class StringInternFunctionTests: XCTestCase {
    func testStringInternSyntheticFunctionIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let internFQName = ["kotlin", "text", "intern"].map { ctx.interner.intern($0) }
        let internSymbols = sema.symbols.lookupAll(fqName: internFQName)
        let internSymbol = try XCTUnwrap(
            internSymbols.first {
                sema.symbols.externalLinkName(for: $0) == "kk_string_intern"
            },
            "kotlin.text.intern must link to kk_string_intern"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: internSymbol))
        XCTAssertEqual(signature.receiverType, sema.types.stringType)
        XCTAssertTrue(signature.parameterTypes.isEmpty)
        XCTAssertEqual(signature.returnType, sema.types.stringType)
    }

    func testStringInternResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun canonical(s: String): String {
            return s.intern()
        }

        fun literalCanonical(): String = "kotlin".intern()
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.intern() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
