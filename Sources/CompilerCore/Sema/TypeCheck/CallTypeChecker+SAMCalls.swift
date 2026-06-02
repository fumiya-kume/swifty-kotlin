import Foundation

extension CallTypeChecker {
    func inferSamConvertedCallExpr(
        _ id: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let samArgIndices = args.enumerated().compactMap { index, argument in
            isSamConvertibleArgument(argument.expr, ast: ctx.ast) ? index : nil
        }
        guard samArgIndices.count == 1 else {
            return nil
        }
        let samArgIndex = samArgIndices[0]
        let samArgExpr = args[samArgIndex].expr

        var visibleCandidates = ctx.filterByVisibility(
            ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        ).visible
        if visibleCandidates.isEmpty {
            visibleCandidates = ctx.sema.symbols.lookupAll(fqName: [calleeName]).filter { candidate in
                guard let symbol = ctx.sema.symbols.symbol(candidate) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        }
        // Path 1: callee is a function/constructor whose single parameter is a
        // fun interface type (e.g. `apply({ ... })` where apply takes Transformer).
        let samCompatibleCandidates = visibleCandidates.filter { candidate in
            guard let signature = ctx.sema.symbols.functionSignature(for: candidate),
                  isCallableArityCompatible(signature: signature, argCount: args.count),
                  samArgIndex < signature.parameterTypes.count
            else {
                return false
            }
            return driver.helpers.samFunctionType(for: signature.parameterTypes[samArgIndex], sema: ctx.sema) != nil
        }
        let narrowedSamCandidates = narrowSamCandidates(
            samCompatibleCandidates,
            args: args,
            samArgIndex: samArgIndex,
            ctx: ctx,
            locals: &locals
        )

        if narrowedSamCandidates.count == 1,
           let signature = ctx.sema.symbols.functionSignature(for: narrowedSamCandidates[0])
        {
            var argTypes: [CallArg] = []
            argTypes.reserveCapacity(args.count)
            for (index, argument) in args.enumerated() {
                let parameterExpectedType = index < signature.parameterTypes.count ? signature.parameterTypes[index] : nil
                let inferredType = driver.inferExpr(
                    argument.expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: parameterExpectedType
                )
                argTypes.append(CallArg(label: argument.label, isSpread: argument.isSpread, type: inferredType))
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: narrowedSamCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: calleeName,
                    args: argTypes,
                    explicitTypeArgs: explicitTypeArgs
                ),
                expectedType: expectedType,
                implicitReceiverType: ctx.implicitReceiverType,
                ctx: ctx.semaCtx
            )
            if let diagnostic = resolved.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
                return ctx.sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                return nil
            }
            driver.helpers.checkDeprecation(
                for: chosen,
                sema: ctx.sema,
                interner: ctx.interner,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: chosen,
                ctx: ctx,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            return bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: ctx.sema)
        }

        // Path 2: SAM constructor — callee name is a fun interface
        // (e.g. `Transformer { it.uppercase() }`).
        if let samType = inferSamConstructorCallExpr(
            id,
            calleeName: calleeName,
            argExpr: samArgExpr,
            ctx: ctx,
            locals: &locals,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return samType
        }

        return nil
    }

    func narrowSamCandidates(
        _ candidates: [SymbolID],
        args: [CallArgument],
        samArgIndex: Int,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> [SymbolID] {
        guard candidates.count > 1 else {
            return candidates
        }

        var inferredNonSamArgTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() where index != samArgIndex {
            inferredNonSamArgTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }

        let narrowed = candidates.filter { candidate in
            guard let signature = ctx.sema.symbols.functionSignature(for: candidate),
                  isCallableArityCompatible(signature: signature, argCount: args.count)
            else {
                return false
            }
            for (index, inferredType) in inferredNonSamArgTypes {
                guard let parameterType = parameterTypeForArgument(
                    at: index,
                    in: signature
                ) else {
                    return false
                }
                if !ctx.sema.types.isSubtype(inferredType, parameterType) {
                    return false
                }
            }
            return true
        }

        return narrowed.isEmpty ? candidates : narrowed
    }

    func isCallableArityCompatible(signature: FunctionSignature, argCount: Int) -> Bool {
        let hasVararg = signature.valueParameterIsVararg.contains(true)
        let requiredCount = zip(signature.parameterTypes.indices, signature.valueParameterHasDefaultValues).reduce(0) { partial, entry in
            let (index, hasDefault) = entry
            if hasVararg, signature.valueParameterIsVararg[index] {
                return partial
            }
            return partial + (hasDefault ? 0 : 1)
        }
        if argCount < requiredCount {
            return false
        }
        if hasVararg {
            return true
        }
        return argCount <= signature.parameterTypes.count
    }

    func parameterTypeForArgument(
        at index: Int,
        in signature: FunctionSignature
    ) -> TypeID? {
        guard index >= 0 else {
            return nil
        }
        if index < signature.parameterTypes.count {
            return signature.parameterTypes[index]
        }
        guard let varargIndex = signature.valueParameterIsVararg.firstIndex(of: true),
              varargIndex < signature.parameterTypes.count,
              index >= varargIndex
        else {
            return nil
        }
        return signature.parameterTypes[varargIndex]
    }

    /// Handles `Transformer { ... }` — calling a fun interface name with a
    /// single trailing lambda produces an anonymous implementation of that
    /// interface by SAM conversion.
    private func inferSamConstructorCallExpr(
        _ id: ExprID,
        calleeName: InternedString,
        argExpr: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        // Look up the callee name as an interface symbol.
        let interfaceCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else { return false }
            return symbol.kind == .interface && symbol.flags.contains(.funInterface)
        }
        guard let interfaceSymID = interfaceCandidates.first else {
            return nil
        }
        let sema = ctx.sema
        let interfaceTypeParameters = sema.types.nominalTypeParameterSymbols(for: interfaceSymID)
        let interfaceArgs: [TypeArg]
        if explicitTypeArgs.isEmpty {
            interfaceArgs = []
        } else {
            guard explicitTypeArgs.count == interfaceTypeParameters.count else {
                return nil
            }
            interfaceArgs = explicitTypeArgs.map { .invariant($0) }
        }
        let interfaceType = sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymID,
            args: interfaceArgs,
            nullability: .nonNull
        )))
        guard let samFT = driver.helpers.samFunctionType(for: interfaceType, sema: sema) else {
            return nil
        }
        let samFTTypeID = sema.types.make(.functionType(samFT))

        // Infer the lambda against the SAM function type.
        _ = driver.inferExpr(
            argExpr,
            ctx: ctx,
            locals: &locals,
            expectedType: interfaceType
        )

        // Mark the lambda as SAM-converted and bind the underlying function type.
        sema.bindings.markSamConversion(argExpr)
        sema.bindings.bindSamUnderlyingFunctionType(argExpr, type: samFTTypeID)

        // The whole call expression has the interface type.
        sema.bindings.bindExprType(id, type: interfaceType)
        return interfaceType
    }

    private func isSamConvertibleArgument(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else {
            return false
        }
        switch expr {
        case .lambdaLiteral, .callableRef:
            return true
        default:
            return false
        }
    }
}
