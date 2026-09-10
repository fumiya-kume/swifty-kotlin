
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
            shared: shared,
            compilationCtx: compilationCtx
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
        if let companionSymbol = sema.symbols.companionObjectSymbol(for: symbol),
           sema.symbols.nominalLayout(for: companionSymbol)?.vtableSize ?? 0 > 0
        {
            let companionType = sema.types.make(.classType(ClassType(
                classSymbol: companionSymbol,
                args: [],
                nullability: .nonNull
            )))
            declIDs.append(arena.appendDecl(.global(KIRGlobal(
                symbol: companionSymbol,
                type: companionType
            ))))
        }
        declIDs.append(contentsOf: synthesizeCompanionInitializerIfNeeded(
            companionDeclID: classDecl.companionObject,
            ownerSymbol: symbol,
            shared: shared
        ))
        declIDs.append(contentsOf: synthesizeConstructorReflectionInitializer(
            classDecl: classDecl,
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

        // MemberLowerer has already emitted nested constructors recursively.
        // Add the reflection initializers and enum helpers here only once.
        lowerNestedClassConstructors(
            nestedClasses: classDecl.nestedClasses,
            shared: shared,
            compilationCtx: compilationCtx,
            declIDs: &declIDs
        )

        declIDs.append(contentsOf: synthesizeEnumConstructorPropertyHelperFunctions(
            classDecl: classDecl,
            ownerSymbol: symbol,
            shared: shared,
            compilationCtx: compilationCtx
        ))

        return declIDs
    }

    /// Adds reflection initializers and enum helpers for nested classes.
    private func lowerNestedClassConstructors(
        nestedClasses: [DeclID],
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        declIDs: inout [KIRDeclID]
    ) {
        let ast = shared.ast
        let sema = shared.sema
        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID),
                  let nestedSymbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            switch decl {
            case let .classDecl(nestedClass):
                declIDs.append(contentsOf: synthesizeConstructorReflectionInitializer(
                    classDecl: nestedClass,
                    ownerSymbol: nestedSymbol,
                    shared: shared
                ))
                // Recurse into further nested classes.
                lowerNestedClassConstructors(
                    nestedClasses: nestedClass.nestedClasses,
                    shared: shared,
                    compilationCtx: compilationCtx,
                    declIDs: &declIDs
                )

                declIDs.append(contentsOf: synthesizeEnumConstructorPropertyHelperFunctions(
                    classDecl: nestedClass,
                    ownerSymbol: nestedSymbol,
                    shared: shared,
                    compilationCtx: compilationCtx
                ))
            default:
                break
            }
        }
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
            ctx.setCurrentFunctionSymbol(forwardingSymbol)

            var params: [KIRParameter] = []
            if let receiverType = signature.receiverType {
                let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: forwardingSymbol)
                params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                ctx.setImplicitReceiver(
                    symbol: receiverSymbol,
                    exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                )
            }
            params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                KIRParameter(symbol: pair.0, type: pair.1)
            })

            var body: KIRLoweringEmitContext = [.beginBlock]
            if let receiverBinding = ctx.activeImplicitReceiver() {
                body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
            }

            let offset = shared.sema.symbols.nominalLayout(for: classSymbol)?.fieldOffsets[info.fieldSymbol] ?? 0
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: shared.sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))

            let delegateResultID = arena.appendTemporary(type: shared.sema.symbols.propertyType(for: info.fieldSymbol) ?? shared.sema.types.anyType
            )
            body.append(.call(
                symbol: nil,
                callee: compilationCtx.interner.intern("kk_array_get"),
                arguments: [ctx.activeImplicitReceiverExprID()!, offsetExpr],
                result: delegateResultID,
                canThrow: true,
                thrownResult: nil,
                isSuperCall: false
            ))

            var callArgExprs: [KIRExprID] = []
            for (paramSym, paramType) in zip(signature.valueParameterSymbols, signature.parameterTypes) {
                callArgExprs.append(arena.appendExpr(.symbolRef(paramSym), type: paramType))
            }

            let delegateTypeIDExpr = arena.appendTemporary(type: intType
            )
            emitNonThrowingCall(
                callee: compilationCtx.interner.intern("kk_object_type_id"),
                arg: delegateResultID,
                result: delegateTypeIDExpr,
                into: &body.instructions
            )

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
                let nullOutThrown = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                body.append(.constValue(result: nullOutThrown, value: .null))
                body.append(.call(
                    symbol: nil,
                    callee: compilationCtx.interner.intern("kk_abort_unreachable"),
                    arguments: [nullOutThrown],
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

        ctx.clearImplicitReceiver()
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

            queue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
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
        case .stringStruct, .classType, .functionType, .typeParam, .any, .intersection, .kClassType:
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
        ctorSymbol: SymbolID,
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
        if let receiver = ctx.activeImplicitReceiverExprID() {
            argIDs.append(receiver)
        }
        for arg in delegation.args {
            let lowered = lowerExpr(arg.expr, shared: shared, emit: &body)
            argIDs.append(lowered)
        }
        let delegationResultID = arena.appendTemporary(type: sema.types.unitType
        )
        // A class can have several constructors sharing the same `<init>` FQ
        // name, so a plain FQ-name lookup can't tell which overload the
        // delegation call means, and can even resolve back to the
        // constructor currently being lowered (infinite self-recursion).
        // Prefer the overload Sema already picked; only fall back to the
        // naive lookup (still excluding self) if that binding is missing.
        let resolvedSymbol = sema.bindings.constructorDelegationTarget(for: ctorSymbol)
            ?? sema.symbols.lookupAll(fqName: delegationTarget).first(where: { $0 != ctorSymbol })
        if let resolvedSymbol,
           sema.symbols.symbol(resolvedSymbol)?.flags.contains(.synthetic) == true,
           sema.symbols.parentSymbol(for: resolvedSymbol) == sema.types.anyClassSymbol
        {
            // Any's compiler-provided constructor is allocation-only.
            return
        }
        body.append(.call(
            symbol: resolvedSymbol,
            callee: compilationCtx.interner.intern("<init>"),
            arguments: argIDs,
            result: delegationResultID,
            canThrow: false,
            thrownResult: nil
        ))
    }

    /// BUG-205: Synthesizes per-enum-class, per-constructor-property helper
    /// functions (`$enumConstructorProperty$<classID>$<propertyName>`) that switch
    /// on the receiver's ordinal and return the corresponding constructor
    /// argument. Without these helpers, reading `s.code` on an enum class
    /// `Status(val code: Int)` is lowered as an unresolved zero-argument call.
    private func synthesizeEnumConstructorPropertyHelperFunctions(
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        guard let ownerInfo = sema.symbols.symbol(ownerSymbol),
              ownerInfo.kind == .enumClass,
              !classDecl.enumEntries.isEmpty
        else {
            return []
        }

        let anyType = sema.types.anyType
        let intType = sema.types.intType
        let nullableAnyType = sema.types.nullableAnyType
        var declIDs: [KIRDeclID] = []

        for (paramIndex, param) in classDecl.primaryConstructorParams.enumerated() where param.isProperty {
            let propertyName = param.name
            guard let propertySymbol = sema.symbols.lookupAll(fqName: ownerInfo.fqName + [propertyName])
                .first(where: { sema.symbols.symbol($0)?.kind == .property })
            else {
                continue
            }
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? anyType
            let helperName = interner.intern("$enumConstructorProperty$\(ownerSymbol.rawValue)$\(interner.resolve(propertyName))")
            let helperFQName = ownerInfo.fqName + [helperName]

            guard sema.symbols.lookupAll(fqName: helperFQName)
                .first(where: { sema.symbols.symbol($0)?.kind == .function }) == nil
            else {
                continue
            }

            let helperSymbol = sema.symbols.define(
                kind: .function,
                name: helperName,
                fqName: helperFQName,
                declSite: classDecl.range,
                visibility: .public,
                flags: [.synthetic, .static]
            )

            let receiverParamName = interner.intern("$receiver")
            let receiverParamSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: receiverParamName,
                fqName: helperFQName + [receiverParamName],
                declSite: classDecl.range,
                visibility: .private,
                flags: [.synthetic]
            )

            let signature = FunctionSignature(
                parameterTypes: [anyType],
                returnType: propertyType,
                isSuspend: false,
                canThrow: false,
                valueParameterSymbols: [receiverParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            )
            sema.symbols.setFunctionSignature(signature, for: helperSymbol)

            let helperBody = ctx.withNewScope { () -> [KIRInstruction] in
                ctx.setCurrentFunctionSymbol(helperSymbol)
                ctx.beginCallableLoweringScope()

                let receiverRef = arena.appendExpr(.symbolRef(receiverParamSymbol), type: anyType)
                var body: KIRLoweringEmitContext = [.beginBlock]
                body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParamSymbol)))

                let unboxedOrdinal = emitNonThrowingCall(
                    callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
                    arg: receiverRef,
                    resultType: intType,
                    arena: arena,
                    into: &body.instructions
                )

                for (ordinal, entry) in classDecl.enumEntries.enumerated() {
                    let ordinalExpr = arena.appendExpr(.intLiteral(Int64(ordinal)), type: intType)
                    body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))
                    let matchLabel = ctx.makeLoopLabel()
                    let nextLabel = ctx.makeLoopLabel()
                    body.append(.jumpIfEqual(lhs: unboxedOrdinal, rhs: ordinalExpr, target: matchLabel))
                    body.append(.jump(nextLabel))
                    body.append(.label(matchLabel))

                    let valueExpr: KIRExprID
                    if paramIndex < entry.constructorArgs.count {
                        valueExpr = lowerExpr(
                            entry.constructorArgs[paramIndex].expr,
                            shared: shared,
                            emit: &body
                        )
                    } else if paramIndex < classDecl.primaryConstructorParams.count,
                              let defaultExprID = classDecl.primaryConstructorParams[paramIndex].defaultValue
                    {
                        valueExpr = lowerExpr(
                            defaultExprID,
                            shared: shared,
                            emit: &body
                        )
                    } else {
                        let defaultValue = delegationDefaultValue(for: propertyType, sema: sema)
                        valueExpr = arena.appendExpr(defaultValue, type: propertyType)
                        body.append(.constValue(result: valueExpr, value: defaultValue))
                    }

                    body.append(.returnValue(valueExpr))
                    body.append(.label(nextLabel))
                }

                let nullOutThrown = arena.appendExpr(.null, type: nullableAnyType)
                body.append(.constValue(result: nullOutThrown, value: .null))
                let fallbackResult = arena.appendTemporary(type: propertyType)
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_abort_unreachable"),
                    arguments: [nullOutThrown],
                    result: fallbackResult,
                    canThrow: false,
                    thrownResult: nil,
                    isSuperCall: false
                ))
                body.append(.returnValue(fallbackResult))
                body.append(.endBlock)

                return body.instructions
            }

            let generatedDecls = ctx.drainGeneratedCallableDecls()
            let kirFunction = KIRFunction(
                symbol: helperSymbol,
                name: helperName,
                params: [KIRParameter(symbol: receiverParamSymbol, type: anyType)],
                returnType: propertyType,
                body: helperBody,
                isSuspend: false,
                isInline: false,
                sourceRange: nil
            )
            declIDs.append(arena.appendDecl(.function(kirFunction)))
            declIDs.append(contentsOf: generatedDecls)
        }

        return declIDs
    }
}
