
extension KIRLoweringDriver {
    // MARK: - Constructor lowering

    /// Lowers a single constructor (primary or secondary) into KIR declarations.
    func lowerConstructor(
        ctorSymbol: SymbolID,
        ctorFQName: [InternedString],
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        let sema = shared.sema

        // Constructors with an external link name are implemented by the
        // runtime. Do not emit a synthetic constructor body: NativeEmitter
        // registers every emitted KIRFunction as an internal definition, and
        // that definition would shadow the runtime entry point at call sites.
        if let externalLink = sema.symbols.externalLinkName(for: ctorSymbol), !externalLink.isEmpty {
            return []
        }

        let arena = shared.arena
        guard let signature = sema.symbols.functionSignature(for: ctorSymbol) else {
            return []
        }
        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()
        ctx.setCurrentFunctionSymbol(ctorSymbol)

        let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: ctorSymbol)
        var params = [KIRParameter(symbol: receiverSymbol, type: signature.returnType)]
        ctx.setImplicitReceiver(
            symbol: receiverSymbol,
            exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: signature.returnType)
        )
        params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
            KIRParameter(symbol: pair.0, type: pair.1)
        })

        let body = buildConstructorBody(
            ctorSymbol: ctorSymbol, ctorFQName: ctorFQName,
            classDecl: classDecl, ownerSymbol: ownerSymbol,
            shared: shared, compilationCtx: compilationCtx
        )

        let decls = finalizeConstructorDecl(
            ctorSymbol: ctorSymbol, classDecl: classDecl,
            params: params, returnType: signature.returnType,
            body: body, signature: signature, shared: shared
        )
        ctx.setCurrentFunctionSymbol(nil)
        return decls
    }

    /// Builds the constructor body instructions for a primary or secondary constructor.
    private func buildConstructorBody(
        ctorSymbol: SymbolID,
        ctorFQName: [InternedString],
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> KIRLoweringEmitContext {
        let sema = shared.sema
        var body: KIRLoweringEmitContext = [.beginBlock]
        if let receiverBinding = ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }
        let constructorDeclSite = sema.symbols.symbol(ctorSymbol)?.declSite
        let isSecondary = classDecl.secondaryConstructors.contains { constructor in
            constructor.range == constructorDeclSite
        }
        if !isSecondary {
            emitSuperConstructorDelegation(
                classDecl: classDecl, ctorSymbol: ctorSymbol, ownerSymbol: ownerSymbol,
                shared: shared, compilationCtx: compilationCtx, body: &body
            )
            emitPrimaryConstructorPropertyInitializers(
                classDecl: classDecl,
                shared: shared,
                compilationCtx: compilationCtx,
                body: &body
            )
            emitClassDelegationInitializers(
                classDecl: classDecl, ownerSymbol: ownerSymbol,
                receiverID: ctx.activeImplicitReceiverExprID()!,
                shared: shared, compilationCtx: compilationCtx, body: &body
            )
            emitClassBodyInitializers(
                classDecl: classDecl, shared: shared,
                compilationCtx: compilationCtx, body: &body
            )
        }
        if isSecondary {
            emitSecondaryConstructorBody(
                classDecl: classDecl, ctorSymbol: ctorSymbol,
                ctorFQName: ctorFQName, ownerSymbol: ownerSymbol,
                shared: shared, compilationCtx: compilationCtx, body: &body
            )
        }
        if let receiver = ctx.activeImplicitReceiverExprID() {
            body.append(.returnValue(receiver))
        } else {
            body.append(.returnUnit)
        }
        body.append(.endBlock)
        return body
    }

    /// Emits the implicit `super(...)` call of a primary constructor.
    ///
    /// Kotlin runs the superclass constructor before the subclass's own
    /// initializers, so the superclass's property initializers and `init`
    /// blocks — which write into the same object at the layout offsets the
    /// subclass inherits — must execute here. Without this call a subclass
    /// instance keeps the zeroed defaults for every inherited property
    /// (BUG-155).
    func emitSuperConstructorDelegation(
        classDecl: ClassDecl,
        ctorSymbol: SymbolID,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        guard let receiverID = ctx.activeImplicitReceiverExprID(),
              let superclassSymbol = sema.symbols.directSupertypes(for: ownerSymbol).first(where: {
                  let kind = sema.symbols.symbol($0)?.kind
                  return kind == .class || kind == .enumClass
              }),
              let superclassInfo = sema.symbols.symbol(superclassSymbol)
        else {
            return
        }
        let superCtorSymbol = sema.bindings.constructorDelegationTarget(for: ctorSymbol)
            ?? sema.symbols
            .lookupAll(fqName: superclassInfo.fqName + [compilationCtx.interner.intern("<init>")])
            .first { $0 != ctorSymbol }
        guard let superCtorSymbol else {
            return
        }

        let superArgs = classDecl.superTypeEntries.first { !$0.constructorArgs.isEmpty }?.constructorArgs ?? []
        if !(sema.symbols.externalLinkName(for: superCtorSymbol)?.isEmpty ?? true) {
            // Runtime-backed Throwable construction returns its own native box,
            // while a Kotlin subclass already owns the compiler-emitted object.
            // Initialize that object through the message accessor instead of
            // discarding it in favor of the factory result.
            let nullableStringType = sema.types.makeNullable(sema.types.stringType)
            let nullableThrowableType = sema.types.make(.classType(ClassType(
                classSymbol: superclassSymbol,
                args: [],
                nullability: .nullable
            )))
            guard superclassInfo.fqName.map({ compilationCtx.interner.resolve($0) }) == ["kotlin", "Throwable"],
                  let signature = sema.symbols.functionSignature(for: superCtorSymbol)
            else {
                return
            }

            func setterSymbol(named name: String) -> SymbolID? {
                sema.symbols.lookupAll(
                    fqName: superclassInfo.fqName.dropLast() + [compilationCtx.interner.intern(name)]
                ).first(where: { candidate in
                    sema.symbols.symbol(candidate)?.kind == .function
                })
            }

            func emitSetter(_ symbol: SymbolID, argument: KIRExprID, fallbackName: String) {
                let resultID = arena.appendTemporary(type: sema.types.unitType)
                body.append(.call(
                    symbol: symbol,
                    callee: compilationCtx.interner.intern(
                        sema.symbols.externalLinkName(for: symbol) ?? fallbackName
                    ),
                    arguments: [receiverID, argument],
                    result: resultID,
                    canThrow: false,
                    thrownResult: nil,
                    isSuperCall: false
                ))
            }

            switch signature.parameterTypes.count {
            case 0:
                guard superArgs.isEmpty,
                      let messageSetter = setterSymbol(named: "__kkThrowableSetMessage")
                else {
                    return
                }
                let messageID = arena.appendExpr(.null, type: nullableStringType)
                body.append(.constValue(result: messageID, value: .null))
                emitSetter(messageSetter, argument: messageID, fallbackName: "__kkThrowableSetMessage")
            case 1:
                guard signature.parameterTypes[0] == nullableStringType,
                      superArgs.count == 1,
                      let messageSetter = setterSymbol(named: "__kkThrowableSetMessage")
                else {
                    return
                }
                let messageID = lowerExpr(superArgs[0].expr, shared: shared, emit: &body)
                emitSetter(messageSetter, argument: messageID, fallbackName: "__kkThrowableSetMessage")
            case 2:
                guard signature.parameterTypes[0] == nullableStringType,
                      signature.parameterTypes[1] == nullableThrowableType,
                      superArgs.count == 2,
                      let messageSetter = setterSymbol(named: "__kkThrowableSetMessage"),
                      let causeSetter = setterSymbol(named: "__kkThrowableSetCause")
                else {
                    return
                }
                let messageID = lowerExpr(superArgs[0].expr, shared: shared, emit: &body)
                let causeID = lowerExpr(superArgs[1].expr, shared: shared, emit: &body)
                emitSetter(messageSetter, argument: messageID, fallbackName: "__kkThrowableSetMessage")
                emitSetter(causeSetter, argument: causeID, fallbackName: "__kkThrowableSetCause")
            default:
                return
            }
            return
        }
        // Synthetic nominal shells may expose a constructor for Sema
        // compatibility without providing a linkable implementation.
        guard !(sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) ?? false) else {
            return
        }

        // HashSet is source-backed while AbstractMutableSet remains a synthetic
        // surface. Its synthetic protected constructor has no emitted body, so
        // a generated parent call would leave an unresolved `<init>` symbol.
        let hashSetFQName = [
            compilationCtx.interner.intern("kotlin"),
            compilationCtx.interner.intern("collections"),
            compilationCtx.interner.intern("HashSet"),
        ]
        if sema.symbols.symbol(ownerSymbol)?.fqName == hashSetFQName,
           sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) == true
        {
            return
        }

        var argIDs: [KIRExprID] = [receiverID]
        for arg in superArgs {
            argIDs.append(lowerExpr(arg.expr, shared: shared, emit: &body))
        }

        let resultID = arena.appendTemporary(type: sema.types.unitType)
        body.append(.call(
            symbol: superCtorSymbol,
            callee: compilationCtx.interner.intern("<init>"),
            arguments: argIDs,
            result: resultID,
            canThrow: false,
            thrownResult: nil,
            isSuperCall: false
        ))
    }

    private func emitPrimaryConstructorPropertyInitializers(
        classDecl: ClassDecl,
        shared: KIRLoweringSharedContext,
        compilationCtx _: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena

        let propertySymbolsByName: [InternedString: SymbolID] = Dictionary(
            uniqueKeysWithValues: classDecl.memberProperties.compactMap { declID in
                guard let symbol = sema.bindings.declSymbols[declID],
                      let decl = shared.ast.arena.decl(declID),
                      case let .propertyDecl(propertyDecl) = decl
                else {
                    return nil
                }
                return (propertyDecl.name, symbol)
            }
        )

        guard let receiverID = ctx.activeImplicitReceiverExprID(),
              let ctorSignature = sema.symbols.functionSignature(for: ctx.activeFunctionSymbol() ?? .invalid)
        else {
            return
        }

        for (index, param) in classDecl.primaryConstructorParams.enumerated() {
            guard param.isProperty,
                  index < ctorSignature.valueParameterSymbols.count,
                  let propertySymbol = propertySymbolsByName[param.name]
            else {
                continue
            }
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            guard let fieldOffset = sema.symbols.nominalLayout(
                for: sema.symbols.parentSymbol(for: propertySymbol) ?? .invalid
            )?.fieldOffsets[targetSymbol] else {
                continue
            }

            let parameterSymbol = ctorSignature.valueParameterSymbols[index]
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            let parameterExpr = arena.appendExpr(.symbolRef(parameterSymbol), type: propertyType)
            body.append(.constValue(result: parameterExpr, value: .symbolRef(parameterSymbol)))

            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

            let unusedResult = arena.appendTemporary(type: sema.types.anyType)
            body.append(.call(
                symbol: nil,
                callee: shared.interner.intern("kk_array_set"),
                arguments: [receiverID, offsetExpr, parameterExpr],
                result: unusedResult,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: false
            ))
        }
    }

    /// Creates the KIR function declaration and default-argument stub for a constructor.
    private func finalizeConstructorDecl(
        ctorSymbol: SymbolID,
        classDecl: ClassDecl,
        params: [KIRParameter],
        returnType: TypeID,
        body: KIRLoweringEmitContext,
        signature: FunctionSignature,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let arena = shared.arena
        var declIDs: [KIRDeclID] = []
        let ctorKirID = arena.appendDecl(
            .function(KIRFunction(
                symbol: ctorSymbol, name: classDecl.name,
                params: params, returnType: returnType,
                body: body, isSuspend: false, isInline: false
            ))
        )
        declIDs.append(ctorKirID)
        if let defaults = ctx.defaultArguments(for: ctorSymbol) {
            let stubID = callSupportLowerer.generateDefaultStubFunction(
                originalSymbol: ctorSymbol, originalName: classDecl.name,
                signature: signature, defaultExpressions: defaults,
                shared: shared
            )
            declIDs.append(stubID)
        }
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        return declIDs
    }

    /// CLASS-008: Emits delegate field initialization for `: Interface by expr`.
    private func emitClassDelegationInitializers(
        classDecl _: ClassDecl,
        ownerSymbol: SymbolID,
        receiverID: KIRExprID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        for interfaceSymbol in sema.symbols.delegatedInterfaces(forClass: ownerSymbol) {
            guard let delegateExpr = sema.symbols.classDelegationExpr(forClass: ownerSymbol, interface: interfaceSymbol),
                  let fieldSymbol = sema.symbols.classDelegationField(forClass: ownerSymbol, interface: interfaceSymbol)
            else {
                continue
            }
            let delegateValue = lowerExpr(delegateExpr, shared: shared, emit: &body)

            guard let fieldOffset = shared.sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[fieldSymbol] else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: shared.sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

            let unusedResult = arena.appendTemporary(type: shared.sema.types.anyType)
            body.append(.call(
                symbol: nil,
                callee: compilationCtx.interner.intern("kk_array_set"),
                arguments: [receiverID, offsetExpr, delegateValue],
                result: unusedResult,
                canThrow: true,
                thrownResult: nil,
                isSuperCall: false
            ))
        }
    }

    /// Emits property initializers and `init { }` blocks in the order they
    /// appear in the class body, matching Kotlin's guaranteed top-to-bottom
    /// initialization semantics.
    ///
    /// The order is driven by `classBodyInitOrder`, which the AST builder
    /// populates from the declaration-order sequence of properties and
    /// `init` blocks in the source.
    func emitClassBodyInitializers(
        classDecl: ClassDecl,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) {
        for member in classDecl.classBodyInitOrder {
            switch member {
            case let .property(index):
                guard index < classDecl.memberProperties.count else { continue }
                let propDeclID = classDecl.memberProperties[index]
                emitPropertyInitializer(
                    propDeclID: propDeclID,
                    shared: shared,
                    compilationCtx: compilationCtx,
                    body: &body
                )
            case let .initBlock(index):
                guard index < classDecl.initBlocks.count else { continue }
                emitInitBlock(classDecl.initBlocks[index], shared: shared, body: &body)
            }
        }
    }

    func emitInitBlock(
        _ initBlock: FunctionBody,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        switch initBlock {
        case let .block(exprIDs, _):
            for exprID in exprIDs {
                _ = lowerExpr(exprID, shared: shared, emit: &body)
            }
        case let .expr(exprID, _):
            _ = lowerExpr(exprID, shared: shared, emit: &body)
        case .unit:
            break
        }
    }

    func emitPropertyInitializer(
        propDeclID: DeclID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        guard let propDecl = ast.arena.decl(propDeclID),
              case let .propertyDecl(prop) = propDecl,
              let propSymbol = sema.bindings.declSymbols[propDeclID]
        else {
            return
        }

        // Handle delegated property initialisation:
        // lower the delegate expression and store it in
        // the $delegate_ storage field.  If the delegate
        // type exposes a `provideDelegate` operator, wrap
        // the initial value in a provideDelegate call;
        // otherwise store the delegate value directly.
        if prop.delegateExpression != nil {
            emitDelegatePropertyInitializer(
                propertyDecl: prop,
                propSymbol: propSymbol,
                sema: sema,
                arena: arena,
                compilationCtx: compilationCtx,
                shared: shared,
                body: &body
            )
            return
        }

        // Kotlin 2.0 explicit backing field: initialize from field's own initializer.
        if let explicitField = prop.explicitBackingField {
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
            let backingFieldType = sema.symbols.propertyType(for: targetSymbol) ?? sema.types.anyType
            let initValue = lowerExpr(
                explicitField.initializer,
                shared: shared, emit: &body
            )
            emitFieldStore(
                propSymbol: propSymbol, targetSymbol: targetSymbol,
                value: initValue, valueType: backingFieldType,
                shared: shared, compilationCtx: compilationCtx, body: &body
            )
            // Also initialize the property itself if it has a regular initializer.
            if let initExpr = prop.initializer {
                let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
                let propInitValue = lowerExpr(initExpr, shared: shared, emit: &body)
                emitFieldStore(
                    propSymbol: propSymbol, targetSymbol: targetSymbol,
                    value: propInitValue, valueType: propType,
                    shared: shared, compilationCtx: compilationCtx, body: &body
                )
            }
            return
        }

        guard let initExpr = prop.initializer else {
            if prop.modifiers.contains(.lateinit) {
                let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
                let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
                let nullExpr = arena.appendExpr(.null, type: propType)
                body.append(.constValue(result: nullExpr, value: .null))
                emitFieldStore(
                    propSymbol: propSymbol, targetSymbol: targetSymbol,
                    value: nullExpr, valueType: propType,
                    shared: shared, compilationCtx: compilationCtx, body: &body
                )
            }
            return
        }
        let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
        let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
        let initValue = lowerExpr(
            initExpr,
            shared: shared, emit: &body
        )
        emitFieldStore(
            propSymbol: propSymbol, targetSymbol: targetSymbol,
            value: initValue, valueType: propType,
            shared: shared, compilationCtx: compilationCtx, body: &body
        )
    }

    /// Stores `value` into the storage backing `targetSymbol` on the instance
    /// currently under construction.
    ///
    /// Class instance properties live inside the heap-allocated object, not in
    /// a module-global slot, so the write must go through `kk_array_set` at
    /// the property's computed field offset (the same mechanism reads use in
    /// `tryLowerStoredMemberPropertyRead`) — mirroring how primary-constructor
    /// property parameters are stored in `emitPrimaryConstructorPropertyInitializers`.
    /// Falls back to a direct symbol copy when no constructor receiver or
    /// layout is available (e.g. if ever invoked outside a constructor body).
    private func emitFieldStore(
        propSymbol: SymbolID,
        targetSymbol: SymbolID,
        value: KIRExprID,
        valueType: TypeID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        if let receiverID = ctx.activeImplicitReceiverExprID(),
           let ownerSymbol = sema.symbols.parentSymbol(for: propSymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface,
           let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[targetSymbol]
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let unusedResult = arena.appendTemporary(type: sema.types.anyType)
            body.append(.call(
                symbol: nil,
                callee: compilationCtx.interner.intern("kk_array_set"),
                arguments: [receiverID, offsetExpr, value],
                result: unusedResult,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: false
            ))
        } else {
            let fieldRef = arena.appendExpr(.symbolRef(targetSymbol), type: valueType)
            body.append(.copy(from: value, to: fieldRef))
        }
    }

    // MARK: - Secondary constructor body emission

    func emitSecondaryConstructorBody(
        classDecl: ClassDecl,
        ctorSymbol: SymbolID,
        ctorFQName: [InternedString],
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        for secondaryCtor in classDecl.secondaryConstructors {
            guard secondaryCtor.range == sema.symbols.symbol(ctorSymbol)?.declSite else {
                continue
            }
            if let delegation = secondaryCtor.delegationCall {
                emitDelegationCall(
                    delegation: delegation,
                    ctorFQName: ctorFQName,
                    ownerSymbol: ownerSymbol,
                    ctorSymbol: ctorSymbol,
                    sema: sema,
                    arena: arena,
                    compilationCtx: compilationCtx,
                    shared: shared,
                    body: &body
                )
            } else if !classDecl.hasPrimaryConstructorSyntax {
                // No explicit delegation and no primary constructor to route
                // through: the superclass constructor is invoked implicitly.
                emitSuperConstructorDelegation(
                    classDecl: classDecl, ctorSymbol: ctorSymbol, ownerSymbol: ownerSymbol,
                    shared: shared, compilationCtx: compilationCtx, body: &body
                )
            }
            // A class without a primary constructor runs its property
            // initializers and `init` blocks inside every secondary
            // constructor that reaches the superclass directly; constructors
            // delegating to `this(...)` inherit them from the target instead.
            if secondaryCtor.delegationCall?.kind != .this {
                emitClassBodyInitializers(
                    classDecl: classDecl, shared: shared,
                    compilationCtx: compilationCtx, body: &body
                )
            }
            switch secondaryCtor.body {
            case let .block(exprIDs, _):
                for exprID in exprIDs {
                    _ = lowerExpr(exprID, shared: shared, emit: &body)
                }
            case let .expr(exprID, _):
                _ = lowerExpr(exprID, shared: shared, emit: &body)
            case .unit:
                break
            }
            break
        }
    }

    private func emitDelegatePropertyInitializer(
        propertyDecl: PropertyDecl,
        propSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        compilationCtx: CompilationContext,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        guard let delegateExpr = propertyDecl.delegateExpression else { return }
        let delegateStorageSym = sema.symbols.delegateStorageSymbol(for: propSymbol)
        let delegateKind = StdlibDelegateKind.detect(
            delegateExpr: delegateExpr, ast: shared.ast, interner: shared.interner
        )

        guard delegateKind == .custom else {
            emitStdlibDelegatePropertyInitializer(
                delegateKind: delegateKind, propertyDecl: propertyDecl,
                propSymbol: propSymbol, delegateStorageSym: delegateStorageSym,
                sema: sema, arena: arena, shared: shared,
                compilationCtx: compilationCtx, body: &body
            )
            return
        }

        let delegateValue = lowerExpr(delegateExpr, shared: shared, emit: &body)
        let delegateExprType = sema.bindings.exprType(for: delegateExpr)
        let hasProvideDelegate = checkHasProvideDelegate(
            delegateExprType: delegateExprType, shared: shared
        )
        let valueToStore: KIRExprID = if hasProvideDelegate, let storageSym = delegateStorageSym {
            emitProvideDelegateCall(
                delegateValue: delegateValue, storageSym: storageSym,
                propSymbol: propSymbol, sema: sema, arena: arena,
                compilationCtx: compilationCtx, shared: shared, body: &body
            )
        } else {
            delegateValue
        }
        if let storageSym = delegateStorageSym {
            emitFieldStore(
                propSymbol: propSymbol, targetSymbol: storageSym,
                value: valueToStore, valueType: sema.types.anyType,
                shared: shared, compilationCtx: compilationCtx, body: &body
            )
        }
    }

    /// Initializes a member delegate property backed by a stdlib delegate
    /// factory (`lazy`, `Delegates.observable/vetoable/notNull`).
    ///
    /// Unlike a custom delegate expression, these factories split their
    /// argument across two AST fields — `delegateExpression` (the initial
    /// value, for observable/vetoable) and `delegateBody` (the trailing
    /// lambda) — so they cannot be lowered by evaluating `delegateExpression`
    /// alone; doing so silently drops the callback/initializer lambda.
    private func emitStdlibDelegatePropertyInitializer(
        delegateKind: StdlibDelegateKind,
        propertyDecl: PropertyDecl,
        propSymbol: SymbolID,
        delegateStorageSym: SymbolID?,
        sema: SemaModule,
        arena: KIRArena,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) {
        guard let storageSym = delegateStorageSym else { return }
        let interner = shared.interner
        let delegateType = sema.types.anyType
        let createResult: KIRExprID

        switch delegateKind {
        case .lazy:
            let lambdaFnPtr = lowerDelegateLambdaBody(
                delegateBody: propertyDecl.delegateBody,
                delegateBodyParams: propertyDecl.delegateBodyParams, propertySymbol: propSymbol,
                paramCount: 0, shared: shared, emit: &body
            )
            let lockValue = LazyThreadSafetyModeLowering.lockExpression(
                from: propertyDecl.delegateExpression,
                ast: shared.ast,
                sema: shared.sema,
                interner: interner
            ).map { lowerExpr($0, shared: shared, emit: &body) }
            let modeExpr = lowerLazyModeExpr(
                delegateExpression: propertyDecl.delegateExpression,
                shared: shared, compilationCtx: compilationCtx, emit: &body
            )
            let lockArgument: KIRExprID
            if let lockValue {
                lockArgument = lockValue
            } else {
                lockArgument = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                body.append(.constValue(result: lockArgument, value: .null))
            }
            let initialValueExpr = arena.appendExpr(.unit, type: sema.types.anyType)
            body.append(.constValue(result: initialValueExpr, value: .null))
            let initialComputedExpr = arena.appendExpr(.boolLiteral(false), type: sema.types.booleanType)
            body.append(.constValue(result: initialComputedExpr, value: .boolLiteral(false)))
            guard let ctorSymbol = stdlibDelegateSymbol(
                fqName: [interner.intern("kotlin"), interner.intern("LazyImpl"), interner.intern("<init>")],
                parameterCount: 5, sema: sema
            ), let ownerSymbol = sema.symbols.parentSymbol(for: ctorSymbol) else {
                preconditionFailure("KSP-491: missing kotlin.LazyImpl constructor")
            }
            let allocatedObj = allocateStdlibDelegateInstance(
                ownerSymbol: ownerSymbol, resultType: delegateType,
                sema: sema, arena: arena, interner: interner, emit: &body
            )
            createResult = arena.appendTemporary(type: delegateType)
            body.append(.call(
                symbol: ctorSymbol, callee: interner.intern("<init>"),
                arguments: [allocatedObj, lambdaFnPtr, modeExpr, lockArgument, initialValueExpr, initialComputedExpr],
                result: createResult, canThrow: false, thrownResult: nil
            ))
        case .observable, .vetoable:
            let initialValueExpr = lowerDelegateInitialValue(
                delegateExpr: propertyDecl.delegateExpression, shared: shared, emit: &body
            )
            let callbackFnPtr = lowerDelegateLambdaBody(
                delegateBody: propertyDecl.delegateBody,
                delegateBodyParams: propertyDecl.delegateBodyParams,
                valueType: sema.symbols.propertyType(for: propSymbol), propertySymbol: propSymbol,
                paramCount: 3, shared: shared, emit: &body
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
                sema: sema, arena: arena, interner: interner, emit: &body
            )
            createResult = arena.appendTemporary(type: delegateType)
            body.append(.call(
                symbol: ctorSymbol, callee: interner.intern("<init>"),
                arguments: [allocatedObj, initialValueExpr, callbackFnPtr],
                result: createResult, canThrow: false, thrownResult: nil
            ))
        case .notNull:
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
                sema: sema, arena: arena, interner: interner, emit: &body
            )
            createResult = arena.appendTemporary(type: delegateType)
            body.append(.call(
                symbol: ctorSymbol, callee: interner.intern("<init>"),
                arguments: [allocatedObj],
                result: createResult, canThrow: false, thrownResult: nil
            ))
        case .custom:
            preconditionFailure("emitStdlibDelegatePropertyInitializer must not be called for .custom")
        }

        emitFieldStore(
            propSymbol: propSymbol, targetSymbol: storageSym,
            value: createResult, valueType: delegateType,
            shared: shared, compilationCtx: compilationCtx, body: &body
        )
    }

    private func emitProvideDelegateCall(
        delegateValue: KIRExprID,
        storageSym: SymbolID,
        propSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        compilationCtx: CompilationContext,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        guard let provideDelegateSymbol = sema.symbols.delegateProvideDelegateSymbol(
            for: propSymbol
        ) else {
            return delegateValue
        }
        let delegateType = sema.types.anyType
        emitFieldStore(
            propSymbol: propSymbol, targetSymbol: storageSym,
            value: delegateValue, valueType: delegateType,
            shared: shared, compilationCtx: compilationCtx, body: &body
        )
        let propertyName = sema.symbols.symbol(propSymbol)?.name
            ?? compilationCtx.interner.intern("")
        let thisRefExprID: KIRExprID
        if let receiver = ctx.activeImplicitReceiverExprID() {
            thisRefExprID = receiver
        } else {
            let nullExpr = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: nullExpr, value: .null))
            thisRefExprID = nullExpr
        }
        let kPropertyExprID = emitKPropertyStubCreate(
            propertyName: propertyName,
            propertyType: sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType,
            shared: shared, emit: &body
        )
        let provideDelegateName = compilationCtx.interner.intern("provideDelegate")
        let provideDelegateResult = arena.appendTemporary(type: sema.types.anyType
        )
        body.append(.call(
            symbol: provideDelegateSymbol, callee: provideDelegateName,
            arguments: [delegateValue, thisRefExprID, kPropertyExprID],
            result: provideDelegateResult,
            canThrow: false, thrownResult: nil
        ))
        return provideDelegateResult
    }

    func synthesizeConstructorReflectionInitializer(
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        guard let ownerInfo = sema.symbols.symbol(ownerSymbol) else {
            return []
        }

        let ctorFQName = ownerInfo.fqName + [interner.intern("<init>")]
        let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
        guard !ctorSymbols.isEmpty else {
            return []
        }

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern("__ctor_reflect_init_\(ownerSymbol.rawValue)")
        let intType = sema.types.intType

        var body: KIRLoweringEmitContext = [.beginBlock]

        let typeToken = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: ownerSymbol,
            sema: sema,
            interner: interner
        )
        let encodedToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: false,
            payload: typeToken
        )
        let typeTokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
        body.append(.constValue(result: typeTokenExpr, value: .intLiteral(encodedToken)))

        let simpleNameInterned = interner.intern(interner.resolve(classDecl.name))
        let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleNameInterned), type: intType)
        body.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleNameInterned)))

        let kclassExpr = arena.appendTemporary(type: sema.types.makeKClassType(argument: sema.types.anyType)
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_kclass_create"),
            arguments: [typeTokenExpr, simpleNameExpr],
            result: kclassExpr,
            canThrow: false,
            thrownResult: nil
        ))

        let ctorNameInterned = interner.intern("<init>")
        let ctorNameExpr = arena.appendExpr(.stringLiteral(ctorNameInterned), type: intType)
        body.append(.constValue(result: ctorNameExpr, value: .stringLiteral(ctorNameInterned)))

        let returnTypeExpr = arena.appendExpr(.stringLiteral(simpleNameInterned), type: intType)
        body.append(.constValue(result: returnTypeExpr, value: .stringLiteral(simpleNameInterned)))

        let visibilityExpr = arena.appendExpr(.intLiteral(0), type: intType)
        body.append(.constValue(result: visibilityExpr, value: .intLiteral(0)))

        for ctorSymbol in ctorSymbols {
            guard let signature = sema.symbols.functionSignature(for: ctorSymbol) else {
                continue
            }
            let arityExpr = arena.appendExpr(.intLiteral(Int64(signature.parameterTypes.count)), type: intType)
            body.append(.constValue(result: arityExpr, value: .intLiteral(Int64(signature.parameterTypes.count))))

            let fnPtrExpr = arena.appendExpr(.symbolRef(ctorSymbol), type: intType)
            body.append(.constValue(result: fnPtrExpr, value: .symbolRef(ctorSymbol)))

            let isPrimary = sema.symbols.symbol(ctorSymbol)?.declSite == classDecl.range ? 1 : 0
            let isPrimaryExpr = arena.appendExpr(.intLiteral(Int64(isPrimary)), type: intType)
            body.append(.constValue(result: isPrimaryExpr, value: .intLiteral(Int64(isPrimary))))

            let registrationResult = arena.appendTemporary(type: intType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_kconstructor_create"),
                arguments: [ctorNameExpr, arityExpr, returnTypeExpr, fnPtrExpr, isPrimaryExpr, visibilityExpr, kclassExpr],
                result: registrationResult,
                canThrow: false,
                thrownResult: nil
            ))
        }

        // STDLIB-REFLECT-ABI-002: Register declared member functions and properties.
        emitMemberReflectionRegistration(
            ownerSymbol: ownerSymbol,
            kclassExpr: kclassExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )

        body.append(.returnUnit)
        body.append(.endBlock)

        let declID = arena.appendDecl(
            .function(KIRFunction(
                symbol: initializerSymbol,
                name: initializerName,
                params: [],
                returnType: sema.types.unitType,
                body: body,
                isSuspend: false,
                isInline: false,
                sourceRange: classDecl.range
            ))
        )
        ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)
        return [declID]
    }

    // MARK: - STDLIB-REFLECT-ABI-002: Member Reflection Registration

    /// Emits `kk_kfunction_create` / `__kk_kproperty_stub_create` calls for each
    /// declared non-synthetic member of a class, followed by
    /// `kk_kclass_register_member` to attach them to the KClass handle.
    /// Called from `synthesizeConstructorReflectionInitializer` so that
    /// `KClass.members` returns real handles rather than count-sized placeholders.
    func emitMemberReflectionRegistration(
        ownerSymbol: SymbolID,
        kclassExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) {
        guard let ownerInfo = sema.symbols.symbol(ownerSymbol) else { return }
        let intType = sema.types.intType
        let childSymbols = sema.symbols.children(ofFQName: ownerInfo.fqName)
        for childID in childSymbols {
            guard let childSym = sema.symbols.symbol(childID),
                  !childSym.flags.contains(.synthetic)
            else { continue }
            switch childSym.kind {
            case .function:
                guard let signature = sema.symbols.functionSignature(for: childID) else { continue }
                let fnName = interner.resolve(childSym.name)
                let fnNameInterned = interner.intern(fnName)
                let fnNameExpr = arena.appendExpr(.stringLiteral(fnNameInterned), type: intType)
                body.append(.constValue(result: fnNameExpr, value: .stringLiteral(fnNameInterned)))
                let arity = Int64(signature.parameterTypes.count)
                let arityExpr = arena.appendExpr(.intLiteral(arity), type: intType)
                body.append(.constValue(result: arityExpr, value: .intLiteral(arity)))
                let returnTypeName = sema.types.displayName(
                    of: signature.returnType, symbols: sema.symbols, interner: interner
                )
                let retTypeInterned = interner.intern(returnTypeName)
                let retTypeExpr = arena.appendExpr(.stringLiteral(retTypeInterned), type: intType)
                body.append(.constValue(result: retTypeExpr, value: .stringLiteral(retTypeInterned)))
                let isSuspendInt = Int64(signature.isSuspend ? 1 : 0)
                let isSuspendExpr = arena.appendExpr(.intLiteral(isSuspendInt), type: intType)
                body.append(.constValue(result: isSuspendExpr, value: .intLiteral(isSuspendInt)))
                let fnPtrExpr = arena.appendExpr(.symbolRef(childID), type: intType)
                body.append(.constValue(result: fnPtrExpr, value: .symbolRef(childID)))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let kfunctionResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_kfunction_create"),
                    arguments: [fnNameExpr, arityExpr, retTypeExpr, isSuspendExpr, fnPtrExpr, zeroExpr],
                    result: kfunctionResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                let fnRegisterResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_kclass_register_member"),
                    arguments: [kclassExpr, kfunctionResult],
                    result: fnRegisterResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            case .property:
                let propName = interner.resolve(childSym.name)
                let propNameInterned = interner.intern(propName)
                let propNameExpr = arena.appendExpr(.stringLiteral(propNameInterned), type: intType)
                body.append(.constValue(result: propNameExpr, value: .stringLiteral(propNameInterned)))
                let propTypeName: String
                if let propTypeID = sema.symbols.propertyType(for: childID) {
                    propTypeName = sema.types.displayName(
                        of: propTypeID, symbols: sema.symbols, interner: interner
                    )
                } else {
                    propTypeName = "kotlin.Any"
                }
                let propTypeInterned = interner.intern(propTypeName)
                let propTypeExpr = arena.appendExpr(.stringLiteral(propTypeInterned), type: intType)
                body.append(.constValue(result: propTypeExpr, value: .stringLiteral(propTypeInterned)))
                let kpropResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_kproperty_stub_create"),
                    arguments: [propNameExpr, propTypeExpr],
                    result: kpropResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                let propRegisterResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_kclass_register_member"),
                    arguments: [kclassExpr, kpropResult],
                    result: propRegisterResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            default:
                break
            }
        }
    }
}
