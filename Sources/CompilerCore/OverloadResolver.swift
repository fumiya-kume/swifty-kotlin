public struct CallArg {
    public let label: InternedString?
    public let type: TypeID

    public init(label: InternedString? = nil, type: TypeID) {
        self.label = label
        self.type = type
    }
}

public struct CallExpr {
    public let range: SourceRange
    public let calleeName: InternedString
    public let args: [CallArg]

    public init(range: SourceRange, calleeName: InternedString, args: [CallArg]) {
        self.range = range
        self.calleeName = calleeName
        self.args = args
    }
}

public struct ResolvedCall {
    public let chosenCallee: SymbolID?
    public let substitutedTypeArguments: [TypeVarID: TypeID]
    public let parameterMapping: [Int: Int]
    public let diagnostic: Diagnostic?

    public init(
        chosenCallee: SymbolID?,
        substitutedTypeArguments: [TypeVarID: TypeID],
        parameterMapping: [Int: Int],
        diagnostic: Diagnostic?
    ) {
        self.chosenCallee = chosenCallee
        self.substitutedTypeArguments = substitutedTypeArguments
        self.parameterMapping = parameterMapping
        self.diagnostic = diagnostic
    }
}

public final class OverloadResolver {
    public init() {}

    public func resolveCall(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        ctx: SemaContext
    ) -> ResolvedCall {
        let solver = ConstraintSolver()
        var viable: [ViableCandidate] = []
        for candidate in candidates {
            guard let symbol = ctx.symbols.symbol(candidate) else {
                continue
            }
            guard symbol.kind == .function || symbol.kind == .constructor else {
                continue
            }
            guard let signature = ctx.symbols.functionSignature(for: candidate) else {
                continue
            }
            // Unqualified calls currently have no receiver expression in CallExpr.
            // Skip extension-call candidates until receiver-based call modeling is added.
            if signature.receiverType != nil {
                continue
            }
            guard let parameterMapping = buildParameterMapping(
                signature: signature,
                callArgs: call.args,
                symbols: ctx.symbols
            ) else {
                continue
            }

            let typeVarBySymbol = makeTypeVarBySymbol(signature.typeParameterSymbols)
            var constraints: [VariableConstraint] = []

            for argIndex in call.args.indices {
                guard let paramIndex = parameterMapping[argIndex],
                      paramIndex >= 0,
                      paramIndex < signature.parameterTypes.count else {
                    constraints.removeAll(keepingCapacity: false)
                    break
                }
                let arg = call.args[argIndex]
                let paramType = signature.parameterTypes[paramIndex]
                let rhsOperand = operand(
                    for: paramType,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: ctx.types
                )
                constraints.append(
                    VariableConstraint(
                        kind: .subtype,
                        left: .type(arg.type),
                        right: rhsOperand,
                        blameRange: call.range
                    )
                )
            }
            if constraints.isEmpty && !call.args.isEmpty {
                continue
            }

            if let expectedType {
                let lhsOperand = operand(
                    for: signature.returnType,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: ctx.types
                )
                constraints.append(
                    VariableConstraint(
                        kind: .subtype,
                        left: lhsOperand,
                        right: .type(expectedType),
                        blameRange: call.range
                    )
                )
            }

            let varsToSolve = usedTypeVariables(from: constraints)
            let substitution: [TypeVarID: TypeID]
            if varsToSolve.isEmpty {
                let allSatisfied = constraints.allSatisfy { constraint in
                    return isConstraintSatisfiedWithoutVariables(constraint, typeSystem: ctx.types)
                }
                if !allSatisfied {
                    continue
                }
                substitution = [:]
            } else {
                let solution = solver.solve(
                    vars: varsToSolve,
                    constraints: constraints,
                    typeSystem: ctx.types
                )
                if !solution.isSuccess {
                    continue
                }
                substitution = solution.substitution
            }

            let instantiatedParameterTypes: [TypeID] = call.args.indices.compactMap { argIndex in
                guard let paramIndex = parameterMapping[argIndex],
                      paramIndex >= 0,
                      paramIndex < signature.parameterTypes.count else {
                    return nil
                }
                let type = signature.parameterTypes[paramIndex]
                return substituteTypeParameters(
                    in: type,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: ctx.types
                )
            }
            if instantiatedParameterTypes.count != call.args.count {
                continue
            }
            viable.append(
                ViableCandidate(
                    symbol: candidate,
                    signature: signature,
                    instantiatedParameterTypes: instantiatedParameterTypes,
                    substitutedTypeArguments: substitution,
                    parameterMapping: parameterMapping
                )
            )
        }

        if viable.isEmpty {
            let diagnostic = Diagnostic(
                severity: .error,
                code: "KSWIFTK-SEMA-0002",
                message: "No viable overload found for call.",
                primaryRange: call.range,
                secondaryRanges: []
            )
            return ResolvedCall(
                chosenCallee: nil,
                substitutedTypeArguments: [:],
                parameterMapping: [:],
                diagnostic: diagnostic
            )
        }

        if viable.count > 1 {
            if let chosen = pickMostSpecific(viable, typeSystem: ctx.types) {
                return ResolvedCall(
                    chosenCallee: chosen.symbol,
                    substitutedTypeArguments: chosen.substitutedTypeArguments,
                    parameterMapping: chosen.parameterMapping,
                    diagnostic: nil
                )
            }
            let diagnostic = Diagnostic(
                severity: .error,
                code: "KSWIFTK-SEMA-0003",
                message: "Ambiguous overload resolution.",
                primaryRange: call.range,
                secondaryRanges: []
            )
            return ResolvedCall(
                chosenCallee: nil,
                substitutedTypeArguments: [:],
                parameterMapping: [:],
                diagnostic: diagnostic
            )
        }

        let chosen = viable[0]
        return ResolvedCall(
            chosenCallee: chosen.symbol,
            substitutedTypeArguments: chosen.substitutedTypeArguments,
            parameterMapping: chosen.parameterMapping,
            diagnostic: nil
        )
    }

    private struct ViableCandidate {
        let symbol: SymbolID
        let signature: FunctionSignature
        let instantiatedParameterTypes: [TypeID]
        let substitutedTypeArguments: [TypeVarID: TypeID]
        let parameterMapping: [Int: Int]
    }

    private func buildParameterMapping(
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

        let hasNamedArgs = callArgs.contains(where: { $0.label != nil })
        if hasNamedArgs {
            return buildNamedMapping(
                callArgs: callArgs,
                paramNames: paramNames,
                hasDefaultValues: hasDefaultValues,
                isVararg: isVararg
            )
        }
        return buildPositionalMapping(
            callArgs: callArgs,
            paramCount: paramCount,
            hasDefaultValues: hasDefaultValues,
            isVararg: isVararg
        )
    }

    private func normalizeFlags(_ flags: [Bool], count: Int) -> [Bool] {
        if flags.count == count {
            return flags
        }
        if flags.count > count {
            return Array(flags.prefix(count))
        }
        return flags + Array(repeating: false, count: count - flags.count)
    }

    private func parameterNames(
        for signature: FunctionSignature,
        symbols: SymbolTable,
        count: Int
    ) -> [InternedString?] {
        var names: [InternedString?] = []
        names.reserveCapacity(count)
        for index in 0..<count {
            if index < signature.valueParameterSymbols.count,
               let symbol = symbols.symbol(signature.valueParameterSymbols[index]) {
                names.append(symbol.name)
            } else {
                names.append(nil)
            }
        }
        return names
    }

    private func buildPositionalMapping(
        callArgs: [CallArg],
        paramCount: Int,
        hasDefaultValues: [Bool],
        isVararg: [Bool]
    ) -> [Int: Int]? {
        let varargIndices = isVararg.enumerated().filter { $0.element }.map(\.offset)
        if varargIndices.count > 1 {
            return nil
        }

        var mapping: [Int: Int] = [:]
        if let varargIndex = varargIndices.first {
            // Keep the initial implementation deterministic: only trailing vararg.
            if varargIndex != paramCount - 1 {
                return nil
            }
            let fixedCount = varargIndex
            if callArgs.count < fixedCount {
                return nil
            }
            for index in 0..<fixedCount {
                mapping[index] = index
            }
            if callArgs.count > fixedCount {
                for argIndex in fixedCount..<callArgs.count {
                    mapping[argIndex] = varargIndex
                }
            }
            return mapping
        }

        if callArgs.count > paramCount {
            return nil
        }
        for index in callArgs.indices {
            mapping[index] = index
        }
        if callArgs.count < paramCount {
            for paramIndex in callArgs.count..<paramCount {
                if !hasDefaultValues[paramIndex] {
                    return nil
                }
            }
        }
        return mapping
    }

    private func buildNamedMapping(
        callArgs: [CallArg],
        paramNames: [InternedString?],
        hasDefaultValues: [Bool],
        isVararg: [Bool]
    ) -> [Int: Int]? {
        if callArgs.contains(where: { $0.label == nil }) {
            return nil
        }

        var mapping: [Int: Int] = [:]
        var boundNonVarargParams: Set<Int> = []
        for (argIndex, arg) in callArgs.enumerated() {
            guard let label = arg.label else {
                return nil
            }
            guard let paramIndex = paramNames.firstIndex(where: { $0 == label }) else {
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

    private func makeTypeVarBySymbol(_ symbols: [SymbolID]) -> [SymbolID: TypeVarID] {
        var mapping: [SymbolID: TypeVarID] = [:]
        var index: Int32 = 0
        for symbol in symbols {
            mapping[symbol] = TypeVarID(rawValue: index)
            index += 1
        }
        return mapping
    }

    private func usedTypeVariables(from constraints: [VariableConstraint]) -> [TypeVarID] {
        var seen: Set<TypeVarID> = []
        for constraint in constraints {
            if case .variable(let variable) = constraint.left {
                seen.insert(variable)
            }
            if case .variable(let variable) = constraint.right {
                seen.insert(variable)
            }
        }
        return seen.sorted(by: { $0.rawValue < $1.rawValue })
    }

    private func operand(
        for type: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem
    ) -> ConstraintOperand {
        let kind = typeSystem.kind(of: type)
        if case .typeParam(let typeParam) = kind,
           let variable = typeVarBySymbol[typeParam.symbol] {
            return .variable(variable)
        }
        return .type(type)
    }

    private func isConstraintSatisfiedWithoutVariables(
        _ constraint: VariableConstraint,
        typeSystem: TypeSystem
    ) -> Bool {
        guard case .type(let lhs) = constraint.left,
              case .type(let rhs) = constraint.right else {
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

    private func substituteTypeParameters(
        in type: TypeID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem
    ) -> TypeID {
        let kind = typeSystem.kind(of: type)
        switch kind {
        case .typeParam(let typeParam):
            if let variable = typeVarBySymbol[typeParam.symbol],
               let concrete = substitution[variable] {
                return concrete
            }
            return type

        case .classType(let classType):
            let newArgs: [TypeArg] = classType.args.map { arg in
                switch arg {
                case .invariant(let type):
                    return .invariant(substituteTypeParameters(
                        in: type,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem
                    ))
                case .out(let type):
                    return .out(substituteTypeParameters(
                        in: type,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem
                    ))
                case .in(let type):
                    return .in(substituteTypeParameters(
                        in: type,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem
                    ))
                case .star:
                    return .star
                }
            }
            if newArgs == classType.args {
                return type
            }
            return typeSystem.make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: newArgs,
                nullability: classType.nullability
            )))

        case .functionType(let functionType):
            let newReceiver = functionType.receiver.map { receiver in
                substituteTypeParameters(
                    in: receiver,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem
                )
            }
            let newParams = functionType.params.map { param in
                substituteTypeParameters(
                    in: param,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem
                )
            }
            let newReturn = substituteTypeParameters(
                in: functionType.returnType,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem
            )
            if newReceiver == functionType.receiver &&
                newParams == functionType.params &&
                newReturn == functionType.returnType {
                return type
            }
            return typeSystem.make(.functionType(FunctionType(
                receiver: newReceiver,
                params: newParams,
                returnType: newReturn,
                isSuspend: functionType.isSuspend,
                nullability: functionType.nullability
            )))

        case .intersection(let parts):
            let newParts = parts.map { part in
                substituteTypeParameters(
                    in: part,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem
                )
            }
            if newParts == parts {
                return type
            }
            return typeSystem.make(.intersection(newParts))

        default:
            return type
        }
    }

    private func pickMostSpecific(
        _ candidates: [ViableCandidate],
        typeSystem: TypeSystem
    ) -> ViableCandidate? {
        let winners = candidates.filter { candidate in
            for other in candidates where other.symbol != candidate.symbol {
                if !isMoreSpecific(
                    candidate.instantiatedParameterTypes,
                    than: other.instantiatedParameterTypes,
                    typeSystem: typeSystem
                ) {
                    return false
                }
            }
            return true
        }
        if winners.count == 1 {
            return winners[0]
        }
        return nil
    }

    private func isMoreSpecific(
        _ lhs: [TypeID],
        than rhs: [TypeID],
        typeSystem: TypeSystem
    ) -> Bool {
        if lhs.count != rhs.count {
            return false
        }
        var sawStrict = false
        for (lhsParam, rhsParam) in zip(lhs, rhs) {
            let lhsSubRhs = typeSystem.isSubtype(lhsParam, rhsParam)
            if !lhsSubRhs {
                return false
            }
            let rhsSubLhs = typeSystem.isSubtype(rhsParam, lhsParam)
            if lhsSubRhs && !rhsSubLhs {
                sawStrict = true
            }
        }
        return sawStrict
    }
}
