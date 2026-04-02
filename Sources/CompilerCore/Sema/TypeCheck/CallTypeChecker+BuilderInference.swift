import Foundation

extension CallTypeChecker {
    func tryResolveExpectedTypeDrivenBuilderInferenceCall(
        _ id: ExprID,
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        calleeName: InternedString?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        guard let expectedType else {
            return nil
        }

        let sema = ctx.sema
        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ctx.ast.arena.expr(argument.expr),
                  case .lambdaLiteral = argumentExpr,
                  let candidateContext = uniqueBuilderInferenceCandidateContext(
                      candidates: candidates,
                      args: args,
                      inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                      argumentIndex: index,
                      expectedType: expectedType,
                      ctx: ctx,
                      range: range
                  )
            else {
                continue
            }

            let signature = candidateContext.signature
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let substitution = provisionalBuilderInferenceSubstitution(
                signature: signature,
                expectedType: expectedType,
                typeVarBySymbol: typeVarBySymbol,
                ctx: ctx,
                range: range
            )
            if substitution.isEmpty && !signature.typeParameterSymbols.isEmpty {
                continue
            }

            let substitutedLambdaExpectedType = sema.types.substituteTypeParameters(
                in: signature.parameterTypes[index],
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            var resolvedArgTypes: [TypeID] = []
            resolvedArgTypes.reserveCapacity(args.count)
            for (argIndex, arg) in args.enumerated() {
                if argIndex == index {
                    resolvedArgTypes.append(
                        driver.inferExpr(
                            arg.expr,
                            ctx: ctx,
                            locals: &locals,
                            expectedType: substitutedLambdaExpectedType
                        )
                    )
                } else if let inferredType = inferredNonLambdaArgTypes[argIndex] {
                    resolvedArgTypes.append(inferredType)
                } else {
                    resolvedArgTypes.append(driver.inferExpr(arg.expr, ctx: ctx, locals: &locals))
                }
            }

            let resolvedArgs = zip(args, resolvedArgTypes).map { argument, type in
                CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
            }
            let call = CallExpr(
                range: range,
                calleeName: calleeName ?? InternedString(),
                args: resolvedArgs,
                explicitTypeArgs: explicitTypeArgs
            )
            guard let parameterMapping = ctx.resolver.buildParameterMapping(
                signature: signature,
                callArgs: call.args,
                symbols: sema.symbols
            ) else {
                continue
            }

            return bindCallAndResolveReturnType(
                id,
                chosen: candidateContext.candidate,
                resolved: ResolvedCall(
                    chosenCallee: candidateContext.candidate,
                    substitutedTypeArguments: substitution,
                    parameterMapping: parameterMapping,
                    diagnostic: nil
                ),
                sema: sema
            )
        }

        return nil
    }

    func provisionalBuilderInferenceExpectedType(
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        argumentIndex: Int,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        range: SourceRange
    ) -> TypeID? {
        let sema = ctx.sema
        guard let candidateContext = uniqueBuilderInferenceCandidateContext(
            candidates: candidates,
            args: args,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            argumentIndex: argumentIndex,
            expectedType: expectedType,
            ctx: ctx,
            range: range
        ) else {
            return nil
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(candidateContext.signature.typeParameterSymbols)
        let expectedTypeSubstitution = provisionalBuilderInferenceSubstitution(
            signature: candidateContext.signature,
            expectedType: expectedType,
            typeVarBySymbol: typeVarBySymbol,
            ctx: ctx,
            range: range
        )
        return sema.types.substituteTypeParameters(
            in: candidateContext.signature.parameterTypes[argumentIndex],
            substitution: expectedTypeSubstitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    func collectBuilderInferenceAdditionalConstraints(
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        range: SourceRange
    ) -> AdditionalCallConstraints {
        let ast = ctx.ast
        let sema = ctx.sema
        var byCandidate: [SymbolID: [VariableConstraint]] = [:]

        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr),
                  case .lambdaLiteral(_, _, _, _) = argumentExpr
            else {
                continue
            }

            guard let candidateContext = uniqueBuilderInferenceCandidateContext(
                candidates: candidates,
                args: args,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                argumentIndex: index,
                expectedType: expectedType,
                ctx: ctx,
                range: range
            ) else {
                continue
            }

            let candidate = candidateContext.candidate
            let signature = candidateContext.signature
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let expectedTypeSubstitution = provisionalBuilderInferenceSubstitution(
                signature: signature,
                expectedType: expectedType,
                typeVarBySymbol: typeVarBySymbol,
                ctx: ctx,
                range: range
            )
            let parameterType = sema.types.substituteTypeParameters(
                in: signature.parameterTypes[index],
                substitution: expectedTypeSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            let nonNullParameterType = sema.types.makeNonNullable(parameterType)
            guard case let .functionType(functionType) = sema.types.kind(of: nonNullParameterType),
                  let receiverType = functionType.receiver
            else {
                continue
            }

            _ = driver.inferExpr(
                argument.expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nonNullParameterType
            )

            let constraints = collectBuilderInferenceConstraints(
                lambdaExprID: argument.expr,
                lambdaReceiverType: receiverType,
                expectedReturnType: functionType.returnType,
                typeVarBySymbol: typeVarBySymbol,
                ctx: ctx,
                range: range
            )
            guard !constraints.isEmpty else {
                continue
            }
            byCandidate[candidate, default: []].append(contentsOf: constraints)
        }

        return AdditionalCallConstraints(byCandidate: byCandidate)
    }

    func builderInferenceFallbackResolvedCall(
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        expectedType: TypeID?,
        additionalConstraints: AdditionalCallConstraints,
        call: CallExpr,
        ctx: TypeInferenceContext
    ) -> ResolvedCall? {
        guard let expectedType else {
            return nil
        }

        for (index, _) in args.enumerated() {
            guard let candidateContext = uniqueBuilderInferenceCandidateContext(
                candidates: candidates,
                args: args,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                argumentIndex: index,
                expectedType: expectedType,
                ctx: ctx,
                range: call.range
            ) else {
                continue
            }

            let sema = ctx.sema
            let signature = candidateContext.signature
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            var constraints = ctx.resolver.decomposeSubtypeConstraint(
                subtype: signature.returnType,
                supertype: expectedType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: sema.types,
                blameRange: call.range
            )
            constraints.append(contentsOf: additionalConstraints.byCandidate[candidateContext.candidate] ?? [])
            let substitution = solveBuilderInferenceSubstitution(
                constraints: constraints,
                typeVarBySymbol: typeVarBySymbol,
                sema: sema
            )
            if substitution.isEmpty && !signature.typeParameterSymbols.isEmpty {
                continue
            }
            guard let parameterMapping = ctx.resolver.buildParameterMapping(
                signature: signature,
                callArgs: call.args,
                symbols: sema.symbols
            ) else {
                continue
            }
            return ResolvedCall(
                chosenCallee: candidateContext.candidate,
                substitutedTypeArguments: substitution,
                parameterMapping: parameterMapping,
                diagnostic: nil
            )
        }

        if let expectedTypeOnly = expectedTypeOnlyBuilderInferenceFallbackResolvedCall(
            candidates: candidates,
            args: args,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            expectedType: expectedType,
            call: call,
            ctx: ctx
        ) {
            return expectedTypeOnly
        }

        return nil
    }

    private func expectedTypeOnlyBuilderInferenceFallbackResolvedCall(
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        expectedType: TypeID?,
        call: CallExpr,
        ctx: TypeInferenceContext
    ) -> ResolvedCall? {
        guard let expectedType else {
            return nil
        }

        for (index, _) in args.enumerated() {
            guard let candidateContext = uniqueBuilderInferenceCandidateContext(
                candidates: candidates,
                args: args,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                argumentIndex: index,
                expectedType: expectedType,
                ctx: ctx,
                range: call.range
            ) else {
                continue
            }

            let sema = ctx.sema
            let signature = candidateContext.signature
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let substitution = provisionalBuilderInferenceSubstitution(
                signature: signature,
                expectedType: expectedType,
                typeVarBySymbol: typeVarBySymbol,
                ctx: ctx,
                range: call.range
            )
            if substitution.isEmpty && !signature.typeParameterSymbols.isEmpty {
                continue
            }
            guard let parameterMapping = ctx.resolver.buildParameterMapping(
                signature: signature,
                callArgs: call.args,
                symbols: sema.symbols
            ) else {
                continue
            }
            return ResolvedCall(
                chosenCallee: candidateContext.candidate,
                substitutedTypeArguments: substitution,
                parameterMapping: parameterMapping,
                diagnostic: nil
            )
        }

        return nil
    }

    private func uniqueBuilderInferenceCandidateContext(
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        argumentIndex: Int,
        expectedType _: TypeID?,
        ctx: TypeInferenceContext,
        range _: SourceRange
    ) -> (candidate: SymbolID, signature: FunctionSignature)? {
        let sema = ctx.sema
        let narrowedCandidates = candidates.filter { candidate in
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
        let expectedTypeCandidates = narrowedCandidates.isEmpty ? candidates : narrowedCandidates
        guard expectedTypeCandidates.count == 1,
              let candidate = expectedTypeCandidates.first,
              let signature = sema.symbols.functionSignature(for: candidate),
              argumentIndex < signature.parameterTypes.count,
              isBuilderInferenceAnnotated(signature: signature, parameterIndex: argumentIndex, sema: sema)
        else {
            return nil
        }
        return (candidate, signature)
    }

    private func provisionalBuilderInferenceSubstitution(
        signature: FunctionSignature,
        expectedType: TypeID?,
        typeVarBySymbol: [SymbolID: TypeVarID],
        ctx: TypeInferenceContext,
        range: SourceRange
    ) -> [TypeVarID: TypeID] {
        let sema = ctx.sema
        guard let expectedType else {
            return [:]
        }
        let constraints = ctx.resolver.decomposeSubtypeConstraint(
            subtype: signature.returnType,
            supertype: expectedType,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: sema.types,
            blameRange: range
        )
        return solveBuilderInferenceSubstitution(
            constraints: constraints,
            typeVarBySymbol: typeVarBySymbol,
            sema: sema
        )
    }

    private func isBuilderInferenceAnnotated(
        signature: FunctionSignature,
        parameterIndex: Int,
        sema: SemaModule
    ) -> Bool {
        guard parameterIndex < signature.valueParameterSymbols.count else {
            return false
        }
        let parameterSymbol = signature.valueParameterSymbols[parameterIndex]
        return sema.symbols.annotations(for: parameterSymbol).contains { annotation in
            KnownCompilerAnnotation.builderInference.matches(annotation.annotationFQName)
        }
    }

    private func collectBuilderInferenceConstraints(
        lambdaExprID: ExprID,
        lambdaReceiverType: TypeID,
        expectedReturnType: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        ctx: TypeInferenceContext,
        range: SourceRange
    ) -> [VariableConstraint] {
        let ast = ctx.ast
        let sema = ctx.sema
        guard case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(lambdaExprID) else {
            return []
        }

        var constraints: [VariableConstraint] = []
        collectBuilderInferenceConstraints(
            in: body,
            lambdaReceiverType: lambdaReceiverType,
            typeVarBySymbol: typeVarBySymbol,
            ctx: ctx,
            output: &constraints
        )

        if expectedReturnType != sema.types.unitType,
           let bodyType = sema.bindings.exprTypes[body] {
            constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: bodyType,
                supertype: expectedReturnType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: sema.types,
                blameRange: ast.arena.exprRange(body) ?? range
            ))
        }

        return constraints
    }

    private func collectBuilderInferenceConstraints(
        in exprID: ExprID,
        lambdaReceiverType: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        ctx: TypeInferenceContext,
        output: inout [VariableConstraint]
    ) {
        let ast = ctx.ast
        guard let expr = ast.arena.expr(exprID) else {
            return
        }

        if case let .call(callee, _, args, range) = expr {
            appendBuilderInferenceConstraintsForImplicitReceiverCall(
                callExprID: exprID,
                calleeExprID: callee,
                args: args,
                lambdaReceiverType: lambdaReceiverType,
                typeVarBySymbol: typeVarBySymbol,
                ctx: ctx,
                range: range,
                output: &output
            )
        }

        for child in childExprIDs(of: expr) {
            collectBuilderInferenceConstraints(
                in: child,
                lambdaReceiverType: lambdaReceiverType,
                typeVarBySymbol: typeVarBySymbol,
                ctx: ctx,
                output: &output
            )
        }
    }

    private func appendBuilderInferenceConstraintsForImplicitReceiverCall(
        callExprID: ExprID,
        calleeExprID: ExprID,
        args: [CallArgument],
        lambdaReceiverType: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        ctx: TypeInferenceContext,
        range: SourceRange,
        output: inout [VariableConstraint]
    ) {
        let ast = ctx.ast
        let sema = ctx.sema

        guard sema.bindings.implicitReceiverMemberNames[calleeExprID] != nil,
              let binding = sema.bindings.callBindings[callExprID],
              let memberSignature = sema.symbols.functionSignature(for: binding.chosenCallee),
              let memberReceiverType = memberSignature.receiverType
        else {
            return
        }

        let memberTypeVarBySymbol = sema.types.makeTypeVarBySymbol(memberSignature.typeParameterSymbols)
        let receiverConstraints = ctx.resolver.decomposeSubtypeConstraint(
            subtype: sema.types.makeNonNullable(lambdaReceiverType),
            supertype: sema.types.makeNonNullable(memberReceiverType),
            typeVarBySymbol: memberTypeVarBySymbol,
            typeSystem: sema.types,
            blameRange: range
        )
        let memberSubstitution = solveBuilderInferenceSubstitution(
            constraints: receiverConstraints,
            typeVarBySymbol: memberTypeVarBySymbol,
            sema: sema
        )

        for (argIndex, argument) in args.enumerated() {
            guard let parameterIndex = binding.parameterMapping[argIndex],
                  parameterIndex < memberSignature.parameterTypes.count,
                  let argumentType = sema.bindings.exprTypes[argument.expr]
            else {
                continue
            }

            let instantiatedParameterType = sema.types.substituteTypeParameters(
                in: memberSignature.parameterTypes[parameterIndex],
                substitution: memberSubstitution,
                typeVarBySymbol: memberTypeVarBySymbol
            )
            output.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: argumentType,
                supertype: instantiatedParameterType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: sema.types,
                blameRange: ast.arena.exprRange(argument.expr) ?? range
            ))
        }
    }

    private func solveBuilderInferenceSubstitution(
        constraints: [VariableConstraint],
        typeVarBySymbol: [SymbolID: TypeVarID],
        sema: SemaModule
    ) -> [TypeVarID: TypeID] {
        let variables = Array(Set(typeVarBySymbol.values)).sorted(by: { $0.rawValue < $1.rawValue })
        guard !variables.isEmpty, !constraints.isEmpty else {
            return [:]
        }
        let solution = ConstraintSolver().solve(
            vars: variables,
            constraints: constraints,
            typeSystem: sema.types
        )
        return solution.isSuccess ? solution.substitution : [:]
    }

    private func childExprIDs(of expr: Expr) -> [ExprID] {
        switch expr {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral,
             .charLiteral, .boolLiteral, .stringLiteral, .nameRef, .breakExpr, .continueExpr,
             .superRef, .thisRef, .objectLiteral:
            return []
        case let .stringTemplate(parts, _):
            return parts.compactMap { part in
                if case let .expression(exprID) = part {
                    return exprID
                }
                return nil
            }
        case let .forExpr(_, iterable, body, _, _):
            return [iterable, body]
        case let .whileExpr(condition, body, _, _):
            return [condition, body]
        case let .doWhileExpr(body, condition, _, _):
            return [body, condition]
        case let .localDecl(_, _, _, initializer, _, _):
            return initializer.map { [$0] } ?? []
        case let .localAssign(_, value, _):
            return [value]
        case let .memberAssign(receiver, _, value, _):
            return [receiver, value]
        case let .indexedAssign(receiver, indices, value, _):
            return [receiver] + indices + [value]
        case let .call(callee, _, args, _):
            return [callee] + args.map(\.expr)
        case let .memberCall(receiver, _, _, args, _):
            return [receiver] + args.map(\.expr)
        case let .indexedAccess(receiver, indices, _):
            return [receiver] + indices
        case let .binary(_, lhs, rhs, _):
            return [lhs, rhs]
        case let .whenExpr(subject, branches, elseExpr, _):
            var exprIDs: [ExprID] = []
            if let subject {
                exprIDs.append(subject)
            }
            for branch in branches {
                exprIDs.append(contentsOf: branch.conditions)
                if let guardExpr = branch.guard_ {
                    exprIDs.append(guardExpr)
                }
                exprIDs.append(branch.body)
            }
            if let elseExpr {
                exprIDs.append(elseExpr)
            }
            return exprIDs
        case let .returnExpr(value, _, _):
            return value.map { [$0] } ?? []
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return [condition, thenExpr] + (elseExpr.map { [$0] } ?? [])
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            return [body] + catchClauses.map(\.body) + (finallyExpr.map { [$0] } ?? [])
        case let .unaryExpr(_, operand, _):
            return [operand]
        case let .isCheck(exprID, _, _, _):
            return [exprID]
        case let .asCast(exprID, _, _, _):
            return [exprID]
        case let .nullAssert(exprID, _):
            return [exprID]
        case let .safeMemberCall(receiver, _, _, args, _):
            return [receiver] + args.map(\.expr)
        case let .compoundAssign(_, _, value, _):
            return [value]
        case let .indexedCompoundAssign(_, receiver, indices, value, _):
            return [receiver] + indices + [value]
        case let .throwExpr(value, _):
            return [value]
        case let .lambdaLiteral(_, body, _, _):
            return [body]
        case let .callableRef(receiver, _, _):
            return receiver.map { [$0] } ?? []
        case let .localFunDecl(_, _, _, body, _):
            switch body {
            case let .block(statements, _):
                return statements
            case let .expr(exprID, _):
                return [exprID]
            case .unit:
                return []
            }
        case let .blockExpr(statements, trailingExpr, _):
            return statements + (trailingExpr.map { [$0] } ?? [])
        case let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            return [lhs, rhs]
        case let .destructuringDecl(_, _, initializer, _):
            return [initializer]
        case let .forDestructuringExpr(_, iterable, body, _):
            return [iterable, body]
        }
    }

}
