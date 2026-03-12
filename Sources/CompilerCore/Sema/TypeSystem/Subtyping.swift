extension TypeSystem {
    public func isSubtype(_ subtype: TypeID, _ supertype: TypeID) -> Bool {
        if subtype == supertype {
            return true
        }

        let lhs = kind(of: subtype)
        let rhs = kind(of: supertype)

        if case .nothing(.nonNull) = lhs {
            return true
        }
        if case .nothing(.nullable) = lhs {
            // Nothing? is subtype of all nullable and platform types, Any?, and Nothing? itself
            switch rhs {
            case .error:
                return true
            case let .any(n):
                return nullabilitySubtype(.nullable, n)
            case let .nothing(n):
                return nullabilitySubtype(.nullable, n)
            case let .primitive(_, n):
                return nullabilitySubtype(.nullable, n)
            case let .classType(ct):
                return nullabilitySubtype(.nullable, ct.nullability)
            case let .typeParam(tp):
                return nullabilitySubtype(.nullable, tp.nullability)
            case let .functionType(ft):
                return nullabilitySubtype(.nullable, ft.nullability)
            case let .intersection(parts):
                return parts.allSatisfy { isSubtype(subtype, $0) }
            default:
                return false
            }
        }
        // Subtype of intersection: C <: A & B if C <: all parts
        // (must come before LHS decomposition so that intersection-vs-intersection
        //  decomposes the RHS first, allowing each part to then match via LHS rule)
        if case let .intersection(parts) = rhs {
            return parts.allSatisfy { isSubtype(subtype, $0) }
        }
        // Intersection as subtype: A & B <: C if any part <: C
        if case let .intersection(parts) = lhs {
            return parts.contains { isSubtype($0, supertype) }
        }
        if case .error = lhs {
            return true
        }
        if case .error = rhs {
            return true
        }
        if case .any(.nullable) = rhs {
            return true
        }
        if case .any(.platformType) = rhs {
            // Any! accepts all types (platform type has unknown nullability)
            return true
        }
        if case .any(.nonNull) = rhs {
            switch lhs {
            case .any(.nonNull), .any(.platformType), .unit, .nothing(.nonNull):
                return true
            case let .primitive(_, nullability):
                return nullabilitySubtype(nullability, .nonNull)
            case let .classType(classType):
                return nullabilitySubtype(classType.nullability, .nonNull)
            case let .functionType(functionType):
                return nullabilitySubtype(functionType.nullability, .nonNull)
            case let .typeParam(typeParam):
                return nullabilitySubtype(typeParam.nullability, .nonNull)
            case .intersection:
                return isSubtype(subtype, supertype)
            default:
                return false
            }
        }

        // primitive <: Comparable<same_primitive>
        // All Kotlin primitive types (Int, Long, Double, Float, Char, Boolean, etc.) implement Comparable<Self>.
        if case let .primitive(_, leftNullability) = lhs,
           case let .classType(rightClass) = rhs,
           let comparableSym = comparableInterfaceSymbol,
           rightClass.classSymbol == comparableSym,
           rightClass.args.count == 1,
           case let .invariant(argType) = rightClass.args[0],
           argType == subtype,
           nullabilitySubtype(leftNullability, rightClass.nullability)
        {
            return true
        }

        switch (lhs, rhs) {
        case (.any(.nonNull), .any(.nullable)):
            return true

        case let (.primitive(leftPrimitive, leftNullability), .primitive(rightPrimitive, rightNullability)):
            return leftPrimitive == rightPrimitive && nullabilitySubtype(leftNullability, rightNullability)

        case let (.classType(leftClass), .classType(rightClass)):
            guard nullabilitySubtype(leftClass.nullability, rightClass.nullability) else {
                return false
            }
            if leftClass.classSymbol != rightClass.classSymbol {
                guard isNominalSubtypeSymbol(leftClass.classSymbol, of: rightClass.classSymbol) else {
                    return false
                }
                let mappedArgs = nominalSupertypeTypeArgs(for: leftClass.classSymbol, supertype: rightClass.classSymbol)
                if mappedArgs.count == rightClass.args.count, !mappedArgs.isEmpty {
                    let substitutedMappedArgs = mappedArgs.map {
                        substituteTypeArg($0, childSymbol: leftClass.classSymbol, childArgs: leftClass.args)
                    }
                    let liftedSupertype = make(.classType(ClassType(
                        classSymbol: rightClass.classSymbol,
                        args: substitutedMappedArgs,
                        nullability: leftClass.nullability
                    )))
                    return isSubtype(liftedSupertype, supertype)
                }
                return rightClass.args.isEmpty || rightClass.args.allSatisfy { arg in
                    if case .star = arg {
                        return true
                    }
                    return false
                }
            }
            if leftClass.args.count != rightClass.args.count {
                return false
            }
            let declarationVariances = normalizedNominalVariances(
                for: leftClass.classSymbol,
                arity: leftClass.args.count
            )
            for index in 0 ..< leftClass.args.count {
                let lhsProjection = composedProjection(
                    declarationVariance: declarationVariances[index],
                    useSite: leftClass.args[index]
                )
                let rhsProjection = composedProjection(
                    declarationVariance: declarationVariances[index],
                    useSite: rightClass.args[index]
                )
                if !isProjectionSubtype(lhsProjection, rhsProjection) {
                    return false
                }
            }
            return true

        case let (.functionType(leftFunction), .functionType(rightFunction)):
            guard leftFunction.params.count == rightFunction.params.count else {
                return false
            }
            guard leftFunction.isSuspend == rightFunction.isSuspend else {
                return false
            }
            guard nullabilitySubtype(leftFunction.nullability, rightFunction.nullability) else {
                return false
            }
            if let lReceiver = leftFunction.receiver, let rReceiver = rightFunction.receiver {
                if !isSubtype(rReceiver, lReceiver) {
                    return false
                }
            } else if leftFunction.receiver != nil || rightFunction.receiver != nil {
                return false
            }
            for (leftParam, rightParam) in zip(leftFunction.params, rightFunction.params) where !isSubtype(rightParam, leftParam) {
                return false
            }
            return isSubtype(leftFunction.returnType, rightFunction.returnType)

        case let (.classType(leftClass), .functionType(rightFunction)):
            // SAM: fun interface <: function type when the SAM method signature matches
            guard nullabilitySubtype(leftClass.nullability, rightFunction.nullability) else {
                return false
            }
            guard let symbols = symbolTable else { return false }
            guard let sym = symbols.symbol(leftClass.classSymbol),
                  sym.kind == .interface,
                  sym.flags.contains(.funInterface)
            else {
                return false
            }
            let children = symbols.children(ofFQName: sym.fqName)
            var abstractSignatures: [(SymbolID, FunctionSignature)] = []
            for childID in children {
                guard let childSym = symbols.symbol(childID),
                      childSym.kind == .function,
                      childSym.flags.contains(.abstractType),
                      let signature = symbols.functionSignature(for: childID)
                else {
                    continue
                }
                abstractSignatures.append((childID, signature))
            }
            guard abstractSignatures.count == 1 else { return false }
            let samSignature = abstractSignatures[0].1
            let typeParamSymbols = nominalTypeParameterSymbols(for: leftClass.classSymbol)
            guard typeParamSymbols.count == leftClass.args.count else { return false }
            let typeVarBySymbol = makeTypeVarBySymbol(typeParamSymbols)
            var substitution: [TypeVarID: TypeID] = [:]
            for (index, arg) in leftClass.args.enumerated() {
                guard index < typeParamSymbols.count else { break }
                let tpSymbol = typeParamSymbols[index]
                guard let typeVar = typeVarBySymbol[tpSymbol] else { continue }
                switch arg {
                case let .invariant(type): substitution[typeVar] = type
                case let .out(type): substitution[typeVar] = type
                case .in, .star: substitution[typeVar] = anyType
                }
            }
            let samParamTypes = samSignature.parameterTypes.map {
                substituteTypeParameters(in: $0, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
            }
            let samReturnType = substituteTypeParameters(
                in: samSignature.returnType,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            guard samParamTypes.count == rightFunction.params.count else { return false }
            guard samSignature.isSuspend == rightFunction.isSuspend else { return false }
            for (samParam, rightParam) in zip(samParamTypes, rightFunction.params) {
                if !isSubtype(rightParam, samParam) { return false }
            }
            return isSubtype(samReturnType, rightFunction.returnType)

        case let (.any(leftNullability), .any(rightNullability)):
            return nullabilitySubtype(leftNullability, rightNullability)

        default:
            return false
        }
    }

    public func lub(_ types: [TypeID]) -> TypeID {
        let hasNullableNothing = types.contains { kind(of: $0) == .nothing(.nullable) }
        let filtered = types.filter { kind(of: $0) != .error && kind(of: $0) != .nothing(.nonNull) && kind(of: $0) != .nothing(.nullable) }
        guard let first = filtered.first else {
            let hasNothing = types.contains { kind(of: $0) == .nothing(.nonNull) || kind(of: $0) == .nothing(.nullable) }
            if hasNullableNothing { return nullableNothingType }
            return hasNothing ? nothingType : errorType
        }
        let result: TypeID = if filtered.dropFirst().allSatisfy({ $0 == first }) {
            first
        } else if filtered.allSatisfy({ isSubtype($0, nullableAnyType) }) {
            nullableAnyType
        } else {
            anyType
        }
        // If any input was Nothing? (null literal), the result must be nullable
        if hasNullableNothing {
            let nullable = makeNullable(result)
            // makeNullable returns the same ID for two reasons:
            // (a) the type is already nullable (e.g. Int?) — keep it as-is
            // (b) makeNullable is a genuine no-op (e.g. Unit) — fall back to Any?
            if nullable == result {
                if isSubtype(nullableNothingType, result) {
                    return result // already nullable, Nothing? <: result
                }
                return nullableAnyType
            }
            return nullable
        }
        return result
    }

    public func glb(_ types: [TypeID]) -> TypeID {
        guard let first = types.first else {
            return errorType
        }
        if types.dropFirst().allSatisfy({ $0 == first }) {
            return first
        }
        let hasNullableNothing = types.contains { kind(of: $0) == .nothing(.nullable) }
        if types.contains(where: { if case .nothing = kind(of: $0) { return true }; return false }) {
            // Only return Nothing? if it is a valid lower bound (subtype of all inputs).
            // glb([Nothing?, Int]) → Nothing (non-null), since Nothing? is NOT <: Int.
            if hasNullableNothing, types.allSatisfy({ isSubtype(nullableNothingType, $0) }) {
                return nullableNothingType
            }
            return nothingType
        }
        return make(.intersection(types))
    }

    func nullabilitySubtype(_ lhs: Nullability, _ rhs: Nullability) -> Bool {
        if lhs == rhs { return true }
        if lhs == .nonNull, rhs == .nullable { return true }
        // Platform type (T!) is assignable to both nullable and non-null
        if lhs == .platformType { return true }
        // Both nullable and non-null are assignable to platform type
        if rhs == .platformType { return true }
        return false
    }

    func isNominalSubtypeSymbol(_ candidate: SymbolID, of base: SymbolID) -> Bool {
        if candidate == base {
            return true
        }
        var queue = directNominalSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while let current = queue.first {
            queue.removeFirst()
            if current == base {
                return true
            }
            if visited.insert(current).inserted {
                queue.append(contentsOf: directNominalSupertypes(for: current))
            }
        }
        return false
    }

    enum Projection {
        case invariant(TypeID)
        case out(TypeID)
        case `in`(TypeID)
        case star
        case invalid
    }

    func normalizedNominalVariances(for symbol: SymbolID, arity: Int) -> [TypeVariance] {
        let stored = nominalTypeParameterVariances(for: symbol)
        if stored.count >= arity {
            return Array(stored.prefix(arity))
        }
        if stored.isEmpty {
            return Array(repeating: .invariant, count: arity)
        }
        return stored + Array(repeating: .invariant, count: arity - stored.count)
    }

    func composedProjection(
        declarationVariance: TypeVariance,
        useSite: TypeArg
    ) -> Projection {
        switch declarationVariance {
        case .invariant:
            projection(from: useSite)
        case .out:
            outProjection(useSite: useSite)
        case .in:
            inProjection(useSite: useSite)
        }
    }

    private func outProjection(useSite: TypeArg) -> Projection {
        switch useSite {
        case let .invariant(type): .out(type)
        case let .out(type): .out(type)
        case .star: .star
        case .in: .invalid
        }
    }

    private func inProjection(useSite: TypeArg) -> Projection {
        switch useSite {
        case let .invariant(type): .in(type)
        case let .in(type):
            // in × in = out (double contravariance = covariance)
            .out(type)
        case .star: .star
        case .out: .invalid
        }
    }

    func projection(from arg: TypeArg) -> Projection {
        switch arg {
        case let .invariant(type):
            .invariant(type)
        case let .out(type):
            .out(type)
        case let .in(type):
            .in(type)
        case .star:
            .star
        }
    }

    func isProjectionSubtype(_ lhs: Projection, _ rhs: Projection) -> Bool {
        if case .star = rhs { return true }
        if case .invalid = rhs { return false }
        if case .invalid = lhs { return false }
        if case .star = lhs { return false }

        switch (lhs, rhs) {
        case let (.invariant(la), .invariant(ra)):
            return isSubtype(la, ra) && isSubtype(ra, la)
        case let (.invariant(la), .out(ra)):
            return isSubtype(la, ra)
        case let (.invariant(la), .in(ra)):
            return isSubtype(ra, la)
        case let (.out(la), .out(ra)):
            return isSubtype(la, ra)
        case let (.in(la), .in(ra)):
            return isSubtype(ra, la)
        default:
            return false
        }
    }

    private func substituteTypeArg(_ arg: TypeArg, childSymbol: SymbolID, childArgs: [TypeArg]) -> TypeArg {
        switch arg {
        case let .invariant(type):
            .invariant(substituteChildTypeParam(type, childSymbol: childSymbol, childArgs: childArgs))
        case let .out(type):
            .out(substituteChildTypeParam(type, childSymbol: childSymbol, childArgs: childArgs))
        case let .in(type):
            .in(substituteChildTypeParam(type, childSymbol: childSymbol, childArgs: childArgs))
        case .star:
            .star
        }
    }

    private func substituteChildTypeParam(_ type: TypeID, childSymbol: SymbolID, childArgs: [TypeArg]) -> TypeID {
        guard case let .typeParam(typeParam) = kind(of: type) else {
            return type
        }
        let childTypeParams = nominalTypeParameterSymbols(for: childSymbol)
        guard let index = childTypeParams.firstIndex(of: typeParam.symbol),
              index < childArgs.count
        else {
            return type
        }
        switch childArgs[index] {
        case let .invariant(inner), let .out(inner), let .in(inner):
            return inner
        case .star:
            return nullableAnyType
        }
    }
}
