import Foundation

class EnumProcessor: CallTypeProcessorBase, CallTypeProcessor {
    
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let calleeName = calleeName else { return false }
        
        return enumStdlibSpecialCallKind(
            calleeName: calleeName,
            args: args,
            explicitTypeArgs: [], // canHandleでは型引数はチェックしない
            ctx: ctx,
            interner: ctx.interner,
            sema: ctx.sema
        ) != nil
    }
    
    func processCall(
        _ id: ExprID,
        calleeName: InternedString?,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        guard let calleeName = calleeName else { return nil }
        
        guard let enumSpecialKind = enumStdlibSpecialCallKind(
            calleeName: calleeName,
            args: args,
            explicitTypeArgs: explicitTypeArgs,
            ctx: ctx,
            interner: ctx.interner,
            sema: ctx.sema
        ) else {
            return nil
        }
        
        let sema = ctx.sema
        
        switch enumSpecialKind {
        case let .enumValues(_, arrayType, stubSymbol):
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: stubSymbol,
                    substitutedTypeArguments: explicitTypeArgs,
                    parameterMapping: [:]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValues)
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: arrayType)
            return arrayType
            
        case let .enumValueOf(enumType, stubSymbol):
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: stubSymbol,
                    substitutedTypeArguments: explicitTypeArgs,
                    parameterMapping: [0: 0]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValueOf)
            sema.bindings.bindExprType(id, type: enumType)
            return enumType
            
        case let .enumEntries(enumType, entriesType, stubSymbol):
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: stubSymbol,
                    substitutedTypeArguments: [enumType],
                    parameterMapping: [:]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumEntries)
            sema.bindings.bindExprType(id, type: entriesType)
            return entriesType
        }
    }
    
    // MARK: - Private Helper Methods
    
    private enum EnumStdlibSpecialCallKind {
        case enumValues(enumType: TypeID, arrayType: TypeID, stubSymbol: SymbolID)
        case enumValueOf(enumType: TypeID, stubSymbol: SymbolID)
        case enumEntries(enumType: TypeID, entriesType: TypeID, stubSymbol: SymbolID)
    }
    
    private func enumStdlibSpecialCallKind(
        calleeName: InternedString,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        ctx: TypeInferenceContext,
        interner: StringInterner,
        sema: SemaModule
    ) -> EnumStdlibSpecialCallKind? {
        let knownNames = KnownCompilerNames(interner: interner)
        let calleeNameStr = interner.resolve(calleeName)
        
        switch (calleeNameStr, args.count) {
        case ("enumValues", 0):
            return handleEnumValues(
                explicitTypeArgs: explicitTypeArgs,
                knownNames: knownNames,
                sema: sema,
                interner: interner
            )
            
        case ("enumValueOf", 1):
            return handleEnumValueOf(
                explicitTypeArgs: explicitTypeArgs,
                knownNames: knownNames,
                sema: sema,
                interner: interner
            )
            
        case ("enumEntries", 0):
            return handleEnumEntries(
                explicitTypeArgs: explicitTypeArgs,
                knownNames: knownNames,
                sema: sema,
                interner: interner
            )
            
        default:
            return nil
        }
    }
    
    private func handleEnumValues(
        explicitTypeArgs: [TypeID],
        knownNames: KnownCompilerNames,
        sema: SemaModule,
        interner: StringInterner
    ) -> EnumStdlibSpecialCallKind? {
        guard let enumType = explicitTypeArgs.first else { return nil }
        
        guard let enumValuesSymbol = sema.symbols.lookup(fqName: knownNames.kotlinEnumValuesFQName) else {
            return nil
        }
        
        let arrayType = makeSyntheticArrayType(
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            elementType: enumType
        ) ?? sema.types.anyType
        
        return .enumValues(enumType: enumType, arrayType: arrayType, stubSymbol: enumValuesSymbol)
    }
    
    private func handleEnumValueOf(
        explicitTypeArgs: [TypeID],
        knownNames: KnownCompilerNames,
        sema: SemaModule,
        interner: StringInterner
    ) -> EnumStdlibSpecialCallKind? {
        guard let enumType = explicitTypeArgs.first else { return nil }
        
        guard let enumValueOfSymbol = sema.symbols.lookup(fqName: knownNames.kotlinEnumValueOfFQName) else {
            return nil
        }
        
        return .enumValueOf(enumType: enumType, stubSymbol: enumValueOfSymbol)
    }
    
    private func handleEnumEntries(
        explicitTypeArgs: [TypeID],
        knownNames: KnownCompilerNames,
        sema: SemaModule,
        interner: StringInterner
    ) -> EnumStdlibSpecialCallKind? {
        guard let enumType = explicitTypeArgs.first else { return nil }
        
        guard let enumEntriesSymbol = sema.symbols.lookup(fqName: knownNames.kotlinEnumEntriesFQName) else {
            return nil
        }
        
        let entriesFQName = [interner.intern("kotlin"), interner.intern("enums"), interner.intern("EnumEntries")]
        let entriesType: TypeID
        
        if let entriesSymbol = sema.symbols.lookup(fqName: entriesFQName) {
            entriesType = sema.types.make(.classType(ClassType(
                classSymbol: entriesSymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
        } else {
            entriesType = sema.types.anyType
        }
        
        return .enumEntries(enumType: enumType, entriesType: entriesType, stubSymbol: enumEntriesSymbol)
    }
}
