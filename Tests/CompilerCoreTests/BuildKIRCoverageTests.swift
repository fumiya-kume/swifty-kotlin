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
}
