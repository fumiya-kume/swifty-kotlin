@testable import CompilerCore
import Foundation
import XCTest

/// Verifies `String?.toBoolean()` (STDLIB-TEXT-FN-087) resolves cleanly in Sema
/// for both nullable and non-null receivers and lowers through to the runtime
/// helper `kk_string_toBoolean`, which is classified as non-throwing per
/// Kotlin's specification (`null.toBoolean()` returns `false`, never throws).
final class StringToBooleanFunctionTests: XCTestCase {
    private func allMemberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { continue }
            results.append(exprID)
        }
        return results
    }

    /// Sema should accept `String?.toBoolean()` directly (no safe-call needed)
    /// because the Kotlin signature is `fun String?.toBoolean(): Boolean`.
    func testToBooleanOnNullableStringResolvesToNonNullBoolean() throws {
        let source = """
        fun parse(value: String?): Boolean {
            return value.toBoolean()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected toBoolean on String? to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "toBoolean", in: ast, interner: ctx.interner)
            XCTAssertEqual(callIDs.count, 1)
            let exprType = try XCTUnwrap(sema.bindings.exprTypes[callIDs[0]])
            XCTAssertEqual(
                exprType,
                sema.types.booleanType,
                "toBoolean should be typed as Boolean even for nullable receivers"
            )
        }
    }

    /// Receiver typed as non-null `String` should also resolve to `Boolean`.
    func testToBooleanOnNonNullStringResolves() throws {
        let source = """
        fun parse(value: String): Boolean {
            return value.toBoolean()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected toBoolean on String to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "toBoolean", in: ast, interner: ctx.interner)
            XCTAssertEqual(callIDs.count, 1)
            let exprType = try XCTUnwrap(sema.bindings.exprTypes[callIDs[0]])
            XCTAssertEqual(exprType, sema.types.booleanType)
        }
    }

    /// `toBoolean()` should lower to `kk_string_toBoolean` and be classified as
    /// non-throwing — `null.toBoolean()` is defined to return `false`, so there
    /// is no NumberFormatException equivalent that propagates out.
    func testToBooleanLowersToRuntimeHelperNonThrowing() throws {
        let source = """
        fun main() {
            val missing: String? = null
            missing.toBoolean()
            val present: String? = "TRUE"
            present.toBoolean()
            val concrete: String = "false"
            concrete.toBoolean()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            let toBooleanFlags = try XCTUnwrap(
                throwFlags["kk_string_toBoolean"],
                "Expected kk_string_toBoolean calls to appear in main()"
            )
            XCTAssertEqual(toBooleanFlags.count, 3)
            XCTAssertTrue(
                toBooleanFlags.allSatisfy { $0 == false },
                "kk_string_toBoolean must be lowered as non-throwing"
            )
        }
    }
}
