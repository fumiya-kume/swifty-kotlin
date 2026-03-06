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
        let intType = sema.types.intType

        for forwardingSymbol in sema.symbols.classDelegationForwardingMethodSymbols(forClass: classSymbol) {
            guard let info = sema.symbols.classDelegationForwardingMethodInfo(for: forwardingSymbol),
                  let signature = sema.symbols.functionSignature(for: forwardingSymbol),
                  let interfaceMethodSym = sema.symbols.symbol(info.interfaceMethodSymbol)
            else {
                continue
            }
            let calleeName = interfaceMethodSym.name
            let dispatchTargets = classDelegationDispatchTargets(
                interfaceSymbol: info.interfaceSymbol,
                interfaceMethodSymbol: info.interfaceMethodSymbol,
                sema: sema,
                interner: compilationCtx.interner
            )
            let fallbackMethodSymbol = classDelegationDefaultMethodSymbol(
                interfaceMethodSymbol: info.interfaceMethodSymbol,
                sema: sema
            )
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
            body.append(.call(
                symbol: nil,
                callee: compilationCtx.interner.intern("kk_array_get"),
                arguments: [ctx.currentImplicitReceiverExprID!, offsetExpr],
                result: delegateResultID,
                canThrow: true,
                thrownResult: nil,
                isSuperCall: false
            ))

            var callArgExprs: [KIRExprID] = []
            for (paramSym, paramType) in zip(signature.valueParameterSymbols, signature.parameterTypes) {
                callArgExprs.append(arena.appendExpr(.symbolRef(paramSym), type: paramType))
            }

            let delegateTypeIDExpr = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: intType
            )
            body.append(.call(
                symbol: nil,
                callee: compilationCtx.interner.intern("kk_object_type_id"),
                arguments: [delegateResultID],
                result: delegateTypeIDExpr,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: false
            ))

            let branchLabels = dispatchTargets.map { _ in ctx.makeLoopLabel() }
            let fallbackLabel = ctx.makeLoopLabel()
            let endLabel = ctx.makeLoopLabel()
            var resultExprID: KIRExprID?
            if signature.returnType != sema.types.unitType {
                let resultExpr = arena.appendExpr(
                    delegationDefaultValue(for: signature.returnType, sema: sema),
                    type: signature.returnType
                )
                resultExprID = resultExpr
            }

            for (target, label) in zip(dispatchTargets, branchLabels) {
                let typeIDExpr = arena.appendExpr(.intLiteral(target.typeID), type: intType)
                body.append(.constValue(result: typeIDExpr, value: .intLiteral(target.typeID)))
                body.append(.jumpIfEqual(lhs: delegateTypeIDExpr, rhs: typeIDExpr, target: label))
            }
            body.append(.jump(fallbackLabel))

            for (target, label) in zip(dispatchTargets, branchLabels) {
                body.append(.label(label))
                let targetCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: target.methodSymbol),
                                                          !externalLinkName.isEmpty
                {
                    compilationCtx.interner.intern(externalLinkName)
                } else {
                    sema.symbols.symbol(target.methodSymbol)?.name ?? calleeName
                }
                body.append(.call(
                    symbol: target.methodSymbol,
                    callee: targetCalleeName,
                    arguments: [delegateResultID] + callArgExprs,
                    result: resultExprID,
                    canThrow: false,
                    thrownResult: nil,
                    isSuperCall: false
                ))
                body.append(.jump(endLabel))
            }

            body.append(.label(fallbackLabel))
            if let fallbackMethodSymbol {
                let fallbackCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: fallbackMethodSymbol),
                                                            !externalLinkName.isEmpty
                {
                    compilationCtx.interner.intern(externalLinkName)
                } else {
                    sema.symbols.symbol(fallbackMethodSymbol)?.name ?? calleeName
                }
                body.append(.call(
                    symbol: fallbackMethodSymbol,
                    callee: fallbackCalleeName,
                    arguments: [delegateResultID] + callArgExprs,
                    result: resultExprID,
                    canThrow: false,
                    thrownResult: nil,
                    isSuperCall: false
                ))
            } else {
                body.append(.call(
                    symbol: nil,
                    callee: compilationCtx.interner.intern("abort"),
                    arguments: [],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil,
                    isSuperCall: false
                ))
            }
            body.append(.jump(endLabel))
            body.append(.label(endLabel))

            if let resultExprID {
                body.append(.returnValue(resultExprID))
            } else {
                body.append(.returnUnit)
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
                sourceRange: nil
            )
            let funcDeclID = arena.appendDecl(.function(kirFunc))
            declIDs.append(funcDeclID)
        }

        ctx.currentImplicitReceiverExprID = nil
        ctx.currentImplicitReceiverSymbol = nil
        return declIDs
    }

    private struct ClassDelegationDispatchTarget {
        let typeID: Int64
        let methodSymbol: SymbolID
    }

    private func classDelegationDispatchTargets(
        interfaceSymbol: SymbolID,
        interfaceMethodSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [ClassDelegationDispatchTarget] {
        var targets: [ClassDelegationDispatchTarget] = []
        var queue = sema.symbols.directSubtypes(of: interfaceSymbol)
        var visited: Set<SymbolID> = []

        while !queue.isEmpty {
            let candidate = queue.removeFirst()
            guard visited.insert(candidate).inserted,
                  let candidateSymbol = sema.symbols.symbol(candidate)
            else {
                continue
            }
            queue.append(contentsOf: sema.symbols.directSubtypes(of: candidate))

            guard candidateSymbol.kind == .class || candidateSymbol.kind == .object || candidateSymbol.kind == .enumClass,
                  !candidateSymbol.flags.contains(.abstractType),
                  let methodSymbol = resolveClassDelegationDispatchMethod(
                      interfaceMethodSymbol: interfaceMethodSymbol,
                      concreteTypeSymbol: candidate,
                      sema: sema
                  )
            else {
                continue
            }

            targets.append(ClassDelegationDispatchTarget(
                typeID: RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: candidate,
                    sema: sema,
                    interner: interner
                ),
                methodSymbol: methodSymbol
            ))
        }

        return targets.sorted { lhs, rhs in
            lhs.typeID < rhs.typeID
        }
    }

    private func resolveClassDelegationDispatchMethod(
        interfaceMethodSymbol: SymbolID,
        concreteTypeSymbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        guard let interfaceMethod = sema.symbols.symbol(interfaceMethodSymbol),
              let interfaceSignature = sema.symbols.functionSignature(for: interfaceMethodSymbol)
        else {
            return nil
        }

        var fallbackMatch: SymbolID?
        var queue: [SymbolID] = [concreteTypeSymbol]
        var visited: Set<SymbolID> = []
        while !queue.isEmpty {
            let owner = queue.removeFirst()
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }

            let fqName = ownerSymbol.fqName + [interfaceMethod.name]
            for candidate in sema.symbols.lookupAll(fqName: fqName) {
                guard sema.symbols.parentSymbol(for: candidate) == owner,
                      let methodSymbol = sema.symbols.symbol(candidate),
                      !methodSymbol.flags.contains(.synthetic),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.receiverType != nil,
                      signature.parameterTypes == interfaceSignature.parameterTypes,
                      signature.isSuspend == interfaceSignature.isSuspend
                else {
                    continue
                }

                if methodSymbol.flags.contains(.overrideMember) {
                    return candidate
                }
                if fallbackMatch == nil {
                    fallbackMatch = candidate
                }
            }

            queue.append(contentsOf: sema.symbols.directSupertypes(for: owner).filter { supertype in
                guard let symbol = sema.symbols.symbol(supertype) else {
                    return false
                }
                return symbol.kind == .class || symbol.kind == .object || symbol.kind == .enumClass
            })
        }

        if let fallbackMatch {
            return fallbackMatch
        }
        return classDelegationDefaultMethodSymbol(interfaceMethodSymbol: interfaceMethodSymbol, sema: sema)
    }

    private func classDelegationDefaultMethodSymbol(
        interfaceMethodSymbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        guard let interfaceMethod = sema.symbols.symbol(interfaceMethodSymbol),
              !interfaceMethod.flags.contains(.abstractType)
        else {
            return nil
        }
        return interfaceMethodSymbol
    }

    private func delegationDefaultValue(for type: TypeID, sema: SemaModule) -> KIRExprKind {
        switch sema.types.kind(of: type) {
        case .unit:
            .unit
        case .primitive(.boolean, _):
            .boolLiteral(false)
        case .primitive(.float, _):
            .floatLiteral(0)
        case .primitive(.double, _):
            .doubleLiteral(0)
        case .primitive, .nothing:
            .intLiteral(0)
        case .classType, .functionType, .typeParam, .any, .intersection:
            .null
        case .error:
            .intLiteral(0)
        }
    }

    /// Emits a constructor delegation call (`this(...)` or `super(...)`).
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
