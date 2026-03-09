import Foundation

// Init block, secondary constructor, and function declaration type checking.

extension DeclTypeChecker {
    private func localTypeForParameter(
        at index: Int,
        signature: FunctionSignature,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let parameterType = index < signature.parameterTypes.count
            ? signature.parameterTypes[index]
            : sema.types.anyType
        guard index < signature.valueParameterIsVararg.count,
              signature.valueParameterIsVararg[index]
        else {
            return parameterType
        }
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = sema.symbols.lookup(fqName: listFQName) else {
            return parameterType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.invariant(parameterType)],
            nullability: .nonNull
        )))
    }

    // MARK: - Init Block & Secondary Constructor Type Checking

    func typeCheckInitBlocks(
        _ blocks: [FunctionBody],
        ctx: TypeInferenceContext
    ) {
        for block in blocks {
            var locals: LocalBindings = [:]
            var initCtx = ctx
            initCtx.allowsValPropertyInitialization = true
            _ = inferFunctionBodyType(block, ctx: initCtx, locals: &locals, expectedType: nil)
        }
    }

    func typeCheckSecondaryConstructors(
        _ constructors: [ConstructorDecl],
        ctx: TypeInferenceContext,
        ownerSymbol: SymbolID? = nil,
        hasPrimaryConstructor: Bool = true
    ) {
        let sema = ctx.sema
        for ctor in constructors {
            var locals: LocalBindings = [:]
            let ctorSymbols = sema.symbols.symbols(atDeclSite: ctor.range)
                .compactMap { sema.symbols.symbol($0) }
                .filter { $0.kind == .constructor }
            let currentCtorSymbolID = ctorSymbols.first?.id
            let constructorScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
            var constructorCtx = ctx.copying(scope: constructorScope)
            if let ctorSymbol = ctorSymbols.first {
                if let signature = sema.symbols.functionSignature(for: ctorSymbol.id) {
                    for typeParameterSymbol in signature.typeParameterSymbols {
                        constructorScope.insert(typeParameterSymbol)
                    }
                    for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
                        guard let param = sema.symbols.symbol(paramSymbol) else { continue }
                        let type = localTypeForParameter(
                            at: index,
                            signature: signature,
                            sema: sema,
                            interner: ctx.interner
                        )
                        locals[param.name] = (type, paramSymbol, false, true)
                        if index < signature.valueParameterIsVararg.count,
                           signature.valueParameterIsVararg[index]
                        {
                            sema.bindings.markCollectionSymbol(paramSymbol)
                        }
                    }
                    constructorCtx = ctx.copying(scope: constructorScope)
                }
            }

            constructorCtx.allowsValPropertyInitialization = true
            if ctor.delegationCall == nil, hasPrimaryConstructor {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0054",
                    "Secondary constructor must delegate to another constructor via this() or super().",
                    range: ctor.range
                )
            }

            typeCheckConstructorDelegation(
                ctor: ctor,
                currentCtorSymbolID: currentCtorSymbolID,
                ownerSymbol: ownerSymbol,
                ctx: constructorCtx,
                locals: &locals
            )
            _ = inferFunctionBodyType(ctor.body, ctx: constructorCtx, locals: &locals, expectedType: nil)
        }
    }

    private func typeCheckConstructorDelegation(
        ctor: ConstructorDecl,
        currentCtorSymbolID: SymbolID?,
        ownerSymbol: SymbolID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        guard let delegation = ctor.delegationCall else { return }

        var argTypes: [CallArg] = []
        for arg in delegation.args {
            let argType = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: nil)
            argTypes.append(CallArg(label: arg.label, isSpread: arg.isSpread, type: argType))
        }

        let delegationTargetFQName = resolveDelegationTarget(
            delegation: delegation,
            ownerSymbol: ownerSymbol,
            ctx: ctx
        )

        if !delegationTargetFQName.isEmpty {
            let candidates = sema.symbols.lookupAll(fqName: delegationTargetFQName)
                .filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else { return false }
                    return symbol.kind == .constructor && candidate != currentCtorSymbolID
                }

            if candidates.isEmpty {
                emitUnresolvedDelegation(delegation: delegation, sema: sema)
            } else {
                let callExpr = CallExpr(
                    range: delegation.range,
                    calleeName: ctx.interner.intern("<init>"),
                    args: argTypes
                )
                let resolved = ctx.resolver.resolveCall(
                    candidates: candidates,
                    call: callExpr,
                    expectedType: nil,
                    ctx: sema
                )
                if let diagnostic = resolved.diagnostic {
                    sema.diagnostics.emit(diagnostic)
                }
            }
        } else if ownerSymbol != nil {
            emitUnresolvedDelegation(delegation: delegation, sema: sema)
        }
    }

    private func resolveDelegationTarget(
        delegation: ConstructorDelegationCall,
        ownerSymbol: SymbolID?,
        ctx: TypeInferenceContext
    ) -> [InternedString] {
        let sema = ctx.sema
        switch delegation.kind {
        case .this:
            if let owner = ownerSymbol {
                if let ownerSym = sema.symbols.symbol(owner) {
                    return ownerSym.fqName + [ctx.interner.intern("<init>")]
                }
            }
            return []
        case .super_:
            guard let owner = ownerSymbol else { return [] }
            let supertypes = sema.symbols.directSupertypes(for: owner)
            let classSupertypes = supertypes.filter {
                let kind = sema.symbols.symbol($0)?.kind
                return kind == .class || kind == .enumClass
            }
            if let superclass = classSupertypes.first {
                if let superSym = sema.symbols.symbol(superclass) {
                    return superSym.fqName + [ctx.interner.intern("<init>")]
                }
            }
            return []
        }
    }

    private func emitUnresolvedDelegation(
        delegation: ConstructorDelegationCall,
        sema: SemaModule
    ) {
        let targetKind = delegation.kind == .this ? "this" : "super"
        sema.diagnostics.error(
            "KSWIFTK-SEMA-0055",
            "Unresolved \(targetKind)() delegation target: no matching constructor found.",
            range: delegation.range
        )
    }

    // MARK: - Function Declaration Type Checking

    func typeCheckFunctionDecl(
        _ function: FunDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        guard let signature = sema.symbols.functionSignature(for: symbol) else {
            return
        }

        var locals: LocalBindings = [:]
        for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            guard let param = sema.symbols.symbol(paramSymbol) else {
                continue
            }
            let type = localTypeForParameter(
                at: index,
                signature: signature,
                sema: sema,
                interner: ctx.interner
            )
            locals[param.name] = (type, paramSymbol, false, true)
            if index < signature.valueParameterIsVararg.count,
               signature.valueParameterIsVararg[index]
            {
                sema.bindings.markCollectionSymbol(paramSymbol)
            }
        }
        let effectiveReceiverType = signature.receiverType ?? ctx.implicitReceiverType
        if let receiverType = effectiveReceiverType {
            let thisName = ctx.interner.intern("this")
            let syntheticThisSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)
            locals[thisName] = (receiverType, syntheticThisSymbol, false, true)
        }

        let functionScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
        for typeParameterSymbol in signature.typeParameterSymbols {
            functionScope.insert(typeParameterSymbol)
        }
        var functionCtx = ctx.copying(scope: functionScope, implicitReceiverType: effectiveReceiverType)
        // Propagate suppression flag so that individual `return` statements inside
        // functions with inferred return types also skip the platform-type warning.
        functionCtx.suppressPlatformReturnWarning = (function.returnType == nil)

        // Abstract methods use .unit as their body sentinel – skip body type
        // inference. Gate on abstractType so non-abstract missing bodies still
        // hit the Unit <: ReturnType constraint.
        let isAbstract = function.body == .unit
            && (sema.symbols.symbol(symbol)?.flags.contains(.abstractType) ?? false)
        if isAbstract { return }

        let bodyType = inferFunctionBodyType(
            function.body,
            ctx: functionCtx,
            locals: &locals,
            expectedType: signature.returnType
        )
        driver.emitSubtypeConstraint(
            left: bodyType,
            right: signature.returnType,
            range: function.range,
            solver: solver,
            sema: sema,
            diagnostics: diagnostics,
            // Suppress platform warning when return type is inferred (not explicitly declared):
            // the placeholder anyType is not a user-declared non-null constraint.
            suppressPlatformWarning: function.returnType == nil
        )

        updateInferredReturnType(
            function: function,
            symbol: symbol,
            bodyType: bodyType,
            signature: signature,
            sema: sema
        )
        recordContractEffects(
            function: function,
            symbol: symbol,
            signature: signature,
            ast: ctx.ast,
            interner: ctx.interner,
            sema: sema
        )
    }

    /// Updates the function signature with the inferred return type when no
    /// explicit annotation is present and the body type is suitable.
    private func updateInferredReturnType(
        function: FunDecl,
        symbol: SymbolID,
        bodyType: TypeID,
        signature: FunctionSignature,
        sema: SemaModule
    ) {
        let skipUpdate = if bodyType == sema.types.errorType {
            true
        } else if bodyType == sema.types.nothingType {
            switch function.body {
            case .block: true
            case .expr, .unit: false
            }
        } else {
            false
        }

        if function.returnType == nil, !skipUpdate {
            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: signature.receiverType,
                    parameterTypes: signature.parameterTypes,
                    returnType: bodyType,
                    isSuspend: signature.isSuspend,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    typeParameterSymbols: signature.typeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices
                ),
                for: symbol
            )
        }
    }

    private func recordContractEffects(
        function: FunDecl,
        symbol: SymbolID,
        signature: FunctionSignature,
        ast: ASTModule,
        interner: StringInterner,
        sema: SemaModule
    ) {
        guard case let .block(expressions, _) = function.body,
              let firstExprID = expressions.first,
              let firstExpr = ast.arena.expr(firstExprID),
              case let .call(calleeExprID, _, args, _) = firstExpr,
              args.count == 1,
              let calleeExpr = ast.arena.expr(calleeExprID),
              case let .nameRef(calleeName, _) = calleeExpr,
              interner.resolve(calleeName) == "contract",
              let lambdaExpr = ast.arena.expr(args[0].expr)
        else {
            return
        }

        let lambdaBodyExprID: ExprID? = switch lambdaExpr {
        case let .lambdaLiteral(_, body, _, _):
            body
        default:
            nil
        }
        guard let lambdaBodyExprID,
              let lambdaBodyExpr = ast.arena.expr(lambdaBodyExprID)
        else {
            return
        }

        let contractExprID: ExprID? = switch lambdaBodyExpr {
        case let .blockExpr(statements, trailingExpr, _):
            statements.first ?? trailingExpr
        default:
            lambdaBodyExprID
        }
        guard let contractExprID,
              let contractExpr = ast.arena.expr(contractExprID),
              case let .memberCall(receiverExprID, impliesName, _, impliesArgs, _) = contractExpr,
              interner.resolve(impliesName) == "implies",
              impliesArgs.count == 1,
              let receiverExpr = ast.arena.expr(receiverExprID),
              case let .call(returnsCalleeExprID, _, returnsArgs, _) = receiverExpr,
              let returnsCalleeExpr = ast.arena.expr(returnsCalleeExprID),
              case let .nameRef(returnsName, _) = returnsCalleeExpr,
              interner.resolve(returnsName) == "returns",
              returnsArgs.isEmpty,
              let conditionExpr = ast.arena.expr(impliesArgs[0].expr),
              case let .binary(.notEqual, lhsExprID, rhsExprID, _) = conditionExpr
        else {
            return
        }

        let parameterName: InternedString? = if let lhsExpr = ast.arena.expr(lhsExprID),
                                                case let .nameRef(name, _) = lhsExpr,
                                                isNullLiteralExpr(rhsExprID, ast: ast, interner: interner)
        {
            name
        } else if let rhsExpr = ast.arena.expr(rhsExprID),
                  case let .nameRef(name, _) = rhsExpr,
                  isNullLiteralExpr(lhsExprID, ast: ast, interner: interner)
        {
            name
        } else {
            nil
        }
        guard let parameterName,
              let parameterIndex = function.valueParams.firstIndex(where: { $0.name == parameterName }),
              parameterIndex < signature.valueParameterSymbols.count
        else {
            return
        }
        sema.symbols.setContractNonNullEffect(
            ContractNonNullEffect(
                parameterSymbol: signature.valueParameterSymbols[parameterIndex],
                appliesOnAnyReturn: true
            ),
            for: symbol
        )
    }

    private func isNullLiteralExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        if case let .nameRef(name, _) = expr {
            return interner.resolve(name) == "null"
        }
        return false
    }
}
