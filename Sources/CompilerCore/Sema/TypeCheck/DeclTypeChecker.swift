import Foundation

/// Handles declaration-level type checking (functions, properties, classes, objects).
final class DeclTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    // MARK: - Function Body Type Inference

    func inferFunctionBodyType(
        _ body: FunctionBody,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        switch body {
        case .unit:
            return ctx.sema.types.unitType

        case let .expr(exprID, _):
            return driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .block(exprIDs, _):
            var last = ctx.sema.types.unitType
            var reachedNothing = false
            for exprID in exprIDs {
                if reachedNothing {
                    if let stmtRange = ctx.ast.arena.exprRange(exprID) {
                        ctx.semaCtx.diagnostics.warning(
                            "KSWIFTK-SEMA-0096",
                            "Unreachable code.",
                            range: stmtRange
                        )
                    }
                    _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: nil)
                    continue
                }
                // Pass expectedType to return expressions (so the return value is
                // checked against the function return type) and to the last expression
                // (which determines the block's result type for expression-body inference).
                let exprExpectedType: TypeID? = if let expr = ctx.ast.arena.expr(exprID), case .returnExpr = expr {
                    expectedType
                } else if exprID == exprIDs.last {
                    expectedType
                } else {
                    nil
                }
                last = driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: exprExpectedType)
                if last == ctx.sema.types.nothingType {
                    reachedNothing = true
                }
            }
            return reachedNothing ? ctx.sema.types.nothingType : last
        }
    }

    // MARK: - Property Type Checking

    func typeCheckPropertyDecl(
        _ property: PropertyDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        var inferredPropertyType: TypeID? = property.type != nil
            ? sema.symbols.propertyType(for: symbol)
            : nil

        if let initializer = property.initializer {
            var locals: LocalBindings = [:]
            let initializerType = driver.inferExpr(
                initializer, ctx: ctx, locals: &locals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                driver.emitSubtypeConstraint(
                    left: initializerType, right: declaredType,
                    range: property.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = initializerType
            }
        }

        // For extension properties, set the implicit receiver type so
        // that `this` resolves correctly inside getter/setter bodies.
        let extRecv = sema.symbols
            .extensionPropertyReceiverType(for: symbol)
        let accessorCtx: TypeInferenceContext = if let extRecv {
            ctx.copying(implicitReceiverType: extRecv)
        } else {
            ctx
        }

        if let getter = property.getter {
            inferredPropertyType = typeCheckGetter(
                getter, symbol: symbol,
                inferredPropertyType: inferredPropertyType,
                accessorCtx: accessorCtx, solver: solver,
                diagnostics: diagnostics
            )
        }

        if let delegateExpr = property.delegateExpression {
            inferredPropertyType = typeCheckDelegate(
                delegateExpr, property: property,
                symbol: symbol,
                inferredPropertyType: inferredPropertyType,
                ctx: ctx
            )
        }

        let finalPropertyType = inferredPropertyType
            ?? sema.types.nullableAnyType
        sema.symbols.setPropertyType(finalPropertyType, for: symbol)

        if let setter = property.setter {
            typeCheckSetter(
                setter, property: property, symbol: symbol,
                finalPropertyType: finalPropertyType,
                accessorCtx: accessorCtx, solver: solver,
                diagnostics: diagnostics
            )
        }
    }
}
