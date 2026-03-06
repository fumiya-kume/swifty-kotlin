import Foundation

/// Delegate class for KIR lowering: ObjectLiteralLowerer.
/// Holds an unowned reference to the driver for mutual recursion.
final class ObjectLiteralLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func lowerObjectLiteralExpr(
        _ exprID: ExprID,
        superTypes: [TypeRefID],
        declID: DeclID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let objectValueType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        if let declID,
           let decl = ast.arena.decl(declID),
           case let .objectDecl(objectDecl) = decl,
           !objectDecl.memberProperties.isEmpty,
           case let .classType(classType) = sema.types.kind(of: objectValueType)
        {
            return lowerStoredObjectLiteralExpr(
                exprID,
                objectDecl: objectDecl,
                objectSymbol: classType.classSymbol,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        let symbols = syntheticObjectLiteralSymbols(for: exprID, interner: interner)
        ensureObjectLiteralGeneratedDecls(
            exprID: exprID,
            superTypeCount: superTypes.count,
            objectValueType: objectValueType,
            symbols: symbols,
            sema: sema,
            arena: arena,
            interner: interner
        )

        let objectValue = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: objectValueType)
        instructions.append(.call(
            symbol: symbols.constructorSymbol,
            callee: symbols.constructorName,
            arguments: [],
            result: objectValue,
            canThrow: false,
            thrownResult: nil
        ))
        return objectValue
    }

    private func lowerStoredObjectLiteralExpr(
        _ exprID: ExprID,
        objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let objectValueType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        ensureObjectLiteralNominalDecl(exprID: exprID, objectSymbol: objectSymbol, arena: arena)

        let intType = sema.types.intType
        let layout = sema.symbols.nominalLayout(for: objectSymbol)
        let slotCount = Int64(max(layout?.instanceSizeWords ?? 1, 1))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol,
            sema: sema,
            interner: interner
        )

        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))

        let objectValue = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: objectValueType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: objectValue,
            canThrow: false,
            thrownResult: nil
        ))

        registerObjectLiteralSupertypes(
            objectSymbol: objectSymbol,
            objectValue: objectValue,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        let savedReceiverExprID = driver.ctx.currentImplicitReceiverExprID
        let savedReceiverSymbol = driver.ctx.currentImplicitReceiverSymbol
        driver.ctx.currentImplicitReceiverExprID = objectValue
        driver.ctx.currentImplicitReceiverSymbol = objectSymbol
        defer {
            driver.ctx.currentImplicitReceiverExprID = savedReceiverExprID
            driver.ctx.currentImplicitReceiverSymbol = savedReceiverSymbol
        }

        for propertyDeclID in objectDecl.memberProperties {
            guard let propertySymbol = sema.bindings.declSymbols[propertyDeclID],
                  let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl,
                  let initializer = propertyDecl.initializer,
                  let fieldOffset = layout?.fieldOffsets[propertySymbol]
            else {
                continue
            }
            let initializerValue = driver.lowerExpr(
                initializer,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let unusedResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [objectValue, offsetExpr, initializerValue],
                result: unusedResult,
                canThrow: true,
                thrownResult: nil
            ))
        }

        return objectValue
    }

    private func registerObjectLiteralSupertypes(
        objectSymbol: SymbolID,
        objectValue: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.intType
        let childTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol,
            sema: sema,
            interner: interner
        )
        let childExpr = arena.appendExpr(.intLiteral(childTypeID), type: intType)
        instructions.append(.constValue(result: childExpr, value: .intLiteral(childTypeID)))

        for superSymbol in sema.symbols.directSupertypes(for: objectSymbol) {
            let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: superSymbol,
                sema: sema,
                interner: interner
            )
            let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
            instructions.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
            let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            let superKind = sema.symbols.symbol(superSymbol)?.kind
            let registerCallee: InternedString = if superKind == .interface {
                interner.intern("kk_type_register_iface")
            } else {
                interner.intern("kk_type_register_super")
            }
            instructions.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [childExpr, parentExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }

    private func ensureObjectLiteralNominalDecl(
        exprID: ExprID,
        objectSymbol: SymbolID,
        arena: KIRArena
    ) {
        guard driver.ctx.emittedObjectLiteralExprIDs.insert(exprID).inserted else {
            return
        }
        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: objectSymbol)))
        driver.ctx.pendingGeneratedCallableDeclIDs.append(nominalDeclID)
    }

    private func syntheticObjectLiteralSymbols(
        for exprID: ExprID,
        interner: StringInterner
    ) -> (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString) {
        if let existing = driver.ctx.syntheticObjectLiteralSymbolsByExprID[exprID] {
            return existing
        }
        let nominalSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let constructorSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let constructorName = interner.intern("kk_object_literal_\(exprID.rawValue)")
        let generated = (
            nominalSymbol: nominalSymbol,
            constructorSymbol: constructorSymbol,
            constructorName: constructorName
        )
        driver.ctx.syntheticObjectLiteralSymbolsByExprID[exprID] = generated
        return generated
    }

    private func ensureObjectLiteralGeneratedDecls(
        exprID: ExprID,
        superTypeCount: Int,
        objectValueType: TypeID,
        symbols: (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString),
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        guard driver.ctx.emittedObjectLiteralExprIDs.insert(exprID).inserted else {
            return
        }

        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbols.nominalSymbol)))
        driver.ctx.pendingGeneratedCallableDeclIDs.append(nominalDeclID)

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let storageSlotCount = max(1, superTypeCount)
        let slotCountExpr = arena.appendExpr(.intLiteral(Int64(storageSlotCount)), type: intType)
        let classIDExpr = arena.appendExpr(.intLiteral(0), type: intType)
        let objectEntityExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: objectValueType)
        var body: [KIRInstruction] = [.beginBlock]
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(Int64(storageSlotCount))))
        body.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: objectEntityExpr,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(objectEntityExpr))
        body.append(.endBlock)

        let constructorDeclID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: symbols.constructorSymbol,
                    name: symbols.constructorName,
                    params: [],
                    returnType: objectValueType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        driver.ctx.pendingGeneratedCallableDeclIDs.append(constructorDeclID)
    }
}
