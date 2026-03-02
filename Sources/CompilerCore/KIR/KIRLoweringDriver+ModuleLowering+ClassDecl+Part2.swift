import Foundation

extension KIRLoweringDriver {
    // MARK: - Constructor lowering

    // Lowers a single constructor (primary or secondary) into KIR declarations.
    // swiftlint:disable:next function_parameter_count
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

        let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: ctorSymbol)
        var params = [KIRParameter(symbol: receiverSymbol, type: signature.returnType)]
        ctx.currentImplicitReceiverSymbol = receiverSymbol
        ctx.currentImplicitReceiverExprID = arena.appendExpr(
            .symbolRef(receiverSymbol), type: signature.returnType
        )
        params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
            KIRParameter(symbol: pair.0, type: pair.1)
        })

        let body = buildConstructorBody(
            ctorSymbol: ctorSymbol, ctorFQName: ctorFQName,
            classDecl: classDecl, ownerSymbol: ownerSymbol,
            shared: shared, compilationCtx: compilationCtx
        )

        return finalizeConstructorDecl(
            ctorSymbol: ctorSymbol, classDecl: classDecl,
            params: params, returnType: signature.returnType,
            body: body, signature: signature, shared: shared
        )
    }

    // Builds the constructor body instructions for a primary or secondary constructor.
    // swiftlint:disable:next function_parameter_count
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
        // swiftlint:disable:next opening_brace
        if let receiverExpr = ctx.currentImplicitReceiverExprID,
           let receiverSym = ctx.currentImplicitReceiverSymbol
        {
            body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSym)))
        }
        let isSecondary = sema.symbols.symbol(ctorSymbol)?.declSite != classDecl.range
        if !isSecondary {
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
        if let receiver = ctx.currentImplicitReceiverExprID {
            body.append(.returnValue(receiver))
        } else {
            body.append(.returnUnit)
        }
        body.append(.endBlock)
        return body
    }

    // Creates the KIR function declaration and default-argument stub for a constructor.
    // swiftlint:disable:next function_parameter_count
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
        if let defaults = ctx.functionDefaultArgumentsBySymbol[ctorSymbol] {
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

    /// Emits property initializers and `init { }` blocks in the order they
    /// appear in the class body, matching Kotlin's guaranteed top-to-bottom
    /// initialization semantics.
    ///
    /// When `classBodyInitOrder` is populated (non-empty) the order recorded
    /// by the AST builder is used.  For backward-compatibility with AST nodes
    /// that pre-date this change the method falls back to the legacy
    /// "all properties first, then all init blocks" ordering.
    func emitClassBodyInitializers(
        classDecl: ClassDecl,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) {
        if !classDecl.classBodyInitOrder.isEmpty {
            // ── Declaration-order path ──────────────────────────────
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
        } else {
            // ── Fallback: legacy ordering (all properties, then init blocks)
            for propDeclID in classDecl.memberProperties {
                emitPropertyInitializer(
                    propDeclID: propDeclID,
                    shared: shared,
                    compilationCtx: compilationCtx,
                    body: &body
                )
            }
            for initBlock in classDecl.initBlocks {
                emitInitBlock(initBlock, shared: shared, body: &body)
            }
        }
    }

    /// Emits a single `init { }` block into the constructor body.
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

    /// Emits a single member property initializer (including delegate
    /// properties) as a field store in the constructor body.
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

    // Emits the body of a secondary constructor, including delegation
    // call and body statements.
    // swiftlint:disable:next function_parameter_count
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

    // Emits a delegated property initializer, handling provideDelegate
    // when available on the delegate type.
    // swiftlint:disable:next function_parameter_count
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
        let hasProvideDelegate = checkProvideDelegate(
            delegateExpr: delegateExpr, sema: sema, compilationCtx: compilationCtx
        )
        let valueToStore: KIRExprID = if hasProvideDelegate, let storageSym = delegateStorageSym {
            emitProvideDelegateCall(
                delegateValue: delegateValue, storageSym: storageSym,
                propSymbol: propSymbol, sema: sema, arena: arena,
                compilationCtx: compilationCtx, body: &body
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

    /// Checks whether the delegate type exposes a `provideDelegate` operator.
    private func checkProvideDelegate(
        delegateExpr: ExprID,
        sema: SemaModule,
        compilationCtx: CompilationContext
    ) -> Bool {
        let delegateExprType = sema.bindings.exprType(for: delegateExpr)
        let provideDelegateName = compilationCtx.interner.intern("provideDelegate")
        guard let delegateType = delegateExprType else { return false }
        let typeKind = sema.types.kind(of: delegateType)
        switch typeKind {
        case let .classType(classType):
            guard let sym = sema.symbols.symbol(classType.classSymbol) else { return false }
            let memberSymbols = sema.symbols.children(ofFQName: sym.fqName)
            return memberSymbols.contains { memberID in
                guard let member = sema.symbols.symbol(memberID) else { return false }
                return member.name == provideDelegateName
                    && member.kind == .function
            }
        default:
            return false
        }
    }

    // Wraps a delegate value in a provideDelegate call.
    // swiftlint:disable:next function_parameter_count
    private func emitProvideDelegateCall(
        delegateValue: KIRExprID,
        storageSym: SymbolID,
        propSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        compilationCtx: CompilationContext,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let delegateType = sema.types.anyType
        let tempFieldRef = arena.appendExpr(.symbolRef(storageSym), type: delegateType)
        body.append(.copy(from: delegateValue, to: tempFieldRef))
        let propertyName = sema.symbols.symbol(propSymbol)?.name
            ?? compilationCtx.interner.intern("")
        let thisRefExprID: KIRExprID
        if let receiver = ctx.currentImplicitReceiverExprID {
            thisRefExprID = receiver
        } else {
            let nullExpr = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: nullExpr, value: .null))
            thisRefExprID = nullExpr
        }
        let kPropertyExprID = arena.appendExpr(
            .stringLiteral(propertyName),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        body.append(.constValue(result: kPropertyExprID, value: .stringLiteral(propertyName)))
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
