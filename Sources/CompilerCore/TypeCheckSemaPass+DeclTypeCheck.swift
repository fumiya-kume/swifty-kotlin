import Foundation

extension TypeCheckSemaPassPhase {
    func inferFunctionBodyType(
        _ body: FunctionBody,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        switch body {
        case .unit:
            return ctx.sema.types.unitType

        case .expr(let exprID, _):
            return inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .block(let exprIDs, _):
            var last = ctx.sema.types.unitType
            for (index, exprID) in exprIDs.enumerated() {
                let expectedTypeForExpr = index == exprIDs.count - 1 ? expectedType : nil
                last = inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: expectedTypeForExpr)
            }
            return last
        }
    }

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
            var locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool)] = [:]
            let initializerType = inferExpr(
                initializer, ctx: ctx, locals: &locals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                emitSubtypeConstraint(
                    left: initializerType, right: declaredType,
                    range: property.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = initializerType
            }
        }

        if let getter = property.getter {
            var getterLocals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool)] = [:]
            if let fieldType = inferredPropertyType {
                getterLocals[interner.intern("field")] = (fieldType, symbol, true)
            }
            let getterType = inferFunctionBodyType(
                getter.body, ctx: ctx, locals: &getterLocals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                emitSubtypeConstraint(
                    left: getterType, right: declaredType,
                    range: getter.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = getterType
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
            var setterLocals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool)] = [:]
            setterLocals[interner.intern("field")] = (finalPropertyType, symbol, true)
            let parameterName = setter.parameterName ?? interner.intern("value")
            setterLocals[parameterName] = (finalPropertyType, symbol, true)
            let setterType = inferFunctionBodyType(
                setter.body, ctx: ctx, locals: &setterLocals,
                expectedType: sema.types.unitType
            )
            emitSubtypeConstraint(
                left: setterType, right: sema.types.unitType,
                range: setter.range, solver: solver,
                sema: sema, diagnostics: diagnostics
            )
        }
    }

    func typeCheckInitBlocks(
        _ blocks: [FunctionBody],
        ctx: TypeInferenceContext
    ) {
        for block in blocks {
            var locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool)] = [:]
            _ = inferFunctionBodyType(block, ctx: ctx, locals: &locals, expectedType: nil)
        }
    }

    func typeCheckSecondaryConstructors(
        _ constructors: [ConstructorDecl],
        ctx: TypeInferenceContext
    ) {
        let sema = ctx.sema
        for ctor in constructors {
            var locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool)] = [:]
            let ctorSymbols = sema.symbols.allSymbols().filter { $0.kind == .constructor && $0.declSite == ctor.range }
            if let ctorSymbol = ctorSymbols.first,
               let signature = sema.symbols.functionSignature(for: ctorSymbol.id) {
                for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
                    guard let param = sema.symbols.symbol(paramSymbol) else { continue }
                    let type = index < signature.parameterTypes.count ? signature.parameterTypes[index] : sema.types.anyType
                    locals[param.name] = (type, paramSymbol, false)
                }
            }
            _ = inferFunctionBodyType(ctor.body, ctx: ctx, locals: &locals, expectedType: nil)
        }
    }
}
