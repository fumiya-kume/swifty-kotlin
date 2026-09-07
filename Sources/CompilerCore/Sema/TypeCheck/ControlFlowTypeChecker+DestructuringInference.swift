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
                sema.bindings.bindDestructuringComponentCallee(id, index: index, symbol: candidate)
            } else {
                // Fallback: componentN declared as an operator extension rather than
                // a member (e.g. the bundled `MatchResult.Destructured.componentN`).
                let scopeCandidates = componentOperatorExtensionCandidates(
                    named: componentName,
                    receiverType: rhsType,
                    ctx: ctx
                )
                if let candidate = scopeCandidates.first,
                   let signature = sema.symbols.functionSignature(for: candidate)
                {
                    componentType = specializeComponentReturnType(
                        signature.returnType,
                        receiverType: rhsType,
                        signature: signature,
                        sema: sema
                    )
                    sema.bindings.bindDestructuringComponentCallee(id, index: index, symbol: candidate)
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
        // `until` desugars to a memberCall (infix function), not a `.binary` range op,
        // so the AST-shape check alone misses it; fall back to the semantic flag that
        // markRangeCallBindings sets when resolving such calls.
        let isRangeExpr = Self.isRangeExpression(iterableExpr, ast: ctx.ast)
            || sema.bindings.isRangeExpr(iterableExpr)
        let elementType: TypeID = bindLoopIterationOperators(
            exprID: id,
            iterableType: iterableType,
            range: range,
            ctx: ctx
        ) ?? driver.helpers.iterableElementType(
            for: iterableType,
            isRangeExpr: isRangeExpr,
            isCharRangeExpr: sema.bindings.isCharRangeExpr(iterableExpr),
            sema: sema,
            interner: interner
        ) ?? {
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
            ) + componentOperatorExtensionCandidates(
                named: componentName,
                receiverType: elementType,
                ctx: ctx
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

    /// `componentN` functions declared as extensions on `receiverType` (member
    /// lookup only finds them when they are declared inside the class). Scope
    /// lookup goes first so imported operator extensions win; the short-name
    /// sweep then recovers extensions that are visible without an import, such
    /// as the bundled `MatchResult.Destructured.componentN`.
    func componentOperatorExtensionCandidates(
        named componentName: InternedString,
        receiverType: TypeID,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)

        func matchesReceiver(_ candidate: SymbolID, requireOperator: Bool) -> Bool {
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  !requireOperator || symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else {
                return false
            }
            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullReceiver,
                declaredReceiver: declaredReceiver,
                sema: sema
            )
        }

        let scoped = ctx.filterByVisibility(ctx.cachedScopeLookup(componentName)).visible
            .filter { matchesReceiver($0, requireOperator: true) }
        if !scoped.isEmpty {
            return scoped
        }
        return sema.symbols.lookupByShortName(componentName)
            .filter { matchesReceiver($0, requireOperator: false) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func isDataClassType(_ type: TypeID, sema: SemaModule) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return symbol.flags.contains(.dataType)
    }

    /// Resolve the effective upper bound for a type parameter, returning `Any?` when
    /// no explicit bounds exist and an intersection type when multiple bounds exist.
    private func effectiveUpperBound(for symbol: SymbolID, sema: SemaModule) -> TypeID {
        let bounds = sema.symbols.typeParameterUpperBounds(for: symbol)
        if bounds.isEmpty { return sema.types.nullableAnyType }
        if bounds.count == 1 { return bounds[0] }
        return sema.types.make(.intersection(bounds))
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

        // A bare type-parameter type argument (e.g. the `K` in `Map.Entry<K, V>`)
        // names the symbol the return type is actually parameterized over. This is
        // the receiver class's own nominal K/V when componentN is declared as a
        // genuine member reusing those symbols (the historical synthetic Map.Entry
        // stubs), but is a distinct, freshly-declared K/V when componentN is a
        // standalone generic extension such as the bundled
        // `operator fun <K, V> Map.Entry<K, V>.component1(): K`. Reading the symbol
        // straight out of the declared receiver's own type argument — rather than
        // assuming it matches the receiver class's nominal parameters — keeps both
        // shapes working.
        func typeParamSymbol(in arg: TypeArg) -> SymbolID? {
            let typeID: TypeID
            switch arg {
            case let .invariant(t): typeID = t
            case let .out(t): typeID = t
            case let .in(t): typeID = t
            case .star: return nil
            }
            guard case let .typeParam(typeParam) = sema.types.kind(of: typeID) else { return nil }
            return typeParam.symbol
        }

        // Inherited members such as Map.Entry.key are declared on a supertype, so
        // lift the concrete receiver arguments through the nominal inheritance edge
        // before building the substitution.
        let declaredReceiver: (args: [TypeArg], paramSymbols: [SymbolID?])? = {
            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
            else {
                return nil
            }
            let liftedArgs = sema.types.liftedNominalSupertypeArgs(
                from: classType.classSymbol,
                childArgs: classType.args,
                to: receiverClassType.classSymbol
            ) ?? classType.args
            return (liftedArgs, receiverClassType.args.map(typeParamSymbol))
        }()
        let receiverArgs = declaredReceiver?.args ?? classType.args
        let declaredParamSymbols = declaredReceiver?.paramSymbols ?? []
        // Fallback for the rare shape where the declared receiver's type argument
        // isn't a bare type-parameter reference (so `typeParamSymbol` found
        // nothing): fall back to the receiver class's own nominal parameters,
        // which is what this substitution relied on before extension componentN
        // declarations existed.
        let classOwnParamSymbols = sema.types.nominalTypeParameterSymbols(for: classType.classSymbol)

        var substitution: [TypeVarID: TypeID] = [:]
        for (index, arg) in receiverArgs.enumerated() {
            let tpSymbol: SymbolID
            if index < declaredParamSymbols.count,
               let symbol = declaredParamSymbols[index],
               typeVarBySymbol[symbol] != nil
            {
                tpSymbol = symbol
            } else if index < classOwnParamSymbols.count,
                      typeVarBySymbol[classOwnParamSymbols[index]] != nil
            {
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
            case .in:               substitution[typeVar] = effectiveUpperBound(for: tpSymbol, sema: sema)
            case .star:             substitution[typeVar] = effectiveUpperBound(for: tpSymbol, sema: sema)
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
