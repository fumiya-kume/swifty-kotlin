@testable import CompilerCore
import XCTest

final class KIRLowererPart2CoverageTests: XCTestCase {
    func testLambdaLowererPart2TraversesNestedExpressionsAndDetectsImplicitReceiver() {
        let fixture = makeDirectKIRFixture()
        let range = makeRange()
        let typeRefID = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: false)
        )

        let capturedSymbol = defineSymbol(
            in: fixture,
            kind: .valueParameter,
            fqName: ["pkg", "captured"]
        )

        func appendNameRef(_ name: String) -> ExprID {
            let id = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern(name), range))
            fixture.bindings.bindIdentifier(id, symbol: capturedSymbol)
            return id
        }

        let lhs = appendNameRef("lhs")
        let rhs = appendNameRef("rhs")
        let receiver = appendNameRef("receiver")
        let iterable = appendNameRef("iterable")
        let condition = appendNameRef("condition")
        let value = appendNameRef("value")

        let stringTemplate = fixture.astArena.appendExpr(
            .stringTemplate(parts: [.literal(fixture.interner.intern("prefix")), .expression(lhs)], range: range)
        )
        let callExpr = fixture.astArena.appendExpr(
            .call(
                callee: receiver,
                typeArgs: [],
                args: [CallArgument(expr: rhs)],
                range: range
            )
        )
        let memberCallExpr = fixture.astArena.appendExpr(
            .memberCall(
                receiver: receiver,
                callee: fixture.interner.intern("member"),
                typeArgs: [],
                args: [CallArgument(expr: value)],
                range: range
            )
        )
        let safeMemberCallExpr = fixture.astArena.appendExpr(
            .safeMemberCall(
                receiver: receiver,
                callee: fixture.interner.intern("safe"),
                typeArgs: [],
                args: [CallArgument(expr: value)],
                range: range
            )
        )
        let indexedAssignExpr = fixture.astArena.appendExpr(
            .indexedAssign(receiver: receiver, indices: [lhs, rhs], value: value, range: range)
        )
        let indexedAccessExpr = fixture.astArena.appendExpr(
            .indexedAccess(receiver: receiver, indices: [lhs], range: range)
        )
        let indexedCompoundExpr = fixture.astArena.appendExpr(
            .indexedCompoundAssign(op: .plusAssign, receiver: receiver, indices: [lhs], value: rhs, range: range)
        )
        let whenExpr = fixture.astArena.appendExpr(
            .whenExpr(
                subject: lhs,
                branches: [WhenBranch(conditions: [rhs], body: value, range: range)],
                elseExpr: receiver,
                range: range
            )
        )
        let ifExpr = fixture.astArena.appendExpr(
            .ifExpr(condition: condition, thenExpr: lhs, elseExpr: rhs, range: range)
        )
        let catchBody = fixture.astArena.appendExpr(.blockExpr(statements: [rhs], trailingExpr: nil, range: range))
        let tryExpr = fixture.astArena.appendExpr(
            .tryExpr(
                body: lhs,
                catchClauses: [CatchClause(paramName: fixture.interner.intern("e"), paramTypeName: fixture.interner.intern("Int"), body: catchBody, range: range)],
                finallyExpr: value,
                range: range
            )
        )
        let unaryExpr = fixture.astArena.appendExpr(.unaryExpr(op: .unaryMinus, operand: lhs, range: range))
        let isCheckExpr = fixture.astArena.appendExpr(.isCheck(expr: lhs, type: typeRefID, negated: false, range: range))
        let asCastExpr = fixture.astArena.appendExpr(.asCast(expr: lhs, type: typeRefID, isSafe: true, range: range))
        let nullAssertExpr = fixture.astArena.appendExpr(.nullAssert(expr: lhs, range: range))
        let throwExpr = fixture.astArena.appendExpr(.throwExpr(value: lhs, range: range))
        let lambdaExpr = fixture.astArena.appendExpr(
            .lambdaLiteral(params: [fixture.interner.intern("p")], body: rhs, label: nil, range: range)
        )
        let callableRefExpr = fixture.astArena.appendExpr(
            .callableRef(receiver: receiver, member: fixture.interner.intern("invoke"), range: range)
        )
        let localFunExpr = fixture.astArena.appendExpr(
            .localFunDecl(
                name: fixture.interner.intern("localFun"),
                valueParams: [],
                returnType: nil,
                body: .block([lhs], range),
                range: range
            )
        )
        let localFunUnitExpr = fixture.astArena.appendExpr(
            .localFunDecl(
                name: fixture.interner.intern("localUnit"),
                valueParams: [],
                returnType: nil,
                body: .unit,
                range: range
            )
        )
        let forExpr = fixture.astArena.appendExpr(
            .forExpr(loopVariable: nil, iterable: iterable, body: lhs, range: range)
        )
        let whileExpr = fixture.astArena.appendExpr(
            .whileExpr(condition: condition, body: rhs, range: range)
        )
        let doWhileExpr = fixture.astArena.appendExpr(
            .doWhileExpr(body: lhs, condition: condition, range: range)
        )
        let returnExpr = fixture.astArena.appendExpr(.returnExpr(value: lhs, range: range))
        let inExpr = fixture.astArena.appendExpr(.inExpr(lhs: lhs, rhs: rhs, range: range))
        let notInExpr = fixture.astArena.appendExpr(.notInExpr(lhs: lhs, rhs: rhs, range: range))
        let destructuringExpr = fixture.astArena.appendExpr(
            .destructuringDecl(names: [fixture.interner.intern("a"), fixture.interner.intern("b")], isMutable: false, initializer: lhs, range: range)
        )
        let forDestructuringExpr = fixture.astArena.appendExpr(
            .forDestructuringExpr(names: [fixture.interner.intern("a")], iterable: iterable, body: rhs, range: range)
        )
        let memberAssignExpr = fixture.astArena.appendExpr(
            .memberAssign(receiver: receiver, callee: fixture.interner.intern("prop"), value: value, range: range)
        )
        let blockWithReceiverRefs = fixture.astArena.appendExpr(
            .blockExpr(
                statements: [
                    stringTemplate,
                    forExpr,
                    whileExpr,
                    doWhileExpr,
                    callExpr,
                    memberCallExpr,
                    safeMemberCallExpr,
                    indexedAssignExpr,
                    indexedAccessExpr,
                    indexedCompoundExpr,
                    whenExpr,
                    ifExpr,
                    tryExpr,
                    unaryExpr,
                    isCheckExpr,
                    asCastExpr,
                    nullAssertExpr,
                    throwExpr,
                    lambdaExpr,
                    callableRefExpr,
                    localFunExpr,
                    localFunUnitExpr,
                    returnExpr,
                    inExpr,
                    notInExpr,
                    destructuringExpr,
                    forDestructuringExpr,
                    memberAssignExpr,
                    fixture.astArena.appendExpr(.thisRef(label: nil, range)),
                    // swiftlint:disable:next trailing_comma
                    fixture.astArena.appendExpr(.superRef(interfaceQualifier: nil, range)),
                ],
                trailingExpr: rhs,
                range: range
            )
        )

        var referenced: [SymbolID] = []
        var seen: Set<SymbolID> = []
        fixture.driver.lambdaLowerer.collectBoundIdentifierSymbols(
            in: blockWithReceiverRefs,
            ast: fixture.ast,
            sema: fixture.sema,
            referenced: &referenced,
            seen: &seen
        )

        XCTAssertTrue(referenced.contains(capturedSymbol))
        XCTAssertEqual(Set(referenced), [capturedSymbol])

        XCTAssertTrue(
            fixture.driver.lambdaLowerer.containsImplicitReceiverReference(in: blockWithReceiverRefs, ast: fixture.ast)
        )

        let onlyLiteral = fixture.astArena.appendExpr(.intLiteral(1, range))
        XCTAssertFalse(
            fixture.driver.lambdaLowerer.containsImplicitReceiverReference(in: onlyLiteral, ast: fixture.ast)
        )
    }

    func testLambdaLowererPart2CaptureHelpersCoverBranchPaths() {
        let fixture = makeDirectKIRFixture()

        let localSymbol = defineSymbol(in: fixture, kind: .local, fqName: ["pkg", "local"])
        let parameterSymbol = defineSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "param"])
        let classSymbol = defineSymbol(in: fixture, kind: .class, fqName: ["pkg", "Nominal"])

        let localExpr = fixture.kirArena.appendExpr(.temporary(0), type: fixture.types.anyType)
        fixture.driver.ctx.localValuesBySymbol[localSymbol] = localExpr

        let receiverExpr = fixture.kirArena.appendExpr(.temporary(1), type: fixture.types.anyType)
        fixture.driver.ctx.currentImplicitReceiverSymbol = classSymbol
        fixture.driver.ctx.currentImplicitReceiverExprID = receiverExpr

        let lambdaExprID = ExprID(rawValue: 44)
        let syntheticParamSymbol = fixture.driver.lambdaLowerer.syntheticLambdaParamSymbol(
            lambdaExprID: lambdaExprID,
            paramIndex: 0
        )

        XCTAssertFalse(
            fixture.driver.lambdaLowerer.canCaptureSymbolForLambda(
                syntheticParamSymbol,
                lambdaExprID: lambdaExprID,
                lambdaParamCount: 1,
                sema: fixture.sema
            )
        )
        XCTAssertTrue(
            fixture.driver.lambdaLowerer.canCaptureSymbolForLambda(
                localSymbol,
                lambdaExprID: lambdaExprID,
                lambdaParamCount: 0,
                sema: fixture.sema
            )
        )
        XCTAssertTrue(
            fixture.driver.lambdaLowerer.canCaptureSymbolForLambda(
                classSymbol,
                lambdaExprID: lambdaExprID,
                lambdaParamCount: 0,
                sema: fixture.sema
            )
        )
        XCTAssertFalse(
            fixture.driver.lambdaLowerer.canCaptureSymbolForLambda(
                SymbolID(rawValue: 9999),
                lambdaExprID: lambdaExprID,
                lambdaParamCount: 0,
                sema: fixture.sema
            )
        )
        XCTAssertTrue(
            fixture.driver.lambdaLowerer.canCaptureSymbolForLambda(
                parameterSymbol,
                lambdaExprID: lambdaExprID,
                lambdaParamCount: 0,
                sema: fixture.sema
            )
        )

        var emit = KIRLoweringEmitContext()
        let captured = fixture.driver.lambdaLowerer.captureValueExpr(
            for: localSymbol,
            sema: fixture.sema,
            arena: fixture.kirArena,
            emit: &emit
        )
        XCTAssertEqual(captured, localExpr)

        let unique = fixture.driver.lambdaLowerer.uniqueSymbolsPreservingOrder([
            localSymbol,
            parameterSymbol,
            localSymbol,
            parameterSymbol,
        ])
        XCTAssertEqual(unique, [localSymbol, parameterSymbol])

        let receiverCaptured = fixture.driver.lambdaLowerer.captureValueExpr(
            for: classSymbol,
            sema: fixture.sema,
            arena: fixture.kirArena,
            emit: &emit
        )
        XCTAssertEqual(receiverCaptured, receiverExpr)

        _ = fixture.driver.lambdaLowerer.captureValueExpr(
            for: parameterSymbol,
            sema: fixture.sema,
            arena: fixture.kirArena,
            emit: &emit
        )
        XCTAssertFalse(emit.instructions.isEmpty)

        let nonCapturable = fixture.driver.lambdaLowerer.captureValueExpr(
            for: SymbolID(rawValue: 7777),
            sema: fixture.sema,
            arena: fixture.kirArena,
            emit: &emit
        )
        XCTAssertNil(nonCapturable)
    }

}

struct DirectKIRFixture {
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    let symbols: SymbolTable
    let types: TypeSystem
    let bindings: BindingTable
    let sema: SemaModule
    let astArena: ASTArena
    let ast: ASTModule
    let kirArena: KIRArena
    let driver: KIRLoweringDriver

    func makeShared(
        propertyConstantInitializers: [SymbolID: KIRExprKind] = [:]
    ) -> KIRLoweringSharedContext {
        KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: kirArena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
    }
}

func makeDirectKIRFixture() -> DirectKIRFixture {
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
    let file = ASTFile(
        fileID: FileID(rawValue: 0),
        packageFQName: [interner.intern("pkg")],
        imports: [],
        topLevelDecls: [],
        scriptBody: []
    )
    let ast = ASTModule(
        files: [file],
        arena: astArena,
        declarationCount: 0,
        tokenCount: 0
    )

    let kirArena = KIRArena()
    let loweringContext = KIRLoweringContext()
    loweringContext.initializeSyntheticLambdaSymbolAllocator(sema: sema)
    let driver = KIRLoweringDriver(ctx: loweringContext)

    return DirectKIRFixture(
        interner: interner,
        diagnostics: diagnostics,
        symbols: symbols,
        types: types,
        bindings: bindings,
        sema: sema,
        astArena: astArena,
        ast: ast,
        kirArena: kirArena,
        driver: driver
    )
}

func defineSymbol(
    in fixture: DirectKIRFixture,
    kind: SymbolKind,
    fqName: [String],
    flags: SymbolFlags = []
) -> SymbolID {
    precondition(!fqName.isEmpty)
    let interned = fqName.map { fixture.interner.intern($0) }
    return fixture.symbols.define(
        kind: kind,
        name: interned.last!,
        fqName: interned,
        declSite: nil,
        visibility: .public,
        flags: flags
    )
}
