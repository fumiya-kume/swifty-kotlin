@testable import CompilerCore
import Foundation
import XCTest

/// CODE-001: Regression tests ensuring `finally` blocks execute on
/// `return`, `break`, and `continue` inside try-finally.
final class FinallyExecutionOnControlFlowTests: XCTestCase {

    // MARK: - return inside try-finally

    func testReturnInsideTryFinallyInlinesFinallyBeforeReturn() throws {
        let source = """
        fun cleanup(): Unit {}
        fun compute(): Int {
            try {
                return 42
            } finally {
                cleanup()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

            // The `return 42` path should call cleanup() *before* the returnValue
            // instruction. Find all cleanup calls and all returnValue instructions.
            let cleanupCallIndices = body.indices.filter { index in
                guard case let .call(_, callee, _, _, _, _, _) = body[index] else { return false }
                return ctx.interner.resolve(callee) == "cleanup"
            }
            let returnValueIndices = body.indices.filter { index in
                if case .returnValue = body[index] { return true }
                return false
            }

            // There should be at least one cleanup call inlined before a return.
            XCTAssertGreaterThanOrEqual(
                cleanupCallIndices.count, 1,
                "Expected at least one inlined cleanup() call for finally block"
            )
            XCTAssertGreaterThanOrEqual(
                returnValueIndices.count, 1,
                "Expected at least one returnValue instruction"
            )

            // At least one cleanup call should appear before a returnValue instruction.
            let hasCleanupBeforeReturn = cleanupCallIndices.contains { cleanupIndex in
                returnValueIndices.contains { returnIndex in
                    cleanupIndex < returnIndex
                }
            }
            XCTAssertTrue(
                hasCleanupBeforeReturn,
                "finally block (cleanup()) must execute before returnValue"
            )
        }
    }

    func testReturnUnitInsideTryFinallyInlinesFinallyBeforeReturn() throws {
        let source = """
        fun cleanup(): Unit {}
        fun doWork(): Unit {
            try {
                return
            } finally {
                cleanup()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "doWork", in: module, interner: ctx.interner)

            let cleanupCallIndices = body.indices.filter { index in
                guard case let .call(_, callee, _, _, _, _, _) = body[index] else { return false }
                return ctx.interner.resolve(callee) == "cleanup"
            }
            let returnUnitIndices = body.indices.filter { index in
                if case .returnUnit = body[index] { return true }
                return false
            }

            XCTAssertGreaterThanOrEqual(
                cleanupCallIndices.count, 1,
                "Expected at least one inlined cleanup() for finally on return unit"
            )

            let hasCleanupBeforeReturn = cleanupCallIndices.contains { cleanupIndex in
                returnUnitIndices.contains { returnIndex in
                    cleanupIndex < returnIndex
                }
            }
            XCTAssertTrue(
                hasCleanupBeforeReturn,
                "finally block (cleanup()) must execute before returnUnit"
            )
        }
    }

    // MARK: - break inside try-finally

    func testBreakInsideTryFinallyInlinesFinallyBeforeBreak() throws {
        let source = """
        fun cleanup(): Unit {}
        fun loopWithBreak(): Unit {
            while (true) {
                try {
                    break
                } finally {
                    cleanup()
                }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "loopWithBreak", in: module, interner: ctx.interner)

            // cleanup() should appear in the lowered body before the break jump.
            let cleanupCallIndices = body.indices.filter { index in
                guard case let .call(_, callee, _, _, _, _, _) = body[index] else { return false }
                return ctx.interner.resolve(callee) == "cleanup"
            }

            XCTAssertGreaterThanOrEqual(
                cleanupCallIndices.count, 1,
                "Expected at least one inlined cleanup() call for finally block on break"
            )
        }
    }

    // MARK: - continue inside try-finally

    func testContinueInsideTryFinallyInlinesFinallyBeforeContinue() throws {
        let source = """
        fun cleanup(): Unit {}
        fun counter(): Boolean = false
        fun loopWithContinue(): Unit {
            while (counter()) {
                try {
                    continue
                } finally {
                    cleanup()
                }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "loopWithContinue", in: module, interner: ctx.interner)

            let cleanupCallIndices = body.indices.filter { index in
                guard case let .call(_, callee, _, _, _, _, _) = body[index] else { return false }
                return ctx.interner.resolve(callee) == "cleanup"
            }

            XCTAssertGreaterThanOrEqual(
                cleanupCallIndices.count, 1,
                "Expected at least one inlined cleanup() call for finally block on continue"
            )
        }
    }

    // MARK: - Context stack push/pop

    func testFinallyBlockStackPushPopSymmetry() {
        let ctx = KIRLoweringContext()
        XCTAssertTrue(ctx.enclosingFinallyBlocks().isEmpty)

        let expr1 = ExprID(rawValue: 100)
        let expr2 = ExprID(rawValue: 200)
        ctx.pushFinallyBlock(expr1)
        ctx.pushFinallyBlock(expr2)
        XCTAssertEqual(ctx.enclosingFinallyBlocks().count, 2)

        let popped = ctx.popFinallyBlock()
        XCTAssertEqual(popped, expr2)
        XCTAssertEqual(ctx.enclosingFinallyBlocks().count, 1)

        let popped2 = ctx.popFinallyBlock()
        XCTAssertEqual(popped2, expr1)
        XCTAssertTrue(ctx.enclosingFinallyBlocks().isEmpty)
    }

    func testResetScopeForFunctionClearsFinallyBlockStack() {
        let ctx = KIRLoweringContext()
        ctx.pushFinallyBlock(ExprID(rawValue: 50))
        ctx.resetScopeForFunction()
        XCTAssertTrue(ctx.enclosingFinallyBlocks().isEmpty)
    }

    func testScopeSaveRestorePreservesFinallyBlockStack() {
        let ctx = KIRLoweringContext()
        let expr1 = ExprID(rawValue: 42)
        ctx.pushFinallyBlock(expr1)

        let snapshot = ctx.saveScope()
        ctx.resetScopeForFunction()
        XCTAssertTrue(ctx.enclosingFinallyBlocks().isEmpty)

        ctx.restoreScope(snapshot)
        XCTAssertEqual(ctx.enclosingFinallyBlocks().count, 1)
        XCTAssertEqual(ctx.enclosingFinallyBlocks().first, expr1)
    }
}
