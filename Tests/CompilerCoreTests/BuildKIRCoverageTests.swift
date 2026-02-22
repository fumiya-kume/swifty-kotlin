import Foundation
import XCTest
@testable import CompilerCore

final class BuildKIRCoverageTests: XCTestCase {
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
                "NormalizeBlocks",
                "OperatorLowering",
                "ForLowering",
                "WhenLowering",
                "PropertyLowering",
                "DataEnumSealedSynthesis",
                "LambdaClosureConversion",
                "InlineLowering",
                "CoroutineLowering",
                "ABILowering"
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
                guard case .binary(let op, _, _, _) = instruction else {
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
                guard case .binary(let op, _, _, _) = instruction else {
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
                guard case .binary(let op, _, _, _) = instruction else {
                    return false
                }
                return op == .add
            })
            XCTAssertFalse(body.contains { instruction in
                guard case .call(_, let callee, _, _, _, _) = instruction else {
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
                  case .binary(let op, _, _, _) = operatorExpr else {
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
                guard case .call(let symbol, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == chosenSymbol
            })
            guard case .call(let callSymbol, let callee, let arguments, _, _, _) = resolvedCall else {
                XCTFail("Expected chosen call instruction for useOperator.")
                return
            }

            XCTAssertEqual(callSymbol, chosenSymbol)
            XCTAssertEqual(ctx.interner.resolve(callee), "plus")
            XCTAssertFalse(ctx.interner.resolve(callee).hasPrefix("kk_op_"))
            XCTAssertFalse(body.contains { instruction in
                guard case .binary(let op, _, _, _) = instruction else {
                    return false
                }
                return op == .add
            })
            XCTAssertFalse(body.contains { instruction in
                guard case .call(_, let callCallee, _, _, _, _) = instruction else {
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
                  case .memberCall = memberExpr else {
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
                guard case .call(let symbol, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == chosenSymbol
            })
            guard case .call(let callSymbol, let callee, let arguments, _, _, _) = memberCall else {
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

    func testThisBasedMemberCallCompilesAndUsesImplicitReceiverInLowering() throws {
        let source = """
        class Vec
        fun Vec.plus(other: Vec): Vec = this
        fun Vec.combine(other: Vec): Vec = this.plus(other)
        fun useCombine(a: Vec, b: Vec): Vec = a.combine(b)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected this-based member call program to compile without errors.")

            let module = try XCTUnwrap(ctx.kir)
            let combineFunction = try findKIRFunction(named: "combine", in: module, interner: ctx.interner)
            let plusCall = try XCTUnwrap(combineFunction.body.first { instruction in
                guard case .call(_, let callee, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "plus"
            })
            guard case .call(_, _, let arguments, _, _, _) = plusCall else {
                XCTFail("Expected combine to lower to a call to plus.")
                return
            }

            let implicitReceiverSymbol = try XCTUnwrap(combineFunction.params.first?.symbol)
            XCTAssertEqual(arguments.count, 2)
            guard case .symbolRef(let insertedReceiver)? = module.arena.expr(arguments[0]) else {
                XCTFail("Expected first argument to be a symbolRef for implicit this receiver.")
                return
            }
            XCTAssertEqual(insertedReceiver, implicitReceiverSymbol)
        }
    }

    func testABILoweringInsertsBoxingCallsForPrimitiveToAnyBoundary() throws {
        let source = """
        fun acceptAny(x: Any?) = x
        fun main() {
            acceptAny(42)
            acceptAny(true)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callNames.contains("kk_box_int"))
            XCTAssertTrue(callNames.contains("kk_box_bool"))
        }
    }

    func testABILoweringBoxingCallsAreNonThrowing() throws {
        let source = """
        fun acceptAny(x: Any?) = x
        fun main() {
            acceptAny(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let boxingThrowFlags = body.compactMap { instruction -> Bool? in
                guard case .call(_, let callee, _, _, let canThrow, _) = instruction else {
                    return nil
                }
                let name = ctx.interner.resolve(callee)
                guard name == "kk_box_int" || name == "kk_box_bool" ||
                      name == "kk_unbox_int" || name == "kk_unbox_bool" else {
                    return nil
                }
                return canThrow
            }
            XCTAssertFalse(boxingThrowFlags.isEmpty)
            XCTAssertTrue(boxingThrowFlags.allSatisfy { $0 == false })
        }
    }

    func testArrayAccessAndAssignmentLowerToRuntimeCallsWithExpectedThrowFlags() throws {
        let source = """
        fun main(): Any? {
            val arr = IntArray(2)
            arr[0] = 7
            return arr[0]
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callNames.contains("kk_array_new"))
            XCTAssertTrue(callNames.contains("kk_array_set"))
            XCTAssertTrue(callNames.contains("kk_array_get"))

            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            XCTAssertEqual(throwFlags["kk_array_new"]?.allSatisfy({ $0 == false }), true)
            XCTAssertEqual(throwFlags["kk_array_set"]?.allSatisfy({ $0 == true }), true)
            XCTAssertEqual(throwFlags["kk_array_get"]?.allSatisfy({ $0 == true }), true)
        }
    }

    func testArrayOutOfBoundsThrownChannelReturnsEarlyBeforeSubsequentReturn() throws {
        let source = """
        fun readOutOfBounds(arr: Any?): Any? = arr[5]
        fun main(): Any? {
            val arr = IntArray(1)
            readOutOfBounds(arr)
            return 99
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ArrayThrownChannel",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            let result: CommandResult
            do {
                result = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected top-level thrown channel to fail process exit.")
                return
            } catch CommandRunnerError.nonZeroExit(let failed) {
                result = failed
            } catch {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.stderr.contains("KSWIFTK-LINK-0003"))
        }
    }

    func testFrontendAndSemaResolveTypedDeclarationsAndEmitExpectedDiagnostics() throws {
        let source = """
        package typed.demo
        import typed.demo.*

        public inline suspend fun transform<T>(
            vararg values: T,
            crossinline mapper: T,
            noinline fallback: T = mapper
        ): String? = "ok"
        fun String.decorate(): String = this

        fun typed(a: Int, b: String?, c: Any): Int = 1
        fun duplicate(x: Int, x: Int): Int = x

        val explicit: Int = 1
        var delegated by delegateProvider
        val unknown: CustomType = explicit
        val explicit: Int = 2

        class TypedBox<T>(value: T)
        object Obj
        typealias Alias = String
        enum class Kind { A, B }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "Typed", emit: .kirDump)
            try runToKIR(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let declarations = ast.arena.declarations()
            XCTAssertGreaterThanOrEqual(declarations.count, 8)

            var sawTypedParameter = false
            var sawFunctionReturnType = false
            var sawFunctionReceiverType = false
            var sawExplicitPropertyType = false
            var sawDelegatedPropertyWithoutType = false

            for decl in declarations {
                switch decl {
                case .funDecl(let fn):
                    if fn.returnType != nil {
                        sawFunctionReturnType = true
                    }
                    if fn.receiverType != nil {
                        sawFunctionReceiverType = true
                    }
                    if fn.valueParams.contains(where: { $0.type != nil }) {
                        sawTypedParameter = true
                    }
                case .propertyDecl(let property):
                    if let typeID = property.type, let typeRef = ast.arena.typeRef(typeID) {
                        sawExplicitPropertyType = true
                        if case .named(let path, _, _) = typeRef {
                            XCTAssertFalse(path.isEmpty)
                        }
                    } else if ctx.interner.resolve(property.name) == "delegated" {
                        sawDelegatedPropertyWithoutType = true
                    }
                default:
                    continue
                }
            }

            XCTAssertTrue(sawTypedParameter)
            XCTAssertTrue(sawFunctionReturnType)
            XCTAssertTrue(sawFunctionReceiverType)
            XCTAssertTrue(sawExplicitPropertyType)
            XCTAssertTrue(sawDelegatedPropertyWithoutType)

            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.symbols.allSymbols().isEmpty)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
            let decorateSymbol = sema.symbols.allSymbols().first(where: { symbol in
                ctx.interner.resolve(symbol.name) == "decorate"
            })
            XCTAssertNotNil(decorateSymbol)
            if let decorateSymbol {
                let signature = sema.symbols.functionSignature(for: decorateSymbol.id)
                XCTAssertNotNil(signature?.receiverType)
            }

            let codes = Set(ctx.diagnostics.diagnostics.map(\.code))
            XCTAssertTrue(codes.contains("KSWIFTK-TYPE-0002"))
            XCTAssertTrue(codes.contains("KSWIFTK-SEMA-0001"))
        }
    }

    // MARK: - Expression Variants Coverage

    private func makeExpressionVariantsFixture() -> (
        ctx: CompilationContext,
        exprIDs: (eUnaryPlus: ExprID, eUnaryMinus: ExprID, eUnaryNot: ExprID,
                  eNe: ExprID, eLt: ExprID, eLe: ExprID,
                  eGt: ExprID, eGe: ExprID, eAnd: ExprID, eOr: ExprID)
    ) {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()

        let range = makeRange(file: FileID(rawValue: 0), start: 0, end: 1)
        let astArena = ASTArena()

        let intTypeRef = astArena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        let boolTypeRef = astArena.appendTypeRef(.named(path: [interner.intern("Boolean")], args: [], nullable: false))
        let stringTypeRef = astArena.appendTypeRef(.named(path: [interner.intern("String")], args: [], nullable: false))

        let helperName = interner.intern("helper")
        let calcName = interner.intern("calc")
        let argName = interner.intern("arg")
        let unknownName = interner.intern("unknown")

        let eInt1 = astArena.appendExpr(.intLiteral(1, range))
        let eInt2 = astArena.appendExpr(.intLiteral(2, range))
        let eBoolTrue = astArena.appendExpr(.boolLiteral(true, range))
        let eBoolFalse = astArena.appendExpr(.boolLiteral(false, range))
        let eString = astArena.appendExpr(.stringLiteral(interner.intern("s"), range))
        let eNameLocal = astArena.appendExpr(.nameRef(argName, range))
        let eNameKnown = astArena.appendExpr(.nameRef(helperName, range))
        let eNameUnknown = astArena.appendExpr(.nameRef(unknownName, range))

        let eAdd = astArena.appendExpr(.binary(op: .add, lhs: eInt1, rhs: eInt2, range: range))
        let eSub = astArena.appendExpr(.binary(op: .subtract, lhs: eInt2, rhs: eInt1, range: range))
        let eMul = astArena.appendExpr(.binary(op: .multiply, lhs: eInt1, rhs: eInt2, range: range))
        let eDiv = astArena.appendExpr(.binary(op: .divide, lhs: eInt2, rhs: eInt1, range: range))
        let eEq = astArena.appendExpr(.binary(op: .equal, lhs: eInt1, rhs: eInt2, range: range))
        let eNe = astArena.appendExpr(.binary(op: .notEqual, lhs: eInt1, rhs: eInt2, range: range))
        let eLt = astArena.appendExpr(.binary(op: .lessThan, lhs: eInt1, rhs: eInt2, range: range))
        let eLe = astArena.appendExpr(.binary(op: .lessOrEqual, lhs: eInt1, rhs: eInt2, range: range))
        let eGt = astArena.appendExpr(.binary(op: .greaterThan, lhs: eInt2, rhs: eInt1, range: range))
        let eGe = astArena.appendExpr(.binary(op: .greaterOrEqual, lhs: eInt2, rhs: eInt1, range: range))
        let eAnd = astArena.appendExpr(.binary(op: .logicalAnd, lhs: eBoolTrue, rhs: eBoolFalse, range: range))
        let eOr = astArena.appendExpr(.binary(op: .logicalOr, lhs: eBoolFalse, rhs: eBoolTrue, range: range))
        let eUnaryPlus = astArena.appendExpr(.unaryExpr(op: .unaryPlus, operand: eInt1, range: range))
        let eUnaryMinus = astArena.appendExpr(.unaryExpr(op: .unaryMinus, operand: eInt2, range: range))
        let eUnaryNot = astArena.appendExpr(.unaryExpr(op: .not, operand: eBoolFalse, range: range))

        let eCallKnown = astArena.appendExpr(.call(callee: eNameKnown, typeArgs: [], args: [CallArgument(expr: eInt1)], range: range))
        let eCallUnknown = astArena.appendExpr(.call(callee: eNameUnknown, typeArgs: [], args: [CallArgument(expr: eInt1)], range: range))
        let eCallNonName = astArena.appendExpr(.call(callee: eInt1, typeArgs: [], args: [], range: range))
        let eBreak = astArena.appendExpr(.breakExpr(range: range))
        let eContinue = astArena.appendExpr(.continueExpr(range: range))
        let eWhile = astArena.appendExpr(.whileExpr(condition: eBoolTrue, body: eBreak, range: range))
        let eDoWhile = astArena.appendExpr(.doWhileExpr(body: eContinue, condition: eBoolTrue, range: range))
        let eFor = astArena.appendExpr(.forExpr(loopVariable: interner.intern("i"), iterable: eNameUnknown, body: eInt1, range: range))

        let whenBranchTrue = WhenBranch(condition: eBoolTrue, body: eInt1, range: range)
        let whenBranchFalse = WhenBranch(condition: eBoolFalse, body: eInt2, range: range)
        let eWhenNoElse = astArena.appendExpr(.whenExpr(subject: eBoolTrue, branches: [whenBranchTrue], elseExpr: nil, range: range))
        let eWhenElse = astArena.appendExpr(.whenExpr(subject: eBoolTrue, branches: [whenBranchTrue, whenBranchFalse], elseExpr: eInt1, range: range))

        let helperDecl = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: helperName,
            modifiers: [],
            typeParams: [],
            receiverType: nil,
            valueParams: [ValueParamDecl(name: interner.intern("x"), type: intTypeRef)],
            returnType: intTypeRef,
            body: .expr(eInt1, range),
            isSuspend: false,
            isInline: false
        )))

        let calcDecl = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: calcName,
            modifiers: [.inline, .suspend],
            typeParams: [],
            receiverType: nil,
            valueParams: [ValueParamDecl(name: argName, type: intTypeRef)],
            returnType: intTypeRef,
            body: .block([
                eInt1, eBoolTrue, eString, eNameLocal, eNameKnown, eNameUnknown,
                eAdd, eSub, eMul, eDiv, eEq, eNe, eLt, eLe, eGt, eGe, eAnd, eOr, eUnaryPlus, eUnaryMinus, eUnaryNot,
                eCallKnown, eCallUnknown, eCallNonName,
                eWhenNoElse, eWhenElse, eWhile, eDoWhile, eFor
            ], range),
            isSuspend: true,
            isInline: true
        )))

        let propertyDecl = astArena.appendDecl(.propertyDecl(PropertyDecl(
            range: range,
            name: interner.intern("text"),
            modifiers: [],
            type: stringTypeRef
        )))

        let boolProperty = astArena.appendDecl(.propertyDecl(PropertyDecl(
            range: range,
            name: interner.intern("flag"),
            modifiers: [],
            type: boolTypeRef
        )))

        let classDecl = astArena.appendDecl(.classDecl(ClassDecl(
            range: range,
            name: interner.intern("C"),
            modifiers: [],
            typeParams: [],
            primaryConstructorParams: []
        )))

        let astFile = ASTFile(
            fileID: FileID(rawValue: 0),
            packageFQName: [interner.intern("pkg")],
            imports: [],
            topLevelDecls: [helperDecl, calcDecl, propertyDecl, boolProperty, classDecl],
            scriptBody: []
        )
        let module = ASTModule(files: [astFile], arena: astArena, declarationCount: 5, tokenCount: 0)

        let options = CompilerOptions(
            moduleName: "ExprCoverage",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.ast = module
        ctx.sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        return (ctx, (eUnaryPlus, eUnaryMinus, eUnaryNot, eNe, eLt, eLe, eGt, eGe, eAnd, eOr))
    }

    func testTypeCheckAndBuildKIRCoverExpressionVariants() throws {
        let (ctx, exprIDs) = makeExpressionVariantsFixture()

        try DataFlowSemaPassPhase().run(ctx)
        try TypeCheckSemaPassPhase().run(ctx)
        try BuildKIRPhase().run(ctx)
        try LoweringPhase().run(ctx)

        let kir = try XCTUnwrap(ctx.kir)
        // helper + calc functions
        XCTAssertGreaterThanOrEqual(kir.functionCount, 2)
        XCTAssertFalse(kir.executedLowerings.isEmpty)
        XCTAssertFalse(kir.arena.exprTypes.isEmpty)
        XCTAssertFalse((ctx.sema?.bindings.exprTypes ?? [:]).isEmpty)
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eUnaryPlus])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eUnaryMinus])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eUnaryNot])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eNe])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eLt])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eLe])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eGt])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eGe])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eAnd])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[exprIDs.eOr])
    }

    func testBuildKIRLowersLoopExpressionsToControlFlowInstructions() throws {
        let source = """
        fun loop(flag: Boolean, items: IntArray): Int {
            while (flag) { break }
            do { continue } while (flag)
            for (item in items) { break }
            return 1
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "LoopIR", emit: .kirDump)
            try runToKIR(ctx)

            let kir = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "loop", in: kir, interner: ctx.interner)

            let labelCount = body.filter { instruction in
                if case .label = instruction { return true }
                return false
            }.count
            // while/do-while/for each need loop-start + loop-end labels;
            // 3 loops need at least 4 labels (some may share via break/continue)
            XCTAssertGreaterThanOrEqual(labelCount, 4)

            let jumpCount = body.filter { instruction in
                if case .jump = instruction { return true }
                if case .jumpIfEqual = instruction { return true }
                return false
            }.count
            // Each loop has conditional jump + unconditional jump-back;
            // 3 loops need at least 4 jumps
            XCTAssertGreaterThanOrEqual(jumpCount, 4)

            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("iterator"))
            XCTAssertTrue(callees.contains("hasNext"))
            XCTAssertTrue(callees.contains("next"))
        }
    }

    // MARK: - Reified Type Token Coverage

    private func makeReifiedCallFixture() -> (
        ctx: CompilationContext,
        pickSymbol: SymbolID,
        mainSymbol: SymbolID,
        typeParameterSymbol: SymbolID,
        intType: TypeID
    ) {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()
        let astArena = ASTArena()
        let range = makeRange()

        let intType = types.make(.primitive(.int, .nonNull))
        let tName = interner.intern("T")
        let valueName = interner.intern("value")
        let pickName = interner.intern("pick")
        let mainName = interner.intern("main")
        let packageName = interner.intern("pkg")

        let valueRefExpr = astArena.appendExpr(.nameRef(valueName, range))
        let pickDeclID = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: pickName,
            modifiers: [.inline],
            typeParams: [TypeParamDecl(name: tName, variance: .invariant, isReified: true)],
            receiverType: nil,
            valueParams: [ValueParamDecl(name: valueName, type: nil)],
            returnType: nil,
            body: .expr(valueRefExpr, range),
            isSuspend: false,
            isInline: true
        )))

        let intArgExpr = astArena.appendExpr(.intLiteral(7, range))
        let pickCalleeExpr = astArena.appendExpr(.nameRef(pickName, range))
        let pickCallExpr = astArena.appendExpr(.call(
            callee: pickCalleeExpr,
            typeArgs: [],
            args: [CallArgument(expr: intArgExpr)],
            range: range
        ))
        let mainDeclID = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: mainName,
            modifiers: [],
            typeParams: [],
            receiverType: nil,
            valueParams: [],
            returnType: nil,
            body: .expr(pickCallExpr, range),
            isSuspend: false,
            isInline: false
        )))

        let astFile = ASTFile(
            fileID: FileID(rawValue: 0),
            packageFQName: [packageName],
            imports: [],
            topLevelDecls: [pickDeclID, mainDeclID],
            scriptBody: []
        )
        let astModule = ASTModule(files: [astFile], arena: astArena, declarationCount: 2, tokenCount: 0)

        let pickSymbol = symbols.define(
            kind: .function,
            name: pickName,
            fqName: [packageName, pickName],
            declSite: range,
            visibility: .public,
            flags: [.inlineFunction]
        )
        let mainSymbol = symbols.define(
            kind: .function,
            name: mainName,
            fqName: [packageName, mainName],
            declSite: range,
            visibility: .public
        )
        let valueSymbol = symbols.define(
            kind: .valueParameter,
            name: valueName,
            fqName: [packageName, interner.intern("$pick"), valueName],
            declSite: range,
            visibility: .private
        )
        let typeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: tName,
            fqName: [packageName, interner.intern("$pick"), tName],
            declSite: range,
            visibility: .private,
            flags: [.reifiedTypeParameter]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [valueSymbol],
                typeParameterSymbols: [typeParameterSymbol],
                reifiedTypeParameterIndices: Set([0])
            ),
            for: pickSymbol
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: intType
            ),
            for: mainSymbol
        )

        bindings.bindDecl(pickDeclID, symbol: pickSymbol)
        bindings.bindDecl(mainDeclID, symbol: mainSymbol)
        bindings.bindIdentifier(valueRefExpr, symbol: valueSymbol)
        bindings.bindExprType(valueRefExpr, type: intType)
        bindings.bindExprType(intArgExpr, type: intType)
        bindings.bindExprType(pickCallExpr, type: intType)
        bindings.bindCall(
            pickCallExpr,
            binding: CallBinding(
                chosenCallee: pickSymbol,
                substitutedTypeArguments: [intType],
                parameterMapping: [0: 0]
            )
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "ReifiedTokenKIR",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.ast = astModule
        ctx.sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )

        return (ctx, pickSymbol, mainSymbol, typeParameterSymbol, intType)
    }

    func testBuildKIRAddsHiddenTypeTokenForInlineReifiedCalls() throws {
        let (ctx, pickSymbol, mainSymbol, typeParameterSymbol, intType) = makeReifiedCallFixture()

        try BuildKIRPhase().run(ctx)

        let kir = try XCTUnwrap(ctx.kir)
        let pickFunction = try XCTUnwrap(kir.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return function.symbol == pickSymbol ? function : nil
        }.first)
        let mainFunction = try XCTUnwrap(kir.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return function.symbol == mainSymbol ? function : nil
        }.first)

        // Type token symbols use a negative offset to avoid collision with real symbol IDs
        let expectedTokenSymbol = SymbolID(rawValue: Int32(typeTokenSymbolOffset) - typeParameterSymbol.rawValue)
        XCTAssertEqual(pickFunction.params.count, 2)
        XCTAssertEqual(pickFunction.params.last?.symbol, expectedTokenSymbol)

        guard let callInstruction = mainFunction.body.first(where: { instruction in
            guard case .call(let symbol, _, _, _, _, _) = instruction else {
                return false
            }
            return symbol == pickSymbol
        }),
        case .call(_, _, let arguments, _, _, _) = callInstruction else {
            XCTFail("Expected main to call inline reified function.")
            return
        }
        XCTAssertEqual(arguments.count, 2)
        let tokenArgument = arguments[1]
        guard case .intLiteral(let tokenLiteral)? = kir.arena.expr(tokenArgument) else {
            XCTFail("Expected hidden type token argument to be lowered as int literal.")
            return
        }
        XCTAssertEqual(tokenLiteral, Int64(intType.rawValue))
    }

    func testVarargMultiplePositionalArgsPackedToArrayInKIR() throws {
        let source = """
        fun sum(vararg items: Int): Int = 0
        fun main() = sum(1, 2, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callNames = body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg packing, got: \(callNames)")
            XCTAssertTrue(callNames.contains("kk_array_set"), "Expected kk_array_set for vararg packing, got: \(callNames)")
        }
    }

    func testVarargWithDefaultParamPacksCorrectly() throws {
        let source = """
        fun greet(prefix: String = "Hi", vararg names: Int): Int = 0
        fun main() = greet("Hello", 1, 2)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callNames = body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg packing with default arg, got: \(callNames)")
        }
    }

    func testVarargEmptyProducesEmptyArrayInKIR() throws {
        let source = """
        fun noArgs(vararg items: Int): Int = 0
        fun main() = noArgs()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callNames = body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for empty vararg, got: \(callNames)")
        }
    }

    func testDefaultArgGeneratesStubFunctionInKIR() throws {
        let source = """
        fun greetUser(name: String, greeting: String = "Hello"): String = greeting
        fun main() = greetUser("Alice")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let allFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else { return nil }
                return function
            }
            let stubNames = allFunctions.map { ctx.interner.resolve($0.name) }
                .filter { $0.hasSuffix("$default") }
            XCTAssertTrue(stubNames.contains("greetUser$default"), "Expected greetUser$default stub, got: \(stubNames)")
        }
    }

    func testDefaultArgCallSiteRedirectsToStub() throws {
        let source = """
        fun add(a: Int, b: Int = 10): Int = a + b
        fun main() = add(5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("add$default"), "Expected call to add$default stub, got: \(callees)")
        }
    }

    func testDefaultArgStubContainsMaskParameterAndOriginalCall() throws {
        let source = """
        fun compute(x: Int, y: Int = 1, z: Int = 2): Int = x + y + z
        fun main() = compute(10)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let stubFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "compute$default" ? function : nil
            }.first
            XCTAssertNotNil(stubFunction, "Expected compute$default stub function")
            if let stub = stubFunction {
                let paramCount = stub.params.count
                XCTAssertGreaterThanOrEqual(paramCount, 4, "Stub should have original params + mask param")
                let stubCallees = extractCallees(from: stub.body, interner: ctx.interner)
                XCTAssertTrue(stubCallees.contains("compute"), "Stub should call original function, got: \(stubCallees)")
            }
        }
    }

    func testDefaultArgEvaluationOrderLeftToRight() throws {
        let source = """
        fun ordered(a: Int = 1, b: Int = 2, c: Int = 3): Int = a + b + c
        fun main() = ordered()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let stubFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "ordered$default" ? function : nil
            }.first
            XCTAssertNotNil(stubFunction, "Expected ordered$default stub function")
            if let stub = stubFunction {
                var labelOrder: [Int32] = []
                for instruction in stub.body {
                    if case .label(let id) = instruction {
                        labelOrder.append(id)
                    }
                }
                for i in 1..<labelOrder.count {
                    XCTAssertGreaterThan(labelOrder[i], labelOrder[i - 1], "Labels should be in ascending order for left-to-right evaluation")
                }
            }
        }
    }

    func testDefaultArgNoStubWhenAllArgsProvided() throws {
        let source = """
        fun add(a: Int, b: Int = 10): Int = a + b
        fun main() = add(5, 20)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("add"), "Expected direct call to add, got: \(callees)")
            XCTAssertFalse(callees.contains("add$default"), "Should not call stub when all args provided, got: \(callees)")
        }
    }

    // MARK: - Nested Return Propagation (P5-48)

    func testNestedReturnInsideIfBranchEmitsReturnValueInstruction() throws {
        let source = """
        fun choose(flag: Boolean): Int {
            if (flag) {
                return 1
            }
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "choose", in: module, interner: ctx.interner)
            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case .returnValue(let id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 2, "Expected at least 2 returnValue instructions (if-branch + fallthrough), got \(returnValues.count)")
        }
    }

    func testNestedReturnInsideBothIfElseBranchesEmitsReturnValues() throws {
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
                guard case .returnValue(let id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 2, "Expected at least 2 returnValue instructions (then-branch + else-branch), got \(returnValues.count)")
        }
    }

    func testNestedReturnInsideWhenBranchEmitsReturnValueInstruction() throws {
        let source = """
        fun describe(x: Int): Int {
            return when (x) {
                1 -> return 10
                2 -> return 20
                else -> 0
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "describe", in: module, interner: ctx.interner)
            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case .returnValue(let id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 2, "Expected at least 2 returnValue instructions for when-branch returns, got \(returnValues.count)")
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
                guard case .function(let function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callNames = body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _, _) = instruction else { return nil }
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

            let hasSelect = body.contains { instruction in
                if case .select = instruction { return true }
                return false
            }
            XCTAssertFalse(hasSelect, "ifExpr should not emit .select; expected control-flow jumps")

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

            let hasSelect = body.contains { instruction in
                if case .select = instruction { return true }
                return false
            }
            XCTAssertFalse(hasSelect, "whenExpr should not emit .select; expected control-flow jumps")

            let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(labelCount, 3, "whenExpr with 2 branches + else needs at least 3 labels")
        }
    }

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

            let hasSelect = body.contains { instruction in
                if case .select = instruction { return true }
                return false
            }
            XCTAssertFalse(hasSelect, "Side-effect branches must use control flow, not select")

            let sideEffectCalls = body.filter { instruction in
                guard case .call(_, let callee, _, _, _, _) = instruction else { return false }
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

            let hasSelect = body.contains { instruction in
                if case .select = instruction { return true }
                return false
            }
            XCTAssertFalse(hasSelect, "return-in-branch must use control flow, not select")
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

            let hasSelect = body.contains { instruction in
                if case .select = instruction { return true }
                return false
            }
            XCTAssertFalse(hasSelect, "when branches with side effects must use control flow, not select")

            let effectCalls = body.filter { instruction in
                guard case .call(_, let callee, _, _, _, _) = instruction else { return false }
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
            guard case .tryExpr(_, let catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
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
                guard case .call(_, let callee, let arguments, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "kk_catch_type_matches" else {
                    return nil
                }
                let _ = arguments
                return instruction
            }
            XCTAssertTrue(matcherCalls.isEmpty, "Try-catch lowering should not require runtime matcher helper calls.")

            let labelPositions: [Int32: Int] = body.enumerated().reduce(into: [:]) { partial, entry in
                if case .label(let labelID) = entry.element {
                    partial[labelID] = entry.offset
                }
            }

            func thrownEdge(for calleeName: String) -> (callIndex: Int, thrownSlot: KIRExprID, typeSlot: KIRExprID, target: Int32)? {
                guard let callIndex = body.firstIndex(where: { instruction in
                    guard case .call(_, let callee, _, _, _, _) = instruction else {
                        return false
                    }
                    return ctx.interner.resolve(callee) == calleeName
                }) else {
                    return nil
                }
                guard case .call(_, _, _, _, _, let thrownResult?) = body[callIndex] else {
                    return nil
                }
                let tokenConstIndex = callIndex + 1
                let tokenCopyIndex = callIndex + 2
                let jumpIndex = callIndex + 3
                guard body.indices.contains(tokenConstIndex),
                      body.indices.contains(tokenCopyIndex),
                      body.indices.contains(jumpIndex),
                      case .constValue(let unknownTypeToken, .intLiteral(0)) = body[tokenConstIndex],
                      case .copy(from: unknownTypeToken, to: let typeSlot) = body[tokenCopyIndex],
                      case .jumpIfNotNull(let value, let target) = body[jumpIndex],
                      value == thrownResult else {
                    return nil
                }
                return (callIndex, thrownResult, typeSlot, target)
            }

            guard let bodyEdge = thrownEdge(for: "bodyCall"),
                  let catchEdge = thrownEdge(for: "catchCall"),
                  let finallyEdge = thrownEdge(for: "finallyCall") else {
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
                  let rethrowPos = labelPositions[finallyEdge.target] else {
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
                      case .intLiteral(let token)? = module.arena.expr(rhs) else {
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
                  case .jumpIfEqual(_, _, let firstMismatchTarget) = body[typeComparisons[0].index + 1],
                let firstMismatchLabelPos = labelPositions[firstMismatchTarget] else {
                XCTFail("Expected mismatch branch after first catch matcher.")
                return
            }
            XCTAssertLessThan(firstMismatchLabelPos, typeComparisons[1].index, "First catch mismatch should fall through to second catch dispatch.")

            guard body.indices.contains(typeComparisons[1].index + 1),
                  case .jumpIfEqual(_, _, let unmatchedLabel) = body[typeComparisons[1].index + 1],
                let unmatchedLabelPos = labelPositions[unmatchedLabel] else {
                XCTFail("Expected unmatched-catch branch after last matcher.")
                return
            }
            let unmatchedJumpIndex = body.index(after: unmatchedLabelPos)
            guard body.indices.contains(unmatchedJumpIndex),
                  case .jump(let unmatchedTarget) = body[unmatchedJumpIndex] else {
                XCTFail("Expected unmatched-catch path to jump to finally.")
                return
            }
            XCTAssertEqual(unmatchedTarget, catchEdge.target, "Unmatched catches must enter finally before rethrow.")

            let finallyGuardJump = body.enumerated().contains { index, instruction in
                guard index > finallyEdge.callIndex + 3,
                      case .jumpIfNotNull(let value, let target) = instruction else {
                    return false
                }
                return value == sharedExceptionSlot && target == finallyEdge.target
            }
            XCTAssertTrue(finallyGuardJump, "Expected post-finally rethrow guard for pending exception slot.")
            XCTAssertTrue(body.contains { instruction in
                if case .rethrow(let value) = instruction {
                    return value == sharedExceptionSlot
                }
                return false
            })

            guard case .call(_, _, let catchArguments, _, _, _) = body[catchEdge.callIndex],
                  let firstCatchArgument = catchArguments.first else {
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
                guard case .call(_, let callee, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee).hasPrefix("kk_object_literal_")
            })

            guard case .call(let factorySymbol, let callee, let arguments, let result, _, _) = objectFactoryCall else {
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
                guard case .function(let function) = decl else {
                    return false
                }
                return function.symbol == generatedFactorySymbol
            }))
            guard case .function(let generatedFactory) = module.arena.declarations[generatedFactoryDeclIndex] else {
                XCTFail("Expected generated object factory function declaration.")
                return
            }
            let hasAllocationRuntimeCall = generatedFactory.body.contains { instruction in
                guard case .call(_, let loweredCallee, _, _, _, _) = instruction else {
                    return false
                }
                let calleeName = ctx.interner.resolve(loweredCallee)
                return calleeName == "kk_alloc" || calleeName == "kk_array_new"
            }
            XCTAssertTrue(
                hasAllocationRuntimeCall,
                "Expected generated object factory to include allocation runtime call."
            )

            let generatedNominalDeclIndex = try XCTUnwrap(module.arena.declarations.firstIndex(where: { decl in
                guard case .nominalType(let nominal) = decl else {
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

    func testBuildKIRObjectLiteralArgumentIsNotLoweredToUnitPlaceholder() throws {
        let source = """
        interface I
        fun consume(value: I): I = value
        fun main(): I {
            val instance = object : I {}
            return consume(instance)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let consumeCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(_, let callee, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "consume"
            })
            guard case .call(_, _, let arguments, _, _, _) = consumeCall else {
                XCTFail("Expected call instruction for consume(instance).")
                return
            }
            let objectArgument = try XCTUnwrap(arguments.first)
            let objectArgumentExpr = try XCTUnwrap(module.arena.expr(objectArgument))
            if case .unit = objectArgumentExpr {
                XCTFail("object literal must not be lowered to .unit placeholder at call sites.")
            }
        }
    }

    func testBuildKIRLowersLambdaLiteralToGeneratedCallableAndPrependsCapturesOnCall() throws {
        let source = """
        fun main(): Int {
            val base = 40
            val add = { x -> base + x }
            return add(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let lambdaCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(_, let callee, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee).hasPrefix("kk_lambda_")
            })

            guard case .call(let callSymbol, let callee, let arguments, _, _, _) = lambdaCall else {
                XCTFail("Expected lowered lambda call in main.")
                return
            }
            XCTAssertNotNil(callSymbol)
            XCTAssertTrue(ctx.interner.resolve(callee).hasPrefix("kk_lambda_"))
            XCTAssertEqual(arguments.count, 2)
            guard case .intLiteral(40)? = module.arena.expr(arguments[0]) else {
                XCTFail("Expected first lambda call argument to be captured 'base'.")
                return
            }
            guard case .intLiteral(2)? = module.arena.expr(arguments[1]) else {
                XCTFail("Expected second lambda call argument to be the explicit call argument.")
                return
            }

            let generatedLambdaFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl,
                      ctx.interner.resolve(function.name).hasPrefix("kk_lambda_") else {
                    return nil
                }
                return function
            }
            XCTAssertFalse(generatedLambdaFunctions.isEmpty)
            if let generatedSymbol = callSymbol,
               let generatedFunction = generatedLambdaFunctions.first(where: { $0.symbol == generatedSymbol }) {
                XCTAssertEqual(generatedFunction.params.count, 2)
            }
        }
    }

    func testBuildKIRCallableValueCallRespectsParameterMappingBeforePrependingCaptures() throws {
        let source = """
        fun main(): Int {
            val base = 100
            val add = { a, b -> base + a + b }
            return add(1, 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let addCallExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case .call(let calleeExprID, _, _, _) = expr,
                      let calleeExpr = ast.arena.expr(calleeExprID),
                      case .nameRef(let calleeName, _) = calleeExpr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "add"
            })
            let existingBinding = try XCTUnwrap(sema.bindings.callableValueCalls[addCallExprID])
            sema.bindings.bindCallableValueCall(
                addCallExprID,
                binding: CallableValueCallBinding(
                    target: existingBinding.target,
                    functionType: existingBinding.functionType,
                    parameterMapping: [0: 1, 1: 0]
                )
            )

            try BuildKIRPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let lambdaCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(_, let callee, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee).hasPrefix("kk_lambda_")
            })

            guard case .call(_, _, let arguments, _, _, _) = lambdaCall else {
                XCTFail("Expected callable-value call to lowered lambda target.")
                return
            }
            XCTAssertEqual(arguments.count, 3)
            guard case .intLiteral(100)? = module.arena.expr(arguments[0]) else {
                XCTFail("Expected capture argument to stay prepended at index 0.")
                return
            }
            guard case .intLiteral(2)? = module.arena.expr(arguments[1]) else {
                XCTFail("Expected parameter mapping to reorder explicit args before call emission.")
                return
            }
            guard case .intLiteral(1)? = module.arena.expr(arguments[2]) else {
                XCTFail("Expected reordered second parameter argument.")
                return
            }
        }
    }

    func testSyntheticLambdaSymbolGenerationNeverUsesZeroOrInvalidSentinel() {
        let phase = BuildKIRPhase()
        let zeroExprSymbol = phase.syntheticLambdaSymbol(for: ExprID(rawValue: 0))
        let maxExprSymbol = phase.syntheticLambdaSymbol(for: ExprID(rawValue: Int32.max))

        XCTAssertEqual(zeroExprSymbol, phase.syntheticLambdaSymbol(for: ExprID(rawValue: 0)))
        XCTAssertGreaterThan(zeroExprSymbol.rawValue, 0)
        XCTAssertNotEqual(zeroExprSymbol.rawValue, 0)
        XCTAssertNotEqual(zeroExprSymbol, .invalid)

        XCTAssertGreaterThan(maxExprSymbol.rawValue, 0)
        XCTAssertNotEqual(maxExprSymbol.rawValue, 0)
        XCTAssertNotEqual(maxExprSymbol, .invalid)
        XCTAssertNotEqual(maxExprSymbol, zeroExprSymbol)
    }

    func testBuildKIRLowersCallableRefToCallableSymbolValue() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main(): Int {
            val f = ::inc
            return f(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let module = try XCTUnwrap(ctx.kir)
            let incSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                symbol.kind == .function && ctx.interner.resolve(symbol.name) == "inc"
            })?.id)

            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let incCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(let symbol, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == incSymbol
            })

            guard case .call(let callSymbol, let callee, let arguments, _, _, _) = incCall else {
                XCTFail("Expected callable reference call to inc.")
                return
            }
            XCTAssertEqual(callSymbol, incSymbol)
            XCTAssertEqual(ctx.interner.resolve(callee), "inc")
            XCTAssertEqual(arguments.count, 1)
            guard case .intLiteral(2)? = module.arena.expr(arguments[0]) else {
                XCTFail("Expected callable reference call to forward the explicit argument.")
                return
            }
        }
    }

    func testBuildKIRPrependsBoundCallableRefReceiverAsCaptureArgument() throws {
        let source = """
        class Box {
            fun plus(x: Int): Int = x
        }
        fun main(box: Box): Int {
            val f = box::plus
            return f(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let module = try XCTUnwrap(ctx.kir)
            let plusSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                symbol.kind == .function && ctx.interner.resolve(symbol.name) == "plus"
            })?.id)

            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let plusCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(let symbol, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == plusSymbol
            })

            guard case .call(_, let callee, let arguments, _, _, _) = plusCall else {
                XCTFail("Expected bound callable reference to lower to plus call.")
                return
            }
            XCTAssertEqual(ctx.interner.resolve(callee), "plus")
            XCTAssertEqual(arguments.count, 2)
            guard case .symbolRef(let receiverSymbol)? = module.arena.expr(arguments[0]),
                  let receiver = sema.symbols.symbol(receiverSymbol) else {
                XCTFail("Expected first argument to be captured receiver symbol.")
                return
            }
            XCTAssertEqual(ctx.interner.resolve(receiver.name), "box")
            guard case .intLiteral(7)? = module.arena.expr(arguments[1]) else {
                XCTFail("Expected second argument to be call-site argument.")
                return
            }
        }
    }

    private func topLevelExpressionBodyExprID(
        named functionName: String,
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        ast.files
            .flatMap(\.topLevelDecls)
            .compactMap { declID -> ExprID? in
                guard let decl = ast.arena.decl(declID),
                      case .funDecl(let funDecl) = decl,
                      interner.resolve(funDecl.name) == functionName,
                      case .expr(let exprID, _) = funDecl.body else {
                    return nil
                }
                return exprID
            }
            .first
    }

    private func symbolNames(
        for arguments: [KIRExprID],
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        arguments.compactMap { argument in
            guard case .symbolRef(let symbolID)? = module.arena.expr(argument),
                  let symbol = sema.symbols.symbol(symbolID) else {
                return nil
            }
            return interner.resolve(symbol.name)
        }
    }

    // MARK: - P5-42: Local function scope registration and KIR generation

    func testLocalFunctionScopeRegistrationAllowsCallResolution() throws {
        let source = """
        fun main(): Int {
            fun helper(x: Int): Int = x * 2
            return helper(21)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Local function call should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    func testLocalFunctionKIRGenerationEmitsFunctionDecl() throws {
        let source = """
        fun main(): Int {
            fun add(a: Int, b: Int): Int = a + b
            return add(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected no errors: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // The module should contain at least 2 functions: main and the local function add.
            XCTAssertGreaterThanOrEqual(module.functionCount, 2, "Expected KIR to contain both main and local function 'add'")
        }
    }

    func testNestedLocalFunctionScopeResolution() throws {
        let source = """
        fun outer(): Int {
            fun middle(): Int {
                fun inner(): Int = 7
                return inner()
            }
            return middle()
        }
        fun main() = outer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Nested local functions should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            // outer, middle, inner, main => at least 4 functions
            XCTAssertGreaterThanOrEqual(module.functionCount, 4)
        }
    }

    func testLocalFunctionWithBlockBodyKIRGeneration() throws {
        let source = """
        fun main(): Int {
            fun compute(x: Int): Int {
                val doubled = x * 2
                return doubled + 1
            }
            return compute(10)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Local function with block body: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try XCTUnwrap(ctx.kir)
            XCTAssertGreaterThanOrEqual(module.functionCount, 2)
        }
    }

    func testLocalFunctionCalledMultipleTimes() throws {
        let source = """
        fun main(): Int {
            fun square(n: Int): Int = n * n
            val a = square(3)
            val b = square(4)
            return a + b
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Multiple calls to local function: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    func testLocalFunctionCapturesOuterVal() throws {
        let source = """
        fun main(): Int {
            val outer = 10
            fun addOuter(x: Int): Int = x + outer
            return addOuter(5)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Local function capturing outer val should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let module = try XCTUnwrap(ctx.kir)
            XCTAssertGreaterThanOrEqual(module.functionCount, 2)
        }
    }

    func testLocalFunctionScopeDoesNotLeakBetweenTopLevelFunctions() throws {
        let source = """
        fun first(): Int {
            fun helper(): Int = 1
            return helper()
        }
        fun second(): Int {
            return helper()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertTrue(
                ctx.diagnostics.hasError,
                "Local function should not be visible outside its defining top-level function: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    private func firstExprID(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else {
                continue
            }
            if predicate(exprID, expr) {
                return exprID
            }
        }
        return nil
    }
}
