import Foundation
import XCTest
@testable import CompilerCore

extension BuildKIRCoverageTests {
    // MARK: - Expression Variants Coverage

    func makeExpressionVariantsFixture() -> (
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

        try DataFlowSemaPhase().run(ctx)
        try TypeCheckSemaPhase().run(ctx)
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
            XCTAssertTrue(callees.contains("kk_range_iterator"))
            XCTAssertTrue(callees.contains("kk_range_hasNext"))
            XCTAssertTrue(callees.contains("kk_range_next"))
        }
    }

    // MARK: - Reified Type Token Coverage

    func makeReifiedCallFixture() -> (
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

}
