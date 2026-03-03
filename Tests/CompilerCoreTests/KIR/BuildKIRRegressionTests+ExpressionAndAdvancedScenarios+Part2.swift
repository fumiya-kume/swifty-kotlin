@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testIfExprSideEffectsDoNotLeakFromUnselectedBranch() throws {
        let source = """
        fun sideEffect(x: Int): Int = x
        fun test(flag: Boolean): Int {
            if (flag) sideEffect(1) else sideEffect(2)
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "test", in: module, interner: ctx.interner)

            // .select was removed; verify control flow guards side-effect branches
            let sideEffectCalls = body.filter { instruction in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee) == "sideEffect"
            }
            XCTAssertEqual(sideEffectCalls.count, 2, "Both branches should have sideEffect calls in IR")

            let jumpIfEqualCount = body.filter { if case .jumpIfEqual = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(jumpIfEqualCount, 1, "Condition should guard branch entry via jumpIfEqual")
        }
    }

    func testIfExprReturnInUnselectedBranchDoesNotLeak() throws {
        let source = """
        fun earlyReturn(flag: Boolean): Int {
            val result = if (flag) return 42 else 0
            return result
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "earlyReturn", in: module, interner: ctx.interner)

            // .select was removed; return-in-branch uses control flow with labels/jumps
            let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(labelCount, 2, "return-in-branch needs labels for control flow")

            let hasReturnValue = body.contains { if case .returnValue = $0 { return true }; return false }
            XCTAssertTrue(hasReturnValue, "Branch with return 42 should emit returnValue")
        }
    }

    func testWhenExprSideEffectsDoNotLeakFromUnselectedBranch() throws {
        let source = """
        fun effect(x: Int): Int = x
        fun test(v: Int): Int = when (v) { 1 -> effect(10), 2 -> effect(20), else -> effect(30) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "test", in: module, interner: ctx.interner)

            // .select was removed; verify control flow guards side-effect branches
            let effectCalls = body.filter { instruction in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee) == "effect"
            }
            XCTAssertEqual(effectCalls.count, 3, "All 3 branches should have effect calls in IR")

            let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(labelCount, 3, "Each branch needs labels for control flow")
        }
    }

    func testTryCatchFinallyLoweringUsesOrderedTypeDispatchAndThrownSlotRouting() throws {
        let source = """
        class MyErr

        fun bodyCall(x: Int): Int = x
        fun catchCall(x: Int): Int = x + 1
        fun finallyCall(): Int = 0

        fun demo(v: Int): Int {
            return try {
                bodyCall(v)
            } catch (e: Int) {
                catchCall(e)
            } catch (e: MyErr) {
                7
            } finally {
                finallyCall()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let module = try XCTUnwrap(ctx.kir)

            let tryExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .tryExpr = expr {
                    return true
                }
                return false
            })
            guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                XCTFail("Expected try expression in demo.")
                return
            }
            XCTAssertEqual(catchClauses.count, 2)

            let catchBindings = try catchClauses.map { clause in
                try XCTUnwrap(sema.bindings.catchClauseBinding(for: clause.body))
            }
            XCTAssertNotEqual(catchBindings[0].parameterSymbol, .invalid)
            XCTAssertNotEqual(catchBindings[1].parameterSymbol, .invalid)

            let body = try findKIRFunctionBody(named: "demo", in: module, interner: ctx.interner)

            let matcherCalls = body.compactMap { instruction -> KIRInstruction? in
                guard case let .call(_, callee, arguments, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "kk_catch_type_matches"
                else {
                    return nil
                }
                _ = arguments
                return instruction
            }
            XCTAssertTrue(matcherCalls.isEmpty, "Try-catch lowering should not require runtime matcher helper calls.")

            let labelPositions: [Int32: Int] = body.enumerated().reduce(into: [:]) { partial, entry in
                if case let .label(labelID) = entry.element {
                    partial[labelID] = entry.offset
                }
            }

            func thrownEdge(for calleeName: String) -> (callIndex: Int, thrownSlot: KIRExprID, typeSlot: KIRExprID, target: Int32)? {
                guard let callIndex = body.firstIndex(where: { instruction in
                    guard case let .call(_, callee, _, _, _, _, _) = instruction else {
                        return false
                    }
                    return ctx.interner.resolve(callee) == calleeName
                }) else {
                    return nil
                }
                guard case let .call(_, _, _, _, _, thrownResult?, _) = body[callIndex] else {
                    return nil
                }
                let tokenConstIndex = callIndex + 1
                let tokenCopyIndex = callIndex + 2
                let jumpIndex = callIndex + 3
                guard body.indices.contains(tokenConstIndex),
                      body.indices.contains(tokenCopyIndex),
                      body.indices.contains(jumpIndex),
                      case let .constValue(unknownTypeToken, .intLiteral(0)) = body[tokenConstIndex],
                      case .copy(from: unknownTypeToken, to: let typeSlot) = body[tokenCopyIndex],
                      case let .jumpIfNotNull(value, target) = body[jumpIndex],
                      value == thrownResult
                else {
                    return nil
                }
                return (callIndex, thrownResult, typeSlot, target)
            }

            guard let bodyEdge = thrownEdge(for: "bodyCall"),
                  let catchEdge = thrownEdge(for: "catchCall"),
                  let finallyEdge = thrownEdge(for: "finallyCall")
            else {
                XCTFail("Expected throw-aware edges for body/catch/finally calls.")
                return
            }

            XCTAssertEqual(bodyEdge.thrownSlot, catchEdge.thrownSlot)
            XCTAssertEqual(bodyEdge.thrownSlot, finallyEdge.thrownSlot)
            XCTAssertEqual(bodyEdge.typeSlot, catchEdge.typeSlot)
            XCTAssertEqual(bodyEdge.typeSlot, finallyEdge.typeSlot)
            let sharedExceptionSlot = bodyEdge.thrownSlot
            let sharedExceptionTypeSlot = bodyEdge.typeSlot

            guard let bodyDispatchPos = labelPositions[bodyEdge.target],
                  let finallyEntryPos = labelPositions[catchEdge.target],
                  let rethrowPos = labelPositions[finallyEdge.target]
            else {
                XCTFail("Expected target labels for body/catch/finally throw edges.")
                return
            }
            XCTAssertLessThan(bodyDispatchPos, finallyEntryPos, "Body exceptions should route to catch dispatch before finally.")
            XCTAssertLessThan(finallyEntryPos, rethrowPos, "Finally exceptions should route directly to outer rethrow.")
            XCTAssertNotEqual(bodyEdge.target, catchEdge.target)
            XCTAssertNotEqual(catchEdge.target, finallyEdge.target)

            let typeComparisons = body.enumerated().compactMap { index, instruction -> (index: Int, typeToken: Int64)? in
                guard case .binary(op: .equal, lhs: let lhs, rhs: let rhs, result: _) = instruction,
                      lhs == sharedExceptionTypeSlot,
                      case let .intLiteral(token)? = module.arena.expr(rhs)
                else {
                    return nil
                }
                return (index, token)
            }
            let expectedTypeTokens = catchBindings.map { Int64($0.parameterType.rawValue) }
            XCTAssertEqual(typeComparisons.count, expectedTypeTokens.count, "Expected one type comparison per catch clause.")
            XCTAssertEqual(typeComparisons.map(\.typeToken), expectedTypeTokens)
            guard typeComparisons.count == expectedTypeTokens.count else {
                return
            }

            guard body.indices.contains(typeComparisons[0].index + 1),
                  case let .jumpIfEqual(_, _, firstMismatchTarget) = body[typeComparisons[0].index + 1],
                  let firstMismatchLabelPos = labelPositions[firstMismatchTarget]
            else {
                XCTFail("Expected mismatch branch after first catch matcher.")
                return
            }
            XCTAssertLessThan(firstMismatchLabelPos, typeComparisons[1].index, "First catch mismatch should fall through to second catch dispatch.")

            guard body.indices.contains(typeComparisons[1].index + 1),
                  case let .jumpIfEqual(_, _, unmatchedLabel) = body[typeComparisons[1].index + 1],
                  let unmatchedLabelPos = labelPositions[unmatchedLabel]
            else {
                XCTFail("Expected unmatched-catch branch after last matcher.")
                return
            }
            let unmatchedJumpIndex = body.index(after: unmatchedLabelPos)
            guard body.indices.contains(unmatchedJumpIndex),
                  case let .jump(unmatchedTarget) = body[unmatchedJumpIndex]
            else {
                XCTFail("Expected unmatched-catch path to jump to finally.")
                return
            }
            XCTAssertEqual(unmatchedTarget, catchEdge.target, "Unmatched catches must enter finally before rethrow.")

            let finallyGuardJump = body.enumerated().contains { index, instruction in
                guard index > finallyEdge.callIndex + 3,
                      case let .jumpIfNotNull(value, target) = instruction
                else {
                    return false
                }
                return value == sharedExceptionSlot && target == finallyEdge.target
            }
            XCTAssertTrue(finallyGuardJump, "Expected post-finally rethrow guard for pending exception slot.")
            XCTAssertTrue(body.contains { instruction in
                if case let .rethrow(value) = instruction {
                    return value == sharedExceptionSlot
                }
                return false
            })

            guard case let .call(_, _, catchArguments, _, _, _, _) = body[catchEdge.callIndex],
                  let firstCatchArgument = catchArguments.first
            else {
                XCTFail("Expected catchCall argument in first catch body.")
                return
            }
            XCTAssertEqual(module.arena.exprType(firstCatchArgument), catchBindings[0].parameterType)
        }
    }

    func testBuildKIRLowersObjectLiteralToGeneratedFactoryReturningRuntimeObjectEntity() throws {
        let source = """
        interface Marker
        fun make(): Marker = object : Marker {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let module = try XCTUnwrap(ctx.kir)
            let makeExprID = try XCTUnwrap(topLevelExpressionBodyExprID(
                named: "make",
                ast: ast,
                interner: ctx.interner
            ))
            let makeBody = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
            let objectFactoryCall = try XCTUnwrap(makeBody.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee).hasPrefix("kk_object_literal_")
            })

            guard case let .call(factorySymbol, callee, arguments, result, _, _, _) = objectFactoryCall else {
                XCTFail("Expected object literal to lower to generated factory call.")
                return
            }

            let generatedFactorySymbol = try XCTUnwrap(factorySymbol)
            XCTAssertGreaterThan(generatedFactorySymbol.rawValue, 0)
            XCTAssertTrue(ctx.interner.resolve(callee).hasPrefix("kk_object_literal_"))
            XCTAssertTrue(arguments.isEmpty)
            let resultExprID = try XCTUnwrap(result)
            XCTAssertEqual(module.arena.exprType(resultExprID), sema.bindings.exprTypes[makeExprID])
            if case .unit? = module.arena.expr(resultExprID) {
                XCTFail("Object literal must not lower to unit.")
            }

            let generatedFactoryDeclIndex = try XCTUnwrap(module.arena.declarations.firstIndex(where: { decl in
                guard case let .function(function) = decl else {
                    return false
                }
                return function.symbol == generatedFactorySymbol
            }))
            guard case let .function(generatedFactory) = module.arena.declarations[generatedFactoryDeclIndex] else {
                XCTFail("Expected generated object factory function declaration.")
                return
            }
            let hasAllocationRuntimeCall = generatedFactory.body.contains { instruction in
                guard case let .call(_, loweredCallee, _, _, _, _, _) = instruction else {
                    return false
                }
                let calleeName = ctx.interner.resolve(loweredCallee)
                return calleeName == "kk_alloc" || calleeName == "kk_array_new" || calleeName == "kk_object_new"
            }
            XCTAssertTrue(
                hasAllocationRuntimeCall,
                "Expected generated object factory to include allocation runtime call."
            )

            let generatedNominalDeclIndex = try XCTUnwrap(module.arena.declarations.firstIndex(where: { decl in
                guard case let .nominalType(nominal) = decl else {
                    return false
                }
                return sema.symbols.symbol(nominal.symbol) == nil
            }))

            let generatedFactoryDeclID = KIRDeclID(rawValue: Int32(generatedFactoryDeclIndex))
            let generatedNominalDeclID = KIRDeclID(rawValue: Int32(generatedNominalDeclIndex))
            let fileDeclIDs = Set(module.files.flatMap(\.decls))
            XCTAssertTrue(fileDeclIDs.contains(generatedFactoryDeclID))
            XCTAssertTrue(fileDeclIDs.contains(generatedNominalDeclID))
        }
    }

    // MARK: - Lambda / CallableRef Lowering (P5-20)
}
