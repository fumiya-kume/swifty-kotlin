import Foundation

extension KIRLoweringDriver {
    func lowerTopLevelClassDecl(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
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
        var finalDirectMembers = directMembers
        let forwardingDeclIDs = synthesizeClassDelegationForwardingMethods(
            classSymbol: symbol,
            shared: shared,
            compilationCtx: compilationCtx
        )
        finalDirectMembers.append(contentsOf: forwardingDeclIDs)
        let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: finalDirectMembers)))
        declIDs.append(kirID)
        declIDs.append(contentsOf: allDecls)
        declIDs.append(contentsOf: forwardingDeclIDs)
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
            declIDs.append(contentsOf: lowerConstructor(
                ctorSymbol: ctorSymbol,
                ctorFQName: ctorFQName,
                classDecl: classDecl,
                ownerSymbol: symbol,
                shared: shared,
                compilationCtx: compilationCtx
            ))
        }

        return declIDs
    }

    /// CLASS-008: Synthesize forwarding method bodies for delegated interface methods.
    private func synthesizeClassDelegationForwardingMethods(
        classSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        var declIDs: [KIRDeclID] = []

        for forwardingSymbol in sema.symbols.classDelegationForwardingMethodSymbols(forClass: classSymbol) {
            guard let info = sema.symbols.classDelegationForwardingMethodInfo(for: forwardingSymbol),
                  let signature = sema.symbols.functionSignature(for: forwardingSymbol),
                  let interfaceLayout = sema.symbols.nominalLayout(for: info.interfaceSymbol),
                  let methodSlot = interfaceLayout.vtableSlots[info.interfaceMethodSymbol],
                  let interfaceSlot = interfaceLayout.itableSlots[info.interfaceSymbol],
                  let interfaceMethodSym = sema.symbols.symbol(info.interfaceMethodSymbol)
            else {
                continue
            }
            let calleeName = interfaceMethodSym.name

            ctx.resetScopeForFunction()
            ctx.beginCallableLoweringScope()
            ctx.currentFunctionSymbol = forwardingSymbol

            var params: [KIRParameter] = []
            if let receiverType = signature.receiverType {
                let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: forwardingSymbol)
                params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                ctx.currentImplicitReceiverSymbol = receiverSymbol
                ctx.currentImplicitReceiverExprID = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            }
            params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                KIRParameter(symbol: pair.0, type: pair.1)
            })

            var body: KIRLoweringEmitContext = [.beginBlock]
            if let receiverExpr = ctx.currentImplicitReceiverExprID,
               let receiverSym = ctx.currentImplicitReceiverSymbol
            {
                body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSym)))
            }

            let offset = shared.sema.symbols.nominalLayout(for: classSymbol)?.fieldOffsets[info.fieldSymbol] ?? 0
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: shared.sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))

            let delegateResultID = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: shared.sema.symbols.propertyType(for: info.fieldSymbol) ?? shared.sema.types.anyType
            )
            let thrownResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: shared.sema.types.anyType)
            body.append(.call(
                symbol: nil,
                callee: compilationCtx.interner.intern("kk_array_get"),
                arguments: [ctx.currentImplicitReceiverExprID!, offsetExpr],
                result: delegateResultID,
                canThrow: true,
                thrownResult: thrownResult,
                isSuperCall: false
            ))

            var callArgExprs: [KIRExprID] = []
            for (paramSym, paramType) in zip(signature.valueParameterSymbols, signature.parameterTypes) {
                callArgExprs.append(arena.appendExpr(.symbolRef(paramSym), type: paramType))
            }

            let resultExprID = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: signature.returnType
            )
            body.append(.virtualCall(
                symbol: info.interfaceMethodSymbol,
                callee: calleeName,
                receiver: delegateResultID,
                arguments: callArgExprs,
                result: resultExprID,
                canThrow: false,
                thrownResult: nil,
                dispatch: .itable(interfaceSlot: interfaceSlot, methodSlot: methodSlot)
            ))

            if signature.returnType == sema.types.unitType {
                body.append(.returnUnit)
            } else {
                body.append(.returnValue(resultExprID))
            }
            body.append(.endBlock)

            let kirFunc = KIRFunction(
                symbol: forwardingSymbol,
                name: calleeName,
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: signature.isSuspend,
                isInline: false,
                isTailrec: false,
                sourceRange: nil
            )
            let funcDeclID = arena.appendDecl(.function(kirFunc))
            declIDs.append(funcDeclID)
        }

        ctx.currentImplicitReceiverExprID = nil
        ctx.currentImplicitReceiverSymbol = nil
        return declIDs
    }

    // Emits a constructor delegation call (`this(...)` or `super(...)`).
    // swiftlint:disable:next function_parameter_count
    func emitDelegationCall(
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
                let superFQ = sema.symbols.symbol(superclass)?.fqName ?? []
                delegationTarget = superFQ + [compilationCtx.interner.intern("<init>")]
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
