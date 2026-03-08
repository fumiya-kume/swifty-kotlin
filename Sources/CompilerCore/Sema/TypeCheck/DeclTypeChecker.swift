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

        if property.modifiers.contains(.lateinit) {
            validateLateinitProperty(
                property,
                finalPropertyType: finalPropertyType,
                diagnostics: diagnostics,
                sema: sema
            )
        }

        if let setter = property.setter {
            typeCheckSetter(
                setter, property: property, symbol: symbol,
                finalPropertyType: finalPropertyType,
                accessorCtx: accessorCtx, solver: solver,
                diagnostics: diagnostics
            )
        }
    }

    private func validateLateinitProperty(
        _ property: PropertyDecl,
        finalPropertyType: TypeID,
        diagnostics: DiagnosticEngine,
        sema: SemaModule
    ) {
        if !property.isVar {
            diagnostics.error(
                "KSWIFTK-SEMA-LATEINIT",
                "'lateinit' is only allowed on mutable properties.",
                range: property.range
            )
        }
        if property.initializer != nil {
            diagnostics.error(
                "KSWIFTK-SEMA-LATEINIT",
                "'lateinit' property must not have an initializer.",
                range: property.range
            )
        }
        if property.type == nil {
            diagnostics.error(
                "KSWIFTK-SEMA-LATEINIT",
                "'lateinit' property must declare an explicit non-null reference type.",
                range: property.range
            )
        }

        switch sema.types.kind(of: finalPropertyType) {
        case let .primitive(primitive, nullability):
            if nullability == .nullable {
                diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' property type must be non-null.",
                    range: property.range
                )
            } else if primitive == .boolean
                || primitive == .char
                || primitive == .int
                || primitive == .long
                || primitive == .float
                || primitive == .double
                || primitive == .uint
                || primitive == .ulong
                || primitive == .ubyte
                || primitive == .ushort
            {
                diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' is not allowed on primitive property types.",
                    range: property.range
                )
            }
        case let .classType(classType):
            if classType.nullability == .nullable {
                diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' property type must be non-null.",
                    range: property.range
                )
            }
        case let .typeParam(typeParam):
            if typeParam.nullability == .nullable {
                diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' property type must be non-null.",
                    range: property.range
                )
            }
        case let .functionType(functionType):
            if functionType.nullability == .nullable {
                diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' property type must be non-null.",
                    range: property.range
                )
            }
        case let .nothing(nullability):
            if nullability == .nullable {
                diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' property type must be non-null.",
                    range: property.range
                )
            }
        case let .any(nullability):
            if nullability == .nullable {
                diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' property type must be non-null.",
                    range: property.range
                )
            }
        case .error, .unit, .intersection:
            break
        }
    }
}
