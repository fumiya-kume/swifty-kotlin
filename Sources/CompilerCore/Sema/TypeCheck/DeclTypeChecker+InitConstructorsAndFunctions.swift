
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

    /// Type-checks each parameter's default-value expression (if any) against its
    /// declared type, visiting parameters in declaration order and revealing each
    /// parameter symbol to `locals` only after its own default has been checked.
    /// This mirrors the visibility that `CallSupportLowerer.generateDefaultStubFunction`
    /// assumes when it lowers these same expressions: a default value may reference
    /// the current or an earlier parameter, but not a later one.
    ///
    /// Without this, default-value expressions are never visited by Sema at all, so
    /// `sema.bindings` (call bindings, expr types, ...) stay empty for them and KIR
    /// lowering silently mis-resolves anything beyond a literal (constructor calls,
    /// property reads, ...).
    func typeCheckParameterDefaultValues(
        _ valueParams: [ValueParamDecl],
        signature: FunctionSignature,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        var locals: LocalBindings = [:]
        for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            guard let param = sema.symbols.symbol(paramSymbol) else { continue }
            let type = localTypeForParameter(
                at: index, signature: signature, sema: sema, interner: ctx.interner
            )
            if index < valueParams.count, let defaultExprID = valueParams[index].defaultValue {
                let defaultType = driver.inferExpr(
                    defaultExprID, ctx: ctx, locals: &locals, expectedType: type
                )
                driver.emitSubtypeConstraint(
                    left: defaultType, right: type,
                    range: ctx.ast.arena.exprRange(defaultExprID),
                    solver: solver, sema: sema, diagnostics: diagnostics
                )
            }
            locals[param.name] = (type, paramSymbol, false, true)
        }
    }

    /// Type-checks primary constructor parameter default-value expressions.
    /// Primary constructor parameters never go through `typeCheckSecondaryConstructors`
    /// or a function body check, so without this call their defaults would never be
    /// visited by Sema at all (see `typeCheckParameterDefaultValues`).
    func typeCheckPrimaryConstructorDefaultValues(
        _ classDecl: ClassDecl,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        guard classDecl.primaryConstructorParams.contains(where: { $0.defaultValue != nil }) else {
            return
        }
        let sema = ctx.sema
        let primaryCtorSymbol = sema.symbols.symbols(atDeclSite: classDecl.range)
            .compactMap { sema.symbols.symbol($0) }
            .first { $0.kind == .constructor }
        guard let primaryCtorSymbol,
              let signature = sema.symbols.functionSignature(for: primaryCtorSymbol.id)
        else {
            return
        }
        typeCheckParameterDefaultValues(
            classDecl.primaryConstructorParams,
            signature: signature,
            ctx: ctx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    /// Type-checks the superclass constructor invocation written in a class
    /// header (`class Sub(n: Int) : Base(n)`) and records the resolved
    /// superclass constructor as the primary constructor's delegation target,
    /// so KIR lowering can emit the `super(...)` call.
    ///
    /// The arguments live in the primary constructor's scope, so they are
    /// checked with the primary constructor parameters seeded as locals — the
    /// same scope `typeCheckClassDelegation` builds for `by` expressions.
    func typeCheckPrimaryConstructorSuperDelegation(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext
    ) {
        let sema = ctx.sema
        guard let superclassSymbol = superclassSymbol(of: symbol, sema: sema),
              let superclassInfo = sema.symbols.symbol(superclassSymbol),
              let primaryCtorSymbol = sema.symbols.symbols(atDeclSite: classDecl.range)
              .compactMap({ sema.symbols.symbol($0) })
              .first(where: { $0.kind == .constructor })
        else {
            return
        }

        let args = classDecl.superTypeEntries.first { !$0.constructorArgs.isEmpty }?.constructorArgs ?? []

        var delegationCtx = ctx
        var locals: LocalBindings = [:]
        if let signature = sema.symbols.functionSignature(for: primaryCtorSymbol.id) {
            let ctorScope = BaseScope(parent: ctx.scope, symbols: sema.symbols)
            for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
                ctorScope.insert(paramSymbol)
                guard let paramInfo = sema.symbols.symbol(paramSymbol) else { continue }
                locals[paramInfo.name] = (
                    type: localTypeForParameter(
                        at: index, signature: signature, sema: sema, interner: ctx.interner
                    ),
                    symbol: paramSymbol,
                    isMutable: false,
                    isInitialized: true
                )
            }
            delegationCtx = ctx.copying(scope: ctorScope)
        }

        var callArgs: [CallArg] = []
        for arg in args {
            let argType = driver.inferExpr(arg.expr, ctx: delegationCtx, locals: &locals, expectedType: nil)
            callArgs.append(CallArg(label: arg.label, isSpread: arg.isSpread, type: argType))
        }

        let candidates = sema.symbols
            .lookupAll(fqName: superclassInfo.fqName + [ctx.interner.intern("<init>")])
            .filter { candidate in
                guard let candidateInfo = sema.symbols.symbol(candidate) else { return false }
                return candidateInfo.kind == .constructor && candidate != primaryCtorSymbol.id
            }
        guard !candidates.isEmpty else { return }

        let callExpr = CallExpr(
            range: classDecl.range,
            calleeName: ctx.interner.intern("<init>"),
            args: callArgs
        )
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: callExpr,
            expectedType: nil,
            ctx: sema
        )
        if let chosenCallee = resolved.chosenCallee {
            sema.bindings.bindConstructorDelegationTarget(primaryCtorSymbol.id, target: chosenCallee)
        }
    }

    /// The single class-kind supertype of `symbol`, if any.
    func superclassSymbol(of symbol: SymbolID, sema: SemaModule) -> SymbolID? {
        sema.symbols.directSupertypes(for: symbol).first {
            let kind = sema.symbols.symbol($0)?.kind
            return kind == .class || kind == .enumClass
        }
    }

    /// Returns the class-kind superclass written in the source header.
    ///
    /// Inheritance binding adds kotlin.Any to classes without an explicit
    /// superclass. That implicit edge represents nominal inheritance, but it
    /// is not an explicit constructor delegation target for `super()`.
    func explicitClassSuperclassSymbol(
        _ classDecl: ClassDecl,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        for entry in classDecl.superTypeEntries {
            let resolved = driver.helpers.resolveTypeRef(
                entry.typeRef,
                ast: ctx.ast,
                sema: ctx.sema,
                interner: ctx.interner,
                scope: ctx.scope,
                diagnostics: nil
            )
            if resolved == ctx.sema.types.anyType,
               let anySymbol = ctx.sema.symbols.lookup(fqName: [
                   ctx.interner.intern("kotlin"),
                   ctx.interner.intern("Any"),
               ])
            {
                return anySymbol
            }
            guard case let .classType(classType) = ctx.sema.types.kind(of: resolved),
                  let symbol = ctx.sema.symbols.symbol(classType.classSymbol)
            else {
                continue
            }
            switch symbol.kind {
            case .class, .enumClass, .annotationClass:
                return classType.classSymbol
            default:
                continue
            }
        }
        return nil
    }

    // MARK: - Init Block & Secondary Constructor Type Checking

    /// Kotlin scopes primary constructor parameters declared without `val`/`var`
    /// to property initializers and `init {}` blocks only — not to regular
    /// member functions. Property-backed parameters (`val`/`var`) are already
    /// reachable as members through `classScope`, so only the non-property
    /// parameters need to be threaded through here as `locals`.
    func primaryConstructorParameterLocals(
        classDecl: ClassDecl,
        ctx: TypeInferenceContext
    ) -> LocalBindings {
        guard !classDecl.primaryConstructorParams.isEmpty else { return [:] }
        let sema = ctx.sema
        guard let ctorSymbol = sema.symbols.symbols(atDeclSite: classDecl.range)
            .compactMap({ sema.symbols.symbol($0) })
            .first(where: { $0.kind == .constructor }),
            let signature = sema.symbols.functionSignature(for: ctorSymbol.id)
        else {
            return [:]
        }
        var locals: LocalBindings = [:]
        for (index, param) in classDecl.primaryConstructorParams.enumerated() {
            guard !param.isProperty, index < signature.valueParameterSymbols.count else { continue }
            let paramSymbol = signature.valueParameterSymbols[index]
            let type = localTypeForParameter(
                at: index, signature: signature, sema: sema, interner: ctx.interner
            )
            locals[param.name] = (type, paramSymbol, false, true)
            if driver.helpers.isOpenEndRangeType(type, sema: sema, interner: ctx.interner) {
                sema.bindings.markRangeSymbol(paramSymbol)
            }
            if index < signature.valueParameterIsVararg.count,
               signature.valueParameterIsVararg[index]
            {
                sema.bindings.markCollectionSymbol(paramSymbol)
            }
        }
        return locals
    }

    func typeCheckInitBlocks(
        _ blocks: [FunctionBody],
        ctx: TypeInferenceContext,
        baseLocals: LocalBindings = [:]
    ) {
        for block in blocks {
            var locals: LocalBindings = baseLocals
            var initCtx = ctx
            initCtx.allowsValPropertyInitialization = true
            _ = inferFunctionBodyType(block, ctx: initCtx, locals: &locals, expectedType: nil)
        }
    }

    func typeCheckSecondaryConstructors(
        _ constructors: [ConstructorDecl],
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        ownerSymbol: SymbolID? = nil,
        hasPrimaryConstructor: Bool = true,
        explicitSuperclassSymbol: SymbolID? = nil
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
                        if driver.helpers.isOpenEndRangeType(type, sema: sema, interner: ctx.interner) {
                            sema.bindings.markRangeSymbol(paramSymbol)
                        }
                        if index < signature.valueParameterIsVararg.count,
                           signature.valueParameterIsVararg[index]
                        {
                            sema.bindings.markCollectionSymbol(paramSymbol)
                        }
                    }
                    constructorCtx = ctx.copying(scope: constructorScope)
                    typeCheckParameterDefaultValues(
                        ctor.valueParams,
                        signature: signature,
                        ctx: constructorCtx,
                        solver: solver,
                        diagnostics: diagnostics
                    )
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
                explicitSuperclassSymbol: explicitSuperclassSymbol,
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
        explicitSuperclassSymbol: SymbolID?,
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
            explicitSuperclassSymbol: explicitSuperclassSymbol,
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
                if let chosenCallee = resolved.chosenCallee, let currentCtorSymbolID {
                    sema.bindings.bindConstructorDelegationTarget(currentCtorSymbolID, target: chosenCallee)
                }
            }
        } else if ownerSymbol != nil {
            emitUnresolvedDelegation(delegation: delegation, sema: sema)
        }
    }

    private func resolveDelegationTarget(
        delegation: ConstructorDelegationCall,
        ownerSymbol: SymbolID?,
        explicitSuperclassSymbol: SymbolID?,
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
            guard ownerSymbol != nil, let superclass = explicitSuperclassSymbol,
                  let superSym = sema.symbols.symbol(superclass)
            else { return [] }
            return superSym.fqName + [ctx.interner.intern("<init>")]
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

    /// - Parameter baseLocals: Seeds the function body's local-name resolution
    ///   with bindings from an enclosing scope. Empty for ordinary member
    ///   functions (a named class has no enclosing local scope to capture).
    ///   Object-literal member functions pass the enclosing function's
    ///   `locals` here so the body can resolve captured outer variables the
    ///   same way lambda bodies do (KSP-CAP-001).
    func typeCheckFunctionDecl(
        _ function: FunDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) {
        let sema = ctx.sema
        guard let signature = sema.symbols.functionSignature(for: symbol) else {
            return
        }

        validateFunctionHeaderOptInTypes(
            symbol,
            ctx: ctx.with(currentDeclSymbol: symbol)
        )
        if function.modifiers.contains(.external), function.body == .unit {
            return
        }

        var locals: LocalBindings = baseLocals
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
            if driver.helpers.isOpenEndRangeType(type, sema: sema, interner: ctx.interner) {
                sema.bindings.markRangeSymbol(paramSymbol)
            }
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
            if driver.helpers.isOpenEndRangeType(receiverType, sema: sema, interner: ctx.interner) {
                sema.bindings.markRangeSymbol(syntheticThisSymbol)
            }
        }

        let functionScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
        for typeParameterSymbol in signature.typeParameterSymbols {
            functionScope.insert(typeParameterSymbol)
        }
        var functionCtx = ctx.copying(
            scope: functionScope,
            implicitReceiverType: effectiveReceiverType,
            lambdaDepth: 0,
            enclosingFunctionReturnType: signature.returnType,
            currentDeclSymbol: symbol
        )
        // Propagate suppression flag so that individual `return` statements inside
        // functions with inferred return types also skip the platform-type warning.
        functionCtx.suppressPlatformReturnWarning = (function.returnType == nil)

        typeCheckParameterDefaultValues(
            function.valueParams,
            signature: signature,
            ctx: functionCtx,
            solver: solver,
            diagnostics: diagnostics
        )

        // Bodyless declarations use .unit as their sentinel. Abstract and expect
        // functions declare a contract only, while external functions lower to a
        // runtime symbol via their header metadata.
        let symbolFlags = sema.symbols.symbol(symbol)?.flags ?? []
        let isAbstract = function.body == .unit
            && symbolFlags.contains(.abstractType)
        if isAbstract { return }
        if function.body == .unit {
            if function.modifiers.contains(.external) || symbolFlags.contains(.expectDeclaration) {
                return
            }
            diagnostics.error(
                "KSWIFTK-SEMA-0009",
                "Function '\(ctx.interner.resolve(function.name))' must have a body.",
                range: function.range
            )
            return
        }

        let bodyType = inferFunctionBodyType(
            function.body,
            ctx: functionCtx,
            locals: &locals,
            expectedType: signature.returnType
        )
        // Expression bodies that are range expressions infer as the scalar element
        // type (the isRangeExpr duck-typing convention), so `fun f(): IntRange = a..b`
        // skips the nominal subtype check like the equivalent local declaration does —
        // but only when the body's actual element type matches IntRange's (KSWIFTK
        // range-element-type gap: `fun f(): LongRange = 1..10` must still be rejected).
        let bodyIsRangeExpr = {
            guard case let .expr(bodyExprID, _) = function.body else { return false }
            return driver.helpers.rangeExprMatchesDeclaredElementType(
                bodyExprID: bodyExprID,
                bodyType: bodyType,
                declaredType: signature.returnType,
                sema: sema,
                interner: ctx.interner
            )
        }()
        if !bodyIsRangeExpr {
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
        }

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
                    valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
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
