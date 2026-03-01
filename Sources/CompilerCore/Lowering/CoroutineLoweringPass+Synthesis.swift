import Foundation

extension CoroutineLoweringPass {
    struct ContinuationNominal {
        let typeSymbol: SymbolID
        let continuationType: TypeID
        let spillSlotByExpr: [KIRExprID: Int64]
    }

    func synthesizeContinuationNominalIfPossible(
        original: KIRFunction,
        loweredName: InternedString,
        plan: SuspendLoweringPlan,
        sema: SemaModule?,
        interner: StringInterner,
        existingSymbolFQNames: inout Set<[InternedString]>
    ) -> ContinuationNominal? {
        guard let sema, let originalSymbol = sema.symbols.symbol(original.symbol) else {
            return nil
        }

        let typeBaseName = interner.intern(interner.resolve(loweredName) + "$Cont")
        let ownerFQNamePrefix = Array(originalSymbol.fqName.dropLast())
        let typeName = uniqueNestedSymbolName(
            preferred: typeBaseName,
            ownerFQNamePrefix: ownerFQNamePrefix,
            existingSymbolFQNames: &existingSymbolFQNames,
            interner: interner
        )
        let typeFQName = ownerFQNamePrefix + [typeName]

        let typeSymbol = sema.symbols.define(
            kind: .class,
            name: typeName,
            fqName: typeFQName,
            declSite: originalSymbol.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let continuationType = sema.types.make(
            .classType(
                ClassType(
                    classSymbol: typeSymbol,
                    args: [],
                    nullability: .nullable
                )
            )
        )

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let anyNullableType = sema.types.nullableAnyType

        let labelFieldName = interner.intern("$label")
        let labelFieldSymbol = sema.symbols.define(
            kind: .field,
            name: labelFieldName,
            fqName: typeFQName + [labelFieldName],
            declSite: originalSymbol.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.symbols.setPropertyType(intType, for: labelFieldSymbol)

        let completionFieldName = interner.intern("$completion")
        let completionFieldSymbol = sema.symbols.define(
            kind: .field,
            name: completionFieldName,
            fqName: typeFQName + [completionFieldName],
            declSite: originalSymbol.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.symbols.setPropertyType(anyNullableType, for: completionFieldSymbol)

        let spilledExprs = plan.spillPlan.slotByExpr.keys.sorted(by: { lhs, rhs in
            let lhsSlot = plan.spillPlan.slotByExpr[lhs] ?? 0
            let rhsSlot = plan.spillPlan.slotByExpr[rhs] ?? 0
            if lhsSlot != rhsSlot {
                return lhsSlot < rhsSlot
            }
            return lhs.rawValue < rhs.rawValue
        })

        var spillFieldByExpr: [KIRExprID: SymbolID] = [:]
        for (index, exprID) in spilledExprs.enumerated() {
            let spillFieldName = interner.intern("$spill\(index)")
            let spillFieldSymbol = sema.symbols.define(
                kind: .field,
                name: spillFieldName,
                fqName: typeFQName + [spillFieldName],
                declSite: originalSymbol.declSite,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setPropertyType(anyNullableType, for: spillFieldSymbol)
            spillFieldByExpr[exprID] = spillFieldSymbol
        }

        let objectHeaderWords = 2
        var fieldOffsets: [SymbolID: Int] = [:]
        var nextFieldOffset = objectHeaderWords
        fieldOffsets[labelFieldSymbol] = nextFieldOffset
        nextFieldOffset += 1
        fieldOffsets[completionFieldSymbol] = nextFieldOffset
        nextFieldOffset += 1
        for exprID in spilledExprs {
            guard let spillField = spillFieldByExpr[exprID] else {
                continue
            }
            fieldOffsets[spillField] = nextFieldOffset
            nextFieldOffset += 1
        }

        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: objectHeaderWords,
                instanceFieldCount: fieldOffsets.count,
                instanceSizeWords: objectHeaderWords + fieldOffsets.count,
                fieldOffsets: fieldOffsets,
                vtableSlots: [:],
                itableSlots: [:],
                vtableSize: 0,
                itableSize: 0,
                superClass: nil
            ),
            for: typeSymbol
        )

        var spillSlotByExpr: [KIRExprID: Int64] = [:]
        if let firstSpillExpr = spilledExprs.first,
           let firstSpillField = spillFieldByExpr[firstSpillExpr],
           let baseOffset = fieldOffsets[firstSpillField]
        {
            for exprID in spilledExprs {
                guard let fieldSymbol = spillFieldByExpr[exprID],
                      let offset = fieldOffsets[fieldSymbol]
                else {
                    continue
                }
                spillSlotByExpr[exprID] = Int64(offset - baseOffset)
            }
        }

        return ContinuationNominal(
            typeSymbol: typeSymbol,
            continuationType: continuationType,
            spillSlotByExpr: spillSlotByExpr
        )
    }

    func uniqueNestedSymbolName(
        preferred: InternedString,
        ownerFQNamePrefix: [InternedString],
        existingSymbolFQNames: inout Set<[InternedString]>,
        interner: StringInterner
    ) -> InternedString {
        var candidate = preferred
        var candidateFQName = ownerFQNamePrefix + [candidate]
        if existingSymbolFQNames.insert(candidateFQName).inserted {
            return candidate
        }

        let base = interner.resolve(preferred)
        var suffix = 1
        while true {
            candidate = interner.intern("\(base)$\(suffix)")
            candidateFQName = ownerFQNamePrefix + [candidate]
            if existingSymbolFQNames.insert(candidateFQName).inserted {
                return candidate
            }
            suffix += 1
        }
    }

    func defineSyntheticCoroutineFunctionSymbol(
        original: KIRFunction,
        loweredName: InternedString,
        nextSyntheticSymbol: inout Int32,
        sema: SemaModule?
    ) -> SymbolID {
        guard let sema, let originalSymbol = sema.symbols.symbol(original.symbol) else {
            return allocateSyntheticSymbol(&nextSyntheticSymbol)
        }
        let loweredFQName = Array(originalSymbol.fqName.dropLast()) + [loweredName]
        return sema.symbols.define(
            kind: .function,
            name: loweredName,
            fqName: loweredFQName,
            declSite: originalSymbol.declSite,
            visibility: originalSymbol.visibility,
            flags: [.synthetic, .static]
        )
    }

    func defineSyntheticContinuationParameterSymbol(
        owner: SymbolID,
        loweredName _: InternedString,
        nextSyntheticSymbol: inout Int32,
        sema: SemaModule?,
        interner: StringInterner
    ) -> SymbolID {
        guard let sema, let loweredSymbol = sema.symbols.symbol(owner) else {
            return allocateSyntheticSymbol(&nextSyntheticSymbol)
        }
        let parameterName = interner.intern("$continuation")
        return sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: loweredSymbol.fqName + [parameterName],
            declSite: loweredSymbol.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
    }

    func updateLoweredFunctionSignatureIfPossible(
        loweredSymbol: SymbolID,
        continuationParameterSymbol: SymbolID,
        originalSymbol: SymbolID,
        continuationType: TypeID,
        sema: SemaModule?
    ) {
        guard let sema else {
            return
        }
        let originalSignature = sema.symbols.functionSignature(for: originalSymbol)
        let loweredParameterTypes = (originalSignature?.parameterTypes ?? []) + [continuationType]
        let loweredValueSymbols = (originalSignature?.valueParameterSymbols ?? []) + [continuationParameterSymbol]
        let loweredDefaults = (originalSignature?.valueParameterHasDefaultValues ?? []) + [false]
        let loweredVararg = (originalSignature?.valueParameterIsVararg ?? []) + [false]
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: originalSignature?.receiverType,
                parameterTypes: loweredParameterTypes,
                returnType: continuationType,
                isSuspend: false,
                valueParameterSymbols: loweredValueSymbols,
                valueParameterHasDefaultValues: loweredDefaults,
                valueParameterIsVararg: loweredVararg,
                typeParameterSymbols: originalSignature?.typeParameterSymbols ?? [],
                reifiedTypeParameterIndices: originalSignature?.reifiedTypeParameterIndices ?? []
            ),
            for: loweredSymbol
        )
    }
}
