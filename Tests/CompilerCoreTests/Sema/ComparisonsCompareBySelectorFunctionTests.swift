@testable import CompilerCore
import Foundation
import XCTest

/// Sema-level coverage for the kotlin.comparisons.compareBy(selector) function
/// (STDLIB-COMP-FN-001).
///
/// Verifies that the synthetic top-level
/// `fun <T> compareBy(selector: (T) -> Comparable<*>?): Comparator<T>`
/// is registered in the `kotlin.comparisons` package and resolves from Kotlin
/// source code that explicitly imports the function.
final class ComparisonsCompareBySelectorFunctionTests: XCTestCase {

    // MARK: - Symbol registration

    func testCompareBySelectorIsRegisteredInComparisonsPackage() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let fqName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("comparisons"),
                ctx.interner.intern("compareBy"),
            ]
            let candidates = sema.symbols.lookupAll(fqName: fqName)
            XCTAssertFalse(
                candidates.isEmpty,
                "Expected kotlin.comparisons.compareBy to be registered as a synthetic top-level function"
            )

            let externalLinks = Set(
                candidates.compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(
                externalLinks.contains("kk_comparator_from_selector"),
                "Expected at least one compareBy overload to link to kk_comparator_from_selector, got: \(externalLinks)"
            )
        }
    }

    func testCompareBySelectorOverloadHasSingleSelectorParameter() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let fqName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("comparisons"),
                ctx.interner.intern("compareBy"),
            ]
            let selectorOverloads = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes.count == 1
                    && sig.typeParameterSymbols.count == 1
                    && sig.valueParameterIsVararg == [false]
            }
            XCTAssertFalse(
                selectorOverloads.isEmpty,
                "Expected at least one single-selector compareBy overload"
            )
        }
    }

    // MARK: - Source resolution

    func testCompareBySelectorFunctionResolvesInSource() throws {
        let source = """
        import kotlin.comparisons.compareBy

        data class Person(val name: String)

        fun makeComparator(): Comparator<Person> {
            return compareBy<Person> { it.name }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected compareBy<Person> selector form to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    func testCompareBySelectorReturnsComparator() throws {
        let source = """
        import kotlin.comparisons.compareBy

        data class Item(val priority: Int)

        fun cmpItems(): Comparator<Item> = compareBy<Item> { it.priority }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { return false }
                return ctx.interner.resolve(calleeName) == "compareBy"
            }, "Expected a call to compareBy")

            let exprType = try XCTUnwrap(sema.bindings.exprTypes[callExpr])
            guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                XCTFail("Expected compareBy result to be a class type (Comparator<T>)")
                return
            }
            let symbol = try XCTUnwrap(sema.symbols.symbol(ct.classSymbol))
            XCTAssertEqual(
                symbol.fqName.map { ctx.interner.resolve($0) },
                ["kotlin", "Comparator"],
                "Expected compareBy(selector) to return kotlin.Comparator<T>"
            )
        }
    }
}
