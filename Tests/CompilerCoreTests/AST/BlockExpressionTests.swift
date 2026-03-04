@testable import CompilerCore
import Foundation
import XCTest

// MARK: - Block Expression Multi-Statement Evaluation Tests

// Covers: P5-47 — block expression with multiple statements + trailing expression
// Spec references: J6, J9, J11

// swiftlint:disable:next type_body_length
final class BlockExpressionTests: XCTestCase {
    // MARK: - AST: single expression block always produces blockExpr

    func testSingleExpressionBlockProducesBlockExprNode() throws {
        let source = """
        fun main(): Int {
            return if (true) { 42 } else { 0 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            // After removing single-expression re-parse, even { 42 } should be a blockExpr
            let foundBlockExpr = ast.arena.exprs.contains { expr in
                if case .blockExpr = expr { return true }
                return false
            }
            XCTAssertTrue(foundBlockExpr, "Expected at least one blockExpr in AST")
        }
    }

    // MARK: - if branch with multi-statement block (return pattern)

    func testIfBranchMultiStatementBlockReturnPattern() throws {
        let source = """
        fun compute(): Int {
            return if (true) {
                val a = 10
                val b = 20
                a + b
            } else {
                0
            }
        }
        fun main() = compute()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - if branch with multi-statement block and String trailing expr (return pattern)

    func testIfBranchMultiStatementBlockStringTrailingExpr() throws {
        let source = """
        fun greet(): String {
            return if (true) {
                val x = 42
                "hello"
            } else {
                "world"
            }
        }
        fun main() = greet()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - when branch with multi-statement block

    func testWhenBranchMultiStatementBlockInfersTrailingExprType() throws {
        let source = """
        fun classify(x: Int): Int {
            return when (x) {
                1 -> {
                    val a = 10
                    a + 1
                }
                else -> {
                    val b = 99
                    b
                }
            }
        }
        fun main() = classify(1)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - try/catch with multi-statement block

    func testTryCatchMultiStatementBlockInfersTrailingExprType() throws {
        let source = """
        fun compute(): Int {
            return try {
                val x = 1
                val y = 2
                x + y
            } catch (e: Exception) {
                0
            }
        }
        fun main() = compute()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - Empty block has Unit type

    func testEmptyBlockHasUnitType() throws {
        let source = """
        fun doNothing(): Unit {
            if (true) {
            } else {
            }
        }
        fun main() = doNothing()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - Block expression with only declarations (no trailing expr -> Unit)

    func testBlockWithOnlyDeclarationsHasUnitType() throws {
        let source = """
        fun main(): Unit {
            if (true) {
                val x = 42
                val y = 99
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - Multi-statement block with three val declarations and trailing expr

    func testThreeValDeclarationsAndTrailingExpr() throws {
        let source = """
        fun compute(): Int {
            return if (true) {
                val a = 1
                val b = 2
                val c = 3
                a + b + c
            } else {
                0
            }
        }
        fun main() = compute()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - Multi-statement block with var reassignment (return pattern)

    func testMultiStatementBlockWithVarReassignment() throws {
        let source = """
        fun compute(): Int {
            return if (true) {
                var x = 10
                x = x + 5
                x
            } else {
                0
            }
        }
        fun main() = compute()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - if branch with single val and trailing expr (return pattern)

    func testIfBranchSingleValAndTrailingExpr() throws {
        let source = """
        fun compute(): Int {
            return if (true) {
                val x = 42
                x
            } else {
                0
            }
        }
        fun main() = compute()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - try/catch both branches with multi-statement blocks

    func testTryCatchBothBranchesMultiStatement() throws {
        let source = """
        fun compute(): Int {
            return try {
                val a = 10
                val b = 20
                a + b
            } catch (e: Exception) {
                val fallback = -1
                fallback
            }
        }
        fun main() = compute()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - when expression-body with multi-statement branches

    func testWhenExpressionBodyMultiStatementBranches() throws {
        let source = """
        fun classify(x: Int): Int = when (x) {
            1 -> {
                val base = 100
                base + x
            }
            2 -> {
                val multiplier = 10
                multiplier * x
            }
            else -> {
                val fallback = -1
                fallback
            }
        }
        fun main() = classify(2)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
        }
    }

    // MARK: - AST structure: blockExpr has statements and trailing expression

    func testBlockExprASTStructure() throws {
        let source = """
        fun compute(): Int {
            return if (true) {
                val a = 10
                a + 1
            } else {
                0
            }
        }
        fun main() = compute()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            // Find a blockExpr with non-empty statements and a trailing expression
            var foundMultiStmtBlock = false
            for expr in ast.arena.exprs {
                if case let .blockExpr(stmts, trailing, _) = expr,
                   !stmts.isEmpty, trailing != nil
                {
                    foundMultiStmtBlock = true
                    break
                }
            }
            XCTAssertTrue(foundMultiStmtBlock, "Expected a blockExpr with statements and trailing expression")
        }
    }
}
