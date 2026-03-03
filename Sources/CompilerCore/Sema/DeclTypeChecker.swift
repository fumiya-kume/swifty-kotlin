import Foundation

/// Handles declaration-level type checking (functions, properties, classes, objects).
/// Derived from TypeCheckSemaPass.swift (second extension) and TypeCheckSemaPass+DeclTypeCheck.swift.
final class DeclTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    // MARK: - Function Body Type Inference (from +DeclTypeCheck.swift)

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

    // MARK: - Property Type Checking (from +DeclTypeCheck.swift)

    func typeCheckPropertyDecl(
        _ property: PropertyDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        let interner = ctx.interner
        var inferredPropertyType: TypeID? = property.type != nil ? sema.symbols.propertyType(for: symbol) : nil

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

        if let getter = property.getter {
            var getterLocals: LocalBindings = [:]
            if let fieldType = inferredPropertyType {
                let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                getterLocals[interner.intern("field")] = (fieldType, fieldSymbol, true, true)
            }
            let getterType = inferFunctionBodyType(
                getter.body, ctx: ctx, locals: &getterLocals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                driver.emitSubtypeConstraint(
                    left: getterType, right: declaredType,
                    range: getter.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = getterType
            }
        }

        if let delegateExpr = property.delegateExpression {
            var delegateLocals: LocalBindings = [:]
            let delegateType = driver.inferExpr(
                delegateExpr, ctx: ctx, locals: &delegateLocals,
                expectedType: nil
            )

            // Record the delegate type on the property symbol so the KIR
            // lowering phase can synthesise getValue/setValue calls.
            sema.symbols.setPropertyType(delegateType, for: SymbolID(rawValue: -(symbol.rawValue + 50000)))

            // Resolve getValue operator on the delegate type to infer the
            // property type from its return type (Kotlin spec J12).
            let getValueName = interner.intern("getValue")
            let getValueCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: getValueName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            if let getValueSymbol = getValueCandidates.first,
               let getValueSig = sema.symbols.functionSignature(for: getValueSymbol)
            {
                // Use getValue return type to infer the property type when
                // no explicit type annotation is provided.
                if inferredPropertyType == nil {
                    inferredPropertyType = getValueSig.returnType
                }
            }

            // Fallback: if no getValue was resolved and no explicit type,
            // use Any? as the property type.
            if inferredPropertyType == nil {
                inferredPropertyType = sema.types.nullableAnyType
            }

            // For var properties, also check that setValue operator exists.
            if property.isVar {
                let setValueName = interner.intern("setValue")
                let setValueCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: setValueName,
                    receiverType: delegateType,
                    sema: sema
                ).filter { candidateID in
                    guard let sym = sema.symbols.symbol(candidateID) else { return false }
                    return sym.flags.contains(.operatorFunction)
                }
                _ = setValueCandidates // Validate existence; diagnostic emitted elsewhere if needed.
            }

            // Check for provideDelegate operator on the delegate type.
            let provideDelegateName = interner.intern("provideDelegate")
            let provideDelegateCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: provideDelegateName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            // Record provideDelegate availability so the KIR lowering phase
            // can emit the provideDelegate call for top-level properties.
            if !provideDelegateCandidates.isEmpty {
                sema.symbols.setHasProvideDelegate(for: symbol)
            }
        }

        let finalPropertyType = inferredPropertyType ?? sema.types.nullableAnyType
        sema.symbols.setPropertyType(finalPropertyType, for: symbol)

        if let setter = property.setter {
            if !property.isVar {
                diagnostics.error(
                    "KSWIFTK-SEMA-0005",
                    "Setter is not allowed for read-only property.",
                    range: setter.range
                )
            }
            var setterLocals: LocalBindings = [:]
            let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
            setterLocals[interner.intern("field")] = (finalPropertyType, fieldSymbol, true, true)
            let parameterName = setter.parameterName ?? interner.intern("value")
            let setterValueSymbol = SyntheticSymbolScheme.semaSetterValueSymbol(for: symbol)
            setterLocals[parameterName] = (finalPropertyType, setterValueSymbol, true, true)
            let setterType = inferFunctionBodyType(
                setter.body, ctx: ctx, locals: &setterLocals,
                expectedType: sema.types.unitType
            )
            driver.emitSubtypeConstraint(
                left: setterType, right: sema.types.unitType,
                range: setter.range, solver: solver,
                sema: sema, diagnostics: diagnostics
            )
        }
    }
}
