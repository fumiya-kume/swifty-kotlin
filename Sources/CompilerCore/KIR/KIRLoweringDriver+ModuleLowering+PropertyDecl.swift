import Foundation

extension KIRLoweringDriver {
    // swiftlint:disable:next function_parameter_count
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

        // Getter-only computed properties (`val x: T get() = expr`) have no
        // storage — skip emitting a KIRGlobal so no backing field is generated
        // in codegen.  The getter accessor function alone is sufficient.
        let isGetterOnlyComputed = propertyDecl.getter != nil
            && propertyDecl.setter == nil
            && propertyDecl.initializer == nil
            && propertyDecl.delegateExpression == nil

        if !isExtensionProperty, !isGetterOnlyComputed {
            let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propType)))
            declIDs.append(kirID)
        }

        emitBackingFieldIfNeeded(
            symbol: symbol, propType: propType, isExtension: isExtensionProperty,
            shared: shared, declIDs: &declIDs
        )
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

    // MARK: - Backing field

    private func emitBackingFieldIfNeeded(
        symbol: SymbolID,
        propType: TypeID,
        isExtension: Bool,
        shared: KIRLoweringSharedContext,
        declIDs: inout [KIRDeclID]
    ) {
        guard !isExtension,
              let backingFieldSymbol = shared.sema.symbols.backingFieldSymbol(for: symbol)
        else { return }
        let backingFieldType = shared.sema.symbols.propertyType(for: backingFieldSymbol) ?? propType
        declIDs.append(shared.arena.appendDecl(.global(KIRGlobal(symbol: backingFieldSymbol, type: backingFieldType))))
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

    // swiftlint:disable:next function_parameter_count
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

        let needsInit = propertyConstantInitializers[symbol] == nil
            || (sema.symbols.symbol(symbol)?.flags.contains(.mutable) == true)
        guard needsInit else { return }
        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()
        var initInstructions: KIRLoweringEmitContext = []
        let initValue = lowerExpr(initializer, shared: shared, emit: &initInstructions)
        let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
        initInstructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
        initInstructions.append(.copy(from: initValue, to: globalRef))
        allTopLevelInitInstructions.append(contentsOf: initInstructions)
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
    }

    // MARK: - Delegate Property

    // swiftlint:disable:next function_parameter_count
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
        let arena = shared.arena
        let delegateType = shared.sema.types.anyType
        let delegateStorageSymbol = resolveDelegateStorageSymbol(
            propertyDecl: propertyDecl, symbol: symbol, shared: shared
        )
        declIDs.append(arena.appendDecl(.global(KIRGlobal(symbol: delegateStorageSymbol, type: delegateType))))
        delegateStorageSymbolByPropertySymbol[symbol] = delegateStorageSymbol
        let delegateKind = detectDelegateKind(
            delegateExpr: propertyDecl.delegateExpression,
            ast: shared.ast, interner: shared.interner
        )
        emitDelegateAccessorsIfCustom(
            delegateKind: delegateKind, propertyDecl: propertyDecl,
            symbol: symbol, propType: propType,
            delegateStorageSymbol: delegateStorageSymbol,
            shared: shared, declIDs: &declIDs
        )
        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()
        var initInstructions: KIRLoweringEmitContext = []
        emitDelegateInitInstructions(
            delegateKind: delegateKind, propertyDecl: propertyDecl,
            symbol: symbol, delegateStorageSymbol: delegateStorageSymbol,
            delegateType: delegateType, shared: shared,
            compilationCtx: compilationCtx, initInstructions: &initInstructions
        )
        allTopLevelInitInstructions.append(contentsOf: initInstructions)
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
    }

    private func resolveDelegateStorageSymbol(
        propertyDecl: PropertyDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> SymbolID {
        let sema = shared.sema
        let interner = shared.interner
        if let existing = sema.symbols.delegateStorageSymbol(for: symbol) {
            return existing
        }
        let storageName = interner.intern("$delegate_\(interner.resolve(propertyDecl.name))")
        let fqName = (sema.symbols.symbol(symbol)?.fqName.dropLast() ?? []) + [storageName]
        let storageSymbol = sema.symbols.define(
            kind: .field, name: storageName, fqName: Array(fqName),
            declSite: propertyDecl.range, visibility: .private, flags: []
        )
        sema.symbols.setDelegateStorageSymbol(storageSymbol, for: symbol)
        return storageSymbol
    }

    // swiftlint:disable:next function_parameter_count
    private func emitDelegateAccessorsIfCustom(
        delegateKind: StdlibDelegateKind,
        propertyDecl: PropertyDecl,
        symbol: SymbolID,
        propType: TypeID,
        delegateStorageSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        declIDs: inout [KIRDeclID]
    ) {
        guard case .custom = delegateKind else { return }
        memberLowerer.lowerDelegateAccessor(
            propertySymbol: symbol, propertyType: propType,
            delegateStorageSymbol: delegateStorageSymbol,
            accessorKind: .getter, shared: shared, allDecls: &declIDs
        )
        if propertyDecl.isVar {
            memberLowerer.lowerDelegateAccessor(
                propertySymbol: symbol, propertyType: propType,
                delegateStorageSymbol: delegateStorageSymbol,
                accessorKind: .setter, shared: shared, allDecls: &declIDs
            )
        }
    }

    // MARK: - Delegate init instructions

    // swiftlint:disable:next function_parameter_count
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
        switch delegateKind {
        case .lazy:
            emitLazyDelegateInit(
                propertyDecl: propertyDecl, symbol: symbol,
                delegateStorageSymbol: delegateStorageSymbol,
                delegateType: delegateType, shared: shared,
                compilationCtx: compilationCtx, initInstructions: &initInstructions
            )
        case .observable:
            emitCallbackDelegateInit(
                runtimeFnName: "kk_observable_create", propertyDecl: propertyDecl,
                symbol: symbol, delegateStorageSymbol: delegateStorageSymbol,
                delegateType: delegateType, shared: shared, initInstructions: &initInstructions
            )
        case .vetoable:
            emitCallbackDelegateInit(
                runtimeFnName: "kk_vetoable_create", propertyDecl: propertyDecl,
                symbol: symbol, delegateStorageSymbol: delegateStorageSymbol,
                delegateType: delegateType, shared: shared, initInstructions: &initInstructions
            )
        case .custom:
            emitCustomDelegateInit(
                propertyDecl: propertyDecl, symbol: symbol,
                delegateStorageSymbol: delegateStorageSymbol,
                delegateType: delegateType, shared: shared,
                compilationCtx: compilationCtx, initInstructions: &initInstructions
            )
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func emitLazyDelegateInit(
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
        let lambdaFnPtr = lowerDelegateLambdaBody(
            delegateBody: propertyDecl.delegateBody, propertySymbol: symbol,
            paramCount: 0, shared: shared, emit: &initInstructions
        )
        let modeValue = Int64(compilationCtx.options.lazyThreadSafetyMode.rawValue)
        let modeExpr = arena.appendExpr(.intLiteral(modeValue), type: shared.sema.types.anyType)
        initInstructions.append(.constValue(result: modeExpr, value: .intLiteral(modeValue)))
        let createResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: delegateType)
        initInstructions.append(.call(
            symbol: nil, callee: interner.intern("kk_lazy_create"),
            arguments: [lambdaFnPtr, modeExpr],
            result: createResult, canThrow: false, thrownResult: nil
        ))
        initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))
    }

    // swiftlint:disable:next function_parameter_count
    private func emitCallbackDelegateInit(
        runtimeFnName: String,
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
            delegateExpr: propertyDecl.delegateExpression, shared: shared, emit: &initInstructions
        )
        let callbackFnPtr = lowerDelegateLambdaBody(
            delegateBody: propertyDecl.delegateBody, propertySymbol: symbol,
            paramCount: 3, shared: shared, emit: &initInstructions
        )
        let createResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: delegateType)
        initInstructions.append(.call(
            symbol: nil, callee: interner.intern(runtimeFnName),
            arguments: [initialValueExpr, callbackFnPtr],
            result: createResult, canThrow: false, thrownResult: nil
        ))
        initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))
    }

    // swiftlint:disable:next function_parameter_count
    private func emitCustomDelegateInit(
        propertyDecl: PropertyDecl,
        symbol: SymbolID,
        delegateStorageSymbol: SymbolID,
        delegateType: TypeID,
        shared: KIRLoweringSharedContext,
        compilationCtx _: CompilationContext,
        initInstructions: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let delegateObjExpr = lowerExpr(propertyDecl.delegateExpression!, shared: shared, emit: &initInstructions)
        let delegateExprType = sema.bindings.exprType(for: propertyDecl.delegateExpression!)
        if checkHasProvideDelegate(delegateExprType: delegateExprType, shared: shared) {
            emitProvideDelegateInit(
                delegateObjExpr: delegateObjExpr, symbol: symbol,
                delegateStorageSymbol: delegateStorageSymbol, delegateType: delegateType,
                shared: shared, emit: &initInstructions
            )
        } else {
            emitSimpleDelegateInit(
                delegateObjExpr: delegateObjExpr,
                delegateStorageSymbol: delegateStorageSymbol, delegateType: delegateType,
                shared: shared, emit: &initInstructions
            )
        }
    }
}
