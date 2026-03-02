import Foundation

// MARK: - Declaration-order class body initializer emission (CLASS-007)

extension KIRLoweringDriver {
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
    // swiftlint:disable:next function_body_length cyclomatic_complexity
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

    /// Emits the body of a secondary constructor, including delegation
    /// call and body statements.
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

    /// Emits a constructor delegation call (`this(...)` or `super(...)`).
    // swiftlint:disable:next function_parameter_count
    private func emitDelegationCall(
        delegation: ConstructorDelegationCall,
        ctorFQName: [InternedString],
        ownerSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        compilationCtx: CompilationContext,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let delegationTarget: [InternedString]
        switch delegation.kind {
        case .this:
            delegationTarget = ctorFQName
        case .super_:
            let supertypes = sema.symbols.directSupertypes(for: ownerSymbol)
            let classSupertypes = supertypes.filter {
                let kind = sema.symbols.symbol($0)?.kind
                return kind == .class || kind == .enumClass
            }
            if let superclass = classSupertypes.first {
                delegationTarget = (sema.symbols.symbol(superclass)?.fqName ?? []) + [compilationCtx.interner.intern("<init>")]
            } else {
                delegationTarget = []
            }
        }
        guard !delegationTarget.isEmpty else { return }
        var argIDs: [KIRExprID] = []
        if let receiver = ctx.currentImplicitReceiverExprID {
            argIDs.append(receiver)
        }
        for arg in delegation.args {
            let lowered = lowerExpr(arg.expr, shared: shared, emit: &body)
            argIDs.append(lowered)
        }
        let delegationResultID = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: sema.types.unitType
        )
        body.append(.call(
            symbol: sema.symbols.lookupAll(fqName: delegationTarget).first,
            callee: compilationCtx.interner.intern("<init>"),
            arguments: argIDs,
            result: delegationResultID,
            canThrow: false,
            thrownResult: nil
        ))
    }

    /// Emits a delegated property initializer, handling `provideDelegate`
    /// when available on the delegate type.
    // swiftlint:disable:next function_body_length function_parameter_count
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
        let delegateValue = lowerExpr(
            delegateExpr,
            shared: shared, emit: &body
        )

        let delegateExprType = sema.bindings.exprType(for: delegateExpr)
        let provideDelegateName = compilationCtx.interner.intern("provideDelegate")
        let hasProvideDelegate: Bool = {
            guard let delegateType = delegateExprType else { return false }
            let typeKind = sema.types.kind(of: delegateType)
            switch typeKind {
            case let .classType(ct):
                guard let sym = sema.symbols.symbol(ct.classSymbol) else { return false }
                let memberSymbols = sema.symbols.children(ofFQName: sym.fqName)
                return memberSymbols.contains { memberID in
                    guard let member = sema.symbols.symbol(memberID) else { return false }
                    return member.name == provideDelegateName
                        && member.kind == .function
                }
            default:
                return false
            }
        }()

        let valueToStore: KIRExprID
        if hasProvideDelegate, let storageSym = delegateStorageSym {
            let delegateType = sema.types.anyType
            let tempFieldRef = arena.appendExpr(.symbolRef(storageSym), type: delegateType)
            body.append(.copy(from: delegateValue, to: tempFieldRef))

            let propertyName = sema.symbols.symbol(propSymbol)?.name ?? compilationCtx.interner.intern("")
            let thisRefExprID: KIRExprID
            if let receiver = ctx.currentImplicitReceiverExprID {
                thisRefExprID = receiver
            } else {
                thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                body.append(.constValue(result: thisRefExprID, value: .null))
            }
            let kPropertyExprID = arena.appendExpr(
                .stringLiteral(propertyName),
                type: sema.types.make(.primitive(.string, .nonNull))
            )
            body.append(.constValue(result: kPropertyExprID, value: .stringLiteral(propertyName)))
            let provideDelegateResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.anyType
            )
            body.append(
                .call(
                    symbol: storageSym,
                    callee: provideDelegateName,
                    arguments: [thisRefExprID, kPropertyExprID],
                    result: provideDelegateResult,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            valueToStore = provideDelegateResult
        } else {
            valueToStore = delegateValue
        }

        if let storageSym = delegateStorageSym {
            let delegateType = sema.types.anyType
            let fieldRef = arena.appendExpr(.symbolRef(storageSym), type: delegateType)
            body.append(.copy(from: valueToStore, to: fieldRef))
        }
    }
}
