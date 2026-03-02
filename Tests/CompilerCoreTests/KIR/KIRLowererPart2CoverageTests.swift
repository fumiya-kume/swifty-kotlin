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

    func testControlFlowLowererPart2CatchBindingAndLegacyTypeResolution() {
        let fixture = makeDirectKIRFixture()
        let range = makeRange()

        let catchExprID = fixture.astArena.appendExpr(.intLiteral(0, range))
        let catchClause = CatchClause(
            paramName: fixture.interner.intern("e"),
            paramTypeName: fixture.interner.intern("Int"),
            body: catchExprID,
            range: range
        )

        let boundSymbol = defineSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "e"])
        let boundType = fixture.types.make(.primitive(.int, .nonNull))
        fixture.bindings.bindCatchClause(
            catchExprID,
            binding: CatchClauseBinding(parameterSymbol: boundSymbol, parameterType: boundType)
        )

        let resolvedExisting = fixture.driver.controlFlowLowerer.resolveCatchClauseBinding(
            catchClause,
            sema: fixture.sema,
            interner: fixture.interner
        )
        XCTAssertEqual(resolvedExisting.parameterSymbol, boundSymbol)
        XCTAssertEqual(resolvedExisting.parameterType, boundType)

        let fallbackExprID = fixture.astArena.appendExpr(.intLiteral(1, range))
        let fallbackClause = CatchClause(
            paramName: fixture.interner.intern("x"),
            paramTypeName: fixture.interner.intern("Long"),
            body: fallbackExprID,
            range: range
        )
        let fallbackSymbol = defineSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "x"])
        fixture.bindings.bindIdentifier(fallbackExprID, symbol: fallbackSymbol)

        let resolvedFallback = fixture.driver.controlFlowLowerer.resolveCatchClauseBinding(
            fallbackClause,
            sema: fixture.sema,
            interner: fixture.interner
        )
        XCTAssertEqual(resolvedFallback.parameterSymbol, fallbackSymbol)
        XCTAssertEqual(fixture.types.kind(of: resolvedFallback.parameterType), .primitive(.long, .nonNull))

        XCTAssertEqual(
            fixture.driver.controlFlowLowerer.resolveLegacyCatchClauseType(
                nil,
                sema: fixture.sema,
                interner: fixture.interner
            ),
            fixture.types.anyType
        )

        let builtinNames = [
            ("Int", TypeKind.primitive(.int, .nonNull)),
            ("Float", TypeKind.primitive(.float, .nonNull)),
            ("Double", TypeKind.primitive(.double, .nonNull)),
            ("Boolean", TypeKind.primitive(.boolean, .nonNull)),
            ("Char", TypeKind.primitive(.char, .nonNull)),
            ("String", TypeKind.primitive(.string, .nonNull)),
        ]

        for (name, expectedKind) in builtinNames {
            let resolved = fixture.driver.controlFlowLowerer.resolveLegacyCatchClauseType(
                fixture.interner.intern(name),
                sema: fixture.sema,
                interner: fixture.interner
            )
            XCTAssertEqual(fixture.types.kind(of: resolved), expectedKind)
        }

        let classSymbol = defineSymbol(in: fixture, kind: .class, fqName: ["CustomThrowable"])
        let resolvedClass = fixture.driver.controlFlowLowerer.resolveLegacyCatchClauseType(
            fixture.interner.intern("CustomThrowable"),
            sema: fixture.sema,
            interner: fixture.interner
        )
        XCTAssertEqual(
            fixture.types.kind(of: resolvedClass),
            .classType(ClassType(classSymbol: classSymbol, args: [], nullability: .nonNull))
        )

        let unresolvedType = fixture.driver.controlFlowLowerer.resolveLegacyCatchClauseType(
            fixture.interner.intern("MissingType"),
            sema: fixture.sema,
            interner: fixture.interner
        )
        XCTAssertEqual(unresolvedType, fixture.types.anyType)

        XCTAssertTrue(fixture.driver.controlFlowLowerer.isCatchAllType(fixture.types.anyType, sema: fixture.sema))
        XCTAssertTrue(fixture.driver.controlFlowLowerer.isCatchAllType(fixture.types.nullableAnyType, sema: fixture.sema))
        XCTAssertFalse(fixture.driver.controlFlowLowerer.isCatchAllType(fixture.types.intType, sema: fixture.sema))
    }

    func testControlFlowLowererPart2ForwardersEmitInstructions() {
        let fixture = makeDirectKIRFixture()
        let range = makeRange()

        let boolType = fixture.types.make(.primitive(.boolean, .nonNull))
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let iterableExpr = fixture.astArena.appendExpr(.intLiteral(10, range))
        fixture.bindings.bindExprType(iterableExpr, type: intType)
        let bodyExpr = fixture.astArena.appendExpr(.intLiteral(1, range))
        fixture.bindings.bindExprType(bodyExpr, type: intType)

        let forExprID = fixture.astArena.appendExpr(
            .forDestructuringExpr(
                names: [fixture.interner.intern("item")],
                iterable: iterableExpr,
                body: bodyExpr,
                range: range
            )
        )
        let componentSymbol = defineSymbol(
            in: fixture,
            kind: .local,
            fqName: ["__for_destructuring_\(forExprID.rawValue)", "item"]
        )
        fixture.symbols.setPropertyType(intType, for: componentSymbol)

        let conditionA = fixture.astArena.appendExpr(.boolLiteral(true, range))
        fixture.bindings.bindExprType(conditionA, type: boolType)
        let conditionB = fixture.astArena.appendExpr(.boolLiteral(false, range))
        fixture.bindings.bindExprType(conditionB, type: boolType)

        let whenExprID = fixture.astArena.appendExpr(
            .whenExpr(
                subject: nil,
                branches: [WhenBranch(conditions: [conditionA, conditionB], body: bodyExpr, range: range)],
                elseExpr: bodyExpr,
                range: range
            )
        )
        fixture.bindings.bindExprType(whenExprID, type: intType)

        var lowered = KIRLoweringEmitContext([
            .call(
                symbol: nil,
                callee: fixture.interner.intern("mayThrow"),
                arguments: [],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ),
        ])
        let exceptionSlot = fixture.kirArena.appendExpr(.temporary(3), type: fixture.types.anyType)
        let exceptionTypeSlot = fixture.kirArena.appendExpr(.temporary(4), type: intType)
        var emitted = KIRLoweringEmitContext()

        fixture.driver.controlFlowLowerer.appendThrowAwareInstructions(
            lowered,
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: 999,
            sema: fixture.sema,
            arena: fixture.kirArena,
            emit: &emitted
        )
        XCTAssertTrue(emitted.instructions.contains { instruction in
            guard case .jumpIfNotNull = instruction else { return false }
            return true
        })

        let shared = fixture.makeShared()
        _ = fixture.driver.controlFlowLowerer.lowerForDestructuringExpr(
            forExprID,
            names: [fixture.interner.intern("item")],
            iterableExpr: iterableExpr,
            bodyExpr: bodyExpr,
            shared: shared,
            emit: &emitted
        )

        _ = fixture.driver.controlFlowLowerer.lowerWhenExpr(
            whenExprID,
            subject: nil,
            branches: [WhenBranch(conditions: [conditionA, conditionB], body: bodyExpr, range: range)],
            elseExpr: bodyExpr,
            shared: shared,
            emit: &emitted
        )

        XCTAssertTrue(emitted.instructions.contains { instruction in
            if case .label = instruction { return true }
            return false
        })
        XCTAssertTrue(emitted.instructions.contains { instruction in
            if case .call = instruction { return true }
            return false
        })

        // Keep compiler warnings away for mutable local that needs to be var.
        lowered.instructions.append(.nop)
    }

    func testCallLowererPart2LowersClassNameMemberValuesAsDirectSymbolRefs() {
        let fixture = makeDirectKIRFixture()
        let range = makeRange()

        let colorSym = defineSymbol(in: fixture, kind: .enumClass, fqName: ["Color"])
        let colorType = fixture.types.make(.classType(ClassType(classSymbol: colorSym, args: [], nullability: .nonNull)))
        let redSym = defineSymbol(in: fixture, kind: .field, fqName: ["Color", "Red"])
        fixture.symbols.setPropertyType(colorType, for: redSym)

        let colorRef = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("Color"), range))
        fixture.bindings.bindIdentifier(colorRef, symbol: colorSym)
        fixture.bindings.bindExprType(colorRef, type: colorType)

        let redAccess = fixture.astArena.appendExpr(.memberCall(
            receiver: colorRef,
            callee: fixture.interner.intern("Red"),
            typeArgs: [],
            args: [],
            range: range
        ))
        fixture.bindings.bindIdentifier(redAccess, symbol: redSym)
        fixture.bindings.bindExprType(redAccess, type: colorType)

        var enumInstructions: [KIRInstruction] = []
        _ = fixture.driver.lowerExpr(
            redAccess,
            ast: fixture.ast,
            sema: fixture.sema,
            arena: fixture.kirArena,
            interner: fixture.interner,
            propertyConstantInitializers: [:],
            instructions: &enumInstructions
        )
        XCTAssertTrue(enumInstructions.contains { instruction in
            if case let .constValue(_, .symbolRef(symbol)) = instruction {
                return symbol == redSym
            }
            return false
        })
        XCTAssertFalse(enumInstructions.contains { instruction in
            if case .call = instruction {
                return true
            }
            return false
        })

        let exprSym = defineSymbol(in: fixture, kind: .class, fqName: ["Expr"])
        let exprType = fixture.types.make(.classType(ClassType(classSymbol: exprSym, args: [], nullability: .nonNull)))
        let nestedObjectSym = defineSymbol(in: fixture, kind: .object, fqName: ["Expr", "A"])
        fixture.symbols.setParentSymbol(exprSym, for: nestedObjectSym)
        let nestedObjectType = fixture.types.make(.classType(ClassType(classSymbol: nestedObjectSym, args: [], nullability: .nonNull)))

        let exprRef = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("Expr"), range))
        fixture.bindings.bindIdentifier(exprRef, symbol: exprSym)
        fixture.bindings.bindExprType(exprRef, type: exprType)

        let objectAccess = fixture.astArena.appendExpr(.memberCall(
            receiver: exprRef,
            callee: fixture.interner.intern("A"),
            typeArgs: [],
            args: [],
            range: range
        ))
        fixture.bindings.bindIdentifier(objectAccess, symbol: nestedObjectSym)
        fixture.bindings.bindExprType(objectAccess, type: nestedObjectType)

        var objectInstructions: [KIRInstruction] = []
        _ = fixture.driver.lowerExpr(
            objectAccess,
            ast: fixture.ast,
            sema: fixture.sema,
            arena: fixture.kirArena,
            interner: fixture.interner,
            propertyConstantInitializers: [:],
            instructions: &objectInstructions
        )
        XCTAssertTrue(objectInstructions.contains { instruction in
            if case let .constValue(_, .symbolRef(symbol)) = instruction {
                return symbol == nestedObjectSym
            }
            return false
        })
        XCTAssertFalse(objectInstructions.contains { instruction in
            if case .call = instruction {
                return true
            }
            return false
        })
    }
}

private struct DirectKIRFixture {
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

private func makeDirectKIRFixture() -> DirectKIRFixture {
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

private func defineSymbol(
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
