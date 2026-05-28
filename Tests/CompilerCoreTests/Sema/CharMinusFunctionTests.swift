@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-038: Validates that the `kotlin.text.minus` operator overloads
/// on `Char` resolve through Sema and link to the correct runtime symbols:
///   - `operator fun Char.minus(other: Char): Int`  →  `kk_char_minus`
///   - `operator fun Char.minus(n: Int): Char`      →  `kk_char_minus_int`
final class CharMinusFunctionTests: XCTestCase {

    // MARK: - Type-check tests (Char.minus(Char): Int)

    func testCharMinusCharResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun charDiff(a: Char, b: Char): Int {
            return a.minus(b)
        }

        fun charDiffLiteral(): Int {
            return 'z'.minus('a')
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.minus(Char) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharMinusCharReturnsInt() throws {
        let ctx = makeContextFromSource("""
        fun charDiff(a: Char, b: Char): Int {
            return a.minus(b)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.minus(Char): Int to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Type-check tests (Char.minus(Int): Char)

    func testCharMinusIntResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun shiftChar(ch: Char, n: Int): Char {
            return ch.minus(n)
        }

        fun shiftCharLiteral(): Char {
            return 'e'.minus(4)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.minus(Int) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharMinusIntReturnsChar() throws {
        let ctx = makeContextFromSource("""
        fun shiftBack(ch: Char): Char {
            return ch.minus(1)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.minus(Int): Char to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Runtime link tests

    func testCharMinusCharLinksToRuntimeSymbol() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "minus"].map { interner.intern($0) }
        let charType = sema.types.charType
        let intType = sema.types.intType

        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == charType
                    && signature.parameterTypes == [charType]
                    && signature.returnType == intType
            },
            "Expected Char.minus(Char): Int to be registered as a synthetic extension"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_char_minus",
            "Char.minus(Char) must link to kk_char_minus"
        )
    }

    func testCharMinusIntLinksToRuntimeSymbol() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "minus"].map { interner.intern($0) }
        let charType = sema.types.charType
        let intType = sema.types.intType

        let symbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == charType
                    && signature.parameterTypes == [intType]
                    && signature.returnType == charType
            },
            "Expected Char.minus(Int): Char to be registered as a synthetic extension"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_char_minus_int",
            "Char.minus(Int) must link to kk_char_minus_int"
        )
    }
}
