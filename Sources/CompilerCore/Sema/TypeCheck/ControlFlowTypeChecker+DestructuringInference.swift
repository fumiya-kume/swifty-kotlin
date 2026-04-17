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
                componentType = specializeComponentReturnType(
                    candidate: candidate,
                    signature: signature,
                    receiverType: rhsType,
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
                        candidate: candidate,
                        signature: signature,
                        receiverType: rhsType,
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
                    candidate: candidate,
                    signature: signature,
                    receiverType: elementType,
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

    /// Specializes the return type of a `componentN()` function by substituting
    /// the receiver's concrete type arguments for the owner class's type parameters.
    ///
    /// For example, given `Pair<String, Int>.component1()` whose raw return type is
    /// type-parameter `A`, this produces the concrete type `String`.
    private func specializeComponentReturnType(
        candidate: SymbolID,
        signature: FunctionSignature,
        receiverType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        let rawReturn = signature.returnType
        guard signature.classTypeParameterCount > 0,
              case let .classType(receiverClassType) = sema.types.kind(
                  of: sema.types.makeNonNullable(receiverType))
        else {
            return rawReturn
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        let count = min(
            signature.classTypeParameterCount,
            receiverClassType.args.count,
            signature.typeParameterSymbols.count
        )
        for index in 0 ..< count {
            let concreteType: TypeID = switch receiverClassType.args[index] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let paramSymbol = signature.typeParameterSymbols[index]
            if let typeVar = typeVarBySymbol[paramSymbol] {
                substitution[typeVar] = concreteType
            }
        }

        guard !substitution.isEmpty else {
            return rawReturn
        }
        return sema.types.substituteTypeParameters(
            in: rawReturn,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    private func isDataClassType(_ type: TypeID, sema: SemaModule) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.flags.contains(.dataType)
    }
}
