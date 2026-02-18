import Foundation

extension TypeCheckSemaPassPhase {
    func inferLocalDeclExpr(
        _ id: ExprID,
        name: InternedString,
        isMutable: Bool,
        typeAnnotation: TypeRefID?,
        initializer: ExprID?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        var declaredType: TypeID?
        if let typeAnnotation {
            declaredType = resolveTypeRef(typeAnnotation, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
        }

        var initializerType: TypeID?
        if let initializer {
            initializerType = inferExpr(initializer, ctx: ctx, locals: &locals, expectedType: declaredType)
        }

        let localType: TypeID
        if let declaredType {
            localType = declaredType
            if let initializerType {
                emitSubtypeConstraint(
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
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let valueType = inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
        guard let local = locals[name] else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0013",
                "Unresolved local variable '\(interner.resolve(name))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        sema.bindings.bindIdentifier(id, symbol: local.symbol)
        if !local.isMutable && local.isInitialized {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0014",
                "Val cannot be reassigned.",
                range: range
            )
        } else {
            emitSubtypeConstraint(
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

    func inferArrayAccessExpr(
        _ id: ExprID,
        arrayExpr: ExprID,
        indexExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let arrayType = inferExpr(arrayExpr, ctx: ctx, locals: &locals, expectedType: nil)
        let indexType = inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: intType)
        emitSubtypeConstraint(
            left: indexType,
            right: intType,
            range: ast.arena.exprRange(indexExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        let elementType = arrayElementType(for: arrayType, sema: sema, interner: interner) ?? sema.types.anyType
        sema.bindings.bindExprType(id, type: elementType)
        return elementType
    }

    func inferArrayAssignExpr(
        _ id: ExprID,
        arrayExpr: ExprID,
        indexExpr: ExprID,
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let arrayType = inferExpr(arrayExpr, ctx: ctx, locals: &locals, expectedType: nil)
        let indexType = inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: intType)
        emitSubtypeConstraint(
            left: indexType,
            right: intType,
            range: ast.arena.exprRange(indexExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        let elementExpectedType = arrayElementType(for: arrayType, sema: sema, interner: interner)
        let valueType = inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: elementExpectedType)
        if let elementExpectedType {
            emitSubtypeConstraint(
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
