@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-066: Validates that `CharSequence.single()` resolves through
/// Sema for String receivers across multiple call sites and links to the
/// runtime helper `kk_string_single` (see
/// `Sources/Runtime/RuntimeStringStdlib.swift`).
final class StringSingleFunctionTests: XCTestCase {
    func testStringSingleResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun singleOf(s: String): Char {
            return s.single()
        }

        fun singleOfLiteral(): Char {
            return "x".single()
        }

        fun singleInBranch(s: String, take: Boolean): Char {
            return if (take) s.single() else "y".single()
        }

        fun callsBoth(s: String): Char {
            val a = s.single()
            val b = "z".single()
            return if (a == b) a else b
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.single() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSingleNoArgOverloadResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        var resolvedReturnType: TypeID?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "single"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            resolvedReturnType = sema.symbols.functionSignature(for: symbol)?.returnType
        }
        XCTAssertEqual(resolvedLink, "kk_string_single")
        XCTAssertNotNil(resolvedReturnType, "single() should expose a return type")
    }

    func testSingleOrNullCompanionResolvesToRuntimeLink() throws {
        // Sanity check that singleOrNull stays wired alongside single, since
        // they share the same kotlin.text registration block.
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "singleOrNull"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
        }
        XCTAssertEqual(resolvedLink, "kk_string_singleOrNull")
    }
}
