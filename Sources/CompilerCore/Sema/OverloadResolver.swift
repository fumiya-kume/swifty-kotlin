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
    /// Optional sema cache context.  When non-nil the resolver checks the
    /// call-resolution cache before performing full candidate evaluation.
    var cacheContext: SemaCacheContext?

    public init() {}

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
        case .success(let value):
            substitution = value
        case .constraintFailure(let diagnostic):
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
                  paramIndex < signature.parameterTypes.count else {
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
                // In Kotlin, positional arguments after named arguments
                // are allowed only when they bind to a vararg parameter.
                // Advance the cursor past already-bound non-vararg params.
                while positionalCursor < paramCount &&
                        !isVararg[positionalCursor] &&
                        boundNonVarargParams.contains(positionalCursor) {
                    positionalCursor += 1
                }
                if positionalCursor >= paramCount || !isVararg[positionalCursor] {
                    return nil
                }
                mapping[argIndex] = positionalCursor
                continue
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

    /// Checks whether a type contains any type parameters mapped in `typeVarBySymbol`.
    private func containsTypeVariable(
        _ type: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem
    ) -> Bool {
        switch typeSystem.kind(of: type) {
        case .typeParam(let typeParam):
            return typeVarBySymbol[typeParam.symbol] != nil
        case .classType(let classType):
            return classType.args.contains { arg in
                switch arg {
                case .invariant(let inner), .out(let inner), .in(let inner):
                    return containsTypeVariable(inner, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
                case .star:
                    return false
                }
            }
        case .functionType(let functionType):
            if let receiver = functionType.receiver,
               containsTypeVariable(receiver, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem) {
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
    private func decomposeSubtypeConstraint(
        subtype: TypeID,
        supertype: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange?
    ) -> [VariableConstraint] {
        let supertypeKind = typeSystem.kind(of: supertype)

        // Case 1: supertype is a direct type parameter → single variable constraint.
        if case .typeParam(let typeParam) = supertypeKind,
           let variable = typeVarBySymbol[typeParam.symbol] {
            return [VariableConstraint(
                kind: .subtype,
                left: .type(subtype),
                right: .variable(variable),
                blameRange: blameRange
            )]
        }

        // Case 2: supertype is a class type with type args containing type variables.
        if case .classType(let superClass) = supertypeKind,
           !superClass.args.isEmpty,
           containsTypeVariable(supertype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem) {
            let subtypeKind = typeSystem.kind(of: subtype)
            if case .classType(let subClass) = subtypeKind,
               subClass.classSymbol == superClass.classSymbol,
               subClass.args.count == superClass.args.count,
               subClass.nullability == superClass.nullability || superClass.nullability == .nullable {
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
            // Different class symbols or mismatched arity – fall through to
            // simple constraint which will use isSubtype.
        }

        // Case 3: supertype is a function type with type variables in params/return.
        if case .functionType(let superFunc) = supertypeKind,
           containsTypeVariable(supertype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem) {
            let subtypeKind = typeSystem.kind(of: subtype)
            if case .functionType(let subFunc) = subtypeKind,
               subFunc.params.count == superFunc.params.count,
               subFunc.isSuspend == superFunc.isSuspend,
               subFunc.nullability == superFunc.nullability || superFunc.nullability == .nullable,
               subFunc.receiver == superFunc.receiver {
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
        if case .typeParam(let typeParam) = subtypeKind,
           let variable = typeVarBySymbol[typeParam.symbol] {
            return [VariableConstraint(
                kind: .subtype,
                left: .variable(variable),
                right: .type(supertype),
                blameRange: blameRange
            )]
        }

        if case .classType(let subClass) = subtypeKind,
           !subClass.args.isEmpty,
           containsTypeVariable(subtype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem) {
            if case .classType(let superClass) = supertypeKind,
               subClass.classSymbol == superClass.classSymbol,
               subClass.args.count == superClass.args.count,
               subClass.nullability == superClass.nullability || superClass.nullability == .nullable {
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

    /// Decomposes a pair of type arguments into constraints respecting variance.
    /// Invariant args produce equality constraints, `out` produces subtype,
    /// `in` produces supertype (reversed direction).
    ///
    /// NOTE: Variance is currently derived from the `TypeArg` enum cases (use-site
    /// projection). A future enhancement could incorporate declaration-site variance
    /// from the enclosing class's type parameter definitions.
    private func decomposeTypeArgConstraint(
        subArg: TypeArg,
        superArg: TypeArg,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange?
    ) -> [VariableConstraint] {
        switch (subArg, superArg) {
        case (.invariant(let subInner), .invariant(let superInner)):
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

        case (.invariant(let subInner), .out(let superInner)),
             (.out(let subInner), .out(let superInner)):
            // Covariant: sub <: super.
            return decomposeSubtypeConstraint(
                subtype: subInner, supertype: superInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            )

        case (.invariant(let subInner), .in(let superInner)),
             (.in(let subInner), .in(let superInner)):
            // Contravariant: super <: sub.
            return decomposeSubtypeConstraint(
                subtype: superInner, supertype: subInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange
            )

        case (.star, .invariant(let superInner)):
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
            case .invariant(let t), .out(let t), .in(let t): subInner = t
            case .star: return []
            }
            switch superArg {
            case .invariant(let t), .out(let t), .in(let t): superInner = t
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

    /// Returns a diagnostic when the solver resolved a type variable to `errorType`,
    /// meaning no constraints existed to determine it.  The caller should require
    /// explicit type arguments in that case.
    private func checkForUninferredTypeVariables(
        signature: FunctionSignature,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        range: SourceRange,
        typeSystem: TypeSystem
    ) -> Diagnostic? {
        for typeParamSymbol in signature.typeParameterSymbols {
            guard let typeVar = typeVarBySymbol[typeParamSymbol] else {
                continue
            }
            let resolved = substitution[typeVar]
            // A type variable is "uninferred" when it was either never
            // included in the substitution (no constraints at all) or the
            // solver explicitly set it to errorType.
            guard resolved == nil || resolved == typeSystem.errorType else {
                continue
            }
            // Only report for type parameters that actually appear in the
            // return type or parameter types. Unused type parameters
            // (e.g. `fun <T, U> foo(x: T): T` where U is never used)
            // are silently ignored.
            let usedInReturn = containsTypeVariable(
                signature.returnType,
                typeVarBySymbol: [typeParamSymbol: typeVar],
                typeSystem: typeSystem
            )
            let usedInParams = signature.parameterTypes.contains {
                containsTypeVariable(
                    $0,
                    typeVarBySymbol: [typeParamSymbol: typeVar],
                    typeSystem: typeSystem
                )
            }
            if usedInReturn || usedInParams {
                return Diagnostic(
                    severity: .error,
                    code: "KSWIFTK-SEMA-INFER",
                    message: "Cannot infer type argument; provide explicit type arguments.",
                    primaryRange: range,
                    secondaryRanges: []
                )
            }
        }
        return nil
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
