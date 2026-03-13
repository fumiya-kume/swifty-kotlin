import Foundation

// MARK: - Pre-interned runtime names for delegate rewriting

private struct DelegateRuntimeNames {
    let getValueName: InternedString
    let setValueName: InternedString
    let lazyGetValue: InternedString
    let observableGetValue: InternedString
    let vetoableGetValue: InternedString
    let customGetValue: InternedString
    let notNullGetValue: InternedString
    let observableSetValue: InternedString
    let vetoableSetValue: InternedString
    let notNullSetValue: InternedString
    let customSetValue: InternedString

    init(interner: StringInterner) {
        getValueName = interner.intern("getValue")
        setValueName = interner.intern("setValue")
        lazyGetValue = interner.intern("kk_lazy_get_value")
        observableGetValue = interner.intern("kk_observable_get_value")
        vetoableGetValue = interner.intern("kk_vetoable_get_value")
        customGetValue = interner.intern("kk_custom_delegate_get_value")
        notNullGetValue = interner.intern("kk_notNull_get_value")
        observableSetValue = interner.intern("kk_observable_set_value")
        vetoableSetValue = interner.intern("kk_vetoable_set_value")
        notNullSetValue = interner.intern("kk_notNull_set_value")
        customSetValue = interner.intern("kk_custom_delegate_set_value")
    }
}

extension KIRLoweringDriver {
    func postProcessTopLevelInitializersAndDelegates(
        ast: ASTModule,
        sema: SemaModule,
        compilationCtx: CompilationContext,
        arena: KIRArena,
        allTopLevelInitInstructions: KIRLoweringEmitContext,
        delegateStorageSymbolByPropertySymbol: [SymbolID: SymbolID]
    ) {
        guard !allTopLevelInitInstructions.isEmpty || !delegateStorageSymbolByPropertySymbol.isEmpty else { return }

        let interner = compilationCtx.interner
        let mainName = interner.intern("main")

        let delegateKindByPropertySymbol = buildDelegateKindMap(ast: ast, sema: sema, interner: interner)
        let names = DelegateRuntimeNames(interner: interner)

        arena.transformFunctions { function in
            var updated = function

            if function.name == mainName, !allTopLevelInitInstructions.isEmpty {
                updated.replaceBody(injectTopLevelInits(
                    body: function.body, inits: allTopLevelInitInstructions
                ))
            }

            if !delegateStorageSymbolByPropertySymbol.isEmpty {
                updated.replaceBody(rewriteDelegateAccesses(
                    body: updated.body, arena: arena, sema: sema,
                    storageMap: delegateStorageSymbolByPropertySymbol,
                    kindMap: delegateKindByPropertySymbol, names: names, interner: interner
                ))
            }

            return updated
        }
    }

    // MARK: - Top-Level Init Injection

    private func injectTopLevelInits(
        body: [KIRInstruction],
        inits: KIRLoweringEmitContext
    ) -> [KIRInstruction] {
        var newBody: KIRLoweringEmitContext = []
        if let first = body.first, case .beginBlock = first {
            newBody.append(first)
            newBody.append(contentsOf: inits)
            newBody.append(contentsOf: body.dropFirst())
        } else {
            newBody.append(contentsOf: inits)
            newBody.append(contentsOf: body)
        }
        return newBody.instructions
    }

    // MARK: - Delegate Kind Map

    private func buildDelegateKindMap(
        ast: ASTModule, sema: SemaModule, interner: StringInterner
    ) -> [SymbolID: StdlibDelegateKind] {
        var map: [SymbolID: StdlibDelegateKind] = [:]

        func collect(from declID: DeclID) {
            guard let decl = ast.arena.decl(declID) else { return }
            switch decl {
            case let .propertyDecl(prop):
                guard let sym = sema.bindings.declSymbols[declID],
                      prop.delegateExpression != nil
                else { return }
                map[sym] = detectDelegateKind(
                    delegateExpr: prop.delegateExpression,
                    ast: ast,
                    interner: interner
                )
            case let .classDecl(classDecl):
                for memberProperty in classDecl.memberProperties {
                    collect(from: memberProperty)
                }
                for nestedClass in classDecl.nestedClasses {
                    collect(from: nestedClass)
                }
                for nestedObject in classDecl.nestedObjects {
                    collect(from: nestedObject)
                }
            case let .objectDecl(objectDecl):
                for memberProperty in objectDecl.memberProperties {
                    collect(from: memberProperty)
                }
                for nestedClass in objectDecl.nestedClasses {
                    collect(from: nestedClass)
                }
                for nestedObject in objectDecl.nestedObjects {
                    collect(from: nestedObject)
                }
            case let .interfaceDecl(interfaceDecl):
                for memberProperty in interfaceDecl.memberProperties {
                    collect(from: memberProperty)
                }
                for nestedClass in interfaceDecl.nestedClasses {
                    collect(from: nestedClass)
                }
                for nestedObject in interfaceDecl.nestedObjects {
                    collect(from: nestedObject)
                }
            default:
                return
            }
        }

        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                collect(from: declID)
            }
        }
        return map
    }

    // MARK: - Delegate Access Rewriting

    private func rewriteDelegateAccesses(
        body: [KIRInstruction],
        arena: KIRArena,
        sema: SemaModule,
        storageMap: [SymbolID: SymbolID],
        kindMap: [SymbolID: StdlibDelegateKind],
        names: DelegateRuntimeNames,
        interner: StringInterner
    ) -> [KIRInstruction] {
        var fullStorageMap = storageMap
        for symbol in sema.symbols.allSymbols() where symbol.kind == .property {
            if let storageSymbol = sema.symbols.delegateStorageSymbol(for: symbol.id) {
                fullStorageMap[symbol.id] = storageSymbol
            }
        }
        var propertyByStorageSymbol: [SymbolID: SymbolID] = [:]
        for (propertySymbol, storageSymbol) in fullStorageMap {
            propertyByStorageSymbol[storageSymbol] = propertySymbol
        }
        // Pass 1: collect copy targets to distinguish getter vs setter paths.
        var copyTargetExprs: Set<KIRExprID> = []
        for instruction in body {
            if case let .copy(_, toExpr) = instruction { copyTargetExprs.insert(toExpr) }
        }

        // Pass 2: rewrite instructions.
        var targets: [KIRExprID: SymbolID] = [:]
        var result: KIRLoweringEmitContext = []
        result.reserveCapacity(body.count)

        for instruction in body {
            if case let .call(symbol, callee, arguments, callResult, _, _, _) = instruction,
               let storageSymbol = symbol,
               let propertySymbol = propertyByStorageSymbol[storageSymbol],
               callee == names.getValueName || callee == names.setValueName
            {
                if kindMap[propertySymbol] == .custom {
                    result.append(instruction)
                    continue
                }
                if callee == names.getValueName {
                    emitGetValue(
                        result: callResult ?? arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType),
                        storageSym: storageSymbol,
                        propSym: propertySymbol,
                        originalArguments: arguments,
                        kindMap: kindMap,
                        names: names,
                        interner: interner,
                        arena: arena,
                        sema: sema,
                        body: &result
                    )
                } else {
                    let valueExpr = arguments.last ?? arena.appendExpr(.unit, type: sema.types.anyType)
                    emitSetValue(
                        fromExpr: valueExpr,
                        storageSym: storageSymbol,
                        propSym: propertySymbol,
                        originalArguments: arguments,
                        kind: kindMap[propertySymbol],
                        names: names,
                        interner: interner,
                        arena: arena,
                        sema: sema,
                        body: &result
                    )
                }
                continue
            }

            if case let .loadGlobal(res, sym) = instruction,
               let storageSym = fullStorageMap[sym]
            {
                if kindMap[sym] == .custom {
                    result.append(
                        .call(
                            symbol: SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym),
                            callee: interner.intern("get"),
                            arguments: [],
                            result: res,
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                    continue
                }
                emitGetValue(
                    result: res, storageSym: storageSym, propSym: sym,
                    originalArguments: [],
                    kindMap: kindMap, names: names,
                    interner: interner,
                    arena: arena, sema: sema, body: &result
                )
                continue
            }

            if case let .constValue(res, value) = instruction,
               case let .symbolRef(sym) = value,
               let storageSym = fullStorageMap[sym]
            {
                if kindMap[sym] == .custom {
                    if copyTargetExprs.contains(res) {
                        targets[res] = sym
                        result.append(instruction)
                    } else {
                        result.append(
                            .call(
                                symbol: SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym),
                                callee: interner.intern("get"),
                                arguments: [],
                                result: res,
                                canThrow: false,
                                thrownResult: nil
                            )
                        )
                    }
                    continue
                }
                if copyTargetExprs.contains(res) {
                    targets[res] = sym
                    result.append(instruction)
                } else {
                    emitGetValue(
                        result: res, storageSym: storageSym, propSym: sym,
                        originalArguments: [],
                        kindMap: kindMap, names: names,
                        interner: interner,
                        arena: arena, sema: sema, body: &result
                    )
                }
                continue
            }

            if case let .copy(fromExpr, toExpr) = instruction,
               let propSym = targets.removeValue(forKey: toExpr),
               let storageSym = fullStorageMap[propSym]
            {
                if kindMap[propSym] == .custom {
                    result.append(
                        .call(
                            symbol: SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propSym),
                            callee: interner.intern("set"),
                            arguments: [fromExpr],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                    continue
                }
                if kindMap[propSym] == .lazy {
                    result.append(instruction)
                    continue
                }
                emitSetValue(
                    fromExpr: fromExpr, storageSym: storageSym, propSym: propSym, originalArguments: [],
                    kind: kindMap[propSym],
                    names: names, interner: interner, arena: arena, sema: sema, body: &result
                )
                continue
            }

            result.append(instruction)
        }
        return result.instructions
    }

    private func emitGetValue(
        result: KIRExprID, storageSym: SymbolID, propSym: SymbolID,
        originalArguments: [KIRExprID],
        kindMap: [SymbolID: StdlibDelegateKind], names: DelegateRuntimeNames,
        interner: StringInterner,
        arena: KIRArena, sema: SemaModule, body: inout KIRLoweringEmitContext
    ) {
        let handle = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)), type: sema.types.anyType
        )
        body.append(.loadGlobal(result: handle, symbol: storageSym))
        let name: InternedString = switch kindMap[propSym] {
        case .lazy: names.lazyGetValue
        case .observable: names.observableGetValue
        case .vetoable: names.vetoableGetValue
        case .notNull: names.notNullGetValue
        case .custom, nil: names.customGetValue
        }
        let arguments: [KIRExprID] = if kindMap[propSym] == .custom || kindMap[propSym] == nil {
            customDelegateGetterArguments(
                handle: handle,
                propSym: propSym,
                originalArguments: originalArguments,
                arena: arena,
                sema: sema,
                interner: interner,
                body: &body
            )
        } else {
            [handle]
        }
        body.append(.call(
            symbol: nil,
            callee: name,
            arguments: arguments,
            result: result, canThrow: false, thrownResult: nil
        ))
    }

    private func emitSetValue(
        fromExpr: KIRExprID, storageSym: SymbolID, propSym: SymbolID, originalArguments: [KIRExprID], kind: StdlibDelegateKind?,
        names: DelegateRuntimeNames,
        interner: StringInterner,
        arena: KIRArena, sema: SemaModule, body: inout KIRLoweringEmitContext
    ) {
        let handle = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)), type: sema.types.anyType
        )
        body.append(.loadGlobal(result: handle, symbol: storageSym))
        let name: InternedString = switch kind {
        case .observable: names.observableSetValue
        case .vetoable: names.vetoableSetValue
        case .notNull: names.notNullSetValue
        case .custom, nil: names.customSetValue
        case .lazy: preconditionFailure("lazy delegate setValue is not supported")
        }
        let setResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)), type: sema.types.anyType
        )
        let arguments: [KIRExprID] = if kind == .custom || kind == nil {
            customDelegateSetterArguments(
                handle: handle,
                propSym: propSym,
                originalArguments: originalArguments,
                valueExpr: fromExpr,
                arena: arena,
                sema: sema,
                interner: interner,
                body: &body
            )
        } else {
            [handle, fromExpr]
        }
        body.append(.call(
            symbol: nil,
            callee: name,
            arguments: arguments,
            result: setResult, canThrow: false, thrownResult: nil
        ))
    }

    private func customDelegateGetterArguments(
        handle: KIRExprID,
        propSym: SymbolID,
        originalArguments: [KIRExprID],
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        if originalArguments.count >= 2 {
            return [handle, originalArguments[0], originalArguments[1]]
        }
        let thisRef = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        body.append(.constValue(result: thisRef, value: .null))
        let propertyStub = buildKPropertyStub(
            propSym: propSym,
            arena: arena,
            sema: sema,
            interner: interner,
            body: &body
        )
        return [handle, thisRef, propertyStub]
    }

    private func customDelegateSetterArguments(
        handle: KIRExprID,
        propSym: SymbolID,
        originalArguments: [KIRExprID],
        valueExpr: KIRExprID,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        if originalArguments.count >= 3 {
            return [handle, originalArguments[0], originalArguments[1], originalArguments[2]]
        }
        return customDelegateGetterArguments(
            handle: handle,
            propSym: propSym,
            originalArguments: originalArguments,
            arena: arena,
            sema: sema,
            interner: interner,
            body: &body
        ) + [valueExpr]
    }

    private func buildKPropertyStub(
        propSym: SymbolID,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let propertyName = sema.symbols.symbol(propSym)?.name ?? interner.intern("")
        let propertyNameExpr = arena.appendExpr(
            .stringLiteral(propertyName),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        body.append(.constValue(result: propertyNameExpr, value: .stringLiteral(propertyName)))
        let propertyType = sema.symbols.propertyType(for: propSym) ?? sema.types.anyType
        let typeName = interner.intern(sema.types.renderType(propertyType))
        let typeExpr = arena.appendExpr(
            .stringLiteral(typeName),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        body.append(.constValue(result: typeExpr, value: .stringLiteral(typeName)))
        let stubExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kproperty_stub_create"),
            arguments: [propertyNameExpr, typeExpr],
            result: stubExpr,
            canThrow: false,
            thrownResult: nil
        ))
        return stubExpr
    }
}

// MARK: - Delegate Lowering Helpers

extension KIRLoweringDriver {
    /// Detects the delegate kind from the delegate expression AST node.
    func detectDelegateKind(
        delegateExpr: ExprID?,
        ast: ASTModule,
        interner: StringInterner
    ) -> StdlibDelegateKind {
        guard let exprID = delegateExpr,
              let expr = ast.arena.expr(exprID) else { return .custom }
        let lazyID = interner.intern("lazy")
        let observableID = interner.intern("observable")
        let vetoableID = interner.intern("vetoable")
        let notNullID = interner.intern("notNull")
        switch expr {
        case let .nameRef(name, _):
            if name == lazyID { return .lazy }
            return .custom
        case let .call(callee, _, _, _):
            if let calleeExpr = ast.arena.expr(callee) {
                switch calleeExpr {
                case let .nameRef(name, _):
                    if name == observableID { return .observable }
                    if name == vetoableID { return .vetoable }
                    if name == notNullID { return .notNull }
                    if name == lazyID { return .lazy }
                default: break
                }
            }
            return detectDelegateKindFromCallExpr(callee: callee, ast: ast, interner: interner)
        case let .memberCall(_, callee, _, _, _):
            if callee == observableID { return .observable }
            if callee == vetoableID { return .vetoable }
            if callee == notNullID { return .notNull }
            return .custom
        default:
            return .custom
        }
    }

    private func detectDelegateKindFromCallExpr(
        callee: ExprID, ast: ASTModule, interner: StringInterner
    ) -> StdlibDelegateKind {
        guard let expr = ast.arena.expr(callee) else { return .custom }
        let observableID = interner.intern("observable")
        let vetoableID = interner.intern("vetoable")
        let notNullID = interner.intern("notNull")
        switch expr {
        case let .memberCall(_, name, _, _, _):
            if name == observableID { return .observable }
            if name == vetoableID { return .vetoable }
            if name == notNullID { return .notNull }
        case let .nameRef(name, _):
            if name == observableID { return .observable }
            if name == vetoableID { return .vetoable }
            if name == notNullID { return .notNull }
        default: break
        }
        return .custom
    }

    /// Creates a lambda function from the delegate body.
    func lowerDelegateLambdaBody(
        delegateBody: FunctionBody?,
        propertySymbol: SymbolID,
        paramCount: Int,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let lambdaSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let lambdaName = interner.intern("kk_delegate_lambda_\(propertySymbol.rawValue)")

        var params: [KIRParameter] = []
        for i in 0 ..< paramCount {
            let paramSymbol = SymbolID(
                rawValue: -(propertySymbol.rawValue + Int32(i + 1) * 1000 + 50000)
            )
            params.append(KIRParameter(symbol: paramSymbol, type: sema.types.anyType))
        }

        var lambdaBody: KIRLoweringEmitContext = [.beginBlock]
        for param in params {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            ctx.setLocalValue(paramExpr, for: param.symbol)
        }

        switch delegateBody {
        case let .block(exprIDs, _):
            var lastValue: KIRExprID?
            for exprID in exprIDs {
                lastValue = lowerExpr(exprID, shared: shared, emit: &lambdaBody)
            }
            if let lastValue {
                lambdaBody.append(.returnValue(lastValue))
            } else {
                lambdaBody.append(.returnUnit)
            }
        case let .expr(exprID, _):
            let value = lowerExpr(exprID, shared: shared, emit: &lambdaBody)
            lambdaBody.append(.returnValue(value))
        case .unit, nil:
            lambdaBody.append(.returnUnit)
        }
        lambdaBody.append(.endBlock)

        let lambdaDecl = arena.appendDecl(.function(KIRFunction(
            symbol: lambdaSymbol, name: lambdaName, params: params,
            returnType: sema.types.anyType, body: lambdaBody,
            isSuspend: false, isInline: false
        )))
        ctx.appendGeneratedCallableDecl(lambdaDecl)

        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: sema.types.anyType)
        instructions.append(.constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)))
        return lambdaRefExpr
    }

    /// Lowers the initial value argument from a delegate expression.
    func lowerDelegateInitialValue(
        delegateExpr: ExprID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        guard let exprID = delegateExpr,
              let expr = ast.arena.expr(exprID)
        else {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return zeroExpr
        }

        switch expr {
        case let .call(_, _, args, _):
            if let firstArg = args.first {
                return lowerExpr(firstArg.expr, shared: shared, emit: &instructions)
            }
        case let .memberCall(_, _, _, args, _):
            if let firstArg = args.first {
                return lowerExpr(firstArg.expr, shared: shared, emit: &instructions)
            }
        default: break
        }

        return lowerExpr(exprID, shared: shared, emit: &instructions)
    }
}
