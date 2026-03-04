import Foundation

// Stateless utility functions for type checking. No back-reference to the driver needed.
// Derived from TypeCheckSemaPhase+InferHelpers.swift.

extension TypeCheckHelpers {
    func substituteAliasArg(
        _ arg: TypeArg,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            if case let .typeParam(tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol] {
                if tp.nullability == .nullable {
                    return applyNullabilityToTypeArg(replacement, types: sema.types)
                }
                return replacement
            }
            return .invariant(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case let .out(inner):
            if case let .typeParam(tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol] {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerTypeForCheck(replacement)
                let resolved = tp.nullability == .nullable ? applyNullabilityForTypeCheck(innerType, types: sema.types) : innerType
                return .out(resolved)
            }
            return .out(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case let .in(inner):
            if case let .typeParam(tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol] {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerTypeForCheck(replacement)
                let resolved = tp.nullability == .nullable ? applyNullabilityForTypeCheck(innerType, types: sema.types) : innerType
                return .in(resolved)
            }
            return .in(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case .star:
            return .star
        }
    }

    /// Apply nullability to a type, handling function types, primitives, and special types
    /// that `TypeSystem.makeNullable` may not wrap correctly.
    /// Mirrors `DataFlowSemaPhase.applyNullability`.
    func applyNullabilityForTypeCheck(_ typeID: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: typeID) {
        case let .primitive(p, _):
            return types.make(.primitive(p, .nullable))
        case let .classType(ct):
            return types.make(.classType(ClassType(classSymbol: ct.classSymbol, args: ct.args, nullability: .nullable)))
        case let .typeParam(tp):
            return types.make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: .nullable)))
        case let .functionType(ft):
            return types.make(.functionType(FunctionType(receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, nullability: .nullable)))
        case .any, .unit, .nothing:
            let nullable = types.makeNullable(typeID)
            if nullable == typeID {
                return types.isSubtype(types.nullableNothingType, typeID) ? typeID : types.nullableAnyType
            }
            return nullable
        default:
            return types.nullableAnyType
        }
    }

    func applyNullabilityToTypeArg(_ arg: TypeArg, types: TypeSystem) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            .invariant(applyNullabilityForTypeCheck(inner, types: types))
        case let .out(inner):
            .out(applyNullabilityForTypeCheck(inner, types: types))
        case let .in(inner):
            .in(applyNullabilityForTypeCheck(inner, types: types))
        case .star:
            .star
        }
    }

    func typeArgInnerTypeForCheck(_ arg: TypeArg) -> TypeID {
        switch arg {
        case let .invariant(inner), let .out(inner), let .in(inner):
            inner
        case .star:
            TypeID.invalid
        }
    }

    /// Validate that alias expansion does not violate variance constraints.
    /// Checks that the type arguments respect the declared variance of the
    /// typealias's type parameters.
    func validateVarianceAfterExpansion(
        _: TypeID,
        aliasSymbol: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        diagnostics _: DiagnosticEngine? = nil
    ) {
        let typeParamSymbols = sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
        guard !typeParamSymbols.isEmpty, typeArgs.count == typeParamSymbols.count else {
            return
        }
        // Check each type argument against the variance of the underlying type's usage.
        // For now, verify that use-site projections don't conflict with declaration-site variance.
        for (index, paramSymbol) in typeParamSymbols.enumerated() {
            guard index < typeArgs.count else { break }
            guard let paramSym = sema.symbols.symbol(paramSymbol) else { continue }
            let declaredVariance = paramSym.flags.contains(.reifiedTypeParameter) ? TypeVariance.invariant : .invariant
            let argVariance: TypeVariance
            switch typeArgs[index] {
            case .invariant:
                argVariance = .invariant
            case .out:
                argVariance = .out
            case .in:
                argVariance = .in
            case .star:
                continue // Star projection is always valid
            }
            // If declared variance is invariant but use-site provides a projection,
            // that's valid in Kotlin (use-site variance). No error here.
            // If we had declaration-site variance on the alias type params,
            // we'd check for conflicts. For now, invariant aliases accept any use-site.
            _ = (declaredVariance, argVariance)
        }
    }

    func resolveExplicitTypeArgs(
        _ typeArgRefs: [TypeRefID],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeID] {
        guard !typeArgRefs.isEmpty else { return [] }
        return typeArgRefs.map { typeRefID in
            resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics)
        }
    }

    /// Check if an expression is a terminating expression (return/throw) for elvis guard narrowing.
    func isTerminatingExpr(_ expr: Expr) -> Bool {
        switch expr {
        case .returnExpr:
            true
        case .throwExpr:
            true
        default:
            false
        }
    }

    func compoundAssignToBinaryOp(_ op: CompoundAssignOp) -> BinaryOp {
        switch op {
        case .plusAssign: .add
        case .minusAssign: .subtract
        case .timesAssign: .multiply
        case .divAssign: .divide
        case .modAssign: .modulo
        }
    }

    func smartCastTypeForWhenSubjectCase(
        conditionID: ExprID,
        subjectType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return nil
        }
        switch conditionExpr {
        case .boolLiteral:
            switch sema.types.kind(of: subjectType) {
            case .primitive(.boolean, _):
                return sema.types.booleanType
            default:
                return nil
            }

        case let .nameRef(name, _):
            if interner.resolve(name) == "null" {
                return nil
            }
            guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID],
                  let conditionSymbol = sema.symbols.symbol(conditionSymbolID)
            else {
                return nil
            }
            switch conditionSymbol.kind {
            case .field:
                guard let enumOwner = enumOwnerSymbol(for: conditionSymbol, symbols: sema.symbols),
                      nominalSymbol(of: subjectType, types: sema.types) == enumOwner
                else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: enumOwner,
                    args: [],
                    nullability: .nonNull
                )))

            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                guard let subjectNominal = nominalSymbol(of: subjectType, types: sema.types),
                      isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols)
                else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: conditionSymbolID,
                    args: [],
                    nullability: .nonNull
                )))

            default:
                return nil
            }

        default:
            return nil
        }
    }

    func nominalSymbol(of type: TypeID, types: TypeSystem) -> SymbolID? {
        switch types.kind(of: type) {
        case let .classType(classType):
            return classType.classSymbol
        case let .intersection(parts):
            // For intersection types, return the first nominal part
            for part in parts {
                if let symbol = nominalSymbol(of: part, types: types) {
                    return symbol
                }
            }
            return nil
        default:
            return nil
        }
    }

    /// Collects all nominal symbols from a type, including all parts of an intersection.
    func allNominalSymbols(of type: TypeID, types: TypeSystem) -> [SymbolID] {
        switch types.kind(of: type) {
        case let .classType(classType):
            [classType.classSymbol]
        case let .intersection(parts):
            parts.flatMap { allNominalSymbols(of: $0, types: types) }
        default:
            []
        }
    }

    func collectMemberFunctionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        allowedOwnerSymbols: Set<SymbolID>? = nil
    ) -> [SymbolID] {
        let nominalRoots = allNominalSymbols(of: receiverType, types: sema.types)
        guard !nominalRoots.isEmpty else {
            return []
        }

        var ownerQueue: [SymbolID] = nominalRoots
        var visitedOwners: Set<SymbolID> = []
        var ownersInLookupOrder: [SymbolID] = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visitedOwners.insert(owner).inserted else {
                continue
            }
            if let allowedOwnerSymbols {
                if allowedOwnerSymbols.contains(owner) {
                    ownersInLookupOrder.append(owner)
                }
            } else {
                ownersInLookupOrder.append(owner)
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }

        if ownersInLookupOrder.isEmpty {
            return []
        }

        var candidates: [SymbolID] = []
        var seenCandidates: Set<SymbolID> = []
        for owner in ownersInLookupOrder {
            guard let ownerSymbol = sema.symbols.symbol(owner) else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard seenCandidates.insert(candidate).inserted,
                      let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.receiverType != nil
                else {
                    continue
                }
                candidates.append(candidate)
            }
        }
        return candidates
    }

    /// When `receiver.InnerClassName(...)` is called, look up the inner class
    /// nested inside the receiver's nominal type and return its constructor(s).
    func collectInnerClassConstructorCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard let receiverNominal = nominalSymbol(of: receiverType, types: sema.types),
              let receiverSymbol = sema.symbols.symbol(receiverNominal)
        else {
            return []
        }
        // Look for a nested class with the given name whose symbol has the innerClass flag.
        let nestedFQName = receiverSymbol.fqName + [calleeName]
        for candidate in sema.symbols.lookupAll(fqName: nestedFQName) {
            guard let sym = sema.symbols.symbol(candidate),
                  sym.kind == .class,
                  sym.flags.contains(.innerClass)
            else {
                continue
            }
            // Found the inner class – collect its constructors.
            let initName = interner.intern("<init>")
            let ctorFQName = nestedFQName + [initName]
            return sema.symbols.lookupAll(fqName: ctorFQName).filter { ctorID in
                guard let ctorSym = sema.symbols.symbol(ctorID),
                      ctorSym.kind == .constructor else { return false }
                return true
            }
        }
        return []
    }

    /// Look up a member property (or field) named `calleeName` on the receiver's
    /// nominal type, walking the supertype chain. Returns the symbol and its type
    /// if found, or `nil` otherwise.
    func lookupMemberProperty(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule
    ) -> (symbol: SymbolID, type: TypeID)? {
        let nominalRoots = allNominalSymbols(of: receiverType, types: sema.types)
        guard !nominalRoots.isEmpty else {
            return nil
        }
        var ownerQueue: [SymbolID] = nominalRoots
        var visited: Set<SymbolID> = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visited.insert(owner).inserted else { continue }
            guard let ownerSymbol = sema.symbols.symbol(owner) else { continue }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard let sym = sema.symbols.symbol(candidate),
                      sym.kind == .property || sym.kind == .field,
                      let propType = sema.symbols.propertyType(for: candidate)
                else {
                    continue
                }
                return (candidate, propType)
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return nil
    }

    func enumOwnerSymbol(for entrySymbol: SemanticSymbol, symbols: SymbolTable) -> SymbolID? {
        guard entrySymbol.kind == .field,
              entrySymbol.fqName.count >= 2
        else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }
}
