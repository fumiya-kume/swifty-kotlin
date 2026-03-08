import Foundation

// Property accessor type-checking helpers extracted from DeclTypeChecker
// to keep the main file within SwiftLint length limits.

extension DeclTypeChecker {
    func typeCheckGetter(
        _ getter: PropertyAccessorDecl,
        symbol: SymbolID,
        inferredPropertyType: TypeID?,
        accessorCtx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) -> TypeID? {
        let sema = accessorCtx.sema
        let interner = accessorCtx.interner
        var getterLocals: LocalBindings = [:]
        if let fieldType = inferredPropertyType {
            let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
            getterLocals[interner.intern("field")] = (fieldType, fieldSymbol, true, true)
        }
        let getterType = inferFunctionBodyType(
            getter.body, ctx: accessorCtx, locals: &getterLocals,
            expectedType: inferredPropertyType
        )
        if let declaredType = inferredPropertyType {
            driver.emitSubtypeConstraint(
                left: getterType, right: declaredType,
                range: getter.range, solver: solver,
                sema: sema, diagnostics: diagnostics
            )
            return inferredPropertyType
        }
        return getterType
    }

    func typeCheckDelegate(
        _ delegateExpr: ExprID,
        property: PropertyDecl,
        symbol: SymbolID,
        inferredPropertyType: TypeID?,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        var result = inferredPropertyType
        var delegateLocals: LocalBindings = [:]
        let delegateType = driver.inferExpr(
            delegateExpr, ctx: ctx, locals: &delegateLocals,
            expectedType: nil
        )

        // Record the delegate type for KIR lowering.
        sema.symbols.setPropertyType(
            delegateType,
            for: SymbolID(rawValue: -(symbol.rawValue + 50000))
        )

        // Resolve getValue operator (Kotlin spec J12).
        let getValueName = interner.intern("getValue")
        let getValueCandidates = driver.helpers
            .collectMemberFunctionCandidates(
                named: getValueName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID)
                else { return false }
                return sym.flags.contains(.operatorFunction)
            }
        if let getValueSymbol = getValueCandidates.first,
           let getValueSig = sema.symbols.functionSignature(
               for: getValueSymbol
           ), result == nil
        {
            sema.symbols.setDelegateGetValueSymbol(getValueSymbol, for: symbol)
            result = getValueSig.returnType
        } else if let getValueSymbol = getValueCandidates.first {
            sema.symbols.setDelegateGetValueSymbol(getValueSymbol, for: symbol)
        }
        if result == nil {
            result = sema.types.nullableAnyType
        }

        // Check setValue for var properties.
        if property.isVar {
            let setValueName = interner.intern("setValue")
            let setValueCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: setValueName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID)
                else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            if let setValueSymbol = setValueCandidates.first {
                sema.symbols.setDelegateSetValueSymbol(setValueSymbol, for: symbol)
            }
        }

        // Check provideDelegate operator.
        let provideDelegateName = interner.intern("provideDelegate")
        let provideDelegateCandidates = driver.helpers
            .collectMemberFunctionCandidates(
                named: provideDelegateName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID)
                else { return false }
                return sym.flags.contains(.operatorFunction)
            }
        if !provideDelegateCandidates.isEmpty {
            sema.symbols.setHasProvideDelegate(for: symbol)
            if let provideDelegateSymbol = provideDelegateCandidates.first {
                sema.symbols.setDelegateProvideDelegateSymbol(provideDelegateSymbol, for: symbol)
            }
        }

        return result
    }

    func typeCheckSetter(
        _ setter: PropertyAccessorDecl,
        property: PropertyDecl,
        symbol: SymbolID,
        finalPropertyType: TypeID,
        accessorCtx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = accessorCtx.sema
        let interner = accessorCtx.interner
        if !property.isVar {
            diagnostics.error(
                "KSWIFTK-SEMA-0005",
                "Setter is not allowed for read-only property.",
                range: setter.range
            )
        }
        var setterLocals: LocalBindings = [:]
        let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol)
            ?? symbol
        setterLocals[interner.intern("field")] = (
            finalPropertyType, fieldSymbol, true, true
        )
        let parameterName = setter.parameterName
            ?? interner.intern("value")
        let setterValueSymbol = SyntheticSymbolScheme
            .semaSetterValueSymbol(for: symbol)
        setterLocals[parameterName] = (
            finalPropertyType, setterValueSymbol, true, true
        )
        let setterType = inferFunctionBodyType(
            setter.body, ctx: accessorCtx, locals: &setterLocals,
            expectedType: sema.types.unitType
        )
        driver.emitSubtypeConstraint(
            left: setterType, right: sema.types.unitType,
            range: setter.range, solver: solver,
            sema: sema, diagnostics: diagnostics
        )
    }
}
