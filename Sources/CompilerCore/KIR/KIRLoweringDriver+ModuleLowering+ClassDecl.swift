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
                // Emit member property initializers and init blocks in
                // declaration order (top-to-bottom), matching Kotlin's
                // guaranteed initialization order (spec.md J7 / CLASS-007).
                emitClassBodyInitializers(
                    classDecl: classDecl,
                    shared: shared,
                    compilationCtx: compilationCtx,
                    body: &body
                )
            }

            if isSecondary {
                emitSecondaryConstructorBody(
                    classDecl: classDecl,
                    ctorSymbol: ctorSymbol,
                    ctorFQName: ctorFQName,
                    ownerSymbol: symbol,
                    shared: shared,
                    compilationCtx: compilationCtx,
                    body: &body
                )
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
