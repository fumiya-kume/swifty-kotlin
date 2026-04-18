import Foundation

extension ControlFlowTypeChecker {
    func inferDestructuringDeclExpr(
        _ id: ExprID,
        names: [InternedString?],
        isMutable: Bool,
        initializer: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        // Infer the type of the RHS initializer
        let rhsType = driver.inferExpr(initializer, ctx: ctx, locals: &locals)

        // For each name, resolve componentN() on the RHS type
        for (index, name) in names.enumerated() {
            guard let name else {
                // Underscore — skip this component
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")

            // Look up componentN as a member function on the RHS type
            let candidates = driver.helpers.collectMemberFunctionCandidates(
                named: componentName,
                receiverType: rhsType,
                sema: sema,
                interner: interner
            )

            let componentType: TypeID
            if let candidate = candidates.first,
               let signature = sema.symbols.functionSignature(for: candidate)
            {
                // Substitute the receiver's class type arguments into the raw return
                // type so that e.g. Pair<List<T>,List<T>>.component1() yields List<T>
                // rather than the generic parameter A.  Fixes STDLIB-021-BUG-01 where
                // `.size` access on destructured partition() results failed to lower.
                componentType = specializeComponentReturnType(
                    signature.returnType,
                    receiverType: rhsType,
                    signature: signature,
                    sema: sema
                )
            } else {
                // Fallback: try to find componentN via scope lookup
                let scopeCandidates = sema.symbols.lookupAll(fqName: [componentName]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          let sig = sema.symbols.functionSignature(for: symbolID)
                    else {
                        return false
                    }
                    return sig.receiverType != nil
                }
                if let candidate = scopeCandidates.first,
                   let signature = sema.symbols.functionSignature(for: candidate)
                {
                    componentType = specializeComponentReturnType(
                        signature.returnType,
                        receiverType: rhsType,
                        signature: signature,
                        sema: sema
                    )
                } else if isDataClassType(rhsType, sema: sema) {
                    // Data class componentN() is synthesized during lowering; fall back to Any
                    componentType = sema.types.anyType
                } else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0086",
                        "Type does not have a 'component\(componentIndex)()' operator for destructuring.",
                        range: range
                    )
                    componentType = sema.types.errorType
                }
            }

            let flags: SymbolFlags = isMutable ? [.mutable] : []
            let symbol = sema.symbols.define(
                kind: .local,
                name: name,
                fqName: [
                    interner.intern("__destructuring_\(id.rawValue)"),
                    name,
                ],
                declSite: range,
                visibility: .private,
                flags: flags
            )
            sema.symbols.setPropertyType(componentType, for: symbol)
            locals[name] = (componentType, symbol, isMutable, true)
        }

        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferForDestructuringExpr(
        _ id: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let iterableType = driver.inferExpr(iterableExpr, ctx: ctx, locals: &locals, expectedType: nil)
        let isRangeExpr = Self.isRangeExpression(iterableExpr, ast: ctx.ast)
        let elementType: TypeID = bindLoopIterationOperators(
            exprID: id,
            iterableType: iterableType,
            range: range,
            ctx: ctx
        ) ?? driver.helpers.iterableElementType(for: iterableType, isRangeExpr: isRangeExpr, sema: sema, interner: interner) ?? {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0087",
                "Cannot determine element type for destructuring in for-loop.",
                range: range
            )
            return sema.types.errorType
        }()

        var bodyLocals = locals

        // For each destructuring name, resolve componentN on the element type
        for (index, name) in names.enumerated() {
            guard let name else {
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")

            let candidates = driver.helpers.collectMemberFunctionCandidates(
                named: componentName,
                receiverType: elementType,
                sema: sema,
                interner: interner
            )

            let componentType: TypeID
            if let candidate = candidates.first,
               let signature = sema.symbols.functionSignature(for: candidate)
            {
                componentType = specializeComponentReturnType(
                    signature.returnType,
                    receiverType: elementType,
                    signature: signature,
                    sema: sema
                )
            } else if isDataClassType(elementType, sema: sema) {
                // Data class componentN() is synthesized during lowering; fall back to Any
                componentType = sema.types.anyType
            } else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0087",
                    "Iterable element type does not have a 'component\(componentIndex)()' operator for destructuring.",
                    range: range
                )
                componentType = sema.types.errorType
            }

            let symbol = sema.symbols.define(
                kind: .local,
                name: name,
                fqName: [
                    interner.intern("__for_destructuring_\(id.rawValue)"),
                    name,
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            sema.symbols.setPropertyType(componentType, for: symbol)
            bodyLocals[name] = (componentType, symbol, false, true)
        }

        _ = driver.inferExpr(
            bodyExpr,
            ctx: ctx.copying(loopDepth: ctx.loopDepth + 1),
            locals: &bodyLocals,
            expectedType: nil
        )
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    static func isRangeExpression(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        switch expr {
        case let .binary(op, _, _, _):
            switch op {
            case .rangeTo, .rangeUntil, .downTo, .step:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    private func isDataClassType(_ type: TypeID, sema: SemaModule) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.flags.contains(.dataType)
    }

    /// Specialises the raw return type of a componentN() member by substituting
    /// the concrete class-level type arguments from the receiver.
    ///
    /// When `receiverType` is `Pair<List<Int>, List<Int>>` and `rawReturn` is the
    /// generic type parameter `A`, the substitution `A → List<Int>` is applied and
    /// `List<Int>` is returned.  This is needed so that member accesses on the
    /// destructured variables (e.g. `.size`) resolve to the correct concrete type
    /// rather than to the raw type parameter.  Fixes STDLIB-021-BUG-01.
    private func specializeComponentReturnType(
        _ rawReturn: TypeID,
        receiverType: TypeID,
        signature: FunctionSignature,
        sema: SemaModule
    ) -> TypeID {
        // Only proceed when the receiver is a concrete generic class type.
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiver),
              !classType.args.isEmpty,
              !signature.typeParameterSymbols.isEmpty
        else {
            return rawReturn
        }

        // Map the signature's type-parameter symbols to TypeVarIDs so we can
        // call substituteTypeParameters.
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)

        // Use the TypeSystem's record of the class's own type-parameter symbols
        // (e.g. [A, B] for Pair) to match each concrete type arg to a TypeVarID.
        let classOwnParamSymbols = sema.types.nominalTypeParameterSymbols(for: classType.classSymbol)

        var substitution: [TypeVarID: TypeID] = [:]
        for (index, arg) in classType.args.enumerated() {
            let tpSymbol: SymbolID
            if index < classOwnParamSymbols.count {
                tpSymbol = classOwnParamSymbols[index]
            } else if index < signature.classTypeParameterCount,
                      index < signature.typeParameterSymbols.count
            {
                tpSymbol = signature.typeParameterSymbols[index]
            } else {
                continue
            }
            guard let typeVar = typeVarBySymbol[tpSymbol] else { continue }
            switch arg {
            case let .invariant(t): substitution[typeVar] = t
            case let .out(t):       substitution[typeVar] = t
            case let .in(t):        substitution[typeVar] = t
            case .star:             substitution[typeVar] = sema.types.nullableAnyType
            }
        }

        guard !substitution.isEmpty else { return rawReturn }
        return sema.types.substituteTypeParameters(
            in: rawReturn,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }
}
