@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testNestedReturnInBothIfElseBranchesDoesNotEmitDeadEpilogue() throws {
        let source = """
        fun pick(flag: Boolean): Int {
            if (flag) {
                return 1
            } else {
                return 2
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "pick", in: module, interner: ctx.interner)

            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case let .returnValue(id) = instruction else { return nil }
                return id
            }
            // Should have exactly 2 returns: one from each branch, no spurious epilogue return
            XCTAssertEqual(returnValues.count, 2, "Expected exactly 2 returnValue instructions (then + else), got \(returnValues.count)")
        }
    }

    func testNestedReturnInWhenBranchDoesNotEmitDeadCopyInstruction() throws {
        let source = """
        fun classify(x: Int): Int {
            when (x) {
                1 -> return 10
                2 -> return 20
                else -> return 30
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "classify", in: module, interner: ctx.interner)

            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case let .returnValue(id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 3, "Expected at least 3 returnValue instructions for when-branch returns, got \(returnValues.count)")

            // Verify no dead copy follows a returnValue in the when branches
            var deadCopyAfterReturn = false
            for (index, instruction) in body.enumerated() {
                if case .returnValue = instruction {
                    var nextIndex = index + 1
                    while nextIndex < body.count {
                        if case .label = body[nextIndex] {
                            nextIndex += 1
                            continue
                        }
                        if case .copy = body[nextIndex] {
                            deadCopyAfterReturn = true
                        }
                        break
                    }
                }
            }
            XCTAssertFalse(deadCopyAfterReturn, "No dead copy should follow a returnValue in when branches")
        }
    }

    func testBlockExprStopsLoweringAfterNestedReturn() throws {
        let source = """
        fun earlyReturn(flag: Boolean): Int {
            if (flag) {
                return 42
                val x = 99
            }
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "earlyReturn", in: module, interner: ctx.interner)

            // The val x = 99 after return should not produce any const 99 in the body
            let has99 = body.contains { instruction in
                guard case let .constValue(_, value) = instruction else { return false }
                if case .intLiteral(99) = value { return true }
                return false
            }
            XCTAssertFalse(has99, "Dead code after return in block should not be lowered")
        }
    }

    func testNestedReturnInTryCatchBranchPropagatesCorrectly() throws {
        let source = """
        fun safeDivide(a: Int, b: Int): Int {
            try {
                return a / b
            } catch (e: Any) {
                return 0
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "safeDivide", in: module, interner: ctx.interner)

            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case let .returnValue(id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 2, "Expected at least 2 returnValue instructions (try body + catch), got \(returnValues.count)")

            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_throwable_is_cancellation"),
                "Try/catch lowering must guard CancellationException with runtime predicate"
            )
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            XCTAssertEqual(throwFlags["kk_throwable_is_cancellation"]?.allSatisfy { $0 == false }, true)
        }
    }

    func testIfExprLoweringUsesLabelBasedBranching() throws {
        let source = """
        fun branch(flag: Boolean): Int {
            val x = if (flag) 1 else 2
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "branch", in: module, interner: ctx.interner)
            let hasJump = body.contains { instruction in
                if case .jump = instruction { return true }
                return false
            }
            let hasLabel = body.contains { instruction in
                if case .label = instruction { return true }
                return false
            }
            XCTAssertTrue(hasJump, "if-expr lowering should use jump instructions for branching")
            XCTAssertTrue(hasLabel, "if-expr lowering should use label instructions for branching")
        }
    }

    func testWhenExprLoweringUsesLabelBasedBranching() throws {
        let source = """
        fun pick(x: Int): Int {
            return when (x) {
                1 -> 10
                2 -> 20
                else -> 0
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "pick", in: module, interner: ctx.interner)
            let labelCount = body.filter { instruction in
                if case .label = instruction { return true }
                return false
            }.count
            let jumpCount = body.filter { instruction in
                if case .jump = instruction { return true }
                return false
            }.count
            XCTAssertGreaterThanOrEqual(labelCount, 2, "when-expr should have labels for branch dispatch")
            XCTAssertGreaterThanOrEqual(jumpCount, 2, "when-expr should have jumps for branch dispatch")
        }
    }

    func testVarargNonTrailingWithNamedTailPacksCorrectly() throws {
        let source = """
        fun tagged(vararg nums: Int, tail: Int): Int = tail
        fun main() = tagged(10, 20, tail = 99)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callNames = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for non-trailing vararg, got: \(callNames)")
            XCTAssertTrue(callNames.contains("kk_array_set"), "Expected kk_array_set for non-trailing vararg, got: \(callNames)")
        }
    }

    // MARK: - if/when Control Flow (P5-51)

    func testIfExprUsesControlFlowInsteadOfSelect() throws {
        let source = """
        fun pick(flag: Boolean): Int = if (flag) 1 else 2
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "pick", in: module, interner: ctx.interner)

            // .select was removed from KIRInstruction; verify control-flow is used
            let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(labelCount, 2, "ifExpr needs at least elseLabel + endLabel")

            let jumpCount = body.filter { instruction in
                if case .jump = instruction { return true }
                if case .jumpIfEqual = instruction { return true }
                return false
            }.count
            XCTAssertGreaterThanOrEqual(jumpCount, 2, "ifExpr needs conditional + unconditional jump")
        }
    }

    func testWhenExprUsesControlFlowInsteadOfSelect() throws {
        let source = """
        fun pick(x: Int): Int = when (x) { 1 -> 10, 2 -> 20, else -> 0 }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "pick", in: module, interner: ctx.interner)

            // .select was removed from KIRInstruction; verify control-flow is used
            let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(labelCount, 3, "whenExpr with 2 branches + else needs at least 3 labels")
        }
    }
}

