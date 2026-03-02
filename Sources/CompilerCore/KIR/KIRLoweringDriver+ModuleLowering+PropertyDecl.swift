import Foundation

extension KIRLoweringDriver {
    /// Lower a top-level property declaration into KIR declarations, collecting
    /// any initialisation instructions and delegate storage mappings.
    func lowerTopLevelPropertyDecl(
        _ propertyDecl: PropertyDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext,
        delegateStorageSymbolByPropertySymbol: inout [SymbolID: SymbolID]
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena

        var declIDs: [KIRDeclID] = []
        let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
        let isExtensionProperty = propertyDecl.receiverType != nil
        if !isExtensionProperty {
            let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propType)))
            declIDs.append(kirID)
        }

        // Emit backing field global for properties with custom accessors.
        if !isExtensionProperty,
           let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol)
        {
            let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol) ?? propType
            let backingFieldKirID = arena.appendDecl(
                .global(KIRGlobal(symbol: backingFieldSymbol, type: backingFieldType))
            )
            declIDs.append(backingFieldKirID)
        }

        lowerPropertyAccessors(
            propertyDecl, symbol: symbol, propType: propType,
            shared: shared, declIDs: &declIDs
        )

        lowerPropertyInitializer(
            propertyDecl, symbol: symbol, propType: propType,
            isExtensionProperty: isExtensionProperty,
            shared: shared,
            allTopLevelInitInstructions: &allTopLevelInitInstructions,
            declIDs: &declIDs
        )

        if propertyDecl.delegateExpression != nil, !isExtensionProperty {
            lowerPropertyDelegate(
                propertyDecl, symbol: symbol, propType: propType,
                shared: shared, compilationCtx: compilationCtx,
                allTopLevelInitInstructions: &allTopLevelInitInstructions,
                delegateStorageSymbolByPropertySymbol: &delegateStorageSymbolByPropertySymbol,
                declIDs: &declIDs
            )
        }

        return declIDs
    }

    // MARK: - Property Accessors

    private func lowerPropertyAccessors(
        _ propertyDecl: PropertyDecl,
        symbol: SymbolID,
        propType: TypeID,
        shared: KIRLoweringSharedContext,
        declIDs: inout [KIRDeclID]
    ) {
        if let getter = propertyDecl.getter, getter.body != .unit {
            memberLowerer.lowerAccessorBody(
                accessorBody: getter.body,
                propertySymbol: symbol,
                propertyType: propType,
                accessorKind: .getter,
                setterParamName: nil,
                shared: shared,
                allDecls: &declIDs
            )
        }

        if let setter = propertyDecl.setter, setter.body != .unit {
            memberLowerer.lowerAccessorBody(
                accessorBody: setter.body,
                propertySymbol: symbol,
                propertyType: propType,
                accessorKind: .setter,
                setterParamName: setter.parameterName,
                shared: shared,
                allDecls: &declIDs
            )
        }
    }

    // MARK: - Property Initializer

    private func lowerPropertyInitializer(
        _ propertyDecl: PropertyDecl,
        symbol: SymbolID,
        propType: TypeID,
        isExtensionProperty: Bool,
        shared: KIRLoweringSharedContext,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext,
        declIDs: inout [KIRDeclID]
    ) {
        guard let initializer = propertyDecl.initializer,
              propertyDecl.delegateExpression == nil,
              !isExtensionProperty
        else { return }

        let sema = shared.sema
        let arena = shared.arena
        let propertyConstantInitializers = shared.propertyConstantInitializers

        if propertyConstantInitializers[symbol] == nil
            || (sema.symbols.symbol(symbol)?.flags.contains(.mutable) == true)
        {
            ctx.resetScopeForFunction()
            ctx.beginCallableLoweringScope()
            var initInstructions: KIRLoweringEmitContext = []
            let initValue = lowerExpr(
                initializer,
                shared: shared, emit: &initInstructions
            )
            let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
            initInstructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
            initInstructions.append(.copy(from: initValue, to: globalRef))
            allTopLevelInitInstructions.append(contentsOf: initInstructions)
            declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        }
    }

    // MARK: - Delegate Property

    private func lowerPropertyDelegate(
        _ propertyDecl: PropertyDecl,
        symbol: SymbolID,
        propType: TypeID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext,
        delegateStorageSymbolByPropertySymbol: inout [SymbolID: SymbolID],
        declIDs: inout [KIRDeclID]
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let delegateType = sema.types.anyType

        let delegateStorageSymbol: SymbolID
        if let existingStorage = sema.symbols.delegateStorageSymbol(for: symbol) {
            delegateStorageSymbol = existingStorage
        } else {
            let delegateStorageName = interner.intern("$delegate_\(interner.resolve(propertyDecl.name))")
            let delegateStorageFQName = (sema.symbols.symbol(symbol)?.fqName.dropLast() ?? []) + [delegateStorageName]
            delegateStorageSymbol = sema.symbols.define(
                kind: .field,
                name: delegateStorageName,
                fqName: Array(delegateStorageFQName),
                declSite: propertyDecl.range,
                visibility: .private,
                flags: []
            )
            sema.symbols.setDelegateStorageSymbol(delegateStorageSymbol, for: symbol)
        }

        let delegateKirID = arena.appendDecl(
            .global(KIRGlobal(symbol: delegateStorageSymbol, type: delegateType))
        )
        declIDs.append(delegateKirID)
        delegateStorageSymbolByPropertySymbol[symbol] = delegateStorageSymbol

        let delegateKind = detectDelegateKind(
            delegateExpr: propertyDecl.delegateExpression,
            ast: ast,
            interner: interner
        )

        if case .custom = delegateKind {
            memberLowerer.lowerDelegateAccessor(
                propertySymbol: symbol,
                propertyType: propType,
                delegateStorageSymbol: delegateStorageSymbol,
                accessorKind: .getter,
                shared: shared,
                allDecls: &declIDs
            )
            if propertyDecl.isVar {
                memberLowerer.lowerDelegateAccessor(
                    propertySymbol: symbol,
                    propertyType: propType,
                    delegateStorageSymbol: delegateStorageSymbol,
                    accessorKind: .setter,
                    shared: shared,
                    allDecls: &declIDs
                )
            }
        }

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()
        var initInstructions: KIRLoweringEmitContext = []

        emitDelegateInitInstructions(
            delegateKind: delegateKind,
            propertyDecl: propertyDecl,
            symbol: symbol,
            delegateStorageSymbol: delegateStorageSymbol,
            delegateType: delegateType,
            shared: shared,
            compilationCtx: compilationCtx,
            initInstructions: &initInstructions
        )

        allTopLevelInitInstructions.append(contentsOf: initInstructions)
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
    }

    private func emitDelegateInitInstructions(
        delegateKind: StdlibDelegateKind,
        propertyDecl: PropertyDecl,
        symbol: SymbolID,
        delegateStorageSymbol: SymbolID,
        delegateType: TypeID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        initInstructions: inout KIRLoweringEmitContext
    ) {
        let arena = shared.arena
        let interner = shared.interner

        switch delegateKind {
        case .lazy:
            let lambdaFnPtr = lowerDelegateLambdaBody(
                delegateBody: propertyDecl.delegateBody,
                propertySymbol: symbol, paramCount: 0,
                shared: shared, emit: &initInstructions
            )
            let modeValue = Int64(compilationCtx.options.lazyThreadSafetyMode.rawValue)
            let modeExpr = arena.appendExpr(.intLiteral(modeValue), type: shared.sema.types.anyType)
            initInstructions.append(.constValue(result: modeExpr, value: .intLiteral(modeValue)))
            let createResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)), type: delegateType
            )
            let lazyCreateName = interner.intern("kk_lazy_create")
            initInstructions.append(.call(
                symbol: nil, callee: lazyCreateName,
                arguments: [lambdaFnPtr, modeExpr],
                result: createResult, canThrow: false, thrownResult: nil
            ))
            initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))

        case .observable:
            emitObservableOrVetoableDelegate(
                kind: "kk_observable_create",
                propertyDecl: propertyDecl, symbol: symbol,
                delegateStorageSymbol: delegateStorageSymbol,
                delegateType: delegateType, shared: shared,
                initInstructions: &initInstructions
            )

        case .vetoable:
            emitObservableOrVetoableDelegate(
                kind: "kk_vetoable_create",
                propertyDecl: propertyDecl, symbol: symbol,
                delegateStorageSymbol: delegateStorageSymbol,
                delegateType: delegateType, shared: shared,
                initInstructions: &initInstructions
            )

        case .custom:
            let delegateObjExpr = lowerExpr(
                propertyDecl.delegateExpression!,
                shared: shared, emit: &initInstructions
            )
            let createResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)), type: delegateType
            )
            let customCreateName = interner.intern("kk_custom_delegate_create")
            initInstructions.append(.call(
                symbol: nil, callee: customCreateName,
                arguments: [delegateObjExpr],
                result: createResult, canThrow: false, thrownResult: nil
            ))
            initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))
        }
    }

    private func emitObservableOrVetoableDelegate(
        kind runtimeFnName: String,
        propertyDecl: PropertyDecl,
        symbol: SymbolID,
        delegateStorageSymbol: SymbolID,
        delegateType: TypeID,
        shared: KIRLoweringSharedContext,
        initInstructions: inout KIRLoweringEmitContext
    ) {
        let arena = shared.arena
        let interner = shared.interner

        let initialValueExpr = lowerDelegateInitialValue(
            delegateExpr: propertyDecl.delegateExpression,
            shared: shared, emit: &initInstructions
        )
        let callbackFnPtr = lowerDelegateLambdaBody(
            delegateBody: propertyDecl.delegateBody,
            propertySymbol: symbol, paramCount: 3,
            shared: shared, emit: &initInstructions
        )
        let createResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)), type: delegateType
        )
        let createName = interner.intern(runtimeFnName)
        initInstructions.append(.call(
            symbol: nil, callee: createName,
            arguments: [initialValueExpr, callbackFnPtr],
            result: createResult, canThrow: false, thrownResult: nil
        ))
        initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))
    }
}
