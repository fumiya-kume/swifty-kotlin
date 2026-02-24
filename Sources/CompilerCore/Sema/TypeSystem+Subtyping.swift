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
            // Nothing? is subtype of all nullable types, Any?, and Nothing? itself
            switch rhs {
            case .error:
                return true
            case .any(.nullable):
                return true
            case .nothing(.nullable):
                return true
            case .primitive(_, .nullable):
                return true
            case .classType(let ct) where ct.nullability == .nullable:
                return true
            case .typeParam(let tp) where tp.nullability == .nullable:
                return true
            case .functionType(let ft) where ft.nullability == .nullable:
                return true
            case .intersection(let parts):
                return parts.contains { isSubtype(subtype, $0) }
            default:
                return false
            }
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
        if case .any(.nonNull) = rhs {
            switch lhs {
            case .any(.nonNull), .unit, .nothing(.nonNull):
                return true
            case .primitive(_, let nullability):
                return nullability == .nonNull
            case .classType(let classType):
                return classType.nullability == .nonNull
            case .functionType(let functionType):
                return functionType.nullability == .nonNull
            case .typeParam(let typeParam):
                return typeParam.nullability == .nonNull
            case .intersection(let parts):
                return parts.allSatisfy { isSubtype($0, supertype) }
            default:
                return false
            }
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
            for index in 0..<leftClass.args.count {
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
            for (leftParam, rightParam) in zip(leftFunction.params, rightFunction.params) {
                if !isSubtype(rightParam, leftParam) {
                    return false
                }
            }
            return isSubtype(leftFunction.returnType, rightFunction.returnType)

        case let (.intersection(parts), _):
            return parts.allSatisfy { isSubtype($0, supertype) }

        case let (_, .intersection(parts)):
            return parts.contains { isSubtype(subtype, $0) }

        case (.any(let leftNullability), .any(let rightNullability)):
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
        let result: TypeID
        if filtered.dropFirst().allSatisfy({ $0 == first }) {
            result = first
        } else if filtered.allSatisfy({ isSubtype($0, nullableAnyType) }) {
            result = nullableAnyType
        } else {
            result = anyType
        }
        // If any input was Nothing? (null literal), the result must be nullable
        if hasNullableNothing {
            let nullable = makeNullable(result)
            // For types where makeNullable is a no-op (e.g. Unit), fall back to Any?
            if nullable == result {
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
            return hasNullableNothing ? nullableNothingType : nothingType
        }
        return make(.intersection(types))
    }

    @available(*, deprecated, message: "Use lub(_:) instead.")
    public func leastUpperBound(_ types: [TypeID]) -> TypeID {
        lub(types)
    }

    @available(*, deprecated, message: "Use glb(_:) instead.")
    public func greatestLowerBound(_ types: [TypeID]) -> TypeID {
        glb(types)
    }

    internal func nullabilitySubtype(_ lhs: Nullability, _ rhs: Nullability) -> Bool {
        lhs == rhs || (lhs == .nonNull && rhs == .nullable)
    }

    internal func isNominalSubtypeSymbol(_ candidate: SymbolID, of base: SymbolID) -> Bool {
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

    internal enum Projection {
        case invariant(TypeID)
        case out(TypeID)
        case `in`(TypeID)
        case star
        case invalid
    }

    internal func normalizedNominalVariances(for symbol: SymbolID, arity: Int) -> [TypeVariance] {
        let stored = nominalTypeParameterVariances(for: symbol)
        if stored.count >= arity {
            return Array(stored.prefix(arity))
        }
        if stored.isEmpty {
            return Array(repeating: .invariant, count: arity)
        }
        return stored + Array(repeating: .invariant, count: arity - stored.count)
    }

    internal func composedProjection(
        declarationVariance: TypeVariance,
        useSite: TypeArg
    ) -> Projection {
        switch declarationVariance {
        case .invariant:
            return projection(from: useSite)
        case .out:
            switch useSite {
            case .invariant(let type):
                return .out(type)
            case .out(let type):
                return .out(type)
            case .star:
                return .star
            case .in:
                return .invalid
            }
        case .in:
            switch useSite {
            case .invariant(let type):
                return .in(type)
            case .in(let type):
                return .in(type)
            case .star:
                return .star
            case .out:
                return .invalid
            }
        }
    }

    internal func projection(from arg: TypeArg) -> Projection {
        switch arg {
        case .invariant(let type):
            return .invariant(type)
        case .out(let type):
            return .out(type)
        case .in(let type):
            return .in(type)
        case .star:
            return .star
        }
    }

    internal func isProjectionSubtype(_ lhs: Projection, _ rhs: Projection) -> Bool {
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
}
