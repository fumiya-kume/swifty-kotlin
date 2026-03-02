import Foundation

// Handles local declaration and assignment type inference.
// Derived from TypeCheckSemaPhase+InferDecls.swift.

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

        let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)
        var indexTypes: [TypeID] = []
        for indexExpr in indices {
            indexTypes.append(driver.inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: nil))
        }
        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)

        let (elementType, operatorResolved) = resolveIndexedGetElement(
            id: id, receiverType: receiverType, indexTypes: indexTypes,
            range: range, ctx: ctx
        )

        if !operatorResolved {
            guard indices.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let intType = sema.types.make(.primitive(.int, .nonNull))
            driver.emitSubtypeConstraint(
                left: indexTypes[0], right: intType,
                range: ctx.ast.arena.exprRange(indices[0]) ?? range,
                solver: ConstraintSolver(), sema: sema, diagnostics: ctx.semaCtx.diagnostics
            )
        }

        let resultType = compoundOpResultType(
            op: op, elementType: elementType, valueType: valueType, sema: sema
        )
        driver.emitSubtypeConstraint(
            left: valueType, right: elementType,
            range: ctx.ast.arena.exprRange(valueExpr) ?? range,
            solver: ConstraintSolver(), sema: sema, diagnostics: ctx.semaCtx.diagnostics
        )
        driver.emitSubtypeConstraint(
            left: resultType, right: elementType, range: range,
            solver: ConstraintSolver(), sema: sema, diagnostics: ctx.semaCtx.diagnostics
        )

        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    /// Resolve `operator fun get` on the receiver and return (elementType, wasResolved).
    private func resolveIndexedGetElement(
        id: ExprID,
        receiverType: TypeID,
        indexTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> (TypeID, Bool) {
        let sema = ctx.sema
        let interner = ctx.interner
        let getName = interner.intern("get")
        let getCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: getName, receiverType: receiverType, sema: sema
        )
        let fallback = driver.helpers.arrayElementType(
            for: receiverType, sema: sema, interner: interner
        ) ?? sema.types.anyType

        guard !getCandidates.isEmpty else { return (fallback, false) }

        let callArgs = indexTypes.map { CallArg(type: $0) }
        let resolved = ctx.resolver.resolveCall(
            candidates: getCandidates,
            call: CallExpr(range: range, calleeName: getName, args: callArgs),
            expectedType: nil, implicitReceiverType: receiverType, ctx: ctx.semaCtx
        )
        guard let chosen = resolved.chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosen)
        else { return (fallback, false) }

        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: resolved.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue }).map(\.value),
            parameterMapping: resolved.parameterMapping
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let elementType = sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
        return (elementType, true)
    }

    /// Compute the result type for a compound binary operation on an indexed element.
    private func compoundOpResultType(
        op: CompoundAssignOp,
        elementType: TypeID,
        valueType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        let stringType = sema.types.stringType
        let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
        return switch underlyingOp {
        case .add:
            (elementType == stringType || valueType == stringType) ? stringType : elementType
        default:
            elementType
        }
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
            let paramType: TypeID = if let typeRefID = param.type {
                driver.helpers.resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            } else {
                sema.types.anyType
            }
            parameterTypes.append(paramType)
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: param.name,
                fqName: [
                    interner.intern("__localfun_\(id.rawValue)"),
                    param.name,
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            sema.symbols.setPropertyType(paramType, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        let resolvedReturnType: TypeID = if let returnTypeRef {
            driver.helpers.resolveTypeRef(returnTypeRef, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
        } else {
            sema.types.unitType
        }

        let funSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: [
                interner.intern("__localfun_\(id.rawValue)"),
                name,
            ],
            declSite: range,
            visibility: .private,
            flags: []
        )

        let signature = FunctionSignature(
            parameterTypes: parameterTypes,
            returnType: resolvedReturnType,
            valueParameterSymbols: paramSymbols,
            valueParameterHasDefaultValues: valueParams.map(\.hasDefaultValue),
            valueParameterIsVararg: valueParams.map(\.isVararg)
        )
        sema.symbols.setFunctionSignature(signature, for: funSymbol)

        let funType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: resolvedReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))

        // Local functions introduce a new scope for control flow: reset loop/lambda stacks.
        var bodyLocals = locals; let bodyCtx = ctx.copying(loopDepth: 0, loopLabelStack: [], lambdaLabelStack: [])
        for (i, param) in valueParams.enumerated() {
            bodyLocals[param.name] = (parameterTypes[i], paramSymbols[i], false, true)
        }
        bodyLocals[name] = (funType, funSymbol, false, true)
        switch body {
        case let .block(exprs, _):
            for (index, expr) in exprs.enumerated() {
                let isLast = index == exprs.count - 1
                let expected = isLast ? resolvedReturnType : nil
                _ = driver.inferExpr(expr, ctx: bodyCtx, locals: &bodyLocals, expectedType: expected)
            }
        case let .expr(exprID, _):
            _ = driver.inferExpr(exprID, ctx: bodyCtx, locals: &bodyLocals, expectedType: resolvedReturnType)
        case .unit:
            break
        }
        locals[name] = (funType, funSymbol, false, true)
        sema.bindings.bindIdentifier(id, symbol: funSymbol)
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
