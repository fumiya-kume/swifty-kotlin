extension OverloadResolver {
    func buildParameterMapping(
        signature: FunctionSignature,
        callArgs: [CallArg],
        symbols: SymbolTable
    ) -> [Int: Int]? {
        let paramCount = signature.parameterTypes.count
        if paramCount == 0 {
            return callArgs.isEmpty ? [:] : nil
        }

        let hasDefaultValues = normalizeFlags(signature.valueParameterHasDefaultValues, count: paramCount)
        let isVararg = normalizeFlags(signature.valueParameterIsVararg, count: paramCount)
        let paramNames = parameterNames(
            for: signature,
            symbols: symbols,
            count: paramCount
        )
        var mapping: [Int: Int] = [:]
        var boundNonVarargParams: Set<Int> = []
        var sawNamedArgument = false
        var positionalCursor = 0

        for (argIndex, arg) in callArgs.enumerated() {
            if let label = arg.label {
                sawNamedArgument = true
                guard let paramIndex = paramNames.firstIndex(where: { $0 == label }) else {
                    return nil
                }
                if arg.isSpread, !isVararg[paramIndex] {
                    return nil
                }
                if isVararg[paramIndex] {
                    mapping[argIndex] = paramIndex
                    continue
                }
                if boundNonVarargParams.contains(paramIndex) {
                    return nil
                }
                boundNonVarargParams.insert(paramIndex)
                mapping[argIndex] = paramIndex
                if paramIndex == positionalCursor {
                    positionalCursor += 1
                }
                continue
            }

            if sawNamedArgument {
                // In Kotlin, positional arguments after named arguments
                // are allowed only when they bind to a vararg parameter.
                // Advance the cursor past already-bound non-vararg params.
                while positionalCursor < paramCount &&
                    !isVararg[positionalCursor] &&
                    boundNonVarargParams.contains(positionalCursor)
                {
                    positionalCursor += 1
                }
                if positionalCursor >= paramCount || !isVararg[positionalCursor] {
                    return nil
                }
                mapping[argIndex] = positionalCursor
                continue
            }

            while positionalCursor < paramCount,
                  !isVararg[positionalCursor],
                  boundNonVarargParams.contains(positionalCursor)
            {
                positionalCursor += 1
            }
            if positionalCursor >= paramCount {
                return nil
            }

            let paramIndex = positionalCursor
            if arg.isSpread, !isVararg[paramIndex] {
                return nil
            }
            if isVararg[paramIndex] {
                mapping[argIndex] = paramIndex
                continue
            }
            boundNonVarargParams.insert(paramIndex)
            mapping[argIndex] = paramIndex
            positionalCursor += 1
        }

        for paramIndex in paramNames.indices {
            if isVararg[paramIndex] {
                continue
            }
            if boundNonVarargParams.contains(paramIndex) {
                continue
            }
            if !hasDefaultValues[paramIndex] {
                return nil
            }
        }
        return mapping
    }

    func normalizeFlags(_ flags: [Bool], count: Int) -> [Bool] {
        if flags.count == count {
            return flags
        }
        if flags.count > count {
            return Array(flags.prefix(count))
        }
        return flags + Array(repeating: false, count: count - flags.count)
    }

    func parameterNames(
        for signature: FunctionSignature,
        symbols: SymbolTable,
        count: Int
    ) -> [InternedString?] {
        var names: [InternedString?] = []
        names.reserveCapacity(count)
        for index in 0 ..< count {
            if index < signature.valueParameterSymbols.count,
               let symbol = symbols.symbol(signature.valueParameterSymbols[index])
            {
                names.append(symbol.name)
            } else {
                names.append(nil)
            }
        }
        return names
    }

    func usedTypeVariables(from constraints: [VariableConstraint]) -> [TypeVarID] {
        var seen: Set<TypeVarID> = []
        for constraint in constraints {
            if case let .variable(variable) = constraint.left {
                seen.insert(variable)
            }
            if case let .variable(variable) = constraint.right {
                seen.insert(variable)
            }
        }
        return seen.sorted(by: { $0.rawValue < $1.rawValue })
    }

    func operand(
        for type: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem
    ) -> ConstraintOperand {
        let kind = typeSystem.kind(of: type)
        if case let .typeParam(typeParam) = kind,
           let variable = typeVarBySymbol[typeParam.symbol]
        {
            return .variable(variable)
        }
        return .type(type)
    }

    /// Checks whether a type contains any type parameters mapped in `typeVarBySymbol`.
    func containsTypeVariable(
        _ type: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem
    ) -> Bool {
        switch typeSystem.kind(of: type) {
        case let .typeParam(typeParam):
            return typeVarBySymbol[typeParam.symbol] != nil
        case let .intersection(parts):
            return parts.contains {
                containsTypeVariable($0, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
            }
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    containsTypeVariable(inner, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
                case .star:
                    false
                }
            }
        case let .functionType(functionType):
            if let receiver = functionType.receiver,
               containsTypeVariable(receiver, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
            {
                return true
            }
            if containsTypeVariable(functionType.returnType, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem) {
                return true
            }
            return functionType.params.contains {
                containsTypeVariable($0, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
            }
        default:
            return false
        }
    }

    /// Decomposes `subtype <: supertype` into fine-grained constraints that expose
    /// type variables nested inside generic class types and function types.
    ///
    /// For example, given `List<Int> <: List<T>` where `T` is a type variable, this
    /// produces the equality constraint `Int == T` (for invariant type arguments).
    /// For `out` positions it produces `Int <: T`, and for `in` positions `T <: Int`.
    ///
    /// When the supertype is a direct type parameter, it produces a single
    /// `subtype <: variable` constraint, matching the previous `operand()` behavior.
    ///
    /// Falls back to a simple `subtype <: supertype` type constraint when no
    /// decomposition is possible (different class symbols, non-generic types, etc.).
    func decomposeSubtypeConstraint(
        subtype: TypeID,
        supertype: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange?
    ) -> [VariableConstraint] {
        let supertypeKind = typeSystem.kind(of: supertype)

        // Case 1: supertype is a direct type parameter → single variable constraint.
        if case let .typeParam(typeParam) = supertypeKind,
           let variable = typeVarBySymbol[typeParam.symbol]
        {
            if typeParam.nullability != .nonNull {
                if case .nothing(.nullable) = typeSystem.kind(of: subtype) {
                    // `null` / `Nothing?` is compatible with `T?` but does not
                    // constrain the underlying non-null type variable.
                    return []
                }
                let nonNullSubtype = typeSystem.makeNonNullable(subtype)
                return [VariableConstraint(
                    kind: .subtype,
                    left: .type(nonNullSubtype),
                    right: .variable(variable),
                    blameRange: blameRange
                )]
            }
            return [VariableConstraint(
                kind: .subtype,
                left: .type(subtype),
                right: .variable(variable),
                blameRange: blameRange
            )]
        }

        // Case 1.5: supertype is an intersection. Decompose into all parts:
        // `A <: (B & C)` => `A <: B` and `A <: C`.
        if case let .intersection(parts) = supertypeKind {
            var result: [VariableConstraint] = []
            for part in parts {
                result.append(contentsOf: decomposeSubtypeConstraint(
                    subtype: subtype,
                    supertype: part,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: blameRange
                ))
            }
            if !result.isEmpty {
                return result
            }
        }

        // Case 2: supertype is a class type with type args containing type variables.
        if case let .classType(superClass) = supertypeKind,
           !superClass.args.isEmpty,
           containsTypeVariable(supertype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
        {
            let subtypeKind = typeSystem.kind(of: subtype)
            if case let .classType(subClass) = subtypeKind,
               subClass.classSymbol == superClass.classSymbol,
               subClass.args.count == superClass.args.count,
               subClass.nullability == superClass.nullability || superClass.nullability == .nullable
            {
                var result: [VariableConstraint] = []
                for (subArg, superArg) in zip(subClass.args, superClass.args) {
                    let decomposed = decomposeTypeArgConstraint(
                        subArg: subArg,
                        superArg: superArg,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange
                    )
                    result.append(contentsOf: decomposed)
                }
                return result
            }
            if case let .classType(subClass) = subtypeKind,
               let liftedSubtype = liftClassType(
                   subClass,
                   to: superClass.classSymbol,
                   typeSystem: typeSystem
               )
            {
                return decomposeSubtypeConstraint(
                    subtype: liftedSubtype,
                    supertype: supertype,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: blameRange
                )
            }
            // Different class symbols or mismatched arity – fall through to
            // simple constraint which will use isSubtype.
        }

        // Case 3: supertype is a function type with type variables in params/return.
        if case let .functionType(superFunc) = supertypeKind,
           containsTypeVariable(supertype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
        {
            let subtypeKind = typeSystem.kind(of: subtype)
            if case let .functionType(subFunc) = subtypeKind,
               subFunc.params.count == superFunc.params.count,
               subFunc.isSuspend == superFunc.isSuspend,
               subFunc.nullability == superFunc.nullability || superFunc.nullability == .nullable,
               subFunc.receiver == superFunc.receiver
            {
                var result: [VariableConstraint] = []
                // Function types are contravariant in parameter types.
                for (subParam, superParam) in zip(subFunc.params, superFunc.params) {
                    result.append(contentsOf: decomposeSubtypeConstraint(
                        subtype: superParam,
                        supertype: subParam,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange
                    ))
                }
                // Covariant in return type.
                result.append(contentsOf: decomposeSubtypeConstraint(
                    subtype: subFunc.returnType,
                    supertype: superFunc.returnType,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: blameRange
                ))
                return result
            }
        }

        // Case 4: subtype contains type variables (e.g. return type T or List<T>).
        let subtypeKind = typeSystem.kind(of: subtype)
        if case let .typeParam(typeParam) = subtypeKind,
           let variable = typeVarBySymbol[typeParam.symbol]
        {
            return [VariableConstraint(
                kind: .subtype,
                left: .variable(variable),
                right: .type(supertype),
                blameRange: blameRange
            )]
        }

        if case let .classType(subClass) = subtypeKind,
           !subClass.args.isEmpty,
           containsTypeVariable(subtype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
        {
            if case let .classType(superClass) = supertypeKind,
               subClass.classSymbol == superClass.classSymbol,
               subClass.args.count == superClass.args.count,
               subClass.nullability == superClass.nullability || superClass.nullability == .nullable
            {
                var result: [VariableConstraint] = []
                for (subArg, superArg) in zip(subClass.args, superClass.args) {
                    let decomposed = decomposeTypeArgConstraint(
                        subArg: subArg,
                        superArg: superArg,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange
                    )
                    result.append(contentsOf: decomposed)
                }
                return result
            }
        }

        // Default: simple type-to-type constraint.
        return [VariableConstraint(
            kind: .subtype,
            left: .type(subtype),
            right: .type(supertype),
            blameRange: blameRange
        )]
    }

    func liftClassType(
        _ subtype: ClassType,
        to targetSymbol: SymbolID,
        typeSystem: TypeSystem
    ) -> TypeID? {
        guard subtype.classSymbol != targetSymbol else {
            return nil
        }
        return liftClassType(subtype, to: targetSymbol, typeSystem: typeSystem, visited: [])
    }

    private func liftClassType(
        _ subtype: ClassType,
        to targetSymbol: SymbolID,
        typeSystem: TypeSystem,
        visited: Set<SymbolID>
    ) -> TypeID? {
        var visited = visited
        guard visited.insert(subtype.classSymbol).inserted else {
            return nil
        }
        guard typeSystem.isNominalSubtypeSymbol(subtype.classSymbol, of: targetSymbol) else {
            return nil
        }
        if let directLift = liftDirectClassType(subtype, to: targetSymbol, typeSystem: typeSystem) {
            return directLift
        }
        for directSupertype in typeSystem.directNominalSupertypes(for: subtype.classSymbol) {
            guard let directLift = liftDirectClassType(subtype, to: directSupertype, typeSystem: typeSystem),
                  case let .classType(liftedClassType) = typeSystem.kind(of: directLift)
            else {
                continue
            }
            if let transitiveLift = liftClassType(
                liftedClassType,
                to: targetSymbol,
                typeSystem: typeSystem,
                visited: visited
            ) {
                return transitiveLift
            }
        }
        return nil
    }

    private func liftDirectClassType(
        _ subtype: ClassType,
        to targetSymbol: SymbolID,
        typeSystem: TypeSystem
    ) -> TypeID? {
        let mappedArgs = typeSystem.nominalSupertypeTypeArgs(for: subtype.classSymbol, supertype: targetSymbol)
        if mappedArgs.isEmpty {
            guard typeSystem.nominalTypeParameterSymbols(for: targetSymbol).isEmpty else {
                return nil
            }
            return typeSystem.make(.classType(ClassType(
                classSymbol: targetSymbol,
                args: [],
                nullability: subtype.nullability
            )))
        }
        let substitutedArgs = mappedArgs.map {
            substituteChildTypeArg(
                $0,
                childSymbol: subtype.classSymbol,
                childArgs: subtype.args,
                typeSystem: typeSystem
            )
        }
        return typeSystem.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: substitutedArgs,
            nullability: subtype.nullability
        )))
    }

    func substituteChildTypeArg(
        _ arg: TypeArg,
        childSymbol: SymbolID,
        childArgs: [TypeArg],
        typeSystem: TypeSystem
    ) -> TypeArg {
        switch arg {
        case let .invariant(type):
            .invariant(substituteChildTypeParam(type, childSymbol: childSymbol, childArgs: childArgs, typeSystem: typeSystem))
        case let .out(type):
            .out(substituteChildTypeParam(type, childSymbol: childSymbol, childArgs: childArgs, typeSystem: typeSystem))
        case let .in(type):
            .in(substituteChildTypeParam(type, childSymbol: childSymbol, childArgs: childArgs, typeSystem: typeSystem))
        case .star:
            .star
        }
    }

    func substituteChildTypeParam(
        _ type: TypeID,
        childSymbol: SymbolID,
        childArgs: [TypeArg],
        typeSystem: TypeSystem
    ) -> TypeID {
        guard case let .typeParam(typeParam) = typeSystem.kind(of: type) else {
            return type
        }
        let childTypeParams = typeSystem.nominalTypeParameterSymbols(for: childSymbol)
        guard let index = childTypeParams.firstIndex(of: typeParam.symbol),
              index < childArgs.count
        else {
            return type
        }
        switch childArgs[index] {
        case let .invariant(inner), let .out(inner), let .in(inner):
            return inner
        case .star:
            return typeSystem.nullableAnyType
        }
    }

    /// Decomposes a pair of type arguments into constraints respecting variance.
    /// Invariant args produce equality constraints, `out` produces subtype,
    /// `in` produces supertype (reversed direction).
    ///
    /// NOTE: Variance is currently derived from the `TypeArg` enum cases (use-site
    /// projection). A future enhancement could incorporate declaration-site variance
    /// from the enclosing class's type parameter definitions.
    func decomposeTypeArgConstraint(
        subArg: TypeArg,
        superArg: TypeArg,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange?
    ) -> [VariableConstraint] {
        switch (subArg, superArg) {
        case let (.invariant(subInner), .invariant(superInner)):
            // Invariant: both directions (equality).
            var result = decomposeSubtypeConstraint(
                subtype: subInner, supertype: superInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            )
            result.append(contentsOf: decomposeSubtypeConstraint(
                subtype: superInner, supertype: subInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            ))
            return result

        case let (.invariant(subInner), .out(superInner)),
             let (.out(subInner), .out(superInner)):
            // Covariant: sub <: super.
            return decomposeSubtypeConstraint(
                subtype: subInner, supertype: superInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            )

        case let (.invariant(subInner), .in(superInner)),
             let (.in(subInner), .in(superInner)):
            // Contravariant: super <: sub.
            return decomposeSubtypeConstraint(
                subtype: superInner, supertype: subInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            )

        case let (.star, .invariant(superInner)):
            // Subtype is star (e.g. receiver `Box<*>` against signature `Box<T>`).
            // Star projection is equivalent to `out Any?`, so constrain T = Any?
            // to ensure the solver can infer the type variable.
            return decomposeSubtypeConstraint(
                subtype: typeSystem.nullableAnyType, supertype: superInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            ) + decomposeSubtypeConstraint(
                subtype: superInner, supertype: typeSystem.nullableAnyType,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            )

        default:
            // Incompatible variance combinations (e.g. .out vs .in) – conservatively
            // treat as invariant so the original subtype relation is still enforced.
            let subInner: TypeID
            let superInner: TypeID
            switch subArg {
            case let .invariant(t), let .out(t), let .in(t): subInner = t
            case .star: return []
            }
            switch superArg {
            case let .invariant(t), let .out(t), let .in(t): superInner = t
            case .star: return []
            }
            var fallback = decomposeSubtypeConstraint(
                subtype: subInner, supertype: superInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            )
            fallback.append(contentsOf: decomposeSubtypeConstraint(
                subtype: superInner, supertype: subInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            ))
            return fallback
        }
    }

    func isConstraintSatisfiedWithoutVariables(
        _ constraint: VariableConstraint,
        typeSystem: TypeSystem
    ) -> Bool {
        guard case let .type(lhs) = constraint.left,
              case let .type(rhs) = constraint.right
        else {
            return false
        }
        switch constraint.kind {
        case .subtype:
            return typeSystem.isSubtype(lhs, rhs)
        case .equal:
            return typeSystem.isSubtype(lhs, rhs) && typeSystem.isSubtype(rhs, lhs)
        case .supertype:
            return typeSystem.isSubtype(rhs, lhs)
        }
    }

    // Returns a diagnostic when the solver resolved a type variable to `errorType`,
    // meaning no constraints existed to determine it.  The caller should require
    // explicit type arguments in that case.
}
