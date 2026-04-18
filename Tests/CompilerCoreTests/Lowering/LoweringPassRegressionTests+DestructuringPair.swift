@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-021-BUG-01: Pair destructuring after partition() failed to lower because
// the componentN return type was the raw generic type parameter (A / B) rather than
// the concrete List<T>.  The sema phase now substitutes the receiver's class type
// arguments into the componentN signature return type so the lowered variable has
// type List<T>, making subsequent member accesses such as .size resolve correctly.

extension LoweringPassRegressionTests {
    /// Regression test for STDLIB-021-BUG-01.
    ///
    /// `val (evens, odds) = listOf(1,2,3,4).partition { it % 2 == 0 }` should
    /// lower to calls of `kk_pair_first` / `kk_pair_second` on the Pair, and
    /// the subsequent `.size` accesses on the resulting lists must lower to
    /// `kk_list_size` calls.  Before the fix the component variables were typed
    /// as raw type parameters, which caused `.size` lookup to fail.
    func testPairDestructuringAfterPartitionEmitsComponentNCalls() throws {
        let source = """
        fun main(): Int {
            val (evens, odds) = listOf(1, 2, 3, 4).partition { it % 2 == 0 }
            return evens.size + odds.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "PairDestructuringPartition",
                emit: .kirDump
            )
            try runToLowering(ctx)

            XCTAssertFalse(
                ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
                "Expected no errors, got: \(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })"
            )

            let module = try XCTUnwrap(ctx.kir, "KIR module must be present after lowering")

            // Collect all callees emitted across all functions.
            var allCallees: [String] = []
            for decl in module.arena.declarations {
                guard case let .function(function) = decl else { continue }
                allCallees.append(contentsOf: extractCallees(from: function.body, interner: ctx.interner))
            }

            // The Pair destructuring must lower to kk_pair_first / kk_pair_second.
            XCTAssertTrue(
                allCallees.contains("kk_pair_first"),
                "Expected kk_pair_first for component1(); callees: \(allCallees)"
            )
            XCTAssertTrue(
                allCallees.contains("kk_pair_second"),
                "Expected kk_pair_second for component2(); callees: \(allCallees)"
            )

            // The .size access on the resulting List<Int> variables must lower to
            // kk_list_size — only possible when the component type was correctly
            // inferred as List<Int> rather than the raw type parameter.
            XCTAssertTrue(
                allCallees.contains("kk_list_size"),
                "Expected kk_list_size for evens.size / odds.size; callees: \(allCallees)"
            )
        }
    }

    /// Verify that sema infers concrete List<Int> types for the destructured
    /// variables — not raw type parameters — so member access on `.size` does
    /// not produce any type-mismatch diagnostic.
    func testPairDestructuringAfterPartitionHasNoSemaDiagnostics() throws {
        let source = """
        fun main(): Int {
            val (evens, odds) = listOf(1, 2, 3, 4).partition { it % 2 == 0 }
            return evens.size + odds.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "PairDestructuringSema")
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
                "Expected no sema errors after partition destructuring fix, got: \(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })"
            )
        }
    }
}
