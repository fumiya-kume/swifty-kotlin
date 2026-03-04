@testable import CompilerCore
import Foundation
import XCTest

// swiftlint:disable:next type_body_length
final class BuildKIRRegressionTests: XCTestCase {
    func testLoadSourcesPhaseReportsMissingInputsAndUnreadableFiles() {
        let emptyCtx = makeCompilationContext(inputs: [])
        XCTAssertThrowsError(try LoadSourcesPhase().run(emptyCtx))
        XCTAssertEqual(emptyCtx.diagnostics.diagnostics.last?.code, "KSWIFTK-SOURCE-0001")

        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kt")
            .path
        let missingCtx = makeCompilationContext(inputs: [missingPath])
        XCTAssertThrowsError(try LoadSourcesPhase().run(missingCtx))
        XCTAssertEqual(missingCtx.diagnostics.diagnostics.last?.code, "KSWIFTK-SOURCE-0002")
    }

    func testRunToKIRAndLoweringRecordsAllPasses() throws {
        let source = """
        inline fun add(a: Int, b: Int) = a + b
        suspend fun susp(v: Int) = v
        fun chooser(flag: Boolean, n: Int) = when (flag) { true -> n + 1, false -> n - 1, else -> n }
        fun main() {
            add(1, 2)
            susp(3)
            chooser(true, 4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            XCTAssertEqual(module.executedLowerings, [
                "TailrecLowering",
                "NormalizeBlocks",
                "OperatorLowering",
                "ForLowering",
                "CollectionLiteralLowering",
                "PropertyLowering",
                "StdlibDelegateLowering",
                "JvmStaticLowering",
                "DataEnumSealedSynthesis",
                "LambdaClosureConversion",
                "InlineLowering",
                "CoroutineLowering",
                "ABILowering",
            ])
            // Source defines add, susp, chooser, main
            XCTAssertGreaterThanOrEqual(module.functionCount, 4)
        }
    }

    func testBuildKIRLowersStringAdditionToRuntimeConcatCall() throws {
        let source = """
        fun main() = "a" + "b"
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_string_concat"))
            XCTAssertFalse(body.contains { instruction in
                guard case let .binary(op, _, _, _) = instruction else {
                    return false
                }
                return op == .add
            })
        }
    }

    func testBuildKIRLowersUnaryOperatorsToExpectedOperations() throws {
        let source = """
        fun main(): Int {
            val x = 2
            val a = -x
            val b = +x
            if (!false) return a + b
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let binaryOps = body.compactMap { instruction -> KIRBinaryOp? in
                guard case let .binary(op, _, _, _) = instruction else {
                    return nil
                }
                return op
            }
            XCTAssertTrue(binaryOps.contains(.subtract))
            XCTAssertTrue(binaryOps.contains(.equal))
        }
    }

    func testBuildKIRLowersComparisonAndLogicalOperatorsToRuntimeCalls() throws {
        let source = """
        fun main(): Int {
            val x = 3
            val a = x != 2
            val b = x < 5
            val c = x <= 3
            val d = x > 1
            val e = x >= 3
            val f = true && false
            val g = false || true
            if (a && b && c && d && e && !f && g) return 1
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            XCTAssertTrue(callees.contains("kk_op_ne"))
            XCTAssertTrue(callees.contains("kk_op_lt"))
            XCTAssertTrue(callees.contains("kk_op_le"))
            XCTAssertTrue(callees.contains("kk_op_gt"))
            XCTAssertTrue(callees.contains("kk_op_ge"))
            XCTAssertTrue(callees.contains("kk_op_and"))
            XCTAssertTrue(callees.contains("kk_op_or"))
        }
    }

    func testBuildKIRUsesResolvedOperatorOverloadCallForBinaryExpression() throws {
        // Kotlin member functions take precedence over extensions with the same
        // signature.  Int.plus is a built-in member, so `operator fun Int.plus`
        // defined as an extension must NOT shadow the built-in `+`.
        let source = """
        operator fun Int.plus(other: Int): Int = this - other
        fun main(): Int = 7 + 3
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            // The built-in binary .add instruction should be used, not a call.
            XCTAssertTrue(body.contains { instruction in
                guard case let .binary(op, _, _, _) = instruction else {
                    return false
                }
                return op == .add
            })
            XCTAssertFalse(body.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "plus"
            })
        }
    }

    // MARK: - Member operator/member call integration (P5-19)

    func testBuildKIRUsesChosenMemberOperatorSymbolForBinaryPlusExpression() throws {
        let source = """
        class Vec {
            operator fun plus(other: Vec): Vec = this
        }
        fun useOperator(a: Vec, b: Vec): Vec = a + b
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            let operatorExprID = try XCTUnwrap(topLevelExpressionBodyExprID(
                named: "useOperator",
                ast: ast,
                interner: ctx.interner
            ))
            guard let operatorExpr = ast.arena.expr(operatorExprID),
                  case let .binary(op, _, _, _) = operatorExpr
            else {
                XCTFail("Expected useOperator body to be a binary expression.")
                return
            }
            XCTAssertEqual(op, .add)
            let resolvedBinding = try XCTUnwrap(sema.bindings.callBindings[operatorExprID])
            let chosenSymbol = resolvedBinding.chosenCallee
            let chosenSemanticSymbol = try XCTUnwrap(sema.symbols.symbol(chosenSymbol))
            XCTAssertEqual(ctx.interner.resolve(chosenSemanticSymbol.name), "plus")
            let ownerSymbolID = try XCTUnwrap(sema.symbols.parentSymbol(for: chosenSymbol))
            let ownerSymbol = try XCTUnwrap(sema.symbols.symbol(ownerSymbolID))
            XCTAssertEqual(ctx.interner.resolve(ownerSymbol.name), "Vec")
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: chosenSymbol))
            XCTAssertNotNil(signature.receiverType)
            XCTAssertEqual(sema.bindings.exprTypes[operatorExprID], signature.returnType)

            try BuildKIRPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)

            let body = try findKIRFunctionBody(named: "useOperator", in: module, interner: ctx.interner)
            let resolvedCall = try XCTUnwrap(body.first { instruction in
                guard case let .call(symbol, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == chosenSymbol
            })
            guard case let .call(callSymbol, callee, arguments, _, _, _, _) = resolvedCall else {
                XCTFail("Expected chosen call instruction for useOperator.")
                return
            }

            XCTAssertEqual(callSymbol, chosenSymbol)
            XCTAssertEqual(ctx.interner.resolve(callee), "plus")
            XCTAssertFalse(ctx.interner.resolve(callee).hasPrefix("kk_op_"))
            XCTAssertFalse(body.contains { instruction in
                guard case let .binary(op, _, _, _) = instruction else {
                    return false
                }
                return op == .add
            })
            XCTAssertFalse(body.contains { instruction in
                guard case let .call(_, callCallee, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callCallee).hasPrefix("kk_op_")
            })
            XCTAssertEqual(
                symbolNames(for: arguments, module: module, sema: sema, interner: ctx.interner),
                ["a", "b"]
            )
        }
    }

    func testBuildKIRLowersExplicitMemberCallByInsertingReceiverArgument() throws {
        let source = """
        class Vec {
            fun plus(other: Vec): Vec = this
        }
        fun useMemberCall(a: Vec, b: Vec): Vec = a.plus(b)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            let memberExprID = try XCTUnwrap(topLevelExpressionBodyExprID(
                named: "useMemberCall",
                ast: ast,
                interner: ctx.interner
            ))
            guard let memberExpr = ast.arena.expr(memberExprID),
                  case .memberCall = memberExpr
            else {
                XCTFail("Expected useMemberCall body to be a member call expression.")
                return
            }
            let resolvedBinding = try XCTUnwrap(sema.bindings.callBindings[memberExprID])
            let chosenSymbol = resolvedBinding.chosenCallee
            let chosenSemanticSymbol = try XCTUnwrap(sema.symbols.symbol(chosenSymbol))
            XCTAssertEqual(ctx.interner.resolve(chosenSemanticSymbol.name), "plus")
            let ownerSymbolID = try XCTUnwrap(sema.symbols.parentSymbol(for: chosenSymbol))
            let ownerSymbol = try XCTUnwrap(sema.symbols.symbol(ownerSymbolID))
            XCTAssertEqual(ctx.interner.resolve(ownerSymbol.name), "Vec")
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: chosenSymbol))
            XCTAssertNotNil(signature.receiverType)
            XCTAssertEqual(sema.bindings.exprTypes[memberExprID], signature.returnType)

            try BuildKIRPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)

            let body = try findKIRFunctionBody(named: "useMemberCall", in: module, interner: ctx.interner)
            let memberCall = try XCTUnwrap(body.first { instruction in
                guard case let .call(symbol, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == chosenSymbol
            })
            guard case let .call(callSymbol, callee, arguments, _, _, _, _) = memberCall else {
                XCTFail("Expected chosen call instruction for useMemberCall.")
                return
            }

            XCTAssertEqual(callSymbol, chosenSymbol)
            XCTAssertEqual(ctx.interner.resolve(callee), "plus")
            XCTAssertEqual(
                symbolNames(for: arguments, module: module, sema: sema, interner: ctx.interner),
                ["a", "b"]
            )
        }
    }

    // MARK: - Expression Variants Scenarios

    // MARK: - Reified Type Token Scenarios

    // MARK: - Default Argument Callee-Context Semantics (P5-56)

    // MARK: - Nested Return Propagation (P5-48)

    // MARK: - if/when Control Flow (P5-51)

    // MARK: - Lambda / CallableRef Lowering (P5-20)

    // MARK: - P5-39: vararg call lowering / ABI regression tests

    // MARK: - P5-42: Local function scope registration and KIR generation
}
