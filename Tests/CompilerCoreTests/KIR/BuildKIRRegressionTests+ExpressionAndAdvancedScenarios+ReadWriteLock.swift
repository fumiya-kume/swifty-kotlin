@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testReadWriteLockReadLowersToThrowingRuntimeCallWithoutContinuation() throws {
        let source = """
        import java.util.concurrent.locks.ReentrantReadWriteLock
        import kotlin.concurrent.read

        fun main(lock: ReentrantReadWriteLock, base: Int): Int {
            return lock.read { base + 1 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected read() lowering sample to compile without diagnostics.")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_reentrant_read_write_lock_read"))

            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            XCTAssertEqual(
                throwFlags["kk_reentrant_read_write_lock_read"]?.allSatisfy { $0 },
                true,
                "kk_reentrant_read_write_lock_read should be lowered as throwing"
            )

            guard let readCall = body.first(where: { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "kk_reentrant_read_write_lock_read"
            }) else {
                XCTFail("Expected a call to kk_reentrant_read_write_lock_read.")
                return
            }

            guard case let .call(_, _, arguments, _, canThrow, _, _, _) = readCall else {
                XCTFail("Expected a call instruction for kk_reentrant_read_write_lock_read.")
                return
            }
            XCTAssertEqual(arguments.count, 3, "The read() lowering should pass receiver, fnPtr, and closureRaw only.")
            XCTAssertTrue(canThrow, "The read() lowering should be marked throwing.")
        }
    }
}
