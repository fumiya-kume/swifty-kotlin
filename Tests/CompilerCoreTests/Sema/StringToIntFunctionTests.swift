@testable import CompilerCore
import Foundation
import XCTest

/// Verifies that `kotlin.text.String.toInt()` and `String.toInt(radix:)` —
/// tracked by STDLIB-TEXT-FN-099 — are registered as synthetic stdlib stubs
/// and resolve to the correct runtime external link names at sema time.
final class StringToIntFunctionTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    /// Both `String.toInt()` and `String.toInt(radix)` must be registered with
    /// their respective runtime ABI bridges (`kk_string_toInt` and
    /// `kk_string_toInt_radix`).
    func testStringToIntStubsRegistered() throws {
        let (sema, interner) = try makeSema()

        let links = externalLinks(for: "toInt", sema: sema, interner: interner)
        XCTAssertTrue(
            links.contains("kk_string_toInt"),
            "String.toInt() should link to kk_string_toInt — got: \(links.sorted())"
        )
        XCTAssertTrue(
            links.contains("kk_string_toInt_radix"),
            "String.toInt(radix) should link to kk_string_toInt_radix — got: \(links.sorted())"
        )
    }

    /// Call expression `"42".toInt()` must resolve through sema to the
    /// `kk_string_toInt` runtime entry and produce an `Int` result.
    func testStringToIntCallResolvesToRuntimeBridge() throws {
        let source = """
        fun parse(value: String): Int {
            return value.toInt()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "toInt" && args.isEmpty
                },
                "Expected member call to toInt() in AST"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for toInt"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_toInt",
                "String.toInt() should resolve to kk_string_toInt"
            )
        }
    }

    /// Call expression `"ff".toInt(16)` must resolve to the radix-aware
    /// runtime bridge `kk_string_toInt_radix`.
    func testStringToIntRadixCallResolvesToRuntimeBridge() throws {
        let source = """
        fun parseHex(value: String): Int {
            return value.toInt(16)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "toInt" && args.count == 1
                },
                "Expected member call to toInt(radix) in AST"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for toInt(radix)"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_toInt_radix",
                "String.toInt(16) should resolve to kk_string_toInt_radix"
            )
        }
    }
}
