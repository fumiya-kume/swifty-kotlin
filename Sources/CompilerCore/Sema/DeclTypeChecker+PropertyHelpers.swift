import Foundation

// Property accessor type-checking helpers extracted from DeclTypeChecker
// to keep the main file within SwiftLint length limits.

extension DeclTypeChecker {
    // swiftlint:disable:next function_parameter_count
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

    // swiftlint:disable:next function_body_length
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
        // swiftlint:disable:next opening_brace
        if let getValueSymbol = getValueCandidates.first,
           let getValueSig = sema.symbols.functionSignature(
               for: getValueSymbol
           ), result == nil
        {
            result = getValueSig.returnType
        }
        if result == nil {
            result = sema.types.nullableAnyType
        }

        // Check setValue for var properties.
        if property.isVar {
            let setValueName = interner.intern("setValue")
            _ = driver.helpers.collectMemberFunctionCandidates(
                named: setValueName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID)
                else { return false }
                return sym.flags.contains(.operatorFunction)
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
        }

        return result
    }

    // swiftlint:disable:next function_parameter_count
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

    // MARK: - Top-Level Decl Type Checking (from TypeCheckSemaPass.swift second extension)

    // swiftlint:disable:next function_body_length
    func typeCheckFunctionDecl(
        _ function: FunDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        guard let signature = sema.symbols.functionSignature(for: symbol) else {
            return
        }

        var locals: LocalBindings = [:]
        for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            guard let param = sema.symbols.symbol(paramSymbol) else {
                continue
            }
            let type = index < signature.parameterTypes.count
                ? signature.parameterTypes[index]
                : sema.types.anyType
            locals[param.name] = (type, paramSymbol, false, true)
        }

        let functionScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
        for typeParameterSymbol in signature.typeParameterSymbols {
            functionScope.insert(typeParameterSymbol)
        }
        let functionCtx = ctx.copying(scope: functionScope, implicitReceiverType: signature.receiverType)
        let bodyType = inferFunctionBodyType(
            function.body,
            ctx: functionCtx,
            locals: &locals,
            expectedType: signature.returnType
        )
        driver.emitSubtypeConstraint(
            left: bodyType,
            right: signature.returnType,
            range: function.range,
            solver: solver,
            sema: sema,
            diagnostics: diagnostics
        )

        // When inferring return type for functions without explicit annotation:
        // - Skip if bodyType is error (broken code)
        // - Skip if bodyType is Nothing AND the body is a block ending with a
        //   control-flow statement (return/break/continue), because Nothing here
        //   reflects control flow, not the function's logical return type.
        // - Allow Nothing for .expr bodies (e.g. `fun f() = throw ...`) and for
        //   .block bodies ending with throw or a Nothing-returning call, since
        //   these genuinely diverge.
        let skipSignatureUpdate = if bodyType == sema.types.errorType {
            true
        } else if bodyType == sema.types.nothingType {
            switch function.body {
            case .block:
                // Block-body functions without explicit return type should not have
                // their return type inferred as Nothing. In Kotlin, block-body
                // functions default to Unit. Nothing can arise from control flow
                // (return/break/continue), throw, compound expressions where all
                // branches return, etc. Return value type checking is already
                // handled at the returnExpr level, so skipping here is safe.
                true
            case .expr, .unit:
                // Expression-body functions (e.g. `fun f() = throw ...`) should
                // infer Nothing when the expression genuinely evaluates to Nothing.
                false
            }
        } else {
            false
        }

        if function.returnType == nil, !skipSignatureUpdate {
            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: signature.receiverType,
                    parameterTypes: signature.parameterTypes,
                    returnType: bodyType,
                    isSuspend: signature.isSuspend,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    typeParameterSymbols: signature.typeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices
                ),
                for: symbol
            )
        }
    }
}
