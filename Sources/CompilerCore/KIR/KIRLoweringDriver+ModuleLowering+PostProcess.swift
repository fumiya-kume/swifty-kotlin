import Foundation

// MARK: - Pre-interned runtime names for delegate rewriting

private struct DelegateRuntimeNames {
    let lazyGetValue: InternedString
    let observableGetValue: InternedString
    let vetoableGetValue: InternedString
    let customGetValue: InternedString
    let observableSetValue: InternedString
    let vetoableSetValue: InternedString
    let customSetValue: InternedString

    init(interner: StringInterner) {
        lazyGetValue = interner.intern("kk_lazy_get_value")
        observableGetValue = interner.intern("kk_observable_get_value")
        vetoableGetValue = interner.intern("kk_vetoable_get_value")
        customGetValue = interner.intern("kk_custom_delegate_get_value")
        observableSetValue = interner.intern("kk_observable_set_value")
        vetoableSetValue = interner.intern("kk_vetoable_set_value")
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
                updated.body = injectTopLevelInits(
                    body: function.body, inits: allTopLevelInitInstructions
                )
            }

            if !delegateStorageSymbolByPropertySymbol.isEmpty {
                updated.body = rewriteDelegateAccesses(
                    body: updated.body, arena: arena, sema: sema,
                    storageMap: delegateStorageSymbolByPropertySymbol,
                    kindMap: delegateKindByPropertySymbol, names: names
                )
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
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .propertyDecl(prop) = decl,
                      let sym = sema.bindings.declSymbols[declID],
                      prop.delegateExpression != nil else { continue }
                map[sym] = detectDelegateKind(
                    delegateExpr: prop.delegateExpression, ast: ast, interner: interner
                )
            }
        }
        return map
    }

    // MARK: - Delegate Access Rewriting

    // swiftlint:disable:next function_body_length
    private func rewriteDelegateAccesses(
        body: [KIRInstruction],
        arena: KIRArena,
        sema: SemaModule,
        storageMap: [SymbolID: SymbolID],
        kindMap: [SymbolID: StdlibDelegateKind],
        names: DelegateRuntimeNames
    ) -> [KIRInstruction] {
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
            if case let .loadGlobal(res, sym) = instruction,
               let storageSym = storageMap[sym] {
                emitGetValue(
                    result: res, storageSym: storageSym, propSym: sym,
                    kindMap: kindMap, names: names,
                    arena: arena, sema: sema, body: &result
                )
                continue
            }

            if case let .constValue(res, value) = instruction,
               case let .symbolRef(sym) = value,
               let storageSym = storageMap[sym] {
                if copyTargetExprs.contains(res) {
                    targets[res] = sym
                    result.append(instruction)
                } else {
                    emitGetValue(
                        result: res, storageSym: storageSym, propSym: sym,
                        kindMap: kindMap, names: names,
                        arena: arena, sema: sema, body: &result
                    )
                }
                continue
            }

            if case let .copy(fromExpr, toExpr) = instruction,
               let propSym = targets.removeValue(forKey: toExpr),
               let storageSym = storageMap[propSym] {
                if kindMap[propSym] == .lazy {
                    result.append(instruction)
                    continue
                }
                emitSetValue(
                    fromExpr: fromExpr, storageSym: storageSym, kind: kindMap[propSym],
                    names: names, arena: arena, sema: sema, body: &result
                )
                continue
            }

            result.append(instruction)
        }
        return result.instructions
    }

    private func emitGetValue(
        result: KIRExprID, storageSym: SymbolID, propSym: SymbolID,
        kindMap: [SymbolID: StdlibDelegateKind], names: DelegateRuntimeNames,
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
        case .custom, nil: names.customGetValue
        }
        body.append(.call(
            symbol: nil, callee: name, arguments: [handle],
            result: result, canThrow: false, thrownResult: nil
        ))
    }

    private func emitSetValue(
        fromExpr: KIRExprID, storageSym: SymbolID, kind: StdlibDelegateKind?,
        names: DelegateRuntimeNames,
        arena: KIRArena, sema: SemaModule, body: inout KIRLoweringEmitContext
    ) {
        let handle = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)), type: sema.types.anyType
        )
        body.append(.loadGlobal(result: handle, symbol: storageSym))
        let name: InternedString = switch kind {
        case .observable: names.observableSetValue
        case .vetoable: names.vetoableSetValue
        case .custom, nil: names.customSetValue
        case .lazy: preconditionFailure("lazy delegate setValue is not supported")
        }
        let setResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)), type: sema.types.anyType
        )
        body.append(.call(
            symbol: nil, callee: name, arguments: [handle, fromExpr],
            result: setResult, canThrow: false, thrownResult: nil
        ))
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
                    if name == lazyID { return .lazy }
                default: break
                }
            }
            return detectDelegateKindFromCallExpr(callee: callee, ast: ast, interner: interner)
        case let .memberCall(_, callee, _, _, _):
            if callee == observableID { return .observable }
            if callee == vetoableID { return .vetoable }
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
        switch expr {
        case let .memberCall(_, name, _, _, _):
            if name == observableID { return .observable }
            if name == vetoableID { return .vetoable }
        case let .nameRef(name, _):
            if name == observableID { return .observable }
            if name == vetoableID { return .vetoable }
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
            ctx.localValuesBySymbol[param.symbol] = paramExpr
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
        ctx.pendingGeneratedCallableDeclIDs.append(lambdaDecl)

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
              let expr = ast.arena.expr(exprID) else {
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
