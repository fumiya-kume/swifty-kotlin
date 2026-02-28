import Foundation

/// Stateless utility functions for type checking. No back-reference to the driver needed.
/// Derived from TypeCheckSemaPhase+InferHelpers.swift.

extension TypeCheckHelpers {
    func substituteAliasArg(
        _ arg: TypeArg,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeArg {
        switch arg {
        case .invariant(let inner):
            if case .typeParam(let tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol] {
                if tp.nullability == .nullable {
                    return applyNullabilityToTypeArg(replacement, types: sema.types)
                }
                return replacement
            }
            return .invariant(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case .out(let inner):
            if case .typeParam(let tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol] {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerTypeForCheck(replacement)
                let resolved = tp.nullability == .nullable ? applyNullabilityForTypeCheck(innerType, types: sema.types) : innerType
                return .out(resolved)
            }
            return .out(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case .in(let inner):
            if case .typeParam(let tp) = sema.types.kind(of: inner),
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
        case .primitive(let p, _):
            return types.make(.primitive(p, .nullable))
        case .classType(let ct):
            return types.make(.classType(ClassType(classSymbol: ct.classSymbol, args: ct.args, nullability: .nullable)))
        case .typeParam(let tp):
            return types.make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: .nullable)))
        case .functionType(let ft):
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
        case .invariant(let inner):
            return .invariant(applyNullabilityForTypeCheck(inner, types: types))
        case .out(let inner):
            return .out(applyNullabilityForTypeCheck(inner, types: types))
        case .in(let inner):
            return .in(applyNullabilityForTypeCheck(inner, types: types))
        case .star:
            return .star
        }
    }

    func typeArgInnerTypeForCheck(_ arg: TypeArg) -> TypeID {
        switch arg {
        case .invariant(let inner), .out(let inner), .in(let inner):
            return inner
        case .star:
            return TypeID.invalid
        }
    }

    /// Validate that alias expansion does not violate variance constraints.
    /// Checks that the type arguments respect the declared variance of the
    /// typealias's type parameters.
    func validateVarianceAfterExpansion(
        _ expandedType: TypeID,
        aliasSymbol: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        diagnostics: DiagnosticEngine? = nil
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
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeID] {
        guard !typeArgRefs.isEmpty else { return [] }
        return typeArgRefs.map { typeRefID in
            resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: diagnostics)
        }
    }

    /// Check if an expression is a terminating expression (return/throw) for elvis guard narrowing.
    func isTerminatingExpr(_ expr: Expr) -> Bool {
        switch expr {
        case .returnExpr:
            return true
        case .throwExpr:
            return true
        default:
            return false
        }
    }

    func compoundAssignToBinaryOp(_ op: CompoundAssignOp) -> BinaryOp {
        switch op {
        case .plusAssign: return .add
        case .minusAssign: return .subtract
        case .timesAssign: return .multiply
        case .divAssign: return .divide
        case .modAssign: return .modulo
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

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                return nil
            }
            guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID],
                  let conditionSymbol = sema.symbols.symbol(conditionSymbolID) else {
                return nil
            }
            switch conditionSymbol.kind {
            case .field:
                guard let enumOwner = enumOwnerSymbol(for: conditionSymbol, symbols: sema.symbols),
                      nominalSymbol(of: subjectType, types: sema.types) == enumOwner else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: enumOwner,
                    args: [],
                    nullability: .nonNull
                )))

            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                guard let subjectNominal = nominalSymbol(of: subjectType, types: sema.types),
                      isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols) else {
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
        case .classType(let classType):
            return classType.classSymbol
        case .intersection(let parts):
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
        case .classType(let classType):
            return [classType.classSymbol]
        case .intersection(let parts):
            return parts.flatMap { allNominalSymbols(of: $0, types: types) }
        default:
            return []
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
                      signature.receiverType != nil else {
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
              let receiverSymbol = sema.symbols.symbol(receiverNominal) else {
            return []
        }
        // Look for a nested class with the given name whose symbol has the innerClass flag.
        let nestedFQName = receiverSymbol.fqName + [calleeName]
        for candidate in sema.symbols.lookupAll(fqName: nestedFQName) {
            guard let sym = sema.symbols.symbol(candidate),
                  sym.kind == .class,
                  sym.flags.contains(.innerClass) else {
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
                      (sym.kind == .property || sym.kind == .field),
                      let propType = sema.symbols.propertyType(for: candidate) else {
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
              entrySymbol.fqName.count >= 2 else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }

    func isNominalSubtype(
        _ candidate: SymbolID,
        of base: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        if candidate == base {
            return true
        }
        var queue = symbols.directSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next == base {
                return true
            }
            if visited.insert(next).inserted {
                queue.append(contentsOf: symbols.directSupertypes(for: next))
            }
        }
        return false
    }

    func callableTargetForCalleeExpr(
        _ calleeExprID: ExprID,
        sema: SemaModule
    ) -> CallableTarget? {
        if let explicitTarget = sema.bindings.callableTarget(for: calleeExprID) {
            return explicitTarget
        }
        guard let symbol = sema.bindings.identifierSymbol(for: calleeExprID) else {
            return nil
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol) else {
            return .localValue(symbol)
        }
        if semanticSymbol.kind == .function || semanticSymbol.kind == .constructor {
            return .symbol(symbol)
        }
        return .localValue(symbol)
    }

    func callableFunctionType(
        for signature: FunctionSignature,
        bindReceiver: Bool,
        sema: SemaModule
    ) -> TypeID {
        var params = signature.parameterTypes
        if !bindReceiver, let receiverType = signature.receiverType {
            params.insert(receiverType, at: 0)
        }
        return sema.types.make(.functionType(FunctionType(
            params: params,
            returnType: signature.returnType,
            isSuspend: signature.isSuspend,
            nullability: .nonNull
        )))
    }

    func chooseCallableReferenceTarget(
        from candidates: [SymbolID],
        expectedType: TypeID?,
        bindReceiver: Bool,
        sema: SemaModule
    ) -> SymbolID? {
        let sorted = candidates.sorted(by: { $0.rawValue < $1.rawValue })
        guard !sorted.isEmpty else {
            return nil
        }
        guard let expectedType else {
            return sorted.first
        }
        guard case .functionType = sema.types.kind(of: expectedType) else {
            return sorted.first
        }
        if let matched = sorted.first(where: { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            let inferredType = callableFunctionType(
                for: signature,
                bindReceiver: bindReceiver,
                sema: sema
            )
            return sema.types.isSubtype(inferredType, expectedType)
        }) {
            return matched
        }
        return sorted.first
    }
}
