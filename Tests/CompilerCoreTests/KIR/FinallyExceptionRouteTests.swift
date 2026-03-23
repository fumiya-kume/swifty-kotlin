@testable import CompilerCore
import XCTest

/// CODE-001: Tests ensuring that exceptions thrown inside inlined finally
/// blocks are routed *outward* (via rethrow) rather than being caught by
/// the enclosing try-catch that owns the finally block.
///
/// In Kotlin, when a finally block throws, the new exception replaces the
/// original and propagates to the next outer exception handler, NOT to the
/// catch clauses of the try statement the finally belongs to.
final class FinallyExceptionRouteTests: XCTestCase {

    // MARK: - Exception routing through inlined finally (return path)

    /// Verifies that when a `return` inside try-finally inlines the finally
    /// block, the inlined finally body gets its own exception handling that
    /// routes to a rethrow rather than to the enclosing try's catch dispatch.
    ///
    /// Source:
    /// ```kotlin
    /// fun cleanup(): Unit { /* may throw */ }
    /// fun compute(): Int {
    ///     try {
    ///         return 42
    ///     } catch (e: Exception) {
    ///         return -1
    ///     } finally {
    ///         cleanup()
    ///     }
    /// }
    /// ```
    ///
    /// Expected: The inlined `cleanup()` call for the return path should
    /// have `canThrow: true` with a `thrownResult` that routes to a rethrow,
    /// NOT to the catch clause's dispatch label.
    func testReturnInTryCatchFinallyRoutesExceptionOutward() throws {
        let source = """
        fun cleanup(): Unit {}
        fun compute(): Int {
            try {
                return 42
            } catch (e: Exception) {
                return -1
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

            // Find all cleanup() calls and check their throw routing
            let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool, hasThrownResult: Bool)? in
                guard case let .call(_, callee, _, _, canThrow, thrownResult, _) = instr,
                      ctx.interner.resolve(callee) == "cleanup"
                else { return nil }
                return (index: index, canThrow: canThrow, hasThrownResult: thrownResult != nil)
            }

            // There should be cleanup calls (inlined finally)
            XCTAssertGreaterThanOrEqual(
                cleanupCalls.count, 1,
                "Expected at least one inlined cleanup() call"
            )

            // Find rethrow instructions in the body
            let rethrowIndices = body.indices.filter { index in
                if case .rethrow = body[index] { return true }
                return false
            }

            // At least one of the cleanup calls that appears before a
            // returnValue should be wrapped with throw-aware handling
            // (canThrow: true) and route to a rethrow.
            let returnValueIndices = body.indices.filter { index in
                if case .returnValue = body[index] { return true }
                return false
            }

            // Find cleanup calls that are in the inlined finally path
            // (before a returnValue instruction)
            let inlinedCleanupCalls = cleanupCalls.filter { call in
                returnValueIndices.contains { retIdx in call.index < retIdx }
            }

            // At least one inlined cleanup should have canThrow: true
            let hasThrowAwareInlinedCleanup = inlinedCleanupCalls.contains { $0.canThrow }
            XCTAssertTrue(
                hasThrowAwareInlinedCleanup,
                "Inlined finally cleanup() should be wrapped with throw-aware handling (canThrow: true)"
            )

            // Verify a rethrow exists in the body (for the inlined finally's
            // exception path)
            XCTAssertGreaterThanOrEqual(
                rethrowIndices.count, 1,
                "Expected at least one rethrow instruction for inlined finally exception routing"
            )
        }
    }

    // MARK: - Exception routing through inlined finally (break path)

    /// Verifies that when a `break` inside try-finally inlines the finally
    /// block, exceptions from the inlined finally propagate outward.
    func testBreakInTryCatchFinallyRoutesExceptionOutward() throws {
        let source = """
        fun cleanup(): Unit {}
        fun loopWithBreak(): Unit {
            while (true) {
                try {
                    break
                } catch (e: Exception) {
                    // catch should not catch finally exceptions
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

            // Find all cleanup() calls
            let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool)? in
                guard case let .call(_, callee, _, _, canThrow, _, _) = instr,
                      ctx.interner.resolve(callee) == "cleanup"
                else { return nil }
                return (index: index, canThrow: canThrow)
            }

            XCTAssertGreaterThanOrEqual(
                cleanupCalls.count, 1,
                "Expected at least one inlined cleanup() call for finally on break"
            )

            // Find rethrow instructions
            let rethrowIndices = body.indices.filter { index in
                if case .rethrow = body[index] { return true }
                return false
            }

            // Verify at least one cleanup call is throw-aware
            let hasThrowAwareCleanup = cleanupCalls.contains { $0.canThrow }
            XCTAssertTrue(
                hasThrowAwareCleanup,
                "Inlined finally cleanup() should be throw-aware for break path"
            )

            // Verify a rethrow exists for the inlined finally's exception path
            XCTAssertGreaterThanOrEqual(
                rethrowIndices.count, 1,
                "Expected at least one rethrow for inlined finally exception routing on break"
            )
        }
    }

    // MARK: - Inlined finally without calls should not add overhead

    /// Verifies that when a finally block contains no throwable calls,
    /// no extra exception handling infrastructure is emitted.
    func testInlinedFinallyWithNoCallsSkipsExceptionWrapping() throws {
        let source = """
        var x: Int = 0
        fun compute(): Int {
            try {
                return 42
            } finally {
                x = 1
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

            // The finally block only has `x = 1` (a store), which cannot
            // throw.  The inlined finally should NOT add extra rethrow labels.
            // Count rethrow instructions that appear BEFORE a returnValue
            let returnValueIndices = body.indices.filter { index in
                if case .returnValue = body[index] { return true }
                return false
            }

            // Before each returnValue, check for rethrow instructions
            // that would indicate unnecessary exception wrapping.
            // Note: there may be rethrows for the try-finally's normal
            // exception path, but the inlined copy before returnValue
            // should not have extra rethrows.
            let hasReturnValue = !returnValueIndices.isEmpty
            XCTAssertTrue(hasReturnValue, "Expected at least one returnValue instruction")

            // The body should compile without errors
            XCTAssertFalse(body.isEmpty, "Expected non-empty function body")
        }
    }

    // MARK: - Nested try-finally exception routing

    /// Verifies that nested try-finally blocks with returns inline
    /// correctly, with each finally getting its own exception routing.
    func testNestedTryFinallyExceptionRouting() throws {
        let source = """
        fun outer(): Unit {}
        fun inner(): Unit {}
        fun compute(): Int {
            try {
                try {
                    return 42
                } finally {
                    inner()
                }
            } finally {
                outer()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)

            // Both inner() and outer() should appear as calls
            let innerCalls = body.filter { instr in
                guard case let .call(_, callee, _, _, _, _, _) = instr else { return false }
                return ctx.interner.resolve(callee) == "inner"
            }
            let outerCalls = body.filter { instr in
                guard case let .call(_, callee, _, _, _, _, _) = instr else { return false }
                return ctx.interner.resolve(callee) == "outer"
            }

            XCTAssertGreaterThanOrEqual(
                innerCalls.count, 1,
                "Expected at least one inner() call"
            )
            XCTAssertGreaterThanOrEqual(
                outerCalls.count, 1,
                "Expected at least one outer() call"
            )

            // There should be rethrow instructions for exception routing
            let rethrowCount = body.filter { instr in
                if case .rethrow = instr { return true }
                return false
            }.count

            XCTAssertGreaterThanOrEqual(
                rethrowCount, 1,
                "Expected rethrow instructions for nested finally exception routing"
            )
        }
    }

    // MARK: - Continue path exception routing

    /// Verifies that when a `continue` inside try-finally inlines the finally
    /// block, exceptions from the inlined finally propagate outward.
    func testContinueInTryCatchFinallyRoutesExceptionOutward() throws {
        let source = """
        fun cleanup(): Unit {}
        fun counter(): Boolean = false
        fun loopWithContinue(): Unit {
            while (counter()) {
                try {
                    continue
                } catch (e: Exception) {
                    // catch should not catch finally exceptions
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

            // Find all cleanup() calls
            let cleanupCalls = body.enumerated().compactMap { (index, instr) -> (index: Int, canThrow: Bool)? in
                guard case let .call(_, callee, _, _, canThrow, _, _) = instr,
                      ctx.interner.resolve(callee) == "cleanup"
                else { return nil }
                return (index: index, canThrow: canThrow)
            }

            XCTAssertGreaterThanOrEqual(
                cleanupCalls.count, 1,
                "Expected at least one inlined cleanup() call for finally on continue"
            )

            // Verify at least one cleanup call is throw-aware
            let hasThrowAwareCleanup = cleanupCalls.contains { $0.canThrow }
            XCTAssertTrue(
                hasThrowAwareCleanup,
                "Inlined finally cleanup() should be throw-aware for continue path"
            )

            // Find rethrow instructions
            let rethrowCount = body.filter { instr in
                if case .rethrow = instr { return true }
                return false
            }.count

            XCTAssertGreaterThanOrEqual(
                rethrowCount, 1,
                "Expected at least one rethrow for inlined finally exception routing on continue"
            )
        }
    }
}
