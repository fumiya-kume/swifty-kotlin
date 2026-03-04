public extension TypeSystem {
    internal func renderType(_ type: TypeID) -> String {
        switch kind(of: type) {
        case .error:
            return "<error>"
        case .unit:
            return "Unit"
        case let .nothing(nullability):
            return nullability == .nullable ? "Nothing?" : "Nothing"
        case let .any(nullability):
            return nullability == .nullable ? "Any?" : "Any"
        case let .primitive(primitive, nullability):
            let base = switch primitive {
            case .boolean:
                "Boolean"
            case .char:
                "Char"
            case .int:
                "Int"
            case .long:
                "Long"
            case .float:
                "Float"
            case .double:
                "Double"
            case .string:
                "String"
            }
            return nullability == .nullable ? "\(base)?" : base
        case let .classType(classType):
            let args = if classType.args.isEmpty {
                ""
            } else {
                "<" + classType.args.map(renderTypeArg).joined(separator: ", ") + ">"
            }
            let nullSuffix = classType.nullability == .nullable ? "?" : ""
            return "Class#\(classType.classSymbol.rawValue)\(args)\(nullSuffix)"
        case let .typeParam(typeParam):
            let nullSuffix = typeParam.nullability == .nullable ? "?" : ""
            return "T#\(typeParam.symbol.rawValue)\(nullSuffix)"
        case let .functionType(functionType):
            let receiverPrefix = if let receiver = functionType.receiver {
                "\(renderType(receiver))."
            } else {
                ""
            }
            let suspendPrefix = functionType.isSuspend ? "suspend " : ""
            let params = functionType.params.map(renderType).joined(separator: ", ")
            let nullSuffix = functionType.nullability == .nullable ? "?" : ""
            return "\(suspendPrefix)\(receiverPrefix)(\(params)) -> \(renderType(functionType.returnType))\(nullSuffix)"
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
        let classSymbol = classType.classSymbol
        let typeParamSymbols = nominalTypeParameterSymbols(for: classSymbol)

        guard !typeParamSymbols.isEmpty, !classType.args.isEmpty else {
            return nil
        }

        // Check if any arg is projected (non-invariant with a concrete type or star)
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

            switch arg {
            case let .invariant(type):
                covariantSub[typeVar] = type
            case let .out(type):
                covariantSub[typeVar] = type
                writeForbidden.insert(tpSymbol)
            case .in:
                let upperBounds = symbols.typeParameterUpperBounds(for: tpSymbol)
                let upperBound: TypeID = if upperBounds.isEmpty {
                    nullableAnyType
                } else if upperBounds.count == 1 {
                    upperBounds[0]
                } else {
                    make(.intersection(upperBounds))
                }
                covariantSub[typeVar] = upperBound
            case .star:
                let upperBounds = symbols.typeParameterUpperBounds(for: tpSymbol)
                let upperBound: TypeID = if upperBounds.isEmpty {
                    nullableAnyType
                } else if upperBounds.count == 1 {
                    upperBounds[0]
                } else {
                    make(.intersection(upperBounds))
                }
                covariantSub[typeVar] = upperBound
                writeForbidden.insert(tpSymbol)
            }
        }

        return VarianceProjectionResult(
            covariantSubstitution: covariantSub,
            writeForbiddenSymbols: writeForbidden
        )
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
               let concrete = substitution[variable] {
                return concrete
            }
            return type

        case let .classType(classType):
            let newArgs: [TypeArg] = classType.args.map { arg in
                switch arg {
                case let .invariant(inner):
                    .invariant(substituteTypeParameters(
                        in: inner,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    ))
                case let .out(inner):
                    .out(substituteTypeParameters(
                        in: inner,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    ))
                case let .in(inner):
                    .in(substituteTypeParameters(
                        in: inner,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    ))
                case .star:
                    .star
                }
            }
            if newArgs == classType.args {
                return type
            }
            return make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: newArgs,
                nullability: classType.nullability
            )))

        case let .functionType(functionType):
            let newReceiver = functionType.receiver.map { receiver in
                substituteTypeParameters(
                    in: receiver,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            let newParams = functionType.params.map { param in
                substituteTypeParameters(
                    in: param,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            let newReturn = substituteTypeParameters(
                in: functionType.returnType,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if newReceiver == functionType.receiver,
               newParams == functionType.params,
               newReturn == functionType.returnType {
                return type
            }
            return make(.functionType(FunctionType(
                receiver: newReceiver,
                params: newParams,
                returnType: newReturn,
                isSuspend: functionType.isSuspend,
                nullability: functionType.nullability
            )))

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
}
