@testable import CompilerCore
import XCTest

final class TypeCheckDelegateCoverageTests: XCTestCase {
    func testInferIndexedCompoundAssignResolvesOperatorGetPath() {
        let fixture = makeTypeCheckFixture()
        let ctx = fixture.makeInferenceContext()
        var locals: LocalBindings = [:]
        let range = makeRange()

        let boxClass = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("Box"),
            fqName: [fixture.interner.intern("Box")],
            declSite: nil,
            visibility: .public
        )
        let boxType = fixture.types.make(.classType(ClassType(classSymbol: boxClass, args: [], nullability: .nonNull)))

        let getSymbol = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("get"),
            fqName: [fixture.interner.intern("Box"), fixture.interner.intern("get")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setParentSymbol(boxClass, for: getSymbol)
        fixture.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: boxType,
                parameterTypes: [fixture.types.intType],
                returnType: fixture.types.intType,
                valueParameterSymbols: [SymbolID(rawValue: 100)]
            ),
            for: getSymbol
        )

        let boxLocalSymbol = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("box"),
            fqName: [fixture.interner.intern("box")],
            declSite: nil,
            visibility: .private
        )
        locals[fixture.interner.intern("box")] = (boxType, boxLocalSymbol, false, true)

        let receiverExpr = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("box"), range))
        let indexExpr = fixture.astArena.appendExpr(.intLiteral(0, range))
        let valueExpr = fixture.astArena.appendExpr(.intLiteral(1, range))
        let targetExpr = fixture.astArena.appendExpr(
            .indexedCompoundAssign(
                op: .plusAssign,
                receiver: receiverExpr,
                indices: [indexExpr],
                value: valueExpr,
                range: range
            )
        )

        let inferred = fixture.driver.localDeclChecker.inferIndexedCompoundAssignExpr(
            targetExpr,
            op: .plusAssign,
            receiverExpr: receiverExpr,
            indices: [indexExpr],
            valueExpr: valueExpr,
            range: range,
            ctx: ctx,
            locals: &locals
        )

        XCTAssertEqual(inferred, fixture.types.unitType)
        XCTAssertEqual(fixture.bindings.exprType(for: targetExpr), fixture.types.unitType)
        XCTAssertEqual(fixture.bindings.callBinding(for: targetExpr)?.chosenCallee, getSymbol)
    }

    func testInferIndexedCompoundAssignFallbackAndMultipleIndicesError() {
        let fixture = makeTypeCheckFixture()
        let ctx = fixture.makeInferenceContext()
        var locals: LocalBindings = [:]
        let range = makeRange()

        let intArraySymbol = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("IntArray"),
            fqName: [fixture.interner.intern("IntArray")],
            declSite: nil,
            visibility: .public
        )
        let intArrayType = fixture.types.make(
            .classType(ClassType(classSymbol: intArraySymbol, args: [], nullability: .nonNull))
        )

        let localArray = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("arr"),
            fqName: [fixture.interner.intern("arr")],
            declSite: nil,
            visibility: .private
        )
        locals[fixture.interner.intern("arr")] = (intArrayType, localArray, true, true)

        let receiverExpr = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("arr"), range))
        let i0 = fixture.astArena.appendExpr(.intLiteral(0, range))
        let i1 = fixture.astArena.appendExpr(.intLiteral(1, range))
        let valueExpr = fixture.astArena.appendExpr(.intLiteral(2, range))

        let targetOK = fixture.astArena.appendExpr(
            .indexedCompoundAssign(
                op: .plusAssign,
                receiver: receiverExpr,
                indices: [i0],
                value: valueExpr,
                range: range
            )
        )
        let inferredOK = fixture.driver.localDeclChecker.inferIndexedCompoundAssignExpr(
            targetOK,
            op: .plusAssign,
            receiverExpr: receiverExpr,
            indices: [i0],
            valueExpr: valueExpr,
            range: range,
            ctx: ctx,
            locals: &locals
        )
        XCTAssertEqual(inferredOK, fixture.types.unitType)

        let targetError = fixture.astArena.appendExpr(
            .indexedCompoundAssign(
                op: .plusAssign,
                receiver: receiverExpr,
                indices: [i0, i1],
                value: valueExpr,
                range: range
            )
        )
        let inferredError = fixture.driver.localDeclChecker.inferIndexedCompoundAssignExpr(
            targetError,
            op: .plusAssign,
            receiverExpr: receiverExpr,
            indices: [i0, i1],
            valueExpr: valueExpr,
            range: range,
            ctx: ctx,
            locals: &locals
        )
        XCTAssertEqual(inferredError, fixture.types.errorType)
        XCTAssertEqual(fixture.bindings.exprType(for: targetError), fixture.types.errorType)
    }

    func testInferLocalFunDeclExprBindsFunctionForAllBodyKinds() {
        let fixture = makeTypeCheckFixture()
        let ctx = fixture.makeInferenceContext()
        var locals: LocalBindings = [:]
        let range = makeRange()

        let intTypeRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: false)
        )

        let bodyExpr = fixture.astArena.appendExpr(.intLiteral(10, range))
        let bodyExpr2 = fixture.astArena.appendExpr(.intLiteral(11, range))

        let exprFunID = ExprID(rawValue: 500)
        let exprResult = fixture.driver.localDeclChecker.inferLocalFunDeclExpr(
            exprFunID,
            name: fixture.interner.intern("exprFun"),
            valueParams: [ValueParamDecl(name: fixture.interner.intern("x"), type: intTypeRef)],
            returnTypeRef: intTypeRef,
            body: .expr(bodyExpr, range),
            range: range,
            ctx: ctx,
            locals: &locals
        )
        XCTAssertEqual(exprResult, fixture.types.unitType)
        XCTAssertEqual(fixture.bindings.exprType(for: exprFunID), fixture.types.unitType)

        let blockFunID = ExprID(rawValue: 501)
        let blockResult = fixture.driver.localDeclChecker.inferLocalFunDeclExpr(
            blockFunID,
            name: fixture.interner.intern("blockFun"),
            valueParams: [ValueParamDecl(name: fixture.interner.intern("x"), type: intTypeRef)],
            returnTypeRef: intTypeRef,
            body: .block([bodyExpr, bodyExpr2], range),
            range: range,
            ctx: ctx,
            locals: &locals
        )
        XCTAssertEqual(blockResult, fixture.types.unitType)

        let unitFunID = ExprID(rawValue: 502)
        let unitResult = fixture.driver.localDeclChecker.inferLocalFunDeclExpr(
            unitFunID,
            name: fixture.interner.intern("unitFun"),
            valueParams: [],
            returnTypeRef: nil,
            body: .unit,
            range: range,
            ctx: ctx,
            locals: &locals
        )
        XCTAssertEqual(unitResult, fixture.types.unitType)

        XCTAssertNotNil(locals[fixture.interner.intern("exprFun")])
        XCTAssertNotNil(locals[fixture.interner.intern("blockFun")])
        XCTAssertNotNil(locals[fixture.interner.intern("unitFun")])

        let exprFunSymbol = fixture.bindings.identifierSymbol(for: exprFunID)
        XCTAssertEqual(fixture.symbols.symbol(exprFunSymbol ?? .invalid)?.kind, .function)
    }

    func testInferDestructuringDeclUsesMemberAndFallbackComponents() {
        let fixture = makeTypeCheckFixture()
        let ctx = fixture.makeInferenceContext()
        var locals: LocalBindings = [:]
        let range = makeRange()

        let pairClass = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("Pair"),
            fqName: [fixture.interner.intern("Pair")],
            declSite: nil,
            visibility: .public
        )
        let pairType = fixture.types.make(.classType(ClassType(classSymbol: pairClass, args: [], nullability: .nonNull)))

        let component1 = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("component1"),
            fqName: [fixture.interner.intern("Pair"), fixture.interner.intern("component1")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setParentSymbol(pairClass, for: component1)
        fixture.symbols.setFunctionSignature(
            FunctionSignature(receiverType: pairType, parameterTypes: [], returnType: fixture.types.intType),
            for: component1
        )

        let component2 = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("component2"),
            fqName: [fixture.interner.intern("Pair"), fixture.interner.intern("component2")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setParentSymbol(pairClass, for: component2)
        fixture.symbols.setFunctionSignature(
            FunctionSignature(receiverType: pairType, parameterTypes: [], returnType: fixture.types.stringType),
            for: component2
        )

        let pairLocalSymbol = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("pair"),
            fqName: [fixture.interner.intern("pair")],
            declSite: nil,
            visibility: .private
        )
        locals[fixture.interner.intern("pair")] = (pairType, pairLocalSymbol, false, true)

        let initializer = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("pair"), range))
        let destructuringID = ExprID(rawValue: 600)

        let inferred = fixture.driver.controlFlowChecker.inferDestructuringDeclExpr(
            destructuringID,
            names: [fixture.interner.intern("a"), fixture.interner.intern("b")],
            isMutable: false,
            initializer: initializer,
            range: range,
            ctx: ctx,
            locals: &locals
        )

        XCTAssertEqual(inferred, fixture.types.unitType)
        XCTAssertEqual(locals[fixture.interner.intern("a")]?.type, fixture.types.intType)
        XCTAssertEqual(locals[fixture.interner.intern("b")]?.type, fixture.types.stringType)

        let otherClass = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("Other"),
            fqName: [fixture.interner.intern("Other")],
            declSite: nil,
            visibility: .public
        )
        let otherType = fixture.types.make(.classType(ClassType(classSymbol: otherClass, args: [], nullability: .nonNull)))
        let fallbackFn = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("component1"),
            fqName: [fixture.interner.intern("component1")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setFunctionSignature(
            FunctionSignature(receiverType: otherType, parameterTypes: [], returnType: fixture.types.booleanType),
            for: fallbackFn
        )

        let otherLocalSymbol = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("other"),
            fqName: [fixture.interner.intern("other")],
            declSite: nil,
            visibility: .private
        )
        locals[fixture.interner.intern("other")] = (otherType, otherLocalSymbol, false, true)
        let otherInit = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("other"), range))

        let fallbackID = ExprID(rawValue: 601)
        _ = fixture.driver.controlFlowChecker.inferDestructuringDeclExpr(
            fallbackID,
            names: [fixture.interner.intern("c")],
            isMutable: true,
            initializer: otherInit,
            range: range,
            ctx: ctx,
            locals: &locals
        )

        XCTAssertEqual(locals[fixture.interner.intern("c")]?.type, fixture.types.booleanType)
    }

    func testInferForDestructuringExprAndRangeDetection() {
        let fixture = makeTypeCheckFixture()
        let ctx = fixture.makeInferenceContext()
        var locals: LocalBindings = [:]
        let range = makeRange()

        let lhs = fixture.astArena.appendExpr(.intLiteral(0, range))
        let rhs = fixture.astArena.appendExpr(.intLiteral(3, range))
        let rangeExpr = fixture.astArena.appendExpr(.binary(op: .rangeTo, lhs: lhs, rhs: rhs, range: range))
        let bodyExpr = fixture.astArena.appendExpr(.intLiteral(1, range))

        let loopID = ExprID(rawValue: 700)
        let inferred = fixture.driver.controlFlowChecker.inferForDestructuringExpr(
            loopID,
            names: [fixture.interner.intern("x"), nil],
            iterableExpr: rangeExpr,
            bodyExpr: bodyExpr,
            range: range,
            ctx: ctx,
            locals: &locals
        )
        XCTAssertEqual(inferred, fixture.types.unitType)
        XCTAssertEqual(fixture.bindings.exprType(for: loopID), fixture.types.unitType)
        XCTAssertTrue(ControlFlowTypeChecker.isRangeExpression(rangeExpr, ast: fixture.ast))
        let rangeUntilExpr = fixture.astArena.appendExpr(.binary(op: .rangeUntil, lhs: lhs, rhs: rhs, range: range))
        let downToExpr = fixture.astArena.appendExpr(.binary(op: .downTo, lhs: lhs, rhs: rhs, range: range))
        let stepExpr = fixture.astArena.appendExpr(.binary(op: .step, lhs: lhs, rhs: rhs, range: range))
        let addExpr = fixture.astArena.appendExpr(.binary(op: .add, lhs: lhs, rhs: rhs, range: range))
        XCTAssertTrue(ControlFlowTypeChecker.isRangeExpression(rangeUntilExpr, ast: fixture.ast))
        XCTAssertTrue(ControlFlowTypeChecker.isRangeExpression(downToExpr, ast: fixture.ast))
        XCTAssertTrue(ControlFlowTypeChecker.isRangeExpression(stepExpr, ast: fixture.ast))
        XCTAssertFalse(ControlFlowTypeChecker.isRangeExpression(addExpr, ast: fixture.ast))
        XCTAssertFalse(ControlFlowTypeChecker.isRangeExpression(ExprID(rawValue: 9999), ast: fixture.ast))
    }

    func testEmitSubtypeConstraintEmitsPlatformWarningWithRange() {
        let fixture = makeTypeCheckFixture()
        let range = makeRange(start: 10, end: 20)
        let platformAny = fixture.types.withNullability(.platformType, for: fixture.types.anyType)
        fixture.driver.emitSubtypeConstraint(
            left: platformAny,
            right: fixture.types.anyType,
            range: range,
            solver: ConstraintSolver(),
            sema: fixture.sema,
            diagnostics: fixture.diagnostics
        )
        let warning = fixture.diagnostics.diagnostics.first { $0.code == "KSWIFTK-SEMA-PLATFORM" }
        XCTAssertNotNil(warning)
        XCTAssertEqual(warning?.primaryRange, range)
    }

    func testEmitSubtypeConstraintSuppressesPlatformWarningWhenFlagIsSet() {
        let fixture = makeTypeCheckFixture()
        let range = makeRange(start: 30, end: 40)
        let platformAny = fixture.types.withNullability(.platformType, for: fixture.types.anyType)
        fixture.driver.emitSubtypeConstraint(
            left: platformAny,
            right: fixture.types.anyType,
            range: range,
            solver: ConstraintSolver(),
            sema: fixture.sema,
            diagnostics: fixture.diagnostics,
            suppressPlatformWarning: true
        )
        XCTAssertFalse(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-PLATFORM" })
    }

    func testEmitSubtypeConstraintSkipsPlatformWarningWithoutRange() {
        let fixture = makeTypeCheckFixture()
        let platformAny = fixture.types.withNullability(.platformType, for: fixture.types.anyType)
        fixture.driver.emitSubtypeConstraint(
            left: platformAny,
            right: fixture.types.anyType,
            range: nil,
            solver: ConstraintSolver(),
            sema: fixture.sema,
            diagnostics: fixture.diagnostics
        )
        XCTAssertFalse(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-PLATFORM" })
    }
}

private struct TypeCheckFixture {
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    let symbols: SymbolTable
    let types: TypeSystem
    let bindings: BindingTable
    let sema: SemaModule
    let astArena: ASTArena
    let ast: ASTModule
    let resolver: OverloadResolver
    let dataFlow: DataFlowAnalyzer
    let driver: TypeCheckDriver

    func makeInferenceContext() -> TypeInferenceContext {
        let scope = FileScope(parent: nil, symbols: symbols)
        return TypeInferenceContext(
            ast: ast,
            sema: sema,
            semaCtx: sema,
            resolver: resolver,
            dataFlow: dataFlow,
            interner: interner,
            scope: scope,
            implicitReceiverType: nil,
            loopDepth: 0,
            loopLabelStack: [], lambdaLabelStack: [],
            exportBlockLocalsForExpr: nil,
            flowState: DataFlowState(),
            currentFileID: FileID(rawValue: 0),
            enclosingClassSymbol: nil,
            visibilityChecker: VisibilityChecker(symbols: symbols),
            outerReceiverTypes: [],
            semaCacheContext: nil
        )
    }
}

private func makeTypeCheckFixture() -> TypeCheckFixture {
    let interner = StringInterner()
    let diagnostics = DiagnosticEngine()
    let symbols = SymbolTable()
    let types = TypeSystem()
    let bindings = BindingTable()
    let sema = SemaModule(
        symbols: symbols,
        types: types,
        bindings: bindings,
        diagnostics: diagnostics
    )

    let astArena = ASTArena()
    let ast = ASTModule(
        files: [
            ASTFile(
                fileID: FileID(rawValue: 0),
                packageFQName: [interner.intern("pkg")],
                imports: [],
                topLevelDecls: [],
                scriptBody: []
            ),
        ],
        arena: astArena,
        declarationCount: 0,
        tokenCount: 0
    )

    let resolver = OverloadResolver()
    let dataFlow = DataFlowAnalyzer()
    let driver = TypeCheckDriver(
        ast: ast,
        sema: sema,
        semaCtx: sema,
        solver: ConstraintSolver(),
        resolver: resolver,
        dataFlow: dataFlow,
        interner: interner,
        diagnostics: diagnostics,
        semaCacheContext: nil
    )

    return TypeCheckFixture(
        interner: interner,
        diagnostics: diagnostics,
        symbols: symbols,
        types: types,
        bindings: bindings,
        sema: sema,
        astArena: astArena,
        ast: ast,
        resolver: resolver,
        dataFlow: dataFlow,
        driver: driver
    )
}
