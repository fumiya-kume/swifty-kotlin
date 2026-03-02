import Foundation

extension KIRLoweringDriver {
    func postProcessTopLevelInitializersAndDelegates(
        ast: ASTModule,
        sema: SemaModule,
        compilationCtx: CompilationContext,
        arena: KIRArena,
        allTopLevelInitInstructions: KIRLoweringEmitContext,
        delegateStorageSymbolByPropertySymbol: [SymbolID: SymbolID]
    ) {
        if !allTopLevelInitInstructions.isEmpty || !delegateStorageSymbolByPropertySymbol.isEmpty {
            let interner = compilationCtx.interner
            let mainName = interner.intern("main")
            let lazyGetValueName = interner.intern("kk_lazy_get_value")
            let observableGetValueName = interner.intern("kk_observable_get_value")
            let vetoableGetValueName = interner.intern("kk_vetoable_get_value")
            let customGetValueName = interner.intern("kk_custom_delegate_get_value")
            let observableSetValueName = interner.intern("kk_observable_set_value")
            let vetoableSetValueName = interner.intern("kk_vetoable_set_value")
            let customSetValueName = interner.intern("kk_custom_delegate_set_value")

            // Build a reverse lookup: property symbol → delegate kind for getValue rewriting.
            var delegateKindByPropertySymbol: [SymbolID: StdlibDelegateKind] = [:]
            for file in ast.sortedFiles {
                for declID in file.topLevelDecls {
                    guard let decl = ast.arena.decl(declID),
                          case let .propertyDecl(prop) = decl,
                          let sym = sema.bindings.declSymbols[declID],
                          prop.delegateExpression != nil
                    else {
                        continue
                    }
                    delegateKindByPropertySymbol[sym] = detectDelegateKind(
                        delegateExpr: prop.delegateExpression,
                        ast: ast,
                        interner: interner
                    )
                }
            }

            arena.transformFunctions { function in
                var updated = function
                // Inject all top-level property init instructions at the beginning of main function.
                // Instructions are already in declaration order (regular and delegate interleaved).
                if function.name == mainName, !allTopLevelInitInstructions.isEmpty {
                    var newBody: KIRLoweringEmitContext = []
                    // Keep .beginBlock at the front if present.
                    if let first = function.body.first, case .beginBlock = first {
                        newBody.append(first)
                        newBody.append(contentsOf: allTopLevelInitInstructions)
                        newBody.append(contentsOf: function.body.dropFirst())
                    } else {
                        newBody.append(contentsOf: allTopLevelInitInstructions)
                        newBody.append(contentsOf: function.body)
                    }
                    updated.body = newBody.instructions
                }

                // Rewrite delegate property accesses (get and set) to runtime calls.
                // Getter: loadGlobal/constValue(.symbolRef) → getValue call.
                // Setter: copy(from:, to:) where target is a delegate-backed property → setValue call.
                if !delegateStorageSymbolByPropertySymbol.isEmpty {
                    // Pass 1: identify constValue(.symbolRef) results that are used as .copy targets.
                    // These are setter destinations; all other constValue(.symbolRef) are getter reads.
                    var copyTargetExprs: Set<KIRExprID> = []
                    for instruction in updated.body {
                        if case let .copy(_, toExpr) = instruction {
                            copyTargetExprs.insert(toExpr)
                        }
                    }

                    // Pass 2: rewrite instructions.
                    var delegateTargetExprs: [KIRExprID: SymbolID] = [:]
                    var rewrittenBody: KIRLoweringEmitContext = []
                    rewrittenBody.reserveCapacity(updated.body.count)
                    for instruction in updated.body {
                        // Rewrite loadGlobal for delegated properties → getValue calls.
                        if case let .loadGlobal(result, sym) = instruction,
                           let delegateStorageSymbol = delegateStorageSymbolByPropertySymbol[sym]
                        {
                            let handleExpr = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)),
                                type: sema.types.anyType
                            )
                            rewrittenBody.append(.loadGlobal(result: handleExpr, symbol: delegateStorageSymbol))

                            let getValueName: InternedString = switch delegateKindByPropertySymbol[sym] {
                            case .lazy:
                                lazyGetValueName
                            case .observable:
                                observableGetValueName
                            case .vetoable:
                                vetoableGetValueName
                            case .custom, nil:
                                customGetValueName
                            }
                            rewrittenBody.append(
                                .call(
                                    symbol: nil,
                                    callee: getValueName,
                                    arguments: [handleExpr],
                                    result: result,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }

                        // Handle constValue(.symbolRef) for delegate-backed properties.
                        if case let .constValue(result, value) = instruction,
                           case let .symbolRef(sym) = value,
                           let delegateStorageSymbol = delegateStorageSymbolByPropertySymbol[sym]
                        {
                            if copyTargetExprs.contains(result) {
                                // This result is a .copy target → setter path.
                                // Track it and emit as-is; the .copy will be rewritten below.
                                delegateTargetExprs[result] = sym
                                rewrittenBody.append(instruction)
                            } else {
                                // Getter path: rewrite to getValue call (same as loadGlobal path).
                                let handleExpr = arena.appendExpr(
                                    .temporary(Int32(arena.expressions.count)),
                                    type: sema.types.anyType
                                )
                                rewrittenBody.append(.loadGlobal(result: handleExpr, symbol: delegateStorageSymbol))

                                let getValueName: InternedString = switch delegateKindByPropertySymbol[sym] {
                                case .lazy:
                                    lazyGetValueName
                                case .observable:
                                    observableGetValueName
                                case .vetoable:
                                    vetoableGetValueName
                                case .custom, nil:
                                    customGetValueName
                                }
                                rewrittenBody.append(
                                    .call(
                                        symbol: nil,
                                        callee: getValueName,
                                        arguments: [handleExpr],
                                        result: result,
                                        canThrow: false,
                                        thrownResult: nil
                                    )
                                )
                            }
                            continue
                        }

                        // Rewrite copy(from: val, to: delegateRef) → setValue call.
                        // This handles assignment to observable/vetoable delegate-backed properties.
                        if case let .copy(fromExpr, toExpr) = instruction,
                           let propertySym = delegateTargetExprs.removeValue(forKey: toExpr),
                           let delegateStorageSymbol = delegateStorageSymbolByPropertySymbol[propertySym]
                        {
                            let kind = delegateKindByPropertySymbol[propertySym]
                            // lazy delegates don't support setValue – skip rewrite.
                            if kind == .lazy {
                                rewrittenBody.append(instruction)
                                continue
                            }
                            let handleExpr = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)),
                                type: sema.types.anyType
                            )
                            rewrittenBody.append(.loadGlobal(result: handleExpr, symbol: delegateStorageSymbol))

                            let setValueName: InternedString = switch kind {
                            case .observable:
                                observableSetValueName
                            case .vetoable:
                                vetoableSetValueName
                            case .custom, nil:
                                customSetValueName
                            case .lazy:
                                preconditionFailure("lazy delegate setValue is not supported")
                            }
                            let setResult = arena.appendExpr(
                                .temporary(Int32(arena.expressions.count)),
                                type: sema.types.anyType
                            )
                            rewrittenBody.append(
                                .call(
                                    symbol: nil,
                                    callee: setValueName,
                                    arguments: [handleExpr, fromExpr],
                                    result: setResult,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }

                        rewrittenBody.append(instruction)
                    }
                    updated.body = rewrittenBody.instructions
                }

                return updated
            }
        }
    }

    // MARK: - Delegate Lowering Helpers

    /// Detects the delegate kind from the delegate expression AST node.
    func detectDelegateKind(
        delegateExpr: ExprID?,
        ast: ASTModule,
        interner: StringInterner
    ) -> StdlibDelegateKind {
        guard let exprID = delegateExpr,
              let expr = ast.arena.expr(exprID)
        else {
            return .custom
        }
        let lazyID = interner.intern("lazy")
        let observableID = interner.intern("observable")
        let vetoableID = interner.intern("vetoable")
        switch expr {
        case let .nameRef(name, _):
            if name == lazyID { return .lazy }
            return .custom
        case let .call(callee, _, _, _):
            // call(callee: memberCall(...) or nameRef(...))
            if let calleeExpr = ast.arena.expr(callee) {
                switch calleeExpr {
                case let .nameRef(name, _):
                    if name == observableID { return .observable }
                    if name == vetoableID { return .vetoable }
                    if name == lazyID { return .lazy }
                default:
                    break
                }
            }
            // Check memberCall pattern: Delegates.observable(...)
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
        callee: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> StdlibDelegateKind {
        guard let expr = ast.arena.expr(callee) else { return .custom }
        let observableID = interner.intern("observable")
        let vetoableID = interner.intern("vetoable")
        // memberAccess: Delegates.observable → memberCall with receiver
        // In the expression parser, `Delegates.observable("initial")` may be parsed as
        // call(callee: memberAccess(...), args: [...])
        // We need to check if the callee resolves to "observable" or "vetoable".
        switch expr {
        case let .memberCall(_, name, _, _, _):
            if name == observableID { return .observable }
            if name == vetoableID { return .vetoable }
        case let .nameRef(name, _):
            if name == observableID { return .observable }
            if name == vetoableID { return .vetoable }
        default:
            break
        }
        return .custom
    }

    /// Creates a lambda function from the delegate body and returns a KIR expression
    /// referencing the lambda's symbol (function pointer).
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

        // Create parameters for the lambda.
        var params: [KIRParameter] = []
        for i in 0 ..< paramCount {
            let paramSymbol = SymbolID(rawValue: -(propertySymbol.rawValue + Int32(i + 1) * 1000 + 50000))
            params.append(KIRParameter(symbol: paramSymbol, type: sema.types.anyType))
        }

        var lambdaBody: KIRLoweringEmitContext = [.beginBlock]
        // Bind parameter symbols so they're accessible in the body.
        for param in params {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            ctx.localValuesBySymbol[param.symbol] = paramExpr
        }

        // Lower the delegate body expressions.
        switch delegateBody {
        case let .block(exprIDs, _):
            var lastValue: KIRExprID?
            for exprID in exprIDs {
                lastValue = lowerExpr(
                    exprID,
                    shared: shared,
                    emit: &lambdaBody
                )
            }
            if let lastValue {
                lambdaBody.append(.returnValue(lastValue))
            } else {
                lambdaBody.append(.returnUnit)
            }
        case let .expr(exprID, _):
            let value = lowerExpr(
                exprID,
                shared: shared,
                emit: &lambdaBody
            )
            lambdaBody.append(.returnValue(value))
        case .unit, nil:
            lambdaBody.append(.returnUnit)
        }
        lambdaBody.append(.endBlock)

        let returnType = sema.types.anyType
        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: params,
                    returnType: returnType,
                    body: lambdaBody,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        ctx.pendingGeneratedCallableDeclIDs.append(lambdaDecl)

        // Return a symbolRef expression pointing to the lambda function.
        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: sema.types.anyType)
        instructions.append(.constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)))
        return lambdaRefExpr
    }

    /// Lowers the initial value argument from a delegate expression
    /// (e.g., the `"initial"` in `Delegates.observable("initial")`).
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
            // Fallback: return 0.
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return zeroExpr
        }

        // For call expressions like `Delegates.observable("initial")` or `observable("initial")`,
        // extract and lower the first argument.
        switch expr {
        case let .call(_, _, args, _):
            if let firstArg = args.first {
                return lowerExpr(
                    firstArg.expr,
                    shared: shared,
                    emit: &instructions
                )
            }
        case let .memberCall(_, _, _, args, _):
            if let firstArg = args.first {
                return lowerExpr(
                    firstArg.expr,
                    shared: shared,
                    emit: &instructions
                )
            }
        default:
            break
        }

        // Fallback: lower the entire delegate expression as the initial value.
        return lowerExpr(
            exprID,
            shared: shared,
            emit: &instructions
        )
    }
}
