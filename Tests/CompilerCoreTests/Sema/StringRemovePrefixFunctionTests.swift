@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-050: Validates that `CharSequence.removePrefix(prefix)` resolves
/// through Sema for `String` receivers across several invocation shapes (variable,
/// literal, chained call, and conditional contexts). The synthetic stub is
/// registered in `HeaderHelpers+SyntheticStringStubs.swift` and lowered to the
/// runtime helper `kk_string_removePrefix` defined in `RuntimeStringStdlib.swift`.
final class StringRemovePrefixFunctionTests: XCTestCase {
    func testRemovePrefixResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripScheme(s: String): String {
            return s.removePrefix("https://")
        }

        fun stripFromLiteral(): String {
            return "HelloWorld".removePrefix("Hello")
        }

        fun stripFromExpression(value: Int): String {
            return value.toString().removePrefix("0")
        }

        fun stripInBranch(s: String): String {
            return if (s.removePrefix("foo").isEmpty()) "empty" else s.removePrefix("foo")
        }

        fun stripChained(s: String): String {
            return s.removePrefix("a").removePrefix("b")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected removePrefix to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// Confirms the synthetic stub for `String.removePrefix(prefix)` is registered
    /// with the expected runtime link name and `String -> String` shape.
    func testRemovePrefixResolvesToRuntimeLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "removePrefix"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes == [sema.types.stringType]
            })
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbol),
                "kk_string_removePrefix"
            )
            XCTAssertEqual(
                sema.symbols.functionSignature(for: symbol)?.returnType,
                sema.types.stringType,
                "String.removePrefix(prefix) should return String"
            )
        }
    }
}
