public struct CallArg {
    public let label: InternedString?
    public let isSpread: Bool
    public let type: TypeID

    public init(label: InternedString? = nil, isSpread: Bool = false, type: TypeID) {
        self.label = label
        self.isSpread = isSpread
        self.type = type
    }
}

public struct CallExpr {
    public let range: SourceRange
    public let calleeName: InternedString
    public let args: [CallArg]
    public let explicitTypeArgs: [TypeID]

    public init(range: SourceRange, calleeName: InternedString, args: [CallArg], explicitTypeArgs: [TypeID] = []) {
        self.range = range
        self.calleeName = calleeName
        self.args = args
        self.explicitTypeArgs = explicitTypeArgs
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
        implicitReceiverType: TypeID? = nil,
        ctx: SemaModule
    ) -> ResolvedCall {
        let solver = ConstraintSolver()
        var viable: [ViableCandidate] = []
        var candidateFailures: [Diagnostic] = []
        for candidate in candidates {
            let evaluation = evaluateCandidate(
                candidate,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                solver: solver,
                ctx: ctx
            )
            switch evaluation {
            case .viable(let value):
                viable.append(value)
            case .constraintFailure(let diagnostic):
                candidateFailures.append(diagnostic)
            case .rejected:
                continue
            }
        }
        return selectResult(
            from: viable,
            call: call,
            typeSystem: ctx.types,
            candidateFailures: candidateFailures
        )
    }

    private func evaluateCandidate(
        _ candidate: SymbolID,
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        solver: ConstraintSolver,
        ctx: SemaModule
    ) -> CandidateEvaluation {
        guard let symbol = ctx.symbols.symbol(candidate),
              symbol.kind == .function || symbol.kind == .constructor,
              let signature = ctx.symbols.functionSignature(for: candidate) else {
            return .rejected
        }

        let typeVarBySymbol = ctx.types.makeTypeVarBySymbol(signature.typeParameterSymbols)

        // Apply explicit type argument constraints if provided
        if !call.explicitTypeArgs.isEmpty {
            guard call.explicitTypeArgs.count == signature.typeParameterSymbols.count else {
                return .rejected
            }
        }

        guard var constraints = buildReceiverConstraints(
            signature: signature,
            implicitReceiverType: implicitReceiverType,
            typeVarBySymbol: typeVarBySymbol,
            range: call.range,
            typeSystem: ctx.types
        ) else {
            return .rejected
        }

        guard let parameterMapping = buildParameterMapping(
            signature: signature,
            callArgs: call.args,
            symbols: ctx.symbols
        ) else {
            return .rejected
        }

        guard appendArgumentConstraints(
            to: &constraints,
            call: call,
            parameterMapping: parameterMapping,
            signature: signature,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: ctx.types
        ) else {
            return .rejected
        }

        // Add equality constraints for explicit type arguments
        for (index, explicitArg) in call.explicitTypeArgs.enumerated() {
            let typeParamSymbol = signature.typeParameterSymbols[index]
            if let typeVar = typeVarBySymbol[typeParamSymbol] {
                constraints.append(
                    VariableConstraint(
                        kind: .equal,
                        left: .variable(typeVar),
                        right: .type(explicitArg),
                        blameRange: call.range
                    )
                )
            }
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

        let solveResult = solveConstraints(
            constraints,
            solver: solver,
            typeSystem: ctx.types
        )
        let substitution: [TypeVarID: TypeID]
        switch solveResult {
        case .success(let value):
            substitution = value
        case .constraintFailure(let diagnostic):
            return .constraintFailure(diagnostic)
        case .rejected:
            return .rejected
        }

        if let boundViolation = checkTypeParameterBounds(
            signature: signature,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol,
            range: call.range,
            ctx: ctx
        ) {
            return .constraintFailure(boundViolation)
        }

        let instantiatedParameterTypes: [TypeID] = call.args.indices.compactMap { argIndex in
            guard let paramIndex = parameterMapping[argIndex],
                  paramIndex >= 0,
                  paramIndex < signature.parameterTypes.count else {
                return nil
            }
            return ctx.types.substituteTypeParameters(
                in: signature.parameterTypes[paramIndex],
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
        }
        guard instantiatedParameterTypes.count == call.args.count else {
            return .rejected
        }

        return .viable(ViableCandidate(
            symbol: candidate,
            signature: signature,
            instantiatedParameterTypes: instantiatedParameterTypes,
            substitutedTypeArguments: substitution,
            parameterMapping: parameterMapping
        ))
    }

    private func buildReceiverConstraints(
        signature: FunctionSignature,
        implicitReceiverType: TypeID?,
        typeVarBySymbol: [SymbolID: TypeVarID],
        range: SourceRange,
        typeSystem: TypeSystem
    ) -> [VariableConstraint]? {
        guard let receiverType = signature.receiverType else {
            return []
        }
        guard let implicitReceiverType else {
            return nil
        }
        let rhsOperand = operand(
            for: receiverType,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: typeSystem
        )
        return [VariableConstraint(
            kind: .subtype,
            left: .type(implicitReceiverType),
            right: rhsOperand,
            blameRange: range
        )]
    }

    private func appendArgumentConstraints(
        to constraints: inout [VariableConstraint],
        call: CallExpr,
        parameterMapping: [Int: Int],
        signature: FunctionSignature,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem
    ) -> Bool {
        for argIndex in call.args.indices {
            guard let paramIndex = parameterMapping[argIndex],
                  paramIndex >= 0,
                  paramIndex < signature.parameterTypes.count else {
                constraints.removeAll(keepingCapacity: false)
                break
            }
            let rhsOperand = operand(
                for: signature.parameterTypes[paramIndex],
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem
            )
            constraints.append(
                VariableConstraint(
                    kind: .subtype,
                    left: .type(call.args[argIndex].type),
                    right: rhsOperand,
                    blameRange: call.range
                )
            )
        }
        return !(constraints.isEmpty && !call.args.isEmpty)
    }

    private func solveConstraints(
        _ constraints: [VariableConstraint],
        solver: ConstraintSolver,
        typeSystem: TypeSystem
    ) -> ConstraintSolveResult {
        let varsToSolve = usedTypeVariables(from: constraints)
        if varsToSolve.isEmpty {
            let allSatisfied = constraints.allSatisfy {
                isConstraintSatisfiedWithoutVariables($0, typeSystem: typeSystem)
            }
            return allSatisfied ? .success([:]) : .rejected
        }
        let solution = solver.solve(
            vars: varsToSolve,
            constraints: constraints,
            typeSystem: typeSystem
        )
        if solution.isSuccess {
            return .success(solution.substitution)
        }
        if let failure = solution.failure {
            return .constraintFailure(failure)
        }
        return .rejected
    }

    private func selectResult(
        from viable: [ViableCandidate],
        call: CallExpr,
        typeSystem: TypeSystem,
        candidateFailures: [Diagnostic]
    ) -> ResolvedCall {
        if viable.isEmpty {
            if let diagnostic = candidateFailures.first {
                return ResolvedCall(
                    chosenCallee: nil,
                    substitutedTypeArguments: [:],
                    parameterMapping: [:],
                    diagnostic: diagnostic
                )
            }
            return errorResult(
                code: "KSWIFTK-SEMA-0002",
                message: "No viable overload found for call.",
                range: call.range
            )
        }
        if viable.count == 1 {
            return viable[0].toResolvedCall()
        }
        if let chosen = pickMostSpecific(viable, typeSystem: typeSystem) {
            return chosen.toResolvedCall()
        }
        return errorResult(
            code: "KSWIFTK-SEMA-0003",
            message: "Ambiguous overload resolution.",
            range: call.range
        )
    }

    private func errorResult(code: String, message: String, range: SourceRange) -> ResolvedCall {
        ResolvedCall(
            chosenCallee: nil,
            substitutedTypeArguments: [:],
            parameterMapping: [:],
            diagnostic: Diagnostic(
                severity: .error,
                code: code,
                message: message,
                primaryRange: range,
                secondaryRanges: []
            )
        )
    }

    private struct ViableCandidate {
        let symbol: SymbolID
        let signature: FunctionSignature
        let instantiatedParameterTypes: [TypeID]
        let substitutedTypeArguments: [TypeVarID: TypeID]
        let parameterMapping: [Int: Int]

        func toResolvedCall() -> ResolvedCall {
            ResolvedCall(
                chosenCallee: symbol,
                substitutedTypeArguments: substitutedTypeArguments,
                parameterMapping: parameterMapping,
                diagnostic: nil
            )
        }
    }

    private enum CandidateEvaluation {
        case viable(ViableCandidate)
        case constraintFailure(Diagnostic)
        case rejected
    }

    private enum ConstraintSolveResult {
        case success([TypeVarID: TypeID])
        case constraintFailure(Diagnostic)
        case rejected
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
                if arg.isSpread && !isVararg[paramIndex] {
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
                return nil
            }

            while positionalCursor < paramCount &&
                    !isVararg[positionalCursor] &&
                    boundNonVarargParams.contains(positionalCursor) {
                positionalCursor += 1
            }
            if positionalCursor >= paramCount {
                return nil
            }

            let paramIndex = positionalCursor
            if arg.isSpread && !isVararg[paramIndex] {
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

    private func checkTypeParameterBounds(
        signature: FunctionSignature,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        range: SourceRange,
        ctx: SemaModule
    ) -> Diagnostic? {
        for (index, typeParamSymbol) in signature.typeParameterSymbols.enumerated() {
            let upperBound: TypeID?
            if index < signature.typeParameterUpperBounds.count {
                upperBound = signature.typeParameterUpperBounds[index]
            } else {
                upperBound = ctx.symbols.typeParameterUpperBound(for: typeParamSymbol)
            }
            guard let bound = upperBound else { continue }
            guard let typeVar = typeVarBySymbol[typeParamSymbol],
                  let substitutedType = substitution[typeVar] else {
                continue
            }
            if !ctx.types.isSubtype(substitutedType, bound) {
                return Diagnostic(
                    severity: .error,
                    code: "KSWIFTK-SEMA-0030",
                    message: "Type argument does not satisfy upper bound constraint.",
                    primaryRange: range,
                    secondaryRanges: []
                )
            }
        }
        return nil
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
