@testable import CompilerCore
import XCTest

/// TYPE-103: Verify that `arrayOf()` preserves element types and that
/// array-specific members are not incorrectly resolved on `Any` receivers.
final class ArrayOfTypeSafetyTests: XCTestCase {

    // MARK: - Positive: arrayOf(1, 2).get(0) should resolve without error

    func testArrayOfIntGetResolvesWithoutError() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val x = arr.get(0)
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    func testArrayOfStringSizeResolvesWithoutError() throws {
        let source = """
        fun main() {
            val arr = arrayOf("a", "b", "c")
            val s = arr.size
            println(s)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    func testArrayOfContainsResolvesWithoutError() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val b = arr.contains(2)
            println(b)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    // MARK: - Negative: array members on Any should fail

    func testArrayGetOnAnyReceiverProducesError() throws {
        let source = """
        fun test(x: Any) {
            x.get(0)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // `get` is not a member of Any; should produce unresolved member error.
            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    func testArraySizeOnAnyReceiverProducesError() throws {
        let source = """
        fun test(x: Any) {
            x.size
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // `size` is not a member of Any; should produce unresolved member/field error.
            let hasDiag = ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0024" || $0.code == "KSWIFTK-SEMA-FIELD"
            }
            XCTAssertTrue(hasDiag, "Expected unresolved member diagnostic for .size on Any, got: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    // MARK: - Element type preservation

    func testArrayOfIntGetReturnsIntNotAny() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val x = arr.get(0)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            // Walk the main body and find `val x = arr.get(0)`, then check
            // the initializer type is Int (not Any).
            let mainBody = try XCTUnwrap(findMainBodyStatements(in: ast, interner: ctx.interner))
            var foundGetResult = false
            for exprID in mainBody {
                guard let expr = ast.arena.expr(exprID),
                      case let .localDecl(_, _, _, initializer, _, _) = expr,
                      let initializer,
                      let boundType = sema.bindings.exprType(for: initializer)
                else { continue }
                // The get(0) call on Array<Int> should return Int, not Any.
                if boundType == sema.types.intType {
                    foundGetResult = true
                }
            }
            XCTAssertTrue(foundGetResult, "Expected arr.get(0) to be typed as Int, not Any.")
        }
    }

    // MARK: - Helpers

    private func findMainBodyStatements(
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID]? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Primitive array factories

    func testIntArrayOfGetReturnsInt() throws {
        let source = """
        fun main() {
            val arr = intArrayOf(10, 20, 30)
            val x = arr.get(0)
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }
}
