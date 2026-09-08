// swiftlint:disable function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallEarlyReceiverSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        if interner.resolve(calleeName) == "flatMapIndexed",
           args.count == 1,
           isSequenceLikeType(receiverType, sema: sema, interner: interner)
        {
            let receiverElementType: TypeID = if case let .classType(classType) = sema.types.kind(
                of: sema.types.makeNonNullable(receiverType)
            ), let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, receiverElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let lambdaBodyType = inferredLambdaReturnType(
                argExpr: args[0].expr,
                ast: ast,
                sema: sema
            )
            let flattenedElementType = getCollectionElementType(
                lambdaBodyType,
                sema: sema,
                interner: interner
            )
            if let sourceCallee = sourceBackedSequenceFlatMapIndexed(
                lambdaBodyType: lambdaBodyType,
                sema: sema,
                interner: interner
            ) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: sourceCallee,
                        substitutedTypeArguments: [receiverElementType, flattenedElementType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(sourceCallee))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            } else if let owner = driver.helpers.nominalSymbol(
                of: sema.types.makeNonNullable(receiverType),
                types: sema.types
            ),
                let ownerSymbol = sema.symbols.symbol(owner)
            {
                let memberFQName = ownerSymbol.fqName + [calleeName]
                if let fallbackCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == owner,
                          let signature = sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return signature.parameterTypes.count == 1
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: fallbackCallee,
                            substitutedTypeArguments: [],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
                }
            }
            sema.bindings.markCollectionExpr(id)
            let resultType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: flattenedElementType
            )
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if let boundContinuationCall = tryContinuationSyntheticMemberCall(
            id,
            calleeName: calleeName,
            receiverType: receiverType,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals
        ) {
            return boundContinuationCall
        }

        if let result = tryInferKClassReceiverMemberCall(
            id, receiverType: receiverType, calleeName: calleeName, args: args,
            explicitTypeArgs: explicitTypeArgs, range: range, ctx: ctx, locals: &locals
        ) {
            return result
        }

        if args.isEmpty,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
           locals[receiverName] == nil,
           let ownerSymbol = ctx.cachedScopeLookup(receiverName).first(where: { candidate in
               guard let symbol = sema.symbols.symbol(candidate) else {
                   return false
               }
               switch symbol.kind {
               case .class, .interface, .enumClass:
                   return true
               default:
                   return false
               }
           }),
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: calleeName,
               sema: sema
           )
        {
            if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
               !ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: memberSymbol,
                    name: interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
            sema.bindings.bindExprType(id, type: staticMember.type)
            return staticMember.type
        }
        return nil
    }

    /// KSP-441: pick the bundled `kotlin.sequences.flatMapIndexed` overload whose
    /// `transform` return type matches the lambda body (`Sequence<R>` or `Iterable<R>`).
    /// Returns `nil` when the bundled source declaration is unavailable, letting the
    /// caller fall back to the synthetic runtime-backed member.
    private func sourceBackedSequenceFlatMapIndexed(
        lambdaBodyType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("flatMapIndexed"),
        ]
        let lambdaReturnsSequence = isSequenceLikeType(lambdaBodyType, sema: sema, interner: interner)
        let candidates = sema.symbols.lookupAll(fqName: fqName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  signature.receiverType != nil
            else {
                return false
            }
            return true
        }
        return candidates.first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  case let .functionType(transformType) = sema.types.kind(of: signature.parameterTypes[0])
            else {
                return false
            }
            return isSequenceLikeType(transformType.returnType, sema: sema, interner: interner)
                == lambdaReturnsSequence
        }) ?? candidates.first
    }
}
