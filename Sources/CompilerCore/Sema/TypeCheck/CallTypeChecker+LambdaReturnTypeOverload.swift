import Foundation

extension CallTypeChecker {
    struct PreparedCallArguments {
        let argTypes: [TypeID]
        let lambdaLiteralIndices: Set<Int>
        let inputOnlyLambdaIndices: Set<Int>
        let blockedLambdaRefinement: Bool
    }

    private struct LambdaParameterCandidate {
        let symbol: SymbolID
        let originalType: TypeID
        let functionType: FunctionType
    }

    func prepareCallArguments(
        args: [CallArgument],
        candidates: [SymbolID],
        preInferredNonLambdaArgTypes: [Int: TypeID] = [:],
        expectedTypeOverrides: [Int: TypeID] = [:],
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
                    sema: sema
                )
            case .lambdaLiteral:
                let expectation = lambdaLiteralExpectedType(
                    at: index,
                    candidates: expectedTypeCandidates,
                    sema: sema
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
            blockedLambdaRefinement: blockedLambdaRefinement
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
        ctx: TypeInferenceContext
    ) -> ResolvedCall {
        let resolvedArgs = zip(args, argTypes).map { argument, type in
            CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
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

        guard !inputOnlyLambdaIndices.isEmpty else {
            return ctx.resolver.resolveCall(
                candidates: candidates,
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

        if blockedLambdaRefinement, hasRefinementAnnotation {
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

    private func callableReferenceExpectedType(
        at index: Int,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> TypeID? {
        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           index < signature.parameterTypes.count
        {
            return signature.parameterTypes[index]
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
        sema: SemaModule
    ) -> (type: TypeID?, isInputOnly: Bool, blocksRefinement: Bool) {
        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           index < signature.parameterTypes.count
        {
            return (signature.parameterTypes[index], false, false)
        }

        let parameterCandidates = lambdaParameterCandidates(
            at: index,
            candidates: candidates,
            sema: sema
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

    private func lambdaParameterCandidates(
        at index: Int,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> [LambdaParameterCandidate] {
        candidates.compactMap { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  index < signature.parameterTypes.count
            else {
                return nil
            }
            let parameterType = signature.parameterTypes[index]
            guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                return nil
            }
            return LambdaParameterCandidate(
                symbol: candidate,
                originalType: parameterType,
                functionType: functionType
            )
        }
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
