import Foundation

extension BuildKIRPhase {
    func lowerObjectLiteralExpr(
        _ exprID: ExprID,
        superTypes: [TypeRefID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let objectValueType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
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

    private func syntheticObjectLiteralSymbols(
        for exprID: ExprID,
        interner: StringInterner
    ) -> (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString) {
        if let existing = syntheticObjectLiteralSymbolsByExprID[exprID] {
            return existing
        }
        let nominalSymbol = allocateSyntheticGeneratedSymbol()
        let constructorSymbol = allocateSyntheticGeneratedSymbol()
        let constructorName = interner.intern("kk_object_literal_\(exprID.rawValue)")
        let generated = (
            nominalSymbol: nominalSymbol,
            constructorSymbol: constructorSymbol,
            constructorName: constructorName
        )
        syntheticObjectLiteralSymbolsByExprID[exprID] = generated
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
        guard emittedObjectLiteralExprIDs.insert(exprID).inserted else {
            return
        }

        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbols.nominalSymbol)))
        pendingGeneratedCallableDeclIDs.append(nominalDeclID)

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let storageSlotCount = max(1, superTypeCount)
        let slotCountExpr = arena.appendExpr(.intLiteral(Int64(storageSlotCount)), type: intType)
        let objectEntityExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: objectValueType)
        var body: [KIRInstruction] = [.beginBlock]
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(Int64(storageSlotCount))))
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_new"),
            arguments: [slotCountExpr],
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
        pendingGeneratedCallableDeclIDs.append(constructorDeclID)
    }
}
