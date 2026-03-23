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
        guard let argExpr = args.only?.expr,
              isSamConvertibleArgument(argExpr, ast: ctx.ast)
        else {
            return nil
        }

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
        if visibleCandidates.count == 1,
           let signature = ctx.sema.symbols.functionSignature(for: visibleCandidates[0]),
           signature.parameterTypes.count == 1,
           driver.helpers.samFunctionType(for: signature.parameterTypes[0], sema: ctx.sema) != nil
        {
            let argType = driver.inferExpr(
                argExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: signature.parameterTypes[0]
            )
            let resolved = ctx.resolver.resolveCall(
                candidates: visibleCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: calleeName,
                    args: [CallArg(label: args[0].label, isSpread: args[0].isSpread, type: argType)],
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
            return bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: ctx.sema)
        }

        // Path 2: SAM constructor — callee name is a fun interface
        // (e.g. `Transformer { it.uppercase() }`).
        if let samType = inferSamConstructorCallExpr(
            id,
            calleeName: calleeName,
            argExpr: argExpr,
            range: range,
            ctx: ctx,
            locals: &locals
        ) {
            return samType
        }

        return nil
    }

    /// Handles `Transformer { ... }` — calling a fun interface name with a
    /// single trailing lambda produces an anonymous implementation of that
    /// interface by SAM conversion.
    private func inferSamConstructorCallExpr(
        _ id: ExprID,
        calleeName: InternedString,
        argExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        // Look up the callee name as an interface symbol.
        let interfaceCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else { return false }
            return symbol.kind == .interface && symbol.flags.contains(.funInterface)
        }
        guard let interfaceSymID = interfaceCandidates.first,
              let interfaceSym = ctx.cachedSymbol(interfaceSymID)
        else {
            return nil
        }
        let sema = ctx.sema
        let interfaceType = sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymID,
            args: [],
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

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
