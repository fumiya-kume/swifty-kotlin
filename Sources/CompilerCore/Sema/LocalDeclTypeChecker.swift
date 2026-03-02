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
                name,
            ],
            declSite: range,
            visibility: .private,
            flags: isMutable ? [.mutable] : []
        )
        locals[name] = (localType, localSymbol, isMutable, initializer != nil)
        sema.bindings.bindIdentifier(id, symbol: localSymbol)
        // Propagate collection marks through local variable declarations
        // so that `val list = listOf(1,2,3); list.size` still recognizes
        // `list` as a collection receiver (P5-84).
        if let initializer, sema.bindings.isCollectionExpr(initializer) {
            sema.bindings.markCollectionExpr(id)
            sema.bindings.markCollectionSymbol(localSymbol)
        }
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
        let interner = ctx.interner

        let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
        if let local = locals[name] {
            ctx.sema.bindings.bindIdentifier(id, symbol: local.symbol)
            if !local.isMutable, local.isInitialized {
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
                    sema: ctx.sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                locals[name] = (local.type, local.symbol, local.isMutable, true)
            }
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }

        // Fall back to scope-visible property lookup for assignments like
        // `counter = counter + 1` where `counter` is a top-level var or a
        // member property accessed via implicit receiver (inside a
        // class/object member function).
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let (visibleIDs, _) = ctx.filterByVisibility(allCandidateIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        if let propSymbol = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let parentID = ctx.sema.symbols.parentSymbol(for: sym.id),
                  let parentSym = ctx.sema.symbols.symbol(parentID) else { return true }
            return parentSym.kind == .package || (ctx.implicitReceiverType != nil
                && (parentSym.kind == .class || parentSym.kind == .object || parentSym.kind == .interface))
        }) {
            ctx.sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            let propType = ctx.sema.symbols.propertyType(for: propSymbol.id) ?? ctx.sema.types.anyType
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
                    sema: ctx.sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }

        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0013",
            "Unresolved local variable '\(interner.resolve(name))'.",
            range: range
        )
        ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
        return ctx.sema.types.errorType
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
}
