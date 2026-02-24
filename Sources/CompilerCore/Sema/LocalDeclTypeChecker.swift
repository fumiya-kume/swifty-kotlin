import Foundation

/// Handles local declaration and assignment type inference.
/// Derived from TypeCheckSemaPass+InferDecls.swift.
final class LocalDeclTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    func inferLocalDeclExpr(
        _ id: ExprID,
        name: InternedString,
        isMutable: Bool,
        typeAnnotation: TypeRefID?,
        initializer: ExprID?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        var declaredType: TypeID?
        if let typeAnnotation {
            declaredType = driver.helpers.resolveTypeRef(typeAnnotation, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
        }

        var initializerType: TypeID?
        if let initializer {
            initializerType = driver.inferExpr(initializer, ctx: ctx, locals: &locals, expectedType: declaredType)
        }

        let localType: TypeID
        if let declaredType {
            localType = declaredType
            if let initializerType {
                driver.emitSubtypeConstraint(
                    left: initializerType, right: declaredType,
                    range: range, solver: ConstraintSolver(),
                    sema: sema, diagnostics: ctx.semaCtx.diagnostics
                )
            }
        } else if let initializerType {
            localType = initializerType
        } else {
            localType = sema.types.errorType
        }

        let localSymbol = sema.symbols.define(
            kind: .local,
            name: name,
            fqName: [
                ctx.interner.intern("__local_\(id.rawValue)"),
                name
            ],
            declSite: range,
            visibility: .private,
            flags: isMutable ? [.mutable] : []
        )
        locals[name] = (localType, localSymbol, isMutable, initializer != nil)
        sema.bindings.bindIdentifier(id, symbol: localSymbol)
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferLocalAssignExpr(
        _ id: ExprID,
        name: InternedString,
        value: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
        if let local = locals[name] {
            sema.bindings.bindIdentifier(id, symbol: local.symbol)
            if !local.isMutable && local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                driver.emitSubtypeConstraint(
                    left: valueType,
                    right: local.type,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                locals[name] = (local.type, local.symbol, local.isMutable, true)
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // Fall back to top-level property lookup for assignments like `counter = counter + 1`
        // where `counter` is a top-level var, not a local variable.
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let (visibleIDs, _) = ctx.filterByVisibility(allCandidateIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        // Only match top-level properties (parent is a package), not class member properties.
        if let propSymbol = candidates.first(where: { sym in
            sym.kind == .property &&
            sema.symbols.parentSymbol(for: sym.id).flatMap({ sema.symbols.symbol($0) }).map({ $0.kind == .package }) == true
        }) {
            sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            let propType = sema.symbols.propertyType(for: propSymbol.id) ?? sema.types.anyType
            if !propSymbol.flags.contains(.mutable) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                driver.emitSubtypeConstraint(
                    left: valueType,
                    right: propType,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0013",
            "Unresolved local variable '\(interner.resolve(name))'.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

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
               let signature = sema.symbols.functionSignature(for: chosen) {
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
                sema.bindings.bindExprType(id, type: signature.returnType)
                return signature.returnType
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
        let elementType = driver.helpers.arrayElementType(for: receiverType, sema: sema, interner: interner) ?? sema.types.anyType
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
        let elementExpectedType = driver.helpers.arrayElementType(for: receiverType, sema: sema, interner: interner)
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
