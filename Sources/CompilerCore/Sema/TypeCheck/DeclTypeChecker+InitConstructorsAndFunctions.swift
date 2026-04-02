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

        validateFunctionHeaderOptInTypes(
            symbol,
            ctx: ctx.with(currentDeclSymbol: symbol)
        )

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
        var functionCtx = ctx.copying(
            scope: functionScope,
            implicitReceiverType: effectiveReceiverType,
            currentDeclSymbol: symbol
        )
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

        if function.returnType == nil, case .expr = function.body, !skipUpdate {
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

        // Collect all effect expression IDs from the contract lambda body.
        let effectExprIDs: [ExprID] = switch lambdaBodyExpr {
        case let .blockExpr(statements, trailingExpr, _):
            statements + (trailingExpr.map { [$0] } ?? [])
        default:
            [lambdaBodyExprID]
        }

        for effectExprID in effectExprIDs {
            recordSingleContractEffect(
                effectExprID: effectExprID,
                function: function,
                symbol: symbol,
                signature: signature,
                ast: ast,
                interner: interner,
                sema: sema
            )
        }
    }

    /// Analyzes a single expression inside a `contract { ... }` lambda and records
    /// any recognized effect on the function symbol.
    ///
    /// Recognized patterns:
    /// - `returns()` -- bare returns effect (STDLIB-591)
    /// - `returns(true)` / `returns(false)` -- Boolean return value effect (STDLIB-591)
    /// - `returns() implies (param != null)` -- non-null smart cast
    /// - `callsInPlace(lambda[, kind])` -- STDLIB-592
    /// - `returnsNotNull()` -- STDLIB-593
    private func recordSingleContractEffect(
        effectExprID: ExprID,
        function: FunDecl,
        symbol: SymbolID,
        signature: FunctionSignature,
        ast: ASTModule,
        interner: StringInterner,
        sema: SemaModule
    ) {
        guard let effectExpr = ast.arena.expr(effectExprID) else { return }

        // Pattern 1: `returns() implies (condition)` or
        //            `returns(true/false) implies (condition)` -- STDLIB-591
        if case let .memberCall(receiverExprID, impliesName, _, impliesArgs, _) = effectExpr,
           interner.resolve(impliesName) == "implies",
           impliesArgs.count == 1,
           let receiverExpr = ast.arena.expr(receiverExprID),
           case let .call(returnsCalleeExprID, _, returnsArgs, _) = receiverExpr,
           let returnsCalleeExpr = ast.arena.expr(returnsCalleeExprID),
           case let .nameRef(returnsName, _) = returnsCalleeExpr,
           interner.resolve(returnsName) == "returns"
        {
            // Determine the returns constraint: nil = any return,
            // true/false = when the function returns that specific Boolean.
            let returnsValue: Bool?
            if returnsArgs.isEmpty {
                returnsValue = nil
                // Also record the bare returns() effect for the function.
                if sema.symbols.contractReturnsEffect(for: symbol) == nil {
                    sema.symbols.setContractReturnsEffect(
                        .returnsNormally,
                        for: symbol
                    )
                }
            } else if returnsArgs.count == 1,
                      let boolValue = extractBooleanLiteral(returnsArgs[0].expr, ast: ast, interner: interner)
            {
                returnsValue = boolValue
            } else {
                return
            }
            recordReturnsImpliesEffect(
                impliesArgs: impliesArgs,
                returnsValue: returnsValue,
                function: function,
                symbol: symbol,
                signature: signature,
                ast: ast,
                interner: interner,
                sema: sema
            )
            return
        }

        // Pattern 2: bare `returns()` call (STDLIB-591)
        if case let .call(returnsCalleeExprID, _, returnsArgs, _) = effectExpr,
           let returnsCalleeExpr = ast.arena.expr(returnsCalleeExprID),
           case let .nameRef(returnsName, _) = returnsCalleeExpr,
           interner.resolve(returnsName) == "returns"
        {
            if returnsArgs.isEmpty {
                // `returns()` -- the function guarantees normal return.
                // Only set if no effect recorded yet; a more specific effect
                // (e.g. `returns(true)`) should not be overwritten by a bare
                // `returns()` when multiple effects appear in the same block.
                if sema.symbols.contractReturnsEffect(for: symbol) == nil {
                    sema.symbols.setContractReturnsEffect(
                        .returnsNormally,
                        for: symbol
                    )
                }
            } else if returnsArgs.count == 1 {
                // `returns(true)` or `returns(false)` -- the function guarantees
                // a specific Boolean *return value* on normal completion.
                // Only valid when the function's return type is Boolean; ignore
                // the effect for non-Boolean-returning functions to prevent
                // encoding an invalid contract.
                guard signature.returnType == sema.types.booleanType else { return }
                if let boolValue = extractBooleanLiteral(returnsArgs[0].expr, ast: ast, interner: interner) {
                    // Heuristic: find the first Boolean parameter for smart-cast binding.
                    let conditionIndex = signature.parameterTypes.firstIndex { typeID in
                        typeID == sema.types.booleanType
                    }
                    sema.symbols.setContractReturnsEffect(
                        .returnsBooleanValue(
                            expectedValue: boolValue,
                            conditionParameterIndex: conditionIndex
                        ),
                        for: symbol
                    )
                }
            }
            return
        }

        // Pattern 3 (STDLIB-592): callsInPlace(lambdaParam) or callsInPlace(lambdaParam, InvocationKind.*)
        if case let .call(calleeExprID, _, callArgs, _) = effectExpr,
           let calleeExpr = ast.arena.expr(calleeExprID),
           case let .nameRef(calleeName, _) = calleeExpr,
           interner.resolve(calleeName) == "callsInPlace",
           callArgs.count >= 1, callArgs.count <= 2,
           let firstArgExpr = ast.arena.expr(callArgs[0].expr),
           case let .nameRef(lambdaParamName, _) = firstArgExpr
        {
            var invocationKind: InvocationKind = .exactlyOnce
            if callArgs.count == 2 {
                invocationKind = resolveInvocationKindArg(
                    callArgs[1].expr, ast: ast, interner: interner
                ) ?? .unknown
            }
            if let parameterIndex = function.valueParams.firstIndex(where: { $0.name == lambdaParamName }),
               parameterIndex < signature.valueParameterSymbols.count
            {
                sema.symbols.addContractCallsInPlaceEffect(
                    ContractCallsInPlaceEffect(
                        parameterSymbol: signature.valueParameterSymbols[parameterIndex],
                        kind: invocationKind
                    ),
                    for: symbol
                )
            }
            return
        }

        // Pattern 4 (STDLIB-593): returnsNotNull()
        if case let .call(calleeExprID, _, returnNNArgs, _) = effectExpr,
           let calleeExpr = ast.arena.expr(calleeExprID),
           case let .nameRef(calleeName, _) = calleeExpr,
           interner.resolve(calleeName) == "returnsNotNull",
           returnNNArgs.isEmpty
        {
            sema.symbols.setContractReturnsNotNull(for: symbol)
            return
        }
    }

    /// Records a `returns() implies (condition)` or `returns(true/false) implies (condition)`
    /// contract effect.
    ///
    /// Handles two sub-patterns for the condition:
    /// 1. `param != null` — records a `ContractNonNullEffect` that narrows the
    ///    parameter to non-null after normal return.
    /// 2. `param` — where `param` is a Boolean parameter, records a
    ///    `ContractConditionEffect` so that the argument expression is analyzed
    ///    for smart casts at the call site (STDLIB-591).
    ///
    /// - Parameter returnsValue: `nil` for `returns()`, `true`/`false` for
    ///   `returns(true)` / `returns(false)`.
    private func recordReturnsImpliesEffect(
        impliesArgs: [CallArgument],
        returnsValue: Bool?,
        function: FunDecl,
        symbol: SymbolID,
        signature: FunctionSignature,
        ast: ASTModule,
        interner: StringInterner,
        sema: SemaModule
    ) {
        guard let conditionExpr = ast.arena.expr(impliesArgs[0].expr) else {
            return
        }

        // Sub-pattern 1: `returns() implies (param != null)`
        if case let .binary(.notEqual, lhsExprID, rhsExprID, _) = conditionExpr {
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
            // For bare `returns() implies (param != null)`, also record the legacy
            // ContractNonNullEffect for backward compatibility.
            if returnsValue == nil {
                sema.symbols.setContractNonNullEffect(
                    ContractNonNullEffect(
                        parameterSymbol: signature.valueParameterSymbols[parameterIndex],
                        appliesOnAnyReturn: true
                    ),
                    for: symbol
                )
            }
            return
        }

        // Sub-pattern 2 (STDLIB-591): `returns() implies param` where param is Boolean.
        // This means the argument expression passed for this parameter is guaranteed
        // true after normal return, enabling smart casts on the call-site expression.
        if case let .nameRef(paramName, _) = conditionExpr,
           let parameterIndex = function.valueParams.firstIndex(where: { $0.name == paramName }),
           parameterIndex < signature.parameterTypes.count,
           signature.parameterTypes[parameterIndex] == sema.types.booleanType
        {
            sema.symbols.setContractConditionEffect(
                ContractConditionEffect(
                    conditionParameterIndex: parameterIndex,
                    returnsValue: returnsValue
                ),
                for: symbol
            )
        }
    }

    /// Resolve an `InvocationKind.*` member-access expression to an `InvocationKind` value.
    /// The AST represents `InvocationKind.EXACTLY_ONCE` as a zero-arg `.memberCall` or
    /// as a plain `.nameRef` when already resolved.
    private func resolveInvocationKindArg(
        _ exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> InvocationKind? {
        guard let expr = ast.arena.expr(exprID) else { return nil }
        // Match `InvocationKind.EXACTLY_ONCE` — parsed as memberCall with zero args
        if case let .memberCall(receiverExprID, memberName, _, memberArgs, _) = expr,
           memberArgs.isEmpty,
           let receiverExpr = ast.arena.expr(receiverExprID),
           case let .nameRef(receiverName, _) = receiverExpr,
           interner.resolve(receiverName) == "InvocationKind"
        {
            return InvocationKind(rawValue: interner.resolve(memberName))
        }
        // Also handle a plain nameRef that already holds the entry name.
        if case let .nameRef(name, _) = expr {
            return InvocationKind(rawValue: interner.resolve(name))
        }
        return nil
    }

    /// Extracts a boolean literal value from an expression (`true` or `false`).
    private func extractBooleanLiteral(
        _ exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> Bool? {
        guard let expr = ast.arena.expr(exprID) else { return nil }
        if case let .nameRef(name, _) = expr {
            let resolved = interner.resolve(name)
            if resolved == "true" { return true }
            if resolved == "false" { return false }
        }
        if case let .boolLiteral(value, _) = expr {
            return value
        }
        return nil
    }

    private func isNullLiteralExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        if case let .nameRef(name, _) = expr {
            return name == KnownCompilerNames(interner: interner).null
        }
        return false
    }
}
