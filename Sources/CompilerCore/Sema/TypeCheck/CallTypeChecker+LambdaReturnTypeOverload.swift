import Foundation

extension CallTypeChecker {
    struct PreparedCallArguments {
        let argTypes: [TypeID]
        let lambdaLiteralIndices: Set<Int>
        let inputOnlyLambdaIndices: Set<Int>
        let blockedLambdaRefinement: Bool
        /// When non-nil, a strict subset of the original candidates list containing
        /// only those where every trailing lambda argument maps directly to a parameter
        /// (no default-parameter skipping required). Used to prefer the simpler
        /// overload — e.g. `forEachLine(action)` over `forEachLine(charset=default, action)` —
        /// when both are otherwise equally viable.
        let preferredCandidates: [SymbolID]?
    }

    private struct LambdaParameterCandidate {
        let symbol: SymbolID
        let originalType: TypeID
        let functionType: FunctionType
        /// True when the lambda parameter was reached only by skipping over
        /// default-valued parameters (i.e. `mappedParameterIndex != index`).
        let usesDefaultSkip: Bool
    }

    func prepareCallArguments(
        args: [CallArgument],
        candidates: [SymbolID],
        preInferredNonLambdaArgTypes: [Int: TypeID] = [:],
        expectedTypeOverrides: [Int: TypeID] = [:],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> PreparedCallArguments {
        let ast = ctx.ast
        let sema = ctx.sema

        var inferredNonLambdaArgTypes = preInferredNonLambdaArgTypes
        var lambdaLiteralIndices: Set<Int> = []
        var inputOnlyLambdaIndices: Set<Int> = []
        var blockedLambdaRefinement = false
        var contextualArgExpectedTypes = Array<TypeID?>(repeating: nil, count: args.count)

        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral:
                lambdaLiteralIndices.insert(index)
            case .callableRef:
                break
            default:
                if inferredNonLambdaArgTypes[index] != nil {
                    continue
                }
                inferredNonLambdaArgTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
            }
        }

        for (index, argument) in args.enumerated() {
            if let override = expectedTypeOverrides[index] {
                contextualArgExpectedTypes[index] = override
                continue
            }

            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            let narrowedCandidates = narrowedCallCandidates(
                candidates: candidates,
                args: args,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                ctx: ctx
            )
            let expectedTypeCandidates = narrowedCandidates.isEmpty ? candidates : narrowedCandidates

            switch argumentExpr {
            case .callableRef:
                contextualArgExpectedTypes[index] = callableReferenceExpectedType(
                    at: index,
                    candidates: expectedTypeCandidates,
                    explicitTypeArgs: explicitTypeArgs,
                    sema: sema
                )
            case .lambdaLiteral:
                let expectation = lambdaLiteralExpectedType(
                    at: index,
                    candidates: expectedTypeCandidates,
                    args: args,
                    inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                    explicitTypeArgs: explicitTypeArgs,
                    receiverType: receiverType,
                    ctx: ctx
                )
                contextualArgExpectedTypes[index] = expectation.type
                if expectation.isInputOnly {
                    inputOnlyLambdaIndices.insert(index)
                }
                if expectation.blocksRefinement {
                    blockedLambdaRefinement = true
                }
            default:
                continue
            }
        }

        if lambdaLiteralIndices.count > 1 {
            blockedLambdaRefinement = true
        }

        let preferredCandidates = computePreferredCandidates(
            lambdaLiteralIndices: lambdaLiteralIndices,
            candidates: candidates,
            args: args,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            ctx: ctx
        )

        let argTypes = args.enumerated().map { index, argument -> TypeID in
            if let contextualExpectedType = contextualArgExpectedTypes[index] {
                let inferredType = driver.inferExpr(
                    argument.expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: contextualExpectedType
                )
                if inputOnlyLambdaIndices.contains(index) {
                    return rebuildLambdaLiteralType(
                        exprID: argument.expr,
                        inferredType: inferredType,
                        contextualExpectedType: contextualExpectedType,
                        sema: sema
                    )
                }
                return inferredType
            }
            if let cached = inferredNonLambdaArgTypes[index] {
                return cached
            }
            return driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }

        return PreparedCallArguments(
            argTypes: argTypes,
            lambdaLiteralIndices: lambdaLiteralIndices,
            inputOnlyLambdaIndices: inputOnlyLambdaIndices,
            blockedLambdaRefinement: blockedLambdaRefinement,
            preferredCandidates: preferredCandidates
        )
    }

    func resolveCallRespectingLambdaReturnType(
        candidates: [SymbolID],
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        calleeName: InternedString,
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        lambdaLiteralIndices: Set<Int>,
        inputOnlyLambdaIndices: Set<Int>,
        blockedLambdaRefinement: Bool,
        preferredCandidates: [SymbolID]? = nil,
        ctx: TypeInferenceContext
    ) -> ResolvedCall {
        let resolvedArgs = zip(args, argTypes).map { argument, type in
            CallArg(
                label: argument.label,
                isSpread: argument.isSpread,
                type: type,
                isLambdaLike: isLambdaLikeArgument(argument, ast: ctx.ast)
            )
        }
        let call = CallExpr(
            range: range,
            calleeName: calleeName,
            args: resolvedArgs,
            explicitTypeArgs: explicitTypeArgs
        )

        let hasRefinementAnnotation = candidates.contains(where: {
            hasOverloadResolutionByLambdaReturnTypeAnnotation(symbol: $0, sema: ctx.sema)
        })
        let functionParameterArgumentPositions = Set(args.indices.filter { argIndex in
            candidates.contains { candidate in
                guard let signature = ctx.sema.symbols.functionSignature(for: candidate),
                      let parameterType = parameterTypeForArgument(at: argIndex, in: signature)
                else {
                    return false
                }
                if case .functionType = ctx.sema.types.kind(of: parameterType) {
                    return true
                }
                return false
            }
        })
        let functionTypedArgumentIndices = Set(args.indices.filter { index in
            guard case .functionType = ctx.sema.types.kind(of: argTypes[index]) else {
                return false
            }
            guard let expr = ctx.ast.arena.expr(args[index].expr) else {
                return false
            }
            if case .callableRef = expr {
                return false
            }
            return true
        })

        if blockedLambdaRefinement, hasRefinementAnnotation {
            return ambiguousCallResult(range: range)
        }

        guard !inputOnlyLambdaIndices.isEmpty else {
            // When preferred candidates were identified (direct-mapped lambdas, no
            // default-parameter skipping), use them to break ties between overloads
            // that differ only in how many default parameters they supply.
            let resolveCandidates = preferredCandidates ?? candidates
            return ctx.resolver.resolveCall(
                candidates: resolveCandidates,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }

        // These ambiguity checks only apply when lambda-return-type overload
        // resolution is actually attempted (inputOnlyLambdaIndices is non-empty).
        // Running them earlier would incorrectly reject single-candidate calls.
        if functionParameterArgumentPositions.count > 1, hasRefinementAnnotation {
            return ambiguousCallResult(range: range)
        }
        if functionTypedArgumentIndices.count > 1, hasRefinementAnnotation {
            return ambiguousCallResult(range: range)
        }

        let overloadResolutionExpectedType: TypeID? = nil

        let probe = ctx.resolver.probeCall(
            candidates: candidates,
            call: call,
            expectedType: overloadResolutionExpectedType,
            implicitReceiverType: implicitReceiverType,
            ignoringLambdaReturnTypeArgumentIndices: inputOnlyLambdaIndices,
            ctx: ctx.semaCtx
        )
        let viableSymbols = probe.viableCandidates.map(\.symbol)
        if viableSymbols.isEmpty {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }
        if viableSymbols.count == 1 {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }
        guard lambdaLiteralIndices.count == 1,
              let lambdaIndex = lambdaLiteralIndices.first,
              inputOnlyLambdaIndices.contains(lambdaIndex)
        else {
            return ambiguousCallResult(range: range)
        }
        guard viableSymbols.contains(where: {
            hasOverloadResolutionByLambdaReturnTypeAnnotation(symbol: $0, sema: ctx.sema)
        }) else {
            return ambiguousCallResult(range: range)
        }

        let refinedCandidates = refineCandidatesByLambdaReturnType(
            candidateSymbols: viableSymbols,
            lambdaArgumentIndex: lambdaIndex,
            argType: argTypes[lambdaIndex],
            sema: ctx.sema
        )
        if refinedCandidates.isEmpty {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }
        if refinedCandidates.count == 1 {
            return ctx.resolver.resolveCall(
                candidates: refinedCandidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }
        return ambiguousCallResult(range: range)
    }

    private func narrowedCallCandidates(
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let narrowed = candidates.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  isCallableArityCompatible(signature: signature, argCount: args.count)
            else {
                return false
            }
            for (otherIndex, inferredType) in inferredNonLambdaArgTypes {
                guard let parameterType = parameterTypeForArgument(at: otherIndex, in: signature) else {
                    return false
                }
                if !sema.types.isSubtype(inferredType, parameterType) {
                    return false
                }
            }
            return true
        }
        return narrowed.isEmpty ? candidates : narrowed
    }

    /// Applies explicit type arguments to a parameter type from a given signature.
    /// When explicit type args are provided, substitutes them into the parameter type.
    /// - Parameter typeArgOffset: Index into `signature.typeParameterSymbols` at which the
    ///   explicit type args begin. For constructors this is 0 (explicit args map to the class's
    ///   own type parameters). For non-constructor member functions this should be
    ///   `signature.classTypeParameterCount`, so that the explicit args skip the leading class
    ///   type parameters (which are inferred from the receiver) and map only to the function's
    ///   own type parameters.
    private func applyExplicitTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        explicitTypeArgs: [TypeID],
        typeArgOffset: Int = 0,
        sema: SemaModule
    ) -> TypeID {
        guard !explicitTypeArgs.isEmpty, !signature.typeParameterSymbols.isEmpty else {
            return parameterType
        }
        let isConstructor = sema.symbols.symbol(candidate)?.kind == .constructor
        let typeArgOffset = isConstructor ? 0 : signature.classTypeParameterCount
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (idx, explicitTypeArg) in explicitTypeArgs.enumerated() {
            let symbolIndex = typeArgOffset + idx
            guard symbolIndex < signature.typeParameterSymbols.count else { break }
            let sym = signature.typeParameterSymbols[symbolIndex]
            if let typeVar = typeVarBySymbol[sym] {
                substitution[typeVar] = explicitTypeArg
            }
        }
        guard !substitution.isEmpty else { return parameterType }
        return sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    /// Substitutes the leading class type parameters of `signature` with the
    /// concrete generic arguments of `receiverType` (if it is a generic class
    /// type). This lets trailing-lambda expected types be computed with the
    /// receiver's generic substitutions already applied, so `it` in
    /// `xs.map { it.uppercase() }` is seen as `String` rather than `T`.
    private func applyReceiverClassTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        receiverType: TypeID?,
        sema: SemaModule
    ) -> TypeID {
        guard let receiverType,
              signature.classTypeParameterCount > 0,
              !signature.typeParameterSymbols.isEmpty,
              sema.symbols.symbol(candidate)?.kind != .constructor,
              case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        else {
            return parameterType
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        let count = min(
            signature.classTypeParameterCount,
            classType.args.count,
            signature.typeParameterSymbols.count
        )
        for index in 0 ..< count {
            let concreteType: TypeID = switch classType.args[index] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let typeParamSymbol = signature.typeParameterSymbols[index]
            if let typeVar = typeVarBySymbol[typeParamSymbol] {
                substitution[typeVar] = concreteType
            }
        }
        guard !substitution.isEmpty else { return parameterType }
        return sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    private func callableReferenceExpectedType(
        at index: Int,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        sema: SemaModule
    ) -> TypeID? {
        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           index < signature.parameterTypes.count
        {
            let rawType = signature.parameterTypes[index]
            let isConstructor = sema.symbols.symbol(candidates[0])?.kind == .constructor
            let typeArgOffset = isConstructor ? 0 : signature.classTypeParameterCount
            return applyExplicitTypeArgs(
                to: rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                typeArgOffset: typeArgOffset,
                sema: sema
            )
        }

        var matchingParameterTypes: [TypeID] = []
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  index < signature.parameterTypes.count
            else {
                continue
            }
            let parameterType = signature.parameterTypes[index]
            if driver.helpers.samFunctionType(for: parameterType, sema: sema) != nil {
                matchingParameterTypes.append(parameterType)
            }
        }
        guard let firstType = matchingParameterTypes.first else {
            return nil
        }
        let allSame = matchingParameterTypes.dropFirst().allSatisfy { $0 == firstType }
        return allSame ? firstType : nil
    }

    private func lambdaLiteralExpectedType(
        at index: Int,
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        ctx: TypeInferenceContext
    ) -> (type: TypeID?, isInputOnly: Bool, blocksRefinement: Bool) {
        let sema = ctx.sema
        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           let parameterIndex = mappedParameterIndex(
               forArgumentAt: index,
               candidate: candidates[0],
               args: args,
               inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
               ctx: ctx
           ),
           parameterIndex < signature.parameterTypes.count
        {
            let rawType = signature.parameterTypes[parameterIndex]
            let isConstructor = sema.symbols.symbol(candidates[0])?.kind == .constructor
            let typeArgOffset = isConstructor ? 0 : signature.classTypeParameterCount
            let explicitSubstituted = applyExplicitTypeArgs(
                to: rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                typeArgOffset: typeArgOffset,
                sema: sema
            )
            let substituted = applyReceiverClassTypeArgs(
                to: explicitSubstituted,
                signature: signature,
                candidate: candidates[0],
                receiverType: receiverType,
                sema: sema
            )
            if let externalLinkName = sema.symbols.externalLinkName(for: candidates[0]),
               externalLinkName == "kk_string_zipWithNextTransform"
                   || externalLinkName == "kk_string_chunked_sequence_transform"
                   || externalLinkName == "kk_string_windowedSequence_transform"
            {
                return (substituted, true, false)
            }
            return (substituted, false, false)
        }

        let parameterCandidates = lambdaParameterCandidates(
            at: index,
            candidates: candidates,
            args: args,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            ctx: ctx
        )
        guard !parameterCandidates.isEmpty else {
            return (nil, false, false)
        }

        if let first = parameterCandidates.first,
           parameterCandidates.dropFirst().allSatisfy({ $0.originalType == first.originalType })
        {
            return (first.originalType, false, false)
        }

        guard let sharedType = sharedLambdaInputOnlyType(
            from: parameterCandidates,
            types: sema.types
        ) else {
            return (nil, false, parameterCandidates.count > 1)
        }
        return (sharedType, true, false)
    }

    private func mappedParameterIndex(
        forArgumentAt index: Int,
        candidate: SymbolID,
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        ctx: TypeInferenceContext
    ) -> Int? {
        guard let signature = ctx.sema.symbols.functionSignature(for: candidate) else {
            return nil
        }
        let callArgs = args.enumerated().map { argIndex, argument in
            CallArg(
                label: argument.label,
                isSpread: argument.isSpread,
                type: inferredNonLambdaArgTypes[argIndex] ?? ctx.sema.types.anyType,
                isLambdaLike: isLambdaLikeArgument(argument, ast: ctx.ast)
            )
        }
        return ctx.resolver.buildParameterMapping(
            signature: signature,
            callArgs: callArgs,
            symbols: ctx.sema.symbols,
            typeSystem: ctx.sema.types
        )?[index]
    }

    private func isLambdaLikeArgument(_ argument: CallArgument, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(argument.expr) else {
            return false
        }
        if case .lambdaLiteral = expr {
            return true
        }
        return false
    }

    /// Returns a strict subset of `candidates` where every trailing lambda argument
    /// (at positions in `lambdaLiteralIndices`) maps directly — without skipping any
    /// default-valued parameters — to a **function-typed** parameter.
    ///
    /// This lets calls like `path.forEachLine { block }` prefer the 1-param overload
    /// `forEachLine(action)` over the 2-param `forEachLine(charset=default, action)`,
    /// while leaving alone cases like `path.visitFileTree { builder }` where the only
    /// candidate that expects a lambda is reached only by skipping default parameters
    /// (so `direct` is empty and no filtering is applied).
    ///
    /// Returns `nil` when no filtering is needed.
    private func computePreferredCandidates(
        lambdaLiteralIndices: Set<Int>,
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        ctx: TypeInferenceContext
    ) -> [SymbolID]? {
        guard !lambdaLiteralIndices.isEmpty else { return nil }
        let sema = ctx.sema
        var preferred = candidates
        for lambdaIndex in lambdaLiteralIndices {
            // Candidates that directly map this lambda arg to a function-typed parameter.
            let direct = preferred.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                guard let parameterIndex = mappedParameterIndex(
                    forArgumentAt: lambdaIndex,
                    candidate: candidate,
                    args: args,
                    inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                    ctx: ctx
                ) else {
                    // Cannot determine mapping — do not exclude this candidate.
                    return true
                }
                guard parameterIndex == lambdaIndex,
                      parameterIndex < signature.parameterTypes.count
                else {
                    return false // uses default-skip
                }
                // Only treat a directly-mapped parameter as a "lambda match" if the
                // parameter type is actually a function type. This prevents overloads
                // like `visitFileTree(visitor: FileVisitor)` — where param 0 is a
                // class type, not a lambda — from being falsely preferred over the
                // `visitFileTree(maxDepth=default, followLinks=default, builderAction)`
                // overload that actually accepts a lambda (at param 2).
                if case .functionType = sema.types.kind(of: signature.parameterTypes[parameterIndex]) {
                    return true
                }
                return false
            }
            if !direct.isEmpty, direct.count < preferred.count {
                preferred = direct
            }
        }
        return preferred.count < candidates.count ? preferred : nil
    }

    private func lambdaParameterCandidates(
        at index: Int,
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        ctx: TypeInferenceContext
    ) -> [LambdaParameterCandidate] {
        let sema = ctx.sema
        var result = candidates.compactMap { candidate -> LambdaParameterCandidate? in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return nil
            }
            let parameterIndex = mappedParameterIndex(
                forArgumentAt: index,
                candidate: candidate,
                args: args,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                ctx: ctx
            ) ?? index
            guard parameterIndex < signature.parameterTypes.count else {
                return nil
            }
            let parameterType = signature.parameterTypes[parameterIndex]
            guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                return nil
            }
            return LambdaParameterCandidate(
                symbol: candidate,
                originalType: parameterType,
                functionType: functionType,
                usesDefaultSkip: parameterIndex != index
            )
        }
        // Prefer direct-mapped candidates over default-skip candidates.
        // If any candidate maps the lambda argument directly (usesDefaultSkip == false),
        // discard all candidates that only match by skipping default parameters,
        // so that e.g. `path.forEachLine { block }` resolves to the 1-param overload
        // rather than becoming ambiguous with the 2-param (charset=default, action) overload.
        if result.contains(where: { !$0.usesDefaultSkip }) {
            result = result.filter { !$0.usesDefaultSkip }
        }
        return result
    }

    private func sharedLambdaInputOnlyType(
        from candidates: [LambdaParameterCandidate],
        types: TypeSystem
    ) -> TypeID? {
        guard let first = candidates.first else {
            return nil
        }
        let sharedInputs = candidates.dropFirst().allSatisfy { candidate in
            functionTypesShareInputShape(first.functionType, candidate.functionType)
        }
        guard sharedInputs else {
            return nil
        }
        return types.make(.functionType(FunctionType(
            receiver: first.functionType.receiver,
            params: first.functionType.params,
            returnType: types.anyType,
            isSuspend: first.functionType.isSuspend,
            nullability: first.functionType.nullability
        )))
    }

    private func functionTypesShareInputShape(
        _ lhs: FunctionType,
        _ rhs: FunctionType
    ) -> Bool {
        guard lhs.isSuspend == rhs.isSuspend,
              lhs.params.count == rhs.params.count,
              lhs.receiver == rhs.receiver
        else {
            return false
        }
        return zip(lhs.params, rhs.params).allSatisfy { $0 == $1 }
    }

    private func rebuildLambdaLiteralType(
        exprID: ExprID,
        inferredType: TypeID,
        contextualExpectedType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard case let .lambdaLiteral(_, bodyExpr, _, _) = driver.ast.arena.expr(exprID),
              case let .functionType(functionType) = sema.types.kind(of: contextualExpectedType),
              let bodyType = sema.bindings.exprType(for: bodyExpr)
        else {
            return inferredType
        }

        return sema.types.make(.functionType(FunctionType(
            receiver: functionType.receiver,
            params: functionType.params,
            returnType: bodyType,
            isSuspend: functionType.isSuspend,
            nullability: functionType.nullability
        )))
    }

    private func refineCandidatesByLambdaReturnType(
        candidateSymbols: [SymbolID],
        lambdaArgumentIndex: Int,
        argType: TypeID,
        sema: SemaModule
    ) -> [SymbolID] {
        guard case let .functionType(argumentFunctionType) = sema.types.kind(of: argType) else {
            return candidateSymbols
        }

        return candidateSymbols.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterType = parameterTypeForArgument(at: lambdaArgumentIndex, in: signature),
                  case let .functionType(parameterFunctionType) = sema.types.kind(of: parameterType)
            else {
                return false
            }
            return sema.types.isSubtype(argumentFunctionType.returnType, parameterFunctionType.returnType)
        }
    }

    private func hasOverloadResolutionByLambdaReturnTypeAnnotation(
        symbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.annotations(for: symbol).contains { annotation in
            KnownCompilerAnnotation.overloadResolutionByLambdaReturnType.matches(annotation.annotationFQName)
        }
    }

    private func ambiguousCallResult(range: SourceRange) -> ResolvedCall {
        ResolvedCall(
            chosenCallee: nil,
            substitutedTypeArguments: [:],
            parameterMapping: [:],
            diagnostic: Diagnostic(
                severity: .error,
                code: "KSWIFTK-SEMA-0003",
                message: "Ambiguous overload resolution.",
                primaryRange: range,
                secondaryRanges: []
            )
        )
    }
}
