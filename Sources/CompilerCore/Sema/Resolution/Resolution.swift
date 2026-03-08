extension OverloadResolver {
    public func resolveCall(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID? = nil,
        ctx: SemaModule
    ) -> ResolvedCall {
        // --- cache lookup ---
        if let cache = cacheContext {
            let key = SemaCacheContext.makeCallResolutionKey(
                candidates: candidates,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                symbols: ctx.symbols
            )
            if let cached = cache.cachedCallResolution(for: key) {
                cache.callResolutionHits += 1
                return cached
            }
            cache.callResolutionMisses += 1
            let result = resolveCallUncached(
                candidates: candidates,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx
            )
            cache.cacheCallResolution(result, for: key)
            return result
        }
        return resolveCallUncached(
            candidates: candidates,
            call: call,
            expectedType: expectedType,
            implicitReceiverType: implicitReceiverType,
            ctx: ctx
        )
    }

    private func resolveCallUncached(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
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
            case let .viable(value):
                viable.append(value)
            case let .constraintFailure(diagnostic):
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
              let signature = ctx.symbols.functionSignature(for: candidate)
        else {
            return .rejected
        }

        let typeVarBySymbol = ctx.types.makeTypeVarBySymbol(signature.typeParameterSymbols)

        // Apply explicit type argument constraints if provided.
        // Only compare against the function's own type params (skip leading
        // class type params that are inferred from the receiver).
        let funcOwnTypeParamCount = signature.typeParameterSymbols.count - signature.classTypeParameterCount
        if !call.explicitTypeArgs.isEmpty {
            guard call.explicitTypeArgs.count == funcOwnTypeParamCount else {
                return .rejected
            }
        }

        // Constructors synthesize their own receiver at the call site, so skip
        // the receiver constraint check that would reject them when there is no
        // implicit receiver in scope (e.g. `Dog()` called from a free function).
        var constraints: [VariableConstraint]
        if symbol.kind == .constructor {
            constraints = []
        } else {
            guard let receiverConstraints = buildReceiverConstraints(
                signature: signature,
                implicitReceiverType: implicitReceiverType,
                typeVarBySymbol: typeVarBySymbol,
                range: call.range,
                typeSystem: ctx.types
            ) else {
                return .rejected
            }
            constraints = receiverConstraints
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

        // Add equality constraints for explicit type arguments.
        // Map to function-own type params (after the class type params).
        for (index, explicitArg) in call.explicitTypeArgs.enumerated() {
            let typeParamSymbol = signature.typeParameterSymbols[signature.classTypeParameterCount + index]
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
            let returnDecomposed = decomposeSubtypeConstraint(
                subtype: signature.returnType,
                supertype: expectedType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: ctx.types,
                blameRange: call.range
            )
            constraints.append(contentsOf: returnDecomposed)
        }

        let solveResult = solveConstraints(
            constraints,
            solver: solver,
            typeSystem: ctx.types
        )
        let substitution: [TypeVarID: TypeID]
        switch solveResult {
        case let .success(value):
            substitution = value
        case let .constraintFailure(diagnostic):
            return .constraintFailure(diagnostic)
        case .rejected:
            return .rejected
        }

        // Emit KSWIFTK-SEMA-INFER when a type variable could not be inferred
        // (solver returned errorType because it had no bounds).
        if let inferDiag = checkForUninferredTypeVariables(
            signature: signature,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol,
            range: call.range,
            typeSystem: ctx.types
        ) {
            return .constraintFailure(inferDiag)
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
                  paramIndex < signature.parameterTypes.count
            else {
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
        // Use decomposeSubtypeConstraint to properly extract type variables
        // from generic receiver types (e.g. Class<T>) so the solver can
        // infer type arguments from projected receivers (e.g. Class<out Any>).
        return decomposeSubtypeConstraint(
            subtype: implicitReceiverType,
            supertype: receiverType,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: typeSystem,
            blameRange: range
        )
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
                  paramIndex < signature.parameterTypes.count
            else {
                constraints.removeAll(keepingCapacity: false)
                break
            }
            let paramType = signature.parameterTypes[paramIndex]
            let argType = call.args[argIndex].type
            let decomposed = decomposeSubtypeConstraint(
                subtype: argType,
                supertype: paramType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: call.range
            )
            constraints.append(contentsOf: decomposed)
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

    private func pickMostSpecific(
        _ candidates: [ViableCandidate],
        typeSystem: TypeSystem
    ) -> ViableCandidate? {
        let winners = candidates.filter { candidate in
            for other in candidates where other.symbol != candidate.symbol {
                if !isMoreSpecificCandidate(candidate, than: other, typeSystem: typeSystem) {
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

    /// Returns true if `lhs` is at least as specific as `rhs`.
    /// First compares parameter types; if they are equivalent, falls back to
    /// receiver type: the more-derived receiver (override) wins over the base.
    private func isMoreSpecificCandidate(
        _ lhs: ViableCandidate,
        than rhs: ViableCandidate,
        typeSystem: TypeSystem
    ) -> Bool {
        if isMoreSpecific(lhs.instantiatedParameterTypes, than: rhs.instantiatedParameterTypes, typeSystem: typeSystem) {
            return true
        }
        // If parameter types are not strictly more specific, check whether they
        // are pairwise equivalent and the receiver type is a subtype (override
        // wins over the base class/interface default method).
        guard lhs.instantiatedParameterTypes.count == rhs.instantiatedParameterTypes.count else {
            return false
        }
        let paramsEqual = zip(lhs.instantiatedParameterTypes, rhs.instantiatedParameterTypes).allSatisfy {
            typeSystem.isSubtype($0, $1) && typeSystem.isSubtype($1, $0)
        }
        guard paramsEqual,
              let lhsReceiver = lhs.signature.receiverType,
              let rhsReceiver = rhs.signature.receiverType
        else {
            return false
        }
        return typeSystem.isSubtype(lhsReceiver, rhsReceiver)
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
            if lhsSubRhs, !rhsSubLhs {
                sawStrict = true
            }
        }
        return sawStrict
    }
}
