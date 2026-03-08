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

        guard visibleCandidates.count == 1,
              let signature = ctx.sema.symbols.functionSignature(for: visibleCandidates[0]),
              signature.parameterTypes.count == 1,
              driver.helpers.samFunctionType(for: signature.parameterTypes[0], sema: ctx.sema) != nil
        else {
            return nil
        }

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
