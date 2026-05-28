@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-044: Validates that `CharSequence.random()` and
/// `CharSequence.random(Random)` resolve through Sema for `String` /
/// `CharSequence` receivers, dispatching to the runtime link names
/// `kk_string_random` and `kk_string_random_random`.
final class StringRandomFunctionTests: XCTestCase {
    func testRandomFunctionResolvesOnString() throws {
        let ctx = makeContextFromSource("""
        fun pickChar(s: String): Char {
            return s.random()
        }

        fun pickCharLiteral(): Char {
            return "hello".random()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected random() to type-check on String, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testRandomStringExtensionHasRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "random"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fqName)
        let noArgCandidate = candidates.first { symID in
            guard let sig = sema.symbols.functionSignature(for: symID) else { return false }
            return sig.parameterTypes.isEmpty
        }
        let symbol = try XCTUnwrap(
            noArgCandidate,
            "Expected kotlin.text.random (no-arg) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_string_random",
            "Expected random() extension to link to kk_string_random"
        )
    }

    func testRandomWithRandomExtensionHasRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "random"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fqName)
        // The random(Random) overload has one parameter type (the Random receiver arg)
        let oneArgCandidate = candidates.first { symID in
            guard let sig = sema.symbols.functionSignature(for: symID) else { return false }
            return sig.parameterTypes.count == 1
        }
        let symbol = try XCTUnwrap(
            oneArgCandidate,
            "Expected kotlin.text.random (Random) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_string_random_random",
            "Expected random(Random) extension to link to kk_string_random_random"
        )
    }

    func testRandomOrNullStringExtensionHasRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "randomOrNull"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fqName)
        let noArgCandidate = candidates.first { symID in
            guard let sig = sema.symbols.functionSignature(for: symID) else { return false }
            return sig.parameterTypes.isEmpty
        }
        let symbol = try XCTUnwrap(
            noArgCandidate,
            "Expected kotlin.text.randomOrNull (no-arg) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_string_randomOrNull",
            "Expected randomOrNull() extension to link to kk_string_randomOrNull"
        )
    }
}
