public extension TypeSystem {
    /// Returns the suffix character representing the given nullability: `""`, `"?"`, or `"!"`.
    internal func nullabilitySuffix(_ nullability: Nullability) -> String {
        switch nullability {
        case .nullable: "?"
        case .platformType: "!"
        case .nonNull: ""
        }
    }

    internal func renderType(_ type: TypeID) -> String {
        switch kind(of: type) {
        case .error:
            return "<error>"
        case .unit:
            return "Unit"
        case let .nothing(nullability):
            return "Nothing\(nullabilitySuffix(nullability))"
        case let .any(nullability):
            return "Any\(nullabilitySuffix(nullability))"
        case let .primitive(primitive, nullability):
            let base = primitive.kotlinName
            return "\(base)\(nullabilitySuffix(nullability))"
        case let .classType(classType):
            let args = if classType.args.isEmpty {
                ""
            } else {
                "<" + classType.args.map(renderTypeArg).joined(separator: ", ") + ">"
            }
            return "Class#\(classType.classSymbol.rawValue)\(args)\(nullabilitySuffix(classType.nullability))"
        case let .typeParam(typeParam):
            return "T#\(typeParam.symbol.rawValue)\(nullabilitySuffix(typeParam.nullability))"
        case let .functionType(functionType):
            let receiverPrefix = if let receiver = functionType.receiver {
                "\(renderType(receiver))."
            } else {
                ""
            }
            let suspendPrefix = functionType.isSuspend ? "suspend " : ""
            let params = functionType.params.map(renderType).joined(separator: ", ")
            let retType = renderType(functionType.returnType)
            let suffix = nullabilitySuffix(functionType.nullability)
            return "\(suspendPrefix)\(receiverPrefix)(\(params)) -> \(retType)\(suffix)"
        case let .intersection(parts):
            return parts.map(renderType).joined(separator: " & ")
        }
    }

    private func renderTypeArg(_ arg: TypeArg) -> String {
        switch arg {
        case let .invariant(type):
            renderType(type)
        case let .out(type):
            "out \(renderType(type))"
        case let .in(type):
            "in \(renderType(type))"
        case .star:
            "*"
        }
    }

    func makeTypeVarBySymbol(_ symbols: [SymbolID]) -> [SymbolID: TypeVarID] {
        var mapping: [SymbolID: TypeVarID] = [:]
        for (index, symbol) in symbols.enumerated() {
            mapping[symbol] = TypeVarID(rawValue: Int32(index))
        }
        return mapping
    }

    /// Result of checking use-site variance projections on a member access.
    struct VarianceProjectionResult {
        /// Substitution for covariant positions (return types).
        /// For `out Number`: T → Number.  For `in Number`: T → Any?.  For `*`: T → Any?.
        public let covariantSubstitution: [TypeVarID: TypeID]
        /// Type parameter symbols that are projected as `out` or `*` (write-forbidden).
        public let writeForbiddenSymbols: Set<SymbolID>
    }

    /// Resolve the effective upper bound for a type parameter, returning `Any?` when
    /// no explicit bounds exist and an intersection type when multiple bounds exist.
    private func effectiveUpperBound(for symbol: SymbolID, symbols: SymbolTable) -> TypeID {
        let bounds = symbols.typeParameterUpperBounds(for: symbol)
        if bounds.isEmpty { return nullableAnyType }
        if bounds.count == 1 { return bounds[0] }
        return make(.intersection(bounds))
    }

    /// Build variance-aware substitutions for a member access on a projected receiver type.
    ///
    /// Given a receiver like `MutableList<out Number>`, this builds:
    /// - Covariant substitution: T → Number (for return types)
    /// - A set of type parameter symbols that are write-forbidden (`out` or `*` projections)
    ///
    /// Returns `nil` if the receiver has no projected type arguments (all invariant).
    func buildVarianceProjectionSubstitutions(
        receiverType: TypeID,
        signature: FunctionSignature,
        symbols: SymbolTable
    ) -> VarianceProjectionResult? {
        guard case let .classType(classType) = kind(of: receiverType) else {
            return nil
        }
        let typeParamSymbols = nominalTypeParameterSymbols(for: classType.classSymbol)
        guard !typeParamSymbols.isEmpty, !classType.args.isEmpty else { return nil }

        let hasProjection = classType.args.contains { arg in
            switch arg {
            case .out, .in, .star: true
            case .invariant: false
            }
        }
        guard hasProjection else { return nil }

        let typeVarBySymbol = makeTypeVarBySymbol(signature.typeParameterSymbols)
        var covariantSub = typeVarBySymbol.isEmpty ? [:] : [TypeVarID: TypeID]()
        var writeForbidden: Set<SymbolID> = []

        for (index, arg) in classType.args.enumerated() {
            guard index < typeParamSymbols.count else { break }
            let tpSymbol = typeParamSymbols[index]
            guard let typeVar = typeVarBySymbol[tpSymbol] else { continue }
            let resolved = resolveVarianceArg(arg, tpSymbol: tpSymbol, symbols: symbols)
            covariantSub[typeVar] = resolved.type
            if resolved.writeForbidden { writeForbidden.insert(tpSymbol) }
        }

        return VarianceProjectionResult(
            covariantSubstitution: covariantSub,
            writeForbiddenSymbols: writeForbidden
        )
    }

    /// Resolve a single variance-projected type argument into a covariant substitution entry.
    /// Returns the substituted type and whether the projection forbids writes.
    private func resolveVarianceArg(
        _ arg: TypeArg, tpSymbol: SymbolID, symbols: SymbolTable
    ) -> (type: TypeID, writeForbidden: Bool) {
        switch arg {
        case let .invariant(type):
            (type, false)
        case let .out(type):
            (type, true)
        case .in:
            (effectiveUpperBound(for: tpSymbol, symbols: symbols), false)
        case .star:
            (effectiveUpperBound(for: tpSymbol, symbols: symbols), true)
        }
    }

    /// Check if a member function's parameters use any write-forbidden type parameters.
    /// Returns the index of the first violating parameter, or nil if no violation.
    func checkVarianceViolationInParameters(
        signature: FunctionSignature,
        writeForbiddenSymbols: Set<SymbolID>
    ) -> Int? {
        guard !writeForbiddenSymbols.isEmpty else { return nil }
        for (index, paramType) in signature.parameterTypes.enumerated() {
            for symbol in writeForbiddenSymbols where typeContainsTypeParam(paramType, symbol: symbol) {
                return index
            }
        }
        return nil
    }

    func substituteTypeParameters(
        in type: TypeID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID]
    ) -> TypeID {
        let kind = kind(of: type)
        switch kind {
        case let .typeParam(typeParam):
            if let variable = typeVarBySymbol[typeParam.symbol],
               let concrete = substitution[variable]
            {
                switch typeParam.nullability {
                case .nullable, .platformType:
                    return withNullability(typeParam.nullability, for: concrete)
                case .nonNull:
                    return concrete
                }
            }
            return type

        case let .classType(classType):
            let newArgs = classType.args.map {
                substituteTypeArg($0, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
            }
            if newArgs == classType.args { return type }
            return make(.classType(ClassType(
                classSymbol: classType.classSymbol, args: newArgs, nullability: classType.nullability
            )))

        case let .functionType(functionType):
            return substituteFunctionType(
                functionType, originalType: type,
                substitution: substitution, typeVarBySymbol: typeVarBySymbol
            )

        case let .intersection(parts):
            let newParts = parts.map { part in
                substituteTypeParameters(
                    in: part,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            if newParts == parts {
                return type
            }
            return make(.intersection(newParts))

        default:
            return type
        }
    }

    private func substituteTypeArg(
        _ arg: TypeArg,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID]
    ) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            .invariant(substituteTypeParameters(in: inner, substitution: substitution, typeVarBySymbol: typeVarBySymbol))
        case let .out(inner):
            .out(substituteTypeParameters(in: inner, substitution: substitution, typeVarBySymbol: typeVarBySymbol))
        case let .in(inner):
            .in(substituteTypeParameters(in: inner, substitution: substitution, typeVarBySymbol: typeVarBySymbol))
        case .star:
            .star
        }
    }

    private func substituteFunctionType(
        _ functionType: FunctionType,
        originalType: TypeID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID]
    ) -> TypeID {
        let sub = { [self] (t: TypeID) in
            substituteTypeParameters(in: t, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
        }
        let newReceiver = functionType.receiver.map { sub($0) }
        let newParams = functionType.params.map { sub($0) }
        let newReturn = sub(functionType.returnType)
        if newReceiver == functionType.receiver, newParams == functionType.params, newReturn == functionType.returnType {
            return originalType
        }
        return make(.functionType(FunctionType(
            receiver: newReceiver, params: newParams, returnType: newReturn,
            isSuspend: functionType.isSuspend, nullability: functionType.nullability
        )))
    }
}
