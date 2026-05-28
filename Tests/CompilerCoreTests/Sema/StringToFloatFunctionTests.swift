@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-097: Validates that `String.toFloat()` resolves through Sema
/// for plain String receivers as well as literal / branch / nullable contexts.
/// The runtime link involved is `kk_string_toFloat` (see
/// `Sources/Runtime/RuntimeStringStdlib.swift`).
final class StringToFloatFunctionTests: XCTestCase {
    func testStringToFloatResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun parseFromVariable(text: String): Float {
            return text.toFloat()
        }

        fun parseFromLiteral(): Float {
            return "3.14".toFloat()
        }

        fun parseNegative(): Float {
            return "-2.5".toFloat()
        }

        fun parseInExpression(text: String): Float {
            return text.toFloat() + 1.0f
        }

        fun parseInIfBranch(text: String): Float {
            return if (text.isNotEmpty()) text.toFloat() else 0.0f
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.toFloat() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testStringToFloatResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        var resolvedReturnType: TypeID?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "toFloat"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            resolvedReturnType = sema.symbols.functionSignature(for: symbol)?.returnType
            XCTAssertEqual(
                resolvedReturnType,
                sema.types.floatType,
                "String.toFloat() should return Float"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_string_toFloat")
    }
}
