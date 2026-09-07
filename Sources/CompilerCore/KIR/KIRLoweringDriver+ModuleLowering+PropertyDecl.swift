
extension KIRLoweringDriver {
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
        // Exception: properties with explicit backing fields always have storage.
        //
        // Delegate properties (`val x: T by expr`) also have no backing storage
        // for the property symbol itself — all access is routed through the
        // delegate storage symbol (e.g. `$delegate_x`) which gets its own
        // KIRGlobal in lowerPropertyDelegate.  Emitting a second KIRGlobal for
        // the property symbol with type `propType` (e.g. `stringStruct`) would
        // cause the code generator to write a wide stringStruct aggregate into
        // an i64-sized slot, corrupting adjacent globals (including the delegate
        // storage).
        let hasExplicitBackingField = propertyDecl.explicitBackingField != nil
        let isGetterOnlyComputed = propertyDecl.getter != nil
            && propertyDecl.setter == nil
            && propertyDecl.initializer == nil
            && propertyDecl.delegateExpression == nil
            && !hasExplicitBackingField
        let isDelegateProperty = propertyDecl.delegateExpression != nil

        if !isExtensionProperty, !isGetterOnlyComputed, !isDelegateProperty {
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

        // Emit explicit backing field initializer if present.
        if let explicitField = propertyDecl.explicitBackingField, !isExtensionProperty {
            lowerExplicitBackingFieldInitializer(
                explicitField, symbol: symbol, propType: propType,
                shared: shared,
                allTopLevelInitInstructions: &allTopLevelInitInstructions,
                declIDs: &declIDs
            )
        }

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

    // MARK: - Explicit Backing Field Initializer (Kotlin 2.0)

    /// Emits initialization instructions for an explicit backing field.
    /// The initializer expression comes from the `field = expr` declaration,
    /// not from the property's own initializer.
    private func lowerExplicitBackingFieldInitializer(
        _ explicitField: ExplicitBackingField,
        symbol: SymbolID,
        propType: TypeID,
        shared: KIRLoweringSharedContext,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext,
        declIDs: inout [KIRDeclID]
    ) {
        let sema = shared.sema
        let arena = shared.arena
        guard let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) else { return }
        let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol) ?? propType

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()
        var initInstructions: KIRLoweringEmitContext = []
        let initValue = lowerExpr(explicitField.initializer, shared: shared, emit: &initInstructions)
        let globalRef = arena.appendExpr(.symbolRef(backingFieldSymbol), type: backingFieldType)
        initInstructions.append(.constValue(result: globalRef, value: .symbolRef(backingFieldSymbol)))
        initInstructions.append(.copy(from: initValue, to: globalRef))
        allTopLevelInitInstructions.appendRelocatingLabels(contentsOf: initInstructions)
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
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
        guard propertyDecl.delegateExpression == nil,
              !isExtensionProperty
        else { return }

        let sema = shared.sema
        let arena = shared.arena
        let propertyConstantInitializers = shared.propertyConstantInitializers

        if propertyDecl.initializer == nil, propertyDecl.modifiers.contains(.lateinit) {
            let nullExpr = arena.appendExpr(.null, type: propType)
            allTopLevelInitInstructions.append(.constValue(result: nullExpr, value: .null))
            let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
            allTopLevelInitInstructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
            allTopLevelInitInstructions.append(.copy(from: nullExpr, to: globalRef))
            return
        }

        guard let initializer = propertyDecl.initializer else { return }

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
        // When the property also has a backing field (a custom getter and/or
        // setter forced one to be materialized), `field` references inside
        // those accessors read/write the backing field's own global — a
        // separate storage location from the property symbol's global above.
        // Seed it with the same initial value so the first `field` read
        // inside a custom getter observes the declared initializer rather
        // than the backing field global's zero-initialized default.
        // Properties with an explicit Kotlin 2.0 backing field declaration
        // (`field = expr`) already seeded that global with its own
        // initializer via lowerExplicitBackingFieldInitializer above — skip
        // here so this doesn't overwrite it with the property's initializer.
        if propertyDecl.explicitBackingField == nil,
           let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) {
            let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol) ?? propType
            let backingFieldRef = arena.appendExpr(.symbolRef(backingFieldSymbol), type: backingFieldType)
            initInstructions.append(.constValue(result: backingFieldRef, value: .symbolRef(backingFieldSymbol)))
            initInstructions.append(.copy(from: initValue, to: backingFieldRef))
        }
        allTopLevelInitInstructions.appendRelocatingLabels(contentsOf: initInstructions)
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
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
        let arena = shared.arena
        let delegateType = shared.sema.types.anyType
        let delegateStorageSymbol = resolveDelegateStorageSymbol(
            propertyDecl: propertyDecl, symbol: symbol, shared: shared
        )
        declIDs.append(arena.appendDecl(.global(KIRGlobal(symbol: delegateStorageSymbol, type: delegateType))))
        delegateStorageSymbolByPropertySymbol[symbol] = delegateStorageSymbol
        let delegateKind = StdlibDelegateKind.detect(
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
        allTopLevelInitInstructions.appendRelocatingLabels(contentsOf: initInstructions)
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

    private func emitDelegateAccessorsIfCustom(
        delegateKind: StdlibDelegateKind,
        propertyDecl: PropertyDecl,
        symbol: SymbolID,
        propType: TypeID,
        delegateStorageSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        declIDs: inout [KIRDeclID]
    ) {
        memberLowerer.lowerDelegateAccessor(
            propertySymbol: symbol, propertyType: propType,
            delegateStorageSymbol: delegateStorageSymbol,
            delegateKind: delegateKind,
            accessorKind: .getter, shared: shared, allDecls: &declIDs
        )
        if propertyDecl.isVar {
            memberLowerer.lowerDelegateAccessor(
                propertySymbol: symbol, propertyType: propType,
                delegateStorageSymbol: delegateStorageSymbol,
                delegateKind: delegateKind,
                accessorKind: .setter, shared: shared, allDecls: &declIDs
            )
        }
    }

    // MARK: - Delegate init instructions

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
        case .observable, .vetoable:
            emitCallbackDelegateInit(
                delegateKind: delegateKind, propertyDecl: propertyDecl,
                symbol: symbol, delegateStorageSymbol: delegateStorageSymbol,
                delegateType: delegateType, shared: shared, initInstructions: &initInstructions
            )
        case .notNull:
            emitNotNullDelegateInit(
                propertyDecl: propertyDecl, symbol: symbol,
                delegateStorageSymbol: delegateStorageSymbol,
                delegateType: delegateType, shared: shared,
                initInstructions: &initInstructions
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
        let sema = shared.sema
        let interner = shared.interner
        let lambdaFnPtr = lowerDelegateLambdaBody(
            delegateBody: propertyDecl.delegateBody,
            delegateBodyParams: propertyDecl.delegateBodyParams, propertySymbol: symbol,
            paramCount: 0, shared: shared, emit: &initInstructions
        )
        let lockValue = LazyThreadSafetyModeLowering.lockExpression(
            from: propertyDecl.delegateExpression,
            ast: shared.ast,
            sema: shared.sema,
            interner: interner
        ).map { lowerExpr($0, shared: shared, emit: &initInstructions) }
        let modeExpr = lowerLazyModeExpr(
            delegateExpression: propertyDecl.delegateExpression,
            shared: shared, compilationCtx: compilationCtx, emit: &initInstructions
        )
        let lockArgument: KIRExprID
        if let lockValue {
            lockArgument = lockValue
        } else {
            lockArgument = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            initInstructions.append(.constValue(result: lockArgument, value: .null))
        }
        let initialValueExpr = arena.appendExpr(.unit, type: sema.types.anyType)
        initInstructions.append(.constValue(result: initialValueExpr, value: .null))
        let initialComputedExpr = arena.appendExpr(.boolLiteral(false), type: sema.types.booleanType)
        initInstructions.append(.constValue(result: initialComputedExpr, value: .boolLiteral(false)))
        guard let ctorSymbol = stdlibDelegateSymbol(
            fqName: [interner.intern("kotlin"), interner.intern("LazyImpl"), interner.intern("<init>")],
            parameterCount: 5, sema: sema
        ), let ownerSymbol = sema.symbols.parentSymbol(for: ctorSymbol) else {
            preconditionFailure("KSP-491: missing kotlin.LazyImpl constructor")
        }
        let allocatedObj = allocateStdlibDelegateInstance(
            ownerSymbol: ownerSymbol, resultType: delegateType,
            sema: sema, arena: arena, interner: interner, emit: &initInstructions
        )
        let createResult = arena.appendTemporary(type: delegateType)
        initInstructions.append(.call(
            symbol: ctorSymbol, callee: interner.intern("<init>"),
            arguments: [allocatedObj, lambdaFnPtr, modeExpr, lockArgument, initialValueExpr, initialComputedExpr],
            result: createResult, canThrow: false, thrownResult: nil
        ))
        initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))
    }

    /// Resolves the `mode` argument for a `lazy`/`lazy(mode)` delegate creation:
    /// lowers the user's explicit `LazyThreadSafetyMode` expression when
    /// `lazy(mode) { ... }` was written, otherwise references the compiler's
    /// default mode entry (matching the bare `lazy { ... }` form's prior
    /// behavior, which honored `-Xfrontend lazy-thread-safety=...`).
    func lowerLazyModeExpr(
        delegateExpression: ExprID?,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let ast = shared.ast
        let interner = shared.interner
        if let exprID = delegateExpression,
           let expr = ast.arena.expr(exprID),
           case let .call(_, _, args, _) = expr,
           let modeArg = args.first(where: { argument in
               guard let type = shared.sema.bindings.exprTypes[argument.expr] else { return false }
               return LazyThreadSafetyModeLowering.isModeType(
                   type, sema: shared.sema, interner: interner
               )
           })
        {
            return lowerExpr(modeArg.expr, shared: shared, emit: &instructions)
        }
        let entryName: String = switch compilationCtx.options.lazyThreadSafetyMode {
        case .synchronized: "SYNCHRONIZED"
        case .publication: "PUBLICATION"
        case .none: "NONE"
        }
        return referenceStdlibEnumEntry(
            ownerFQName: [interner.intern("kotlin"), interner.intern("LazyThreadSafetyMode")],
            entryName: entryName,
            shared: shared, emit: &instructions
        )
    }

    private func emitCallbackDelegateInit(
        delegateKind: StdlibDelegateKind,
        propertyDecl: PropertyDecl,
        symbol: SymbolID,
        delegateStorageSymbol: SymbolID,
        delegateType: TypeID,
        shared: KIRLoweringSharedContext,
        initInstructions: inout KIRLoweringEmitContext
    ) {
        let arena = shared.arena
        let sema = shared.sema
        let interner = shared.interner
        let initialValueExpr = lowerDelegateInitialValue(
            delegateExpr: propertyDecl.delegateExpression, shared: shared, emit: &initInstructions
        )
        let callbackFnPtr = lowerDelegateLambdaBody(
            delegateBody: propertyDecl.delegateBody,
            delegateBodyParams: propertyDecl.delegateBodyParams,
            valueType: shared.sema.symbols.propertyType(for: symbol), propertySymbol: symbol,
            paramCount: 3, shared: shared, emit: &initInstructions
        )
        let className = delegateKind == .observable ? "SimpleObservableProperty" : "SimpleVetoableProperty"
        guard let ctorSymbol = stdlibDelegateSymbol(
            fqName: [
                interner.intern("kotlin"), interner.intern("properties"),
                interner.intern(className), interner.intern("<init>"),
            ],
            parameterCount: 2, sema: sema
        ), let ownerSymbol = sema.symbols.parentSymbol(for: ctorSymbol) else {
            preconditionFailure("KSP-491: missing kotlin.properties.\(className) constructor")
        }
        let allocatedObj = allocateStdlibDelegateInstance(
            ownerSymbol: ownerSymbol, resultType: delegateType,
            sema: sema, arena: arena, interner: interner, emit: &initInstructions
        )
        let createResult = arena.appendTemporary(type: delegateType)
        initInstructions.append(.call(
            symbol: ctorSymbol, callee: interner.intern("<init>"),
            arguments: [allocatedObj, initialValueExpr, callbackFnPtr],
            result: createResult, canThrow: false, thrownResult: nil
        ))
        initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))
    }

    private func emitNotNullDelegateInit(
        propertyDecl _: PropertyDecl,
        symbol _: SymbolID,
        delegateStorageSymbol: SymbolID,
        delegateType: TypeID,
        shared: KIRLoweringSharedContext,
        initInstructions: inout KIRLoweringEmitContext
    ) {
        let arena = shared.arena
        let sema = shared.sema
        let interner = shared.interner
        guard let ctorSymbol = stdlibDelegateSymbol(
            fqName: [
                interner.intern("kotlin"), interner.intern("properties"),
                interner.intern("NotNullVar"), interner.intern("<init>"),
            ],
            parameterCount: 0, sema: sema
        ), let ownerSymbol = sema.symbols.parentSymbol(for: ctorSymbol) else {
            preconditionFailure("KSP-491: missing kotlin.properties.NotNullVar constructor")
        }
        let allocatedObj = allocateStdlibDelegateInstance(
            ownerSymbol: ownerSymbol, resultType: delegateType,
            sema: sema, arena: arena, interner: interner, emit: &initInstructions
        )
        let createResult = arena.appendTemporary(type: delegateType)
        initInstructions.append(.call(
            symbol: ctorSymbol, callee: interner.intern("<init>"),
            arguments: [allocatedObj],
            result: createResult, canThrow: false, thrownResult: nil
        ))
        initInstructions.append(.storeGlobal(value: createResult, symbol: delegateStorageSymbol))
    }

    /// Looks up a bundled stdlib delegate implementation's constructor or
    /// factory-function symbol by exact parameter count. KSP-491's stdlib
    /// delegate kinds are never overloaded on anything but arity, so arity
    /// alone disambiguates (e.g. `lazy`'s 1-arg vs 2-arg overload).
    func stdlibDelegateSymbol(
        fqName: [InternedString],
        parameterCount: Int,
        sema: SemaModule
    ) -> SymbolID? {
        sema.symbols.lookupAll(fqName: fqName).first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.count == parameterCount
        }
    }

    /// References a bundled enum entry by name as a plain value (KSP-491:
    /// `LazyThreadSafetyMode.SYNCHRONIZED`/`.PUBLICATION`/`.NONE` for the
    /// implicit-mode `lazy { ... }` form).
    func referenceStdlibEnumEntry(
        ownerFQName: [InternedString],
        entryName: String,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let interner = shared.interner
        guard let entrySymbol = sema.symbols.lookup(fqName: ownerFQName + [interner.intern(entryName)]) else {
            preconditionFailure("KSP-491: missing bundled enum entry \(ownerFQName).\(entryName)")
        }
        let type = sema.symbols.propertyType(for: entrySymbol) ?? sema.types.anyType
        let ref = shared.arena.appendExpr(.symbolRef(entrySymbol), type: type)
        instructions.append(.constValue(result: ref, value: .symbolRef(entrySymbol)))
        return ref
    }

    /// Allocates a heap object for a direct constructor call (KSP-491: the
    /// bundled `LazyImpl`/`SimpleObservableProperty`/`SimpleVetoableProperty`/
    /// `NotNullVar` delegate implementations), mirroring the allocation
    /// `CallLowerer.lowerCallExpr` performs for an ordinary `NewExpr(...)`
    /// call before invoking its constructor (`kk_object_new` sized from the
    /// class's `NominalLayout`, then itable/vtable/supertype-edge
    /// registration) -- constructors always need this as their implicit
    /// receiver (p0); they are never called on an already-allocated object.
    func allocateStdlibDelegateInstance(
        ownerSymbol: SymbolID,
        resultType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let intType = sema.types.intType
        let slotCount = Int64(max(sema.symbols.nominalLayout(for: ownerSymbol)?.instanceSizeWords ?? 1, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(symbol: ownerSymbol, sema: sema, interner: interner)
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let allocatedObj = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: allocatedObj,
            canThrow: false,
            thrownResult: nil
        ))
        for superSymbol in sema.symbols.directSupertypes(for: ownerSymbol) {
            let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: superSymbol, sema: sema, interner: interner)
            let childExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
            instructions.append(.constValue(result: childExpr, value: .intLiteral(classIDValue)))
            let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
            instructions.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
            let registerResult = arena.appendTemporary(type: intType)
            let registerCallee = sema.symbols.symbol(superSymbol)?.kind == .interface
                ? interner.intern("kk_type_register_iface")
                : interner.intern("kk_type_register_super")
            instructions.append(.call(
                symbol: nil, callee: registerCallee,
                arguments: [childExpr, parentExpr],
                result: registerResult, canThrow: false, thrownResult: nil
            ))
        }
        appendObjectItableMethodRegistrations(
            objectValue: allocatedObj, nominalSymbol: ownerSymbol,
            driver: self, sema: sema, arena: arena, interner: interner,
            instructions: &instructions.instructions
        )
        appendObjectItablePropertyGetterRegistrations(
            objectValue: allocatedObj, nominalSymbol: ownerSymbol,
            sema: sema, arena: arena, interner: interner,
            instructions: &instructions.instructions
        )
        appendObjectVtableMethodRegistrations(
            objectValue: allocatedObj, nominalSymbol: ownerSymbol,
            driver: self,
            sema: sema, arena: arena, interner: interner,
            instructions: &instructions.instructions
        )
        return allocatedObj
    }

    private func emitCustomDelegateInit(
        propertyDecl: PropertyDecl,
        symbol: SymbolID,
        delegateStorageSymbol: SymbolID,
        delegateType: TypeID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        initInstructions: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        guard let delegateExpr = propertyDecl.delegateExpression else {
            // Internal error: emitCustomDelegateInit called for a property without delegate expression.
            // This indicates an AST invariant violation — emit a diagnostic and bail out.
            compilationCtx.diagnostics.error(
                "KSWIFTK-KIR-0002",
                "Internal error: emitCustomDelegateInit called for a property without a delegate expression.",
                range: propertyDecl.range
            )
            return
        }
        let delegateObjExpr = lowerExpr(delegateExpr, shared: shared, emit: &initInstructions)
        let delegateExprType = sema.bindings.exprType(for: delegateExpr)
        if checkHasProvideDelegate(delegateExprType: delegateExprType, shared: shared) {
            emitProvideDelegateInit(
                delegateObjExpr: delegateObjExpr, symbol: symbol,
                delegateStorageSymbol: delegateStorageSymbol, delegateType: delegateType,
                shared: shared, emit: &initInstructions
            )
        } else {
            emitSimpleDelegateInit(
                delegateObjExpr: delegateObjExpr,
                delegateStorageSymbol: delegateStorageSymbol,
                shared: shared, emit: &initInstructions
            )
        }
    }
}
