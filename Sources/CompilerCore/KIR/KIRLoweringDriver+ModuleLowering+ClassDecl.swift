import Foundation

extension KIRLoweringDriver {
    func lowerTopLevelClassDecl(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena

        var declIDs: [KIRDeclID] = []
        // Collect nested objects including the companion object
        var allNestedObjects = classDecl.nestedObjects
        if let companionDeclID = classDecl.companionObject {
            allNestedObjects.append(companionDeclID)
        }
        let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            shared: shared
        )
        let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
        declIDs.append(kirID)
        declIDs.append(contentsOf: allDecls)
        declIDs.append(contentsOf: synthesizeCompanionInitializerIfNeeded(
            companionDeclID: classDecl.companionObject,
            ownerSymbol: symbol,
            shared: shared
        ))

        let ctorFQName = (sema.symbols.symbol(symbol)?.fqName ?? []) + [compilationCtx.interner.intern("<init>")]
        let ctorSymbols = sema.symbols.lookupAll(
            fqName: ctorFQName
        )
        for ctorSymbol in ctorSymbols {
            guard let signature = sema.symbols.functionSignature(for: ctorSymbol) else {
                continue
            }
            ctx.resetScopeForFunction()
            ctx.beginCallableLoweringScope()

            let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: ctorSymbol)
            var params = [KIRParameter(symbol: receiverSymbol, type: signature.returnType)]
            ctx.currentImplicitReceiverSymbol = receiverSymbol
            ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: signature.returnType)

            params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                KIRParameter(symbol: pair.0, type: pair.1)
            })
            let returnType = signature.returnType
            var body: KIRLoweringEmitContext = [.beginBlock]

            if let receiverExpr = ctx.currentImplicitReceiverExprID,
               let receiverSym = ctx.currentImplicitReceiverSymbol
            {
                body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSym)))
            }

            let isSecondary = sema.symbols.symbol(ctorSymbol)?.declSite != classDecl.range

            if !isSecondary {
                // Emit member property initializers as field stores.
                for propDeclID in classDecl.memberProperties {
                    guard let propDecl = ast.arena.decl(propDeclID),
                          case let .propertyDecl(prop) = propDecl,
                          let propSymbol = sema.bindings.declSymbols[propDeclID]
                    else {
                        continue
                    }

                    // Handle delegated property initialisation:
                    // lower the delegate expression and store it in
                    // the $delegate_ storage field.  If the delegate
                    // type exposes a `provideDelegate` operator, wrap
                    // the initial value in a provideDelegate call;
                    // otherwise store the delegate value directly.
                    if let delegateExpr = prop.delegateExpression {
                        let delegateStorageSym = sema.symbols.delegateStorageSymbol(for: propSymbol)
                        let delegateValue = lowerExpr(
                            delegateExpr,
                            shared: shared, emit: &body
                        )

                        // Check whether the delegate type defines a
                        // provideDelegate operator.  Only emit the call
                        // when it is actually available; otherwise store
                        // the raw delegate value directly.
                        let delegateExprType = sema.bindings.exprType(for: delegateExpr)
                        let provideDelegateName = compilationCtx.interner.intern("provideDelegate")
                        let hasProvideDelegate: Bool = {
                            guard let delegateType = delegateExprType else { return false }
                            // Look up provideDelegate on the delegate's nominal type.
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
                            // First, store the raw delegate value so we
                            // have a receiver for the method call.
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
                            let kPropertyExprID = emitKPropertyStubCreate(
                                propertyName: propertyName,
                                propertyType: sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType,
                                shared: shared, emit: &body
                            )
                            let provideDelegateResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)),
                                type: sema.types.anyType
                            )
                            // Emit as method call on the delegate storage
                            // (2 args: thisRef, kProperty) matching Kotlin's
                            // delegate.provideDelegate(thisRef, property).
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
                            // No provideDelegate — store the delegate
                            // expression value directly.
                            valueToStore = delegateValue
                        }

                        if let storageSym = delegateStorageSym {
                            let delegateType = sema.types.anyType
                            let fieldRef = arena.appendExpr(.symbolRef(storageSym), type: delegateType)
                            body.append(.copy(from: valueToStore, to: fieldRef))
                        }
                        continue
                    }

                    guard let initExpr = prop.initializer else {
                        continue
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

                for initBlock in classDecl.initBlocks {
                    switch initBlock {
                    case let .block(exprIDs, _):
                        for exprID in exprIDs {
                            _ = lowerExpr(
                                exprID,
                                shared: shared, emit: &body
                            )
                        }
                    case let .expr(exprID, _):
                        _ = lowerExpr(
                            exprID,
                            shared: shared, emit: &body
                        )
                    case .unit:
                        break
                    }
                }
            }

            if isSecondary {
                for secondaryCtor in classDecl.secondaryConstructors {
                    guard secondaryCtor.range == sema.symbols.symbol(ctorSymbol)?.declSite else {
                        continue
                    }
                    if let delegation = secondaryCtor.delegationCall {
                        let delegationTarget: [InternedString]
                        switch delegation.kind {
                        case .this:
                            delegationTarget = ctorFQName
                        case .super_:
                            let supertypes = sema.symbols.directSupertypes(for: symbol)
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
                        if !delegationTarget.isEmpty {
                            var argIDs: [KIRExprID] = []
                            if let receiver = ctx.currentImplicitReceiverExprID {
                                argIDs.append(receiver)
                            }
                            for arg in delegation.args {
                                let lowered = lowerExpr(
                                    arg.expr,
                                    shared: shared, emit: &body
                                )
                                argIDs.append(lowered)
                            }
                            let delegationResultID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.unitType)
                            body.append(.call(
                                symbol: sema.symbols.lookupAll(fqName: delegationTarget).first,
                                callee: compilationCtx.interner.intern("<init>"),
                                arguments: argIDs,
                                result: delegationResultID,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                    }
                    switch secondaryCtor.body {
                    case let .block(exprIDs, _):
                        for exprID in exprIDs {
                            _ = lowerExpr(
                                exprID,
                                shared: shared, emit: &body
                            )
                        }
                    case let .expr(exprID, _):
                        _ = lowerExpr(
                            exprID,
                            shared: shared, emit: &body
                        )
                    case .unit:
                        break
                    }
                    break
                }
            }

            if let receiver = ctx.currentImplicitReceiverExprID {
                body.append(.returnValue(receiver))
            } else {
                body.append(.returnUnit)
            }
            body.append(.endBlock)

            let ctorKirID = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: ctorSymbol,
                        name: classDecl.name,
                        params: params,
                        returnType: returnType,
                        body: body,
                        isSuspend: false,
                        isInline: false
                    )
                )
            )
            declIDs.append(ctorKirID)
            // Generate default argument stub for constructors with defaults.
            if let defaults = ctx.functionDefaultArgumentsBySymbol[ctorSymbol] {
                let stubID = callSupportLowerer.generateDefaultStubFunction(
                    originalSymbol: ctorSymbol,
                    originalName: classDecl.name,
                    signature: signature,
                    defaultExpressions: defaults,
                    shared: shared
                )
                declIDs.append(stubID)
            }
            declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        }

        return declIDs
    }

    func synthesizeCompanionInitializerIfNeeded(
        companionDeclID: DeclID?,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        guard let companionDeclID,
              let decl = shared.ast.arena.decl(companionDeclID),
              case let .objectDecl(companionDecl) = decl,
              let companionSymbol = shared.sema.bindings.declSymbols[companionDeclID]
        else {
            return []
        }

        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern("__companion_init_\(ownerSymbol.rawValue)_\(companionSymbol.rawValue)")

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()

        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let companionReceiverExpr = arena.appendExpr(.symbolRef(companionSymbol), type: companionType)
        ctx.currentImplicitReceiverSymbol = companionSymbol
        ctx.currentImplicitReceiverExprID = companionReceiverExpr

        var body: KIRLoweringEmitContext = [.beginBlock]
        body.append(.constValue(result: companionReceiverExpr, value: .symbolRef(companionSymbol)))

        // Property initializers run before init blocks, in declaration order.
        for propertyDeclID in companionDecl.memberProperties {
            guard let propertyDecl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(property) = propertyDecl,
                  let propertySymbol = sema.bindings.declSymbols[propertyDeclID]
            else {
                continue
            }
            // Delegate-specific initialization is handled separately.
            if property.delegateExpression != nil {
                continue
            }
            guard let initializer = property.initializer else {
                continue
            }
            let initializerValue = lowerExpr(
                initializer,
                shared: shared,
                emit: &body
            )
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            let propertyType = sema.symbols.propertyType(for: targetSymbol) ?? sema.types.anyType
            let targetRef = arena.appendExpr(.symbolRef(targetSymbol), type: propertyType)
            body.append(.constValue(result: targetRef, value: .symbolRef(targetSymbol)))
            body.append(.copy(from: initializerValue, to: targetRef))
        }

        for initBlock in companionDecl.initBlocks {
            switch initBlock {
            case let .block(exprIDs, _):
                for exprID in exprIDs {
                    _ = lowerExpr(
                        exprID,
                        shared: shared,
                        emit: &body
                    )
                }
            case let .expr(exprID, _):
                _ = lowerExpr(
                    exprID,
                    shared: shared,
                    emit: &body
                )
            case .unit:
                break
            }
        }

        body.append(.returnUnit)
        body.append(.endBlock)

        let initDeclID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: initializerSymbol,
                    name: initializerName,
                    params: [],
                    returnType: sema.types.unitType,
                    body: body,
                    isSuspend: false,
                    isInline: false,
                    sourceRange: companionDecl.range
                )
            )
        )
        ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)

        var declIDs: [KIRDeclID] = [initDeclID]
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.currentImplicitReceiverExprID = nil
        ctx.currentImplicitReceiverSymbol = nil
        return declIDs
    }
}
