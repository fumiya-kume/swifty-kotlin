// swiftlint:disable function_body_length cyclomatic_complexity
import Foundation

extension CallTypeChecker {
    func tryInferMemberCallEarlyReceiverSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        recoveredReceiverType: TypeID?,
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
        let effectiveCallRecursiveReceiverType = recoveredReceiverType ?? receiverType
        if interner.resolve(calleeName) == "execute",
           args.count == 3,
           explicitTypeArgs.count <= 2,
           let workerSymbol = driver.helpers.nominalSymbol(
               of: sema.types.makeNonNullable(receiverType),
               types: sema.types
           ),
           let workerInfo = sema.symbols.symbol(workerSymbol),
           workerInfo.fqName.map({ interner.resolve($0) }) == ["kotlin", "native", "concurrent", "Worker"]
        {
            let transferModeType = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("native"),
                interner.intern("concurrent"),
                interner.intern("TransferMode"),
            ]).map { symbol in
                sema.types.make(.classType(ClassType(
                    classSymbol: symbol,
                    args: [],
                    nullability: .nonNull
                )))
            } ?? sema.types.anyType
            let modeType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: transferModeType)
            driver.emitSubtypeConstraint(
                left: modeType,
                right: transferModeType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let explicitProducedType = explicitTypeArgs.first
            let initialProducerExpectedType = explicitProducedType.map { producedType in
                sema.types.make(.functionType(FunctionType(
                    params: [],
                    returnType: producedType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            }
            let producerType = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: initialProducerExpectedType
            )
            let producedType = explicitTypeArgs.first ?? inferredLambdaReturnType(
                argExpr: args[1].expr,
                ast: ast,
                sema: sema
            )
            let producerExpectedType = initialProducerExpectedType ?? sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: producedType,
                isSuspend: false,
                nullability: .nonNull
            )))
            driver.emitSubtypeConstraint(
                left: producerType,
                right: producerExpectedType,
                range: ast.arena.exprRange(args[1].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let jobReturnExpectation = explicitTypeArgs.dropFirst().first ?? sema.types.anyType
            let jobExpectedType = sema.types.make(.functionType(FunctionType(
                params: [producedType],
                returnType: jobReturnExpectation,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let jobExpr = ast.arena.expr(args[2].expr), jobExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[2].expr)
            }
            let jobType = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: jobExpectedType)
            driver.emitSubtypeConstraint(
                left: jobType,
                right: jobExpectedType,
                range: ast.arena.exprRange(args[2].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let jobReturnType = explicitTypeArgs.dropFirst().first ?? inferredLambdaReturnType(
                argExpr: args[2].expr,
                ast: ast,
                sema: sema
            )
            let futureFQName = ["kotlin", "native", "concurrent", "Future"].map { interner.intern($0) }
            let resultType: TypeID
            if let futureSymbol = sema.symbols.lookup(fqName: futureFQName) {
                resultType = sema.types.make(.classType(ClassType(
                    classSymbol: futureSymbol,
                    args: [.invariant(jobReturnType)],
                    nullability: .nonNull
                )))
            } else {
                resultType = sema.types.anyType
            }
            let executeFQName = workerInfo.fqName + [calleeName]
            if let executeSymbol = sema.symbols.lookupAll(fqName: executeFQName).first(where: { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == "kk_worker_execute"
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: executeSymbol,
                        substitutedTypeArguments: [producedType, jobReturnType],
                        parameterMapping: [0: 0, 1: 1, 2: 2]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(executeSymbol))
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

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
            if let owner = driver.helpers.nominalSymbol(
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
        if interner.resolve(calleeName) == "callRecursive",
           args.count == 1,
           case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(effectiveCallRecursiveReceiverType)),
           let receiverSymbol = sema.symbols.symbol(classType.classSymbol),
           receiverSymbol.fqName.count == 2,
           interner.resolve(receiverSymbol.fqName[0]) == "kotlin",
           interner.resolve(receiverSymbol.fqName[1]) == "DeepRecursiveFunction"
        {
            let parameterType: TypeID = if let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let returnType: TypeID = if classType.args.count > 1 {
                switch classType.args[1] {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: parameterType)
            if let memberSymbol = sema.symbols.lookupAll(fqName: [
                interner.intern("kotlin"),
                interner.intern("DeepRecursiveScope"),
                interner.intern("callRecursive"),
            ]).first(where: { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == "kk_deep_recursive_function_callRecursive"
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: memberSymbol,
                        substitutedTypeArguments: [parameterType, returnType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(memberSymbol))
            }
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
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
}
