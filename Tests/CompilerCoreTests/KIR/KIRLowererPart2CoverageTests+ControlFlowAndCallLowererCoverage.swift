@testable import CompilerCore
import XCTest

// MARK: - ControlFlow and Call lowerer tests extracted to reduce file length.

extension KIRLowererPart2CoverageTests {
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
        XCTAssertTrue(
            fixture.driver.controlFlowLowerer.isCatchAllType(fixture.types.nullableAnyType, sema: fixture.sema)
        )
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
            interner: fixture.interner,
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
        let colorType = fixture.types.make(
            .classType(ClassType(classSymbol: colorSym, args: [], nullability: .nonNull))
        )
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
        let exprType = fixture.types.make(
            .classType(ClassType(classSymbol: exprSym, args: [], nullability: .nonNull))
        )
        let nestedObjectSym = defineSymbol(in: fixture, kind: .object, fqName: ["Expr", "A"])
        fixture.symbols.setParentSymbol(exprSym, for: nestedObjectSym)
        let nestedObjectType = fixture.types.make(
            .classType(ClassType(classSymbol: nestedObjectSym, args: [], nullability: .nonNull))
        )

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
