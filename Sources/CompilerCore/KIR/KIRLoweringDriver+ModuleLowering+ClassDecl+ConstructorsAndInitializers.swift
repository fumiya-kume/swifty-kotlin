import Foundation

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
        let isSecondary = sema.symbols.symbol(ctorSymbol)?.declSite != classDecl.range
        if !isSecondary {
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
                  let propertySymbol = propertySymbolsByName[param.name],
                  let fieldOffset = sema.symbols.nominalLayout(for: sema.symbols.parentSymbol(for: propertySymbol) ?? .invalid)?
                  .fieldOffsets[propertySymbol]
            else {
                continue
            }

            let parameterSymbol = ctorSignature.valueParameterSymbols[index]
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            let parameterExpr = arena.appendExpr(.symbolRef(parameterSymbol), type: propertyType)
            body.append(.constValue(result: parameterExpr, value: .symbolRef(parameterSymbol)))

            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

            let unusedResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
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

            let unusedResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: shared.sema.types.anyType)
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
        if let delegateExpr = prop.delegateExpression {
            emitDelegatePropertyInitializer(
                delegateExpr: delegateExpr,
                propSymbol: propSymbol,
                sema: sema,
                arena: arena,
                compilationCtx: compilationCtx,
                shared: shared,
                body: &body
            )
            return
        }

        guard let initExpr = prop.initializer else {
            if prop.modifiers.contains(.lateinit) {
                let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
                let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
                let nullExpr = arena.appendExpr(.null, type: propType)
                body.append(.constValue(result: nullExpr, value: .null))
                if let receiverID = ctx.activeImplicitReceiverExprID(),
                   let ownerSymbol = sema.symbols.parentSymbol(for: propSymbol),
                   let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[targetSymbol]
                {
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                    body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    let unusedResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
                    body.append(.call(
                        symbol: nil,
                        callee: compilationCtx.interner.intern("kk_array_set"),
                        arguments: [receiverID, offsetExpr, nullExpr],
                        result: unusedResult,
                        canThrow: false,
                        thrownResult: nil,
                        isSuperCall: false
                    ))
                } else {
                    let fieldRef = arena.appendExpr(.symbolRef(targetSymbol), type: propType)
                    body.append(.copy(from: nullExpr, to: fieldRef))
                }
            }
            return
        }
        let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
        let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
        let initValue = lowerExpr(
            initExpr,
            shared: shared, emit: &body
        )
        let fieldRef = arena.appendExpr(.symbolRef(targetSymbol), type: propType)
        body.append(.copy(from: initValue, to: fieldRef))
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
                    sema: sema,
                    arena: arena,
                    compilationCtx: compilationCtx,
                    shared: shared,
                    body: &body
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
        delegateExpr: ExprID,
        propSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        compilationCtx: CompilationContext,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let delegateStorageSym = sema.symbols.delegateStorageSymbol(for: propSymbol)
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
            let delegateType = sema.types.anyType
            let fieldRef = arena.appendExpr(.symbolRef(storageSym), type: delegateType)
            body.append(.copy(from: valueToStore, to: fieldRef))
        }
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
        let delegateType = sema.types.anyType
        let tempFieldRef = arena.appendExpr(.symbolRef(storageSym), type: delegateType)
        body.append(.copy(from: delegateValue, to: tempFieldRef))
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
        let provideDelegateResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: sema.types.anyType
        )
        body.append(.call(
            symbol: storageSym, callee: provideDelegateName,
            arguments: [thisRefExprID, kPropertyExprID],
            result: provideDelegateResult,
            canThrow: false, thrownResult: nil
        ))
        return provideDelegateResult
    }
}
