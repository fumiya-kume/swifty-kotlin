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
        let sema = ctx.sema
        let interner = ctx.interner

        let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
        if let local = locals[name] {
            sema.bindings.bindIdentifier(id, symbol: local.symbol)
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
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                locals[name] = (local.type, local.symbol, local.isMutable, true)
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        return assignToScopeProperty(
            id, name: name, valueType: valueType,
            range: range, ctx: ctx
        )
    }

    /// Resolve a simple assignment (`name = value`) against scope-visible
    /// properties when no matching local variable exists.  Accepts top-level
    /// properties and member properties when inside a class/object member
    /// function context (implicit receiver is non-nil).
    func assignToScopeProperty(
        _ id: ExprID,
        name: InternedString,
        valueType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let (visibleIDs, _) = ctx.filterByVisibility(allCandidateIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        let hasReceiver = ctx.implicitReceiverType != nil
        if let prop = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let pid = sema.symbols.parentSymbol(for: sym.id),
                  let p = sema.symbols.symbol(pid) else { return true }
            if p.kind == .package { return true }
            if hasReceiver {
                return p.kind == .class
                    || p.kind == .object
                    || p.kind == .interface
            }
            return false
        }) {
            sema.bindings.bindIdentifier(id, symbol: prop.id)
            let propType = sema.symbols.propertyType(for: prop.id)
                ?? sema.types.anyType
            if !prop.flags.contains(.mutable) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                driver.emitSubtypeConstraint(
                    left: valueType, right: propType,
                    range: range, solver: ConstraintSolver(),
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
}
