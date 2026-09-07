
final class MemberLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func lowerMemberDecls(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        compilationCtx: CompilationContext? = nil,
        isInterfaceContext: Bool = false
    ) -> (directMembers: [KIRDeclID], allDecls: [KIRDeclID]) {
        var directMembers: [KIRDeclID] = []
        var allDecls: [KIRDeclID] = []

        for declID in memberFunctions {
            lowerSingleMemberFunction(
                declID: declID, ast: ast, sema: sema, arena: arena,
                interner: interner, propertyConstantInitializers: propertyConstantInitializers,
                directMembers: &directMembers, allDecls: &allDecls
            )
        }

        for declID in memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType

            // Getter-only computed properties (`val x: T get() = expr`) have no
            // storage — skip emitting a KIRGlobal so no backing field is generated
            // in codegen.  The getter accessor function alone is sufficient.
            // Exception: properties with explicit backing fields always have storage.
            //
            // Delegate properties (`val x: T by expr`) also have no backing storage
            // for the property symbol itself — all access is routed through the
            // delegate storage symbol (e.g. `$delegate_x`) which gets its own
            // KIRGlobal below.  Emitting a second KIRGlobal for the property symbol
            // with type `propType` (e.g. `stringStruct`) would cause the code
            // generator to write a wide stringStruct aggregate into an i64-sized
            // slot, corrupting adjacent globals (including the delegate storage).
            //
            // Interface properties never have per-instance storage of their own —
            // any state lives in the implementing class, which gets its own
            // KIRGlobal/backing field when it declares (or overrides) the property.
            // Skip storage emission here so a plain interface property (with no
            // accessor body) doesn't leak a bogus module-level global.
            let hasExplicitBackingField = propertyDecl.explicitBackingField != nil
            let isAbstractProperty = sema.symbols.symbol(symbol)?.flags.contains(.abstractType) == true
            let isGetterOnlyComputed = propertyDecl.getter != nil
                && propertyDecl.setter == nil
                && propertyDecl.initializer == nil
                && propertyDecl.delegateExpression == nil
                && !hasExplicitBackingField
            let isDelegateProperty = propertyDecl.delegateExpression != nil

            if !isInterfaceContext, !isAbstractProperty, !isGetterOnlyComputed, !isDelegateProperty {
                let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propType)))
                directMembers.append(kirID)
                allDecls.append(kirID)
            }

            // Emit backing field global for properties with custom accessors.
            if !isInterfaceContext, let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) {
                let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol) ?? propType
                let backingFieldKirID = arena.appendDecl(
                    .global(KIRGlobal(symbol: backingFieldSymbol, type: backingFieldType))
                )
                allDecls.append(backingFieldKirID)
            }

            // Lower getter body as a KIR accessor function.
            if let getter = propertyDecl.getter, getter.body != .unit {
                lowerAccessorBody(
                    accessorBody: getter.body,
                    propertySymbol: symbol,
                    propertyType: propType,
                    accessorKind: .getter,
                    setterParamName: nil,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            }

            // Lower setter body as a KIR accessor function.
            if let setter = propertyDecl.setter, setter.body != .unit {
                lowerAccessorBody(
                    accessorBody: setter.body,
                    propertySymbol: symbol,
                    propertyType: propType,
                    accessorKind: .setter,
                    setterParamName: setter.parameterName,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            }

            // BUG-141: give properties that participate in interface itable
            // dispatch a getter accessor function. A plain interface property
            // (no custom getter, no delegate) gets a stub whose signature the
            // dispatch site targets; a concrete `override` stored property gets
            // a field-reading getter that is registered into the itable so an
            // interface-typed receiver can dispatch to it. Custom-getter and
            // delegated properties already emit their own accessor above.
            //
            // BUG-227: the same field-reading getter is also exactly what a
            // *class* vtable slot needs behind it, so every property that
            // ever needs virtual dispatch — not just `override` members, but
            // also the open stored-property root of the chain — gets one here too.
            // A `final` property never needs one: LayoutSynthesis never gives
            // it a vtable slot, so no call site ever looks for this accessor.
            let hasCustomGetterBody = (propertyDecl.getter?.body).map { $0 != .unit } ?? false
            let hasCustomSetterBody = (propertyDecl.setter?.body).map { $0 != .unit } ?? false
            let hasDelegate = propertyDecl.delegateExpression != nil
            let propFlags = sema.symbols.symbol(symbol)?.flags
            let needsVirtualAccessor = propFlags.map {
                $0.contains(.overrideMember) || $0.contains(.openType) || $0.contains(.abstractType)
            } ?? false
            if !hasCustomGetterBody, !hasDelegate,
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol)
            {
                let isExternalLinked = sema.symbols.externalLinkName(for: symbol).map { !$0.isEmpty } ?? false
                if isInterfaceContext, !isExternalLinked {
                    synthesizeInterfacePropertyGetterStub(
                        propertySymbol: symbol,
                        ownerSymbol: ownerSymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                } else if !isInterfaceContext, needsVirtualAccessor {
                    synthesizeStoredPropertyGetterAccessor(
                        propertySymbol: symbol,
                        ownerSymbol: ownerSymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                }
            }
            // BUG-227: symmetric default setter accessor for a `var` in the
            // same situation — a write through a base-typed reference must
            // dispatch to the actual runtime type's setter the same way a
            // read dispatches to the getter above.
            if !hasCustomSetterBody, !hasDelegate, !isInterfaceContext, needsVirtualAccessor,
               propFlags?.contains(.mutable) == true,
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol)
            {
                synthesizeStoredPropertySetterAccessor(
                    propertySymbol: symbol,
                    ownerSymbol: ownerSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    allDecls: &allDecls
                )
            }

            // Lower delegated property: emit delegate storage global and
            // synthesise getter (and setter for var) that call getValue/setValue
            // on the delegate instance.
            // Delegated properties in interfaces are rejected in Sema
            // (KSWIFTK-SEMA-0304); isInterfaceContext guards this as defense in
            // depth so an interface property never gets delegate storage or
            // synthesized accessors, matching the storage/backing-field
            // suppression above.
            if !isInterfaceContext, propertyDecl.delegateExpression != nil {
                let delegateKind = StdlibDelegateKind.detect(
                    delegateExpr: propertyDecl.delegateExpression,
                    ast: ast,
                    interner: interner
                )
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
                }
                let delegateType = sema.types.anyType
                let delegateKirID = arena.appendDecl(
                    .global(KIRGlobal(symbol: delegateStorageSymbol, type: delegateType))
                )
                allDecls.append(delegateKirID)

                // Synthesise getter: calls getValue on the delegate storage.
                lowerDelegateAccessor(
                    propertySymbol: symbol,
                    propertyType: propType,
                    delegateStorageSymbol: delegateStorageSymbol,
                    delegateKind: delegateKind,
                    accessorKind: .getter,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    allDecls: &allDecls
                )

                // Synthesise setter for var properties: calls setValue on the delegate.
                if propertyDecl.isVar {
                    lowerDelegateAccessor(
                        propertySymbol: symbol,
                        propertyType: propType,
                        delegateStorageSymbol: delegateStorageSymbol,
                        delegateKind: delegateKind,
                        accessorKind: .setter,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                }
            }
        }

        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            switch decl {
            case let .classDecl(nested):
                var nestedAllObjects = nested.nestedObjects
                if let companionDeclID = nested.companionObject {
                    nestedAllObjects.append(companionDeclID)
                }
                let (nestedDirect, nestedAll) = lowerMemberDecls(
                    memberFunctions: nested.memberFunctions,
                    memberProperties: nested.memberProperties,
                    nestedClasses: nested.nestedClasses,
                    nestedObjects: nestedAllObjects,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    compilationCtx: compilationCtx
                )
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: nestedDirect)))
                directMembers.append(kirID)
                allDecls.append(kirID)
                allDecls.append(contentsOf: nestedAll)

                // Lower constructors for nested classes (inner and static).
                // Without this, nested class constructors would not be emitted
                // into KIR and codegen would produce undefined symbol references.
                if let compilationCtx {
                    let ctorFQName = (sema.symbols.symbol(symbol)?.fqName ?? []) + [interner.intern("<init>")]
                    let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                    let shared = KIRLoweringSharedContext(
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers
                    )
                    for ctorSymbol in ctorSymbols {
                        let ctorDecls = driver.lowerConstructor(
                            ctorSymbol: ctorSymbol,
                            ctorFQName: ctorFQName,
                            classDecl: nested,
                            ownerSymbol: symbol,
                            shared: shared,
                            compilationCtx: compilationCtx
                        )
                        allDecls.append(contentsOf: ctorDecls)
                    }
                }
            case let .interfaceDecl(nestedInterface):
                // Interface properties have no backing storage of their own, but
                // properties with a default accessor body (e.g. `val x get() = ...`)
                // still need that body lowered so non-overriding implementers can
                // dispatch to it. isInterfaceContext suppresses storage emission.
                var nestedInterfaceAllObjects = nestedInterface.nestedObjects
                if let companionDeclID = nestedInterface.companionObject {
                    nestedInterfaceAllObjects.append(companionDeclID)
                }
                let (nestedDirect, nestedAll) = lowerMemberDecls(
                    memberFunctions: nestedInterface.memberFunctions,
                    memberProperties: nestedInterface.memberProperties,
                    nestedClasses: nestedInterface.nestedClasses,
                    nestedObjects: nestedInterfaceAllObjects,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    compilationCtx: compilationCtx,
                    isInterfaceContext: true
                )
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: nestedDirect)))
                directMembers.append(kirID)
                allDecls.append(kirID)
                allDecls.append(contentsOf: nestedAll)
            default:
                continue
            }
        }

        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case let .objectDecl(nested) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            let (nestedDirect, nestedAll) = lowerMemberDecls(
                memberFunctions: nested.memberFunctions,
                memberProperties: nested.memberProperties,
                nestedClasses: nested.nestedClasses,
                nestedObjects: nested.nestedObjects,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                compilationCtx: compilationCtx
            )
            let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: nestedDirect)))
            directMembers.append(kirID)
            allDecls.append(kirID)
            allDecls.append(contentsOf: nestedAll)
        }

        return (directMembers, allDecls)
    }

    private func lowerSingleMemberFunction(
        declID: DeclID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        directMembers: inout [KIRDeclID],
        allDecls: inout [KIRDeclID]
    ) {
        guard let decl = ast.arena.decl(declID),
              case let .funDecl(function) = decl,
              let symbol = sema.bindings.declSymbols[declID]
        else { return }
        // Functions with an external link name are bridged to a runtime
        // function; call sites are redirected via the external link name
        // (see CallLowerer), so the source body is never executed. Do NOT
        // emit a KIRFunction declaration for them at all: NativeEmitter
        // unconditionally registers every emitted KIRFunction in
        // `internalFunctions[symbol]`, and call-site codegen prefers that
        // internal definition over the redirected external callee name.
        // Emitting even a stub body here would shadow the real runtime
        // function and cause calls to silently invoke the stub instead.
        if let externalLink = sema.symbols.externalLinkName(for: symbol), !externalLink.isEmpty {
            return
        }
        if function.modifiers.contains(.external), function.body == .unit {
            return
        }
        // BUG (found via KSP-CAP-001): member functions are usually lowered
        // between top-level declarations, where resetting scope with no
        // restore is harmless -- there is no enclosing function lowering in
        // progress. But an object literal's member functions are lowered
        // *from inside* whichever function's expression lowering constructs
        // it (`ObjectLiteralLowerer.lowerObjectLiteralMemberFunctions`), so
        // without save/restore here, this reset previously wiped that
        // enclosing function's own locals (parameters, prior `val`/`var`
        // declarations) for the remainder of its lowering. Save/restore
        // (mirroring `LambdaLowerer`'s per-closure scope handling) makes
        // this a no-op for the ordinary top-level case while fixing the
        // nested case.
        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()
        driver.ctx.setCurrentFunctionSymbol(symbol)

        let signature = sema.symbols.functionSignature(for: symbol)
        var params: [KIRParameter] = []
        if let signature {
            if let receiverType = signature.receiverType {
                let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol)
                params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                driver.ctx.setImplicitReceiver(
                    symbol: receiverSymbol,
                    exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                )
            }
            let isVararg = driver.callSupportLowerer.normalizeBoolFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count)
            for (index, (paramSymbol, paramType)) in zip(signature.valueParameterSymbols, signature.parameterTypes).enumerated() {
                let effectiveType: TypeID
                if index < isVararg.count, isVararg[index] {
                    let listFQName: [InternedString] = [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("List"),
                    ]
                    if let listSymbol = sema.symbols.lookup(fqName: listFQName) {
                        effectiveType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(paramType)],
                            nullability: .nonNull
                        )))
                    } else {
                        effectiveType = paramType
                    }
                } else {
                    effectiveType = paramType
                }
                params.append(KIRParameter(symbol: paramSymbol, type: effectiveType))
            }
        }
        if function.isInline, let signature, !signature.reifiedTypeParameterIndices.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            for index in signature.reifiedTypeParameterIndices.sorted() {
                guard index < signature.typeParameterSymbols.count else { continue }
                let typeParamSymbol = signature.typeParameterSymbols[index]
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                params.append(KIRParameter(symbol: tokenSymbol, type: intType))
            }
        }
        let returnType = signature?.returnType ?? sema.types.unitType
        var body: [KIRInstruction] = [.beginBlock]
        bindFunctionParameterLocals(params: params, body: &body, arena: arena)
        // KSP-CAP-001: no-op for ordinary class members -- only object
        // literals ever populate `objectLiteralCaptureSymbols`.
        driver.objectLiteralLowerer.restoreObjectLiteralCaptures(
            forMemberFunction: symbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        )
        switch function.body {
        case let .block(exprIDs, _):
            var terminatedByReturn = false
            for exprID in exprIDs {
                if let expr = ast.arena.expr(exprID), case let .returnExpr(value, _, _) = expr {
                    if let value {
                        let lowered = driver.lowerExpr(value, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &body)
                        body.append(.returnValue(lowered))
                    } else {
                        body.append(.returnUnit)
                    }
                    terminatedByReturn = true
                    break
                }
                let lowered = driver.lowerExpr(exprID, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &body)
                if driver.controlFlowLowerer.isTerminatedExpr(lowered, arena: arena, sema: sema) {
                    terminatedByReturn = true
                    break
                }
            }
            if !terminatedByReturn {
                body.append(.returnUnit)
            }
        case let .expr(exprID, _):
            let value = driver.lowerExpr(exprID, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &body)
            body.append(.returnValue(value))
        case .unit:
            body.append(.returnUnit)
        }
        body.append(.endBlock)
        let kirID = arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: function.name, params: params, returnType: returnType,
            body: body, isSuspend: function.isSuspend, isInline: function.isInline, isTailrec: function.isTailrec
        )))
        directMembers.append(kirID)
        allDecls.append(kirID)
        if let defaults = driver.ctx.defaultArguments(for: symbol), let sig = signature {
            let stubID = driver.callSupportLowerer.generateDefaultStubFunction(
                originalSymbol: symbol, originalName: function.name, signature: sig,
                defaultExpressions: defaults, ast: ast, sema: sema, arena: arena,
                interner: interner, propertyConstantInitializers: propertyConstantInitializers
            )
            allDecls.append(stubID)
        }
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
        driver.ctx.clearImplicitReceiver()
        driver.ctx.setCurrentFunctionSymbol(nil)
    }

    /// Synthesise a getter or setter function for a delegated property.
    ///
    /// Getter emits: `return $delegate_x.getValue(thisRef, KProperty("x"))`
    /// Setter emits: `$delegate_x.setValue(thisRef, KProperty("x"), value)`
    ///
    /// The actual `getValue`/`setValue` calls use the delegate storage symbol
    /// so that `PropertyLoweringPass` can later rewrite them to
    /// `kk_property_access`.
    func lowerDelegateAccessor(
        propertySymbol: SymbolID,
        propertyType: TypeID,
        delegateStorageSymbol: SymbolID,
        delegateKind: StdlibDelegateKind,
        accessorKind: PropertyAccessorKind,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        let shared = KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: [:]
        )
        lowerDelegateAccessor(
            propertySymbol: propertySymbol,
            propertyType: propertyType,
            delegateStorageSymbol: delegateStorageSymbol,
            delegateKind: delegateKind,
            accessorKind: accessorKind,
            shared: shared,
            allDecls: &allDecls
        )
    }

    /// Lower a property getter or setter body as a synthetic KIR function.
    ///
    /// Getter signature: `(<receiver>) -> PropertyType`
    /// Setter signature: `(<receiver>, value: PropertyType) -> Unit`
    func lowerAccessorBody(
        accessorBody: FunctionBody,
        propertySymbol: SymbolID,
        propertyType: TypeID,
        accessorKind: PropertyAccessorKind,
        setterParamName: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        allDecls: inout [KIRDeclID]
    ) {
        let shared = KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        lowerAccessorBody(
            accessorBody: accessorBody,
            propertySymbol: propertySymbol,
            propertyType: propertyType,
            accessorKind: accessorKind,
            setterParamName: setterParamName,
            shared: shared,
            allDecls: &allDecls
        )
    }

    private func bindFunctionParameterLocals(
        params: [KIRParameter],
        body: inout [KIRInstruction],
        arena: KIRArena
    ) {
        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
            driver.ctx.setLocalValue(receiverBinding.exprID, for: receiverBinding.symbol)
        }

        for param in params where param.symbol != driver.ctx.activeImplicitReceiverSymbol() {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            driver.ctx.setLocalValue(paramExpr, for: param.symbol)
        }
    }
}
