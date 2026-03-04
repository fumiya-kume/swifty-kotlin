import Foundation

// swiftlint:disable function_body_length function_parameter_count

// Indexed access and assignment type inference.
// Split from LocalDeclTypeChecker+Part2.swift to satisfy file_length limit.

extension LocalDeclTypeChecker {
    func inferIndexedAccessExpr(
        _ id: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)

        // Try to resolve operator fun get on the receiver type
        let getName = interner.intern("get")
        let getCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: getName,
            receiverType: receiverType,
            sema: sema
        )

        // Infer all index expressions without forcing Int.
        // Int constraint is only applied in the built-in array fallback.
        var indexTypes: [TypeID] = []
        for indexExpr in indices {
            let indexType = driver.inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: nil)
            indexTypes.append(indexType)
        }

        if !getCandidates.isEmpty {
            // Resolve via operator fun get
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
               let signature = sema.symbols.functionSignature(for: chosen)
            {
                // Record the resolved call so KIR lowering can dispatch correctly
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
                // Substitute type parameters in the return type so that
                // generic get() calls (e.g. List<String?>.get()) return
                // the concrete element type (String?) instead of T.
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                let returnType = sema.types.substituteTypeParameters(
                    in: signature.returnType,
                    substitution: resolved.substitutedTypeArguments,
                    typeVarBySymbol: typeVarBySymbol
                )
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
            }
        }

        // Fallback: built-in array access (single Int index only)
        guard indices.count == 1 else {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        driver.emitSubtypeConstraint(
            left: indexTypes[0],
            right: intType,
            range: ast.arena.exprRange(indices[0]) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        let elementType = driver.helpers.arrayElementType(
            for: receiverType, sema: sema, interner: interner
        ) ?? sema.types.anyType
        sema.bindings.bindExprType(id, type: elementType)
        return elementType
    }

    func inferIndexedAssignExpr(
        _ id: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)

        // Try to resolve operator fun set on the receiver type
        let setName = interner.intern("set")
        let setCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: setName,
            receiverType: receiverType,
            sema: sema
        )

        // Infer all index expressions without forcing Int.
        // Int constraint is only applied in the built-in array fallback.
        var indexTypes: [TypeID] = []
        for indexExpr in indices {
            let indexType = driver.inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: nil)
            indexTypes.append(indexType)
        }

        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)

        if !setCandidates.isEmpty {
            // Resolve via operator fun set
            var callArgTypes = indexTypes
            callArgTypes.append(valueType)
            let callArgs = callArgTypes.map { CallArg(type: $0) }
            let resolved = ctx.resolver.resolveCall(
                candidates: setCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: setName,
                    args: callArgs
                ),
                expectedType: nil,
                implicitReceiverType: receiverType,
                ctx: ctx.semaCtx
            )
            if let chosen = resolved.chosenCallee {
                // Record the resolved call so KIR lowering can dispatch correctly
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
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
        }

        // Fallback: built-in array assign (single Int index only)
        guard indices.count == 1 else {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        driver.emitSubtypeConstraint(
            left: indexTypes[0],
            right: intType,
            range: ast.arena.exprRange(indices[0]) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        let elementExpectedType = driver.helpers.arrayElementType(
            for: receiverType, sema: sema, interner: interner
        )
        if let elementExpectedType {
            driver.emitSubtypeConstraint(
                left: valueType,
                right: elementExpectedType,
                range: ast.arena.exprRange(valueExpr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}

// swiftlint:enable function_body_length function_parameter_count
