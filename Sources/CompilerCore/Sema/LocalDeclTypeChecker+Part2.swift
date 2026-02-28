import Foundation

/// Handles local declaration and assignment type inference.
/// Derived from TypeCheckSemaPhase+InferDecls.swift.

extension LocalDeclTypeChecker {
    func inferIndexedCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        let stringType = sema.types.stringType

        let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)

        // Infer index types without forcing Int.
        // Int constraint is only applied in the built-in array fallback.
        var indexTypes: [TypeID] = []
        for indexExpr in indices {
            let indexType = driver.inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: nil)
            indexTypes.append(indexType)
        }

        // Infer value type
        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)

        // Resolve get via proper overload resolution to determine element type
        let getName = interner.intern("get")
        let getCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: getName,
            receiverType: receiverType,
            sema: sema
        )
        var elementType: TypeID = driver.helpers.arrayElementType(for: receiverType, sema: sema, interner: interner) ?? sema.types.anyType
        var operatorResolved = false
        if !getCandidates.isEmpty {
            let callArgs = indexTypes.map { CallArg(type: $0) }
            let resolved = ctx.resolver.resolveCall(
                candidates: getCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: getName,
                    args: callArgs
                ),
                expectedType: nil,
                implicitReceiverType: receiverType,
                ctx: ctx.semaCtx
            )
            if let chosen = resolved.chosenCallee,
               let signature = sema.symbols.functionSignature(for: chosen) {
                // Record the resolved get call so KIR lowering can dispatch correctly
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: resolved.substitutedTypeArguments
                            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                            .map(\.value),
                        parameterMapping: resolved.parameterMapping
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                elementType = signature.returnType
                operatorResolved = true
            }
        }

        // Fallback: built-in array (single Int index only)
        if !operatorResolved {
            guard indices.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
        }

        // Built-in array fallback: enforce Int index constraint (matching inferIndexedAccessExpr/inferIndexedAssignExpr)
        if !operatorResolved {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            driver.emitSubtypeConstraint(
                left: indexTypes[0],
                right: intType,
                range: ctx.ast.arena.exprRange(indices[0]) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }

        // Determine the result type of the compound binary operation
        let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
        let resultType: TypeID
        switch underlyingOp {
        case .add:
            resultType = (elementType == stringType || valueType == stringType) ? stringType : elementType
        case .subtract, .multiply, .divide, .modulo:
            resultType = elementType
        default:
            resultType = elementType
        }

        // Emit constraint: value must be compatible with element type
        driver.emitSubtypeConstraint(
            left: valueType,
            right: elementType,
            range: ctx.ast.arena.exprRange(valueExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )

        // Emit constraint: result of binary op must be compatible with element type for set
        driver.emitSubtypeConstraint(
            left: resultType,
            right: elementType,
            range: range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )

        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferLocalFunDeclExpr(
        _ id: ExprID,
        name: InternedString,
        valueParams: [ValueParamDecl],
        returnTypeRef: TypeRefID?,
        body: FunctionBody,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        var parameterTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        for param in valueParams {
            let paramType: TypeID
            if let typeRefID = param.type {
                paramType = driver.helpers.resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            } else {
                paramType = sema.types.anyType
            }
            parameterTypes.append(paramType)
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: param.name,
                fqName: [
                    interner.intern("__localfun_\(id.rawValue)"),
                    param.name
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            sema.symbols.setPropertyType(paramType, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        let resolvedReturnType: TypeID
        if let returnTypeRef {
            resolvedReturnType = driver.helpers.resolveTypeRef(returnTypeRef, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
        } else {
            resolvedReturnType = sema.types.unitType
        }

        let funSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: [
                interner.intern("__localfun_\(id.rawValue)"),
                name
            ],
            declSite: range,
            visibility: .private,
            flags: []
        )

        let signature = FunctionSignature(
            parameterTypes: parameterTypes,
            returnType: resolvedReturnType,
            valueParameterSymbols: paramSymbols,
            valueParameterHasDefaultValues: valueParams.map { $0.hasDefaultValue },
            valueParameterIsVararg: valueParams.map { $0.isVararg }
        )
        sema.symbols.setFunctionSignature(signature, for: funSymbol)

        let funType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: resolvedReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))

        var bodyLocals = locals
        for (i, param) in valueParams.enumerated() {
            bodyLocals[param.name] = (parameterTypes[i], paramSymbols[i], false, true)
        }
        bodyLocals[name] = (funType, funSymbol, false, true)
        switch body {
        case .block(let exprs, _):
            for (index, expr) in exprs.enumerated() {
                let isLast = index == exprs.count - 1
                let expected = isLast ? resolvedReturnType : nil
                _ = driver.inferExpr(expr, ctx: ctx, locals: &bodyLocals, expectedType: expected)
            }
        case .expr(let exprID, _):
            _ = driver.inferExpr(exprID, ctx: ctx, locals: &bodyLocals, expectedType: resolvedReturnType)
        case .unit:
            break
        }
        locals[name] = (funType, funSymbol, false, true)
        sema.bindings.bindIdentifier(id, symbol: funSymbol)
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
