extension OverloadResolver {
    public func probeCall(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID? = nil,
        ignoringLambdaReturnTypeArgumentIndices: Set<Int> = [],
        ctx: SemaModule
    ) -> ProbedCallResult {
        let solver = ConstraintSolver()
        var viable: [ViableCandidate] = []
        for candidate in candidates {
            let evaluation = evaluateCandidate(
                candidate,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                ignoredLambdaReturnTypeArgumentIndices: ignoringLambdaReturnTypeArgumentIndices,
                solver: solver,
                ctx: ctx
            )
            switch evaluation {
            case let .viable(value):
                viable.append(value)
            case .constraintFailure, .rejected:
                continue
            }
        }
        return ProbedCallResult(
            viableCandidates: viable.map { $0.toProbedCallCandidate() }
        )
    }

    /// Derives a partial type-variable substitution for `signature`'s type
    /// parameters using only the argument positions present in
    /// `knownArgumentTypes`. Used to seed a lambda argument's expected type with
    /// type-parameter bindings already inferred from the call's other
    /// (non-lambda) arguments, before the lambda literal itself is type-checked
    /// (see `lambdaLiteralExpectedType` in `CallTypeChecker+LambdaReturnTypeOverload.swift`).
    /// A missing key in the result means that type parameter could not be
    /// constrained from the known arguments — callers must treat it as
    /// "unconstrained", not as an error.
    func probeArgumentTypeSubstitution(
        signature: FunctionSignature,
        typeVarBySymbol: [SymbolID: TypeVarID],
        knownArgumentTypes: [Int: TypeID],
        typeSystem: TypeSystem,
        blameRange: SourceRange? = nil
    ) -> [TypeVarID: TypeID] {
        guard !typeVarBySymbol.isEmpty, !knownArgumentTypes.isEmpty else {
            return [:]
        }
        var constraints: [VariableConstraint] = []
        for (index, argType) in knownArgumentTypes {
            guard index >= 0, index < signature.parameterTypes.count else { continue }
            constraints.append(contentsOf: decomposeSubtypeConstraint(
                subtype: argType,
                supertype: signature.parameterTypes[index],
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange
            ))
        }
        guard !constraints.isEmpty else { return [:] }
        guard !usedTypeVariables(from: constraints).isEmpty else { return [:] }

        // A known argument can determine a type parameter indirectly through
        // another parameter's dependent upper bound. For example, a destination
        // argument can infer `M` in `M : MutableMap<in K, S>`, which in turn
        // determines `S` before the operation lambda is type-checked. Expand
        // those bounds while the probe still has concrete argument types; the
        // full call resolver performs the authoritative bound check later.
        var solution = ConstraintSolver().solve(
            vars: usedTypeVariables(from: constraints),
            constraints: constraints,
            typeSystem: typeSystem
        )
        guard solution.isSuccess else { return [:] }
        let symbolTable = typeSystem.symbolTable
        for _ in 0 ... max(1, signature.typeParameterSymbols.count) {
            var addedDependentConstraint = false
            for (index, typeParamSymbol) in signature.typeParameterSymbols.enumerated() {
                guard let typeVar = typeVarBySymbol[typeParamSymbol],
                      let substitutedType = solution.substitution[typeVar]
                else {
                    continue
                }
                let signatureBounds = index < signature.typeParameterUpperBoundsList.count
                    ? signature.typeParameterUpperBoundsList[index]
                    : []
                let symbolBounds = symbolTable?.typeParameterUpperBounds(for: typeParamSymbol) ?? []
                let upperBounds = signatureBounds + symbolBounds.filter { !signatureBounds.contains($0) }
                for upperBound in upperBounds {
                    let substitutedBound = typeSystem.substituteTypeParameters(
                        in: upperBound,
                        substitution: solution.substitution,
                        typeVarBySymbol: typeVarBySymbol
                    )
                    guard containsTypeVariable(
                        substitutedBound,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem
                    ) else {
                        continue
                    }
                    let dependentConstraints = decomposeSubtypeConstraint(
                        subtype: substitutedType,
                        supertype: substitutedBound,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange
                    )
                    guard !usedTypeVariables(from: dependentConstraints).isEmpty else {
                        continue
                    }
                    constraints.append(contentsOf: dependentConstraints)
                    addedDependentConstraint = true
                }
            }
            guard addedDependentConstraint else { break }
            solution = ConstraintSolver().solve(
                vars: usedTypeVariables(from: constraints),
                constraints: constraints,
                typeSystem: typeSystem
            )
            guard solution.isSuccess else { return [:] }
        }

        // An upper bound alone is not a usable lambda context. For example,
        // Comparator<Any> passed to Comparator<in R> only establishes R <: Any;
        // the trailing selector still has to infer R from its return type. If
        // this helper substituted Any eagerly, the selector would be checked as
        // (T) -> Any and its concrete return type would be lost before the main
        // call solver ran. Keep substitutions that have a concrete lower bound,
        // while leaving upper-only variables unresolved for the lambda pass.
        let lowerBoundedVariables: Set<TypeVarID> = Set(constraints.compactMap { constraint in
            guard case .type = constraint.left,
                  case let .variable(variable) = constraint.right
            else {
                return nil
            }
            return variable
        })
        return solution.substitution.filter { lowerBoundedVariables.contains($0.key) }
    }

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
                cache.recordCallResolutionHit()
                return cached
            }
            cache.recordCallResolutionMiss()
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
                ignoredLambdaReturnTypeArgumentIndices: [],
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
        ignoredLambdaReturnTypeArgumentIndices: Set<Int>,
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
        // For constructors, explicit type args map to the class type params
        // (e.g. ArrayDeque<Int>() — <Int> binds the class's E parameter).
        // For regular functions, only compare against the function's own type
        // params (skip leading class type params inferred from the receiver).
        let funcOwnTypeParamCount = signature.typeParameterSymbols.count - signature.classTypeParameterCount
        let isConstructor = symbol.kind == .constructor
        if !call.explicitTypeArgs.isEmpty {
            let expectedTypeArgCount = isConstructor
                ? signature.classTypeParameterCount
                : funcOwnTypeParamCount
            guard call.explicitTypeArgs.count == expectedTypeArgCount else {
                return .rejected
            }
        }

        // Constructors synthesize their own receiver at the call site, so skip
        // the receiver constraint check that would reject them when there is no
        // implicit receiver in scope (e.g. `Dog()` called from a free function).
        var constraints: [VariableConstraint]
        if isConstructor {
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
            symbols: ctx.symbols,
            typeSystem: ctx.types
        ) else {
            return .rejected
        }

        guard appendArgumentConstraints(
            to: &constraints,
            call: call,
            parameterMapping: parameterMapping,
            signature: signature,
            typeVarBySymbol: typeVarBySymbol,
            ignoredLambdaReturnTypeArgumentIndices: ignoredLambdaReturnTypeArgumentIndices,
            typeSystem: ctx.types
        ) else {
            return .rejected
        }

        // Add equality constraints for explicit type arguments.
        // For constructors, explicit type args bind class type params (offset 0).
        // For regular functions, map to function-own type params (after class type params).
        let typeArgOffset = isConstructor ? 0 : signature.classTypeParameterCount
        for (index, explicitArg) in call.explicitTypeArgs.enumerated() {
            let typeParamSymbol = signature.typeParameterSymbols[typeArgOffset + index]
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

        // Upper bounds can relate two function type parameters (for example
        // `where C : Collection<*>, C : R`). Add those relationships to the
        // inference graph before solving so a receiver lower bound can widen
        // the result type as required by Kotlin's self-type extensions.
        for (index, typeParamSymbol) in signature.typeParameterSymbols.enumerated() {
            guard index < signature.typeParameterUpperBoundsList.count else {
                continue
            }
            let signatureBounds = signature.typeParameterUpperBoundsList[index]
            let symbolBounds = ctx.symbols.typeParameterUpperBounds(for: typeParamSymbol)
            let upperBounds = signatureBounds + symbolBounds.filter { !signatureBounds.contains($0) }
            for upperBound in upperBounds {
                guard case let .typeParam(boundTypeParam) = ctx.types.kind(of: upperBound),
                      let typeParamVariable = typeVarBySymbol[typeParamSymbol],
                      let boundTypeParamVariable = typeVarBySymbol[boundTypeParam.symbol]
                else {
                    continue
                }
                constraints.append(VariableConstraint(
                    kind: .subtype,
                    left: .variable(typeParamVariable),
                    right: .variable(boundTypeParamVariable),
                    blameRange: call.range
                ))
            }
        }

        // Kotlin's Unit-coercion rule: a call whose result is used where Unit is
        // expected (e.g. the trailing expression of a `(T) -> Unit` lambda body,
        // such as `also { it.append(x) }`) does not need its return type to be
        // Unit — the value is simply discarded. Skip the return-type constraint
        // in that case so overload candidates aren't rejected solely because
        // none of them happen to return Unit.
        if let expectedType, expectedType != ctx.types.unitType {
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

        let instantiatedReceiverType = signature.receiverType.map {
            ctx.types.substituteTypeParameters(
                in: $0,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
        }

        return .viable(ViableCandidate(
            symbol: candidate,
            signature: signature,
            instantiatedReceiverType: instantiatedReceiverType,
            instantiatedParameterTypes: instantiatedParameterTypes,
            substitutedTypeArguments: substitution,
            parameterMapping: parameterMapping,
            usesVararg: normalizeFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count).contains(true)
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
        // A receiver can itself be a type parameter with a non-recursive upper
        // bound (for example `M : MutableMap<in K, in V>`). Resolve the member
        // against that bound so calls such as `destination.put(key, value)`
        // infer the member's class type parameters from the projected bound.
        // Star-projected bounds erase those member type arguments, so preserve
        // the direct receiver constraint instead of inferring them as Any?.
        if case let .typeParam(typeParam) = typeSystem.kind(of: implicitReceiverType),
           typeVarBySymbol[typeParam.symbol] == nil,
           let symbols = typeSystem.symbolTable
        {
            let upperBounds = symbols.typeParameterUpperBounds(for: typeParam.symbol)
            if !upperBounds.isEmpty,
               upperBounds.allSatisfy({
                   !typeSystem.typeContainsTypeParam($0, symbol: typeParam.symbol)
                       && !containsStarProjection($0, typeSystem: typeSystem)
               })
            {
                return upperBounds.flatMap { upperBound in
                    decomposeSubtypeConstraint(
                        subtype: upperBound,
                        supertype: receiverType,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: range
                    )
                }
            }
        }
        return decomposeSubtypeConstraint(
            subtype: implicitReceiverType,
            supertype: receiverType,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: typeSystem,
            blameRange: range
        )
    }

    private func containsStarProjection(_ type: TypeID, typeSystem: TypeSystem) -> Bool {
        switch typeSystem.kind(of: type) {
        case let .classType(classType):
            classType.args.contains { argument in
                switch argument {
                case .star:
                    true
                case let .invariant(inner), let .out(inner), let .in(inner):
                    containsStarProjection(inner, typeSystem: typeSystem)
                }
            }
        case let .functionType(functionType):
            functionType.contextReceivers.contains { containsStarProjection($0, typeSystem: typeSystem) }
                || functionType.receiver.map { containsStarProjection($0, typeSystem: typeSystem) } == true
                || functionType.params.contains { containsStarProjection($0, typeSystem: typeSystem) }
                || containsStarProjection(functionType.returnType, typeSystem: typeSystem)
                || functionType.throws.contains { containsStarProjection($0, typeSystem: typeSystem) }
        case let .intersection(parts):
            parts.contains { containsStarProjection($0, typeSystem: typeSystem) }
        case let .kClassType(kClassType):
            containsStarProjection(kClassType.argument, typeSystem: typeSystem)
        default:
            false
        }
    }

    private func appendArgumentConstraints(
        to constraints: inout [VariableConstraint],
        call: CallExpr,
        parameterMapping: [Int: Int],
        signature: FunctionSignature,
        typeVarBySymbol: [SymbolID: TypeVarID],
        ignoredLambdaReturnTypeArgumentIndices: Set<Int>,
        typeSystem: TypeSystem
    ) -> Bool {
        let isVararg = normalizeFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count)
        var processedAll = true
        for argIndex in call.args.indices {
            guard let paramIndex = parameterMapping[argIndex],
                  paramIndex >= 0,
                  paramIndex < signature.parameterTypes.count
            else {
                constraints.removeAll(keepingCapacity: false)
                processedAll = false
                break
            }
            let paramType = signature.parameterTypes[paramIndex]
            let arg = call.args[argIndex]
            let argType = arg.type

            // When a spread argument (*array) is passed to a vararg parameter,
            // the argument type is an array/collection type (e.g. Array<String>,
            // IntArray) while the parameter type is the element type (String, Int).
            // Skip the type constraint for spread arguments — the parameter mapping
            // already verified this maps to a vararg param and the runtime handles
            // the concatenation via kk_vararg_spread_concat.
            if arg.isSpread, isVararg[paramIndex] {
                continue
            }

            if ignoredLambdaReturnTypeArgumentIndices.contains(argIndex),
               appendLambdaInputConstraintsIgnoringReturn(
                   to: &constraints,
                   argType: argType,
                   paramType: paramType,
                   typeVarBySymbol: typeVarBySymbol,
                   typeSystem: typeSystem,
                   blameRange: call.range
               )
            {
                continue
            }

            let decomposed = decomposeSubtypeConstraint(
                subtype: argType,
                supertype: paramType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: call.range
            )
            constraints.append(contentsOf: decomposed)
        }
        if !processedAll {
            return !(constraints.isEmpty && !call.args.isEmpty)
        }
        return true
    }

    private func appendLambdaInputConstraintsIgnoringReturn(
        to constraints: inout [VariableConstraint],
        argType: TypeID,
        paramType: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange
    ) -> Bool {
        guard case let .functionType(argFunction) = typeSystem.kind(of: argType),
              case let .functionType(paramFunction) = typeSystem.kind(of: paramType),
              argFunction.isSuspend == paramFunction.isSuspend,
              argFunction.params.count == paramFunction.params.count
        else {
            return false
        }

        if let argReceiver = argFunction.receiver,
           let paramReceiver = paramFunction.receiver
        {
            // Function receivers are contravariant — flip direction.
            constraints.append(contentsOf: decomposeSubtypeConstraint(
                subtype: paramReceiver,
                supertype: argReceiver,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange
            ))
        } else if argFunction.receiver != nil || paramFunction.receiver != nil {
            return false
        }

        // Function type parameters are contravariant — flip direction
        // (matching decomposeSubtypeConstraintImpl in Resolution+TypeConstraints.swift).
        for (argParameter, paramParameter) in zip(argFunction.params, paramFunction.params) {
            constraints.append(contentsOf: decomposeSubtypeConstraint(
                subtype: paramParameter,
                supertype: argParameter,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange
            ))
        }
        return true
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
        let instantiatedReceiverType: TypeID?
        let instantiatedParameterTypes: [TypeID]
        let substitutedTypeArguments: [TypeVarID: TypeID]
        let parameterMapping: [Int: Int]
        let usesVararg: Bool

        func toResolvedCall() -> ResolvedCall {
            ResolvedCall(
                chosenCallee: symbol,
                substitutedTypeArguments: substitutedTypeArguments,
                parameterMapping: parameterMapping,
                diagnostic: nil
            )
        }

        func toProbedCallCandidate() -> ProbedCallCandidate {
            ProbedCallCandidate(symbol: symbol)
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
    /// When counts differ because one candidate has additional unbound default
    /// parameters, the candidate binding the same arguments to fewer parameters
    /// is preferred (e.g. trailing-lambda overloads without optional prefix args).
    private func isMoreSpecificCandidate(
        _ lhs: ViableCandidate,
        than rhs: ViableCandidate,
        typeSystem: TypeSystem
    ) -> Bool {
        if isMoreSpecific(lhs.instantiatedParameterTypes, than: rhs.instantiatedParameterTypes, typeSystem: typeSystem) {
            return true
        }

        // If parameter counts differ because one candidate supplied additional
        // default arguments, the candidate with fewer parameters is more specific
        // when every bound argument type is at least as specific.
        let rhsBound = Set(rhs.parameterMapping.values)
        var lhsBoundIsNoLessSpecific = true
        for argIndex in lhs.instantiatedParameterTypes.indices {
            guard argIndex < rhs.instantiatedParameterTypes.count else {
                lhsBoundIsNoLessSpecific = false
                break
            }
            if !typeSystem.isSubtype(lhs.instantiatedParameterTypes[argIndex], rhs.instantiatedParameterTypes[argIndex]) {
                lhsBoundIsNoLessSpecific = false
                break
            }
        }
        if lhsBoundIsNoLessSpecific {
            let lhsCount = lhs.signature.parameterTypes.count
            let rhsCount = rhs.signature.parameterTypes.count
            if lhsCount < rhsCount {
                // The larger candidate is more specific only if its extra formal
                // parameters are not supplied by the call and are optional (default
                // or vararg). If every extra parameter is bound, the smaller
                // candidate (e.g. a vararg overload) is not preferred.
                let rhsDefaults = normalizeFlags(rhs.signature.valueParameterHasDefaultValues, count: rhsCount)
                let rhsVarargs = normalizeFlags(rhs.signature.valueParameterIsVararg, count: rhsCount)
                var unboundFound = false
                var extraAreOptional = true
                for p in 0..<rhsCount {
                    if rhsBound.contains(p) { continue }
                    unboundFound = true
                    if rhsVarargs[p] { continue }
                    if rhsDefaults[p] { continue }
                    extraAreOptional = false
                    break
                }
                if unboundFound && extraAreOptional {
                    return true
                }
            }
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
        guard paramsEqual else {
            return false
        }
        if let lhsReceiver = lhs.instantiatedReceiverType,
           let rhsReceiver = rhs.instantiatedReceiverType
        {
            let lhsReceiverSubRhs = typeSystem.isSubtype(lhsReceiver, rhsReceiver)
            let rhsReceiverSubLhs = typeSystem.isSubtype(rhsReceiver, lhsReceiver)
            if lhsReceiverSubRhs && !rhsReceiverSubLhs {
                return true
            }
            if rhsReceiverSubLhs && !lhsReceiverSubRhs {
                return false
            }
        }
        let lhsHasTypeParameter = signatureContainsTypeParameter(lhs.signature, typeSystem: typeSystem)
        let rhsHasTypeParameter = signatureContainsTypeParameter(rhs.signature, typeSystem: typeSystem)
        if lhsHasTypeParameter != rhsHasTypeParameter {
            return !lhsHasTypeParameter
        }
        let lhsOwnTypeParamCount = lhs.signature.typeParameterSymbols.count - lhs.signature.classTypeParameterCount
        let rhsOwnTypeParamCount = rhs.signature.typeParameterSymbols.count - rhs.signature.classTypeParameterCount
        if lhsOwnTypeParamCount != rhsOwnTypeParamCount {
            return lhsOwnTypeParamCount < rhsOwnTypeParamCount
        }
        if lhs.usesVararg != rhs.usesVararg {
            return !lhs.usesVararg && rhs.usesVararg
        }
        return false
    }

    /// Returns `true` if `signature` declares any receiver or parameter type
    /// that contains a type parameter (e.g. `fun <T> T.compareTo(T)`).
    private func signatureContainsTypeParameter(
        _ signature: FunctionSignature,
        typeSystem: TypeSystem
    ) -> Bool {
        var typesToCheck: [TypeID] = signature.parameterTypes
        if let receiver = signature.receiverType {
            typesToCheck.append(receiver)
        }
        return typesToCheck.contains { typeContainsTypeParameter($0, typeSystem: typeSystem) }
    }

    private func typeContainsTypeParameter(
        _ type: TypeID,
        typeSystem: TypeSystem
    ) -> Bool {
        switch typeSystem.kind(of: type) {
        case .typeParam:
            return true
        case let .classType(classType):
            for arg in classType.args {
                let argType: TypeID? = switch arg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: nil
                }
                if let argType, typeContainsTypeParameter(argType, typeSystem: typeSystem) {
                    return true
                }
            }
            return false
        case let .functionType(functionType):
            let allTypes = functionType.contextReceivers
                + (functionType.receiver.map { [$0] } ?? [])
                + functionType.params
                + [functionType.returnType]
            return allTypes.contains { typeContainsTypeParameter($0, typeSystem: typeSystem) }
        case let .kClassType(kClassType):
            return typeContainsTypeParameter(kClassType.argument, typeSystem: typeSystem)
        case let .intersection(parts):
            return parts.contains { typeContainsTypeParameter($0, typeSystem: typeSystem) }
        default:
            return false
        }
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
