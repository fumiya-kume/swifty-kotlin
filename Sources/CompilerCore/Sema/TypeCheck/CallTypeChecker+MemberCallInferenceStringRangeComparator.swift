// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallStringRangeComparatorSpecials(
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
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        // Early range HOF fallback: range forEach/map need lambda inference with
        // expectedType so the implicit `it` parameter gets bound correctly.
        // Must run before argument pre-inference below to avoid resolving
        // lambdas without the expected function type.
        if sema.bindings.isRangeExpr(receiverID),
           !args.isEmpty
        {
            if let fallbackType = tryRangeMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: false,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
        }

        let stringHOFReceiverType = safeCall
            ? sema.types.makeNonNullable(receiverType)
            : receiverType
        if interner.resolve(calleeName) == "toCollection",
           args.count == 1,
           isSyntheticStringLikeType(stringHOFReceiverType, sema: sema)
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            bindSyntheticStringMemberDirectlyIfAvailable(
                id,
                calleeName: calleeName,
                argumentCount: args.count,
                receiverType: stringHOFReceiverType,
                sema: sema,
                interner: interner
            )
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if let boundType = tryBindStringChunkedTransform(
            id,
            calleeName: calleeName,
            receiverType: stringHOFReceiverType,
            args: args,
            safeCall: safeCall,
            ast: ast,
            ctx: ctx,
            locals: &locals,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return boundType
        }
        if let boundType = tryBindStringWindowedTransform(
            id,
            calleeName: calleeName,
            receiverType: stringHOFReceiverType,
            args: args,
            safeCall: safeCall,
            ast: ast,
            ctx: ctx,
            locals: &locals,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return boundType
        }

        if args.count == 1 {
            let stringHOFCalleeStr = interner.resolve(calleeName)
            let isStringHOFReceiver = sema.types.isSubtype(stringHOFReceiverType, sema.types.stringType)
                || ((stringHOFCalleeStr == "ifBlank" || stringHOFCalleeStr == "ifEmpty" || stringHOFCalleeStr == "zipWithNext"
                    || stringHOFCalleeStr == "onEach" || stringHOFCalleeStr == "onEachIndexed")
                    && isSyntheticStringLikeType(stringHOFReceiverType, sema: sema))
            if isStringHOFReceiver,
               [
                   "indexOfFirst", "indexOfLast",
                   "map", "mapIndexed", "mapNotNull",
                   "takeWhile", "dropWhile",
                   "trim", "trimStart", "trimEnd",
                   "zipWithNext",
                   "onEach", "onEachIndexed",
                   "ifBlank",
                   "ifEmpty",
               ].contains(stringHOFCalleeStr)
            {
                let charType = sema.types.make(.primitive(.char, .nonNull))
                let intType = sema.types.intType
                if stringHOFCalleeStr != "splitToSequence" && stringHOFCalleeStr != "zipWithNext" {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    let lambdaExpectedType: TypeID = switch stringHOFCalleeStr {
                    case "map":
                        sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "mapIndexed":
                        sema.types.make(.functionType(FunctionType(
                            params: [intType, charType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "mapNotNull":
                        sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: sema.types.nullableAnyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "zipWithNext":
                        sema.types.make(.functionType(FunctionType(
                            params: [charType, charType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "onEach":
                        sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: sema.types.unitType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "onEachIndexed":
                        sema.types.make(.functionType(FunctionType(
                            params: [intType, charType],
                            returnType: sema.types.unitType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "ifBlank", "ifEmpty":
                        sema.types.make(.functionType(FunctionType(
                            params: [],
                            returnType: sema.types.stringType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    default:
                        sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: sema.types.booleanType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                }
                let resolvedArgTypes = args.map { arg in
                    sema.bindings.exprType(for: arg.expr) ?? sema.types.anyType
                }
                if stringHOFCalleeStr == "zipWithNext" {
                    // Re-run inference with the transform overload so the result type
                    // comes from the lambda body rather than the placeholder `Any`.
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    guard explicitTypeArgs.count <= 1 else {
                        sema.bindings.bindExprType(id, type: sema.types.anyType)
                        return sema.types.anyType
                    }
                    let lambdaReturnType = explicitTypeArgs.first ?? sema.types.anyType
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [charType, charType],
                        returnType: lambdaReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let bodyType = explicitTypeArgs.first
                        ?? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                    if let chosen = sema.symbols.lookupAll(fqName: [
                        interner.intern("kotlin"),
                        interner.intern("text"),
                        calleeName,
                    ]).first(where: { candidate in
                        isSyntheticStringMemberCandidate(
                            candidate,
                            named: calleeName,
                            receiverType: stringHOFReceiverType,
                            sema: sema,
                            interner: interner
                        )
                            && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == args.count
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [bodyType],
                                parameterMapping: [0: 0]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    let resultType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: bodyType
                    )
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: stringHOFReceiverType,
                    args: args,
                    argTypes: resolvedArgTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                bindSyntheticStringMemberDirectlyIfAvailable(
                    id,
                    calleeName: calleeName,
                    argumentCount: args.count,
                    receiverType: stringHOFReceiverType,
                    sema: sema,
                    interner: interner
                )
                let sequenceStringType: TypeID = {
                    let knownNames = KnownCompilerNames(interner: interner)
                    guard let sequenceSymbol = sema.symbols.lookupAll(fqName: knownNames.kotlinSequenceFQName).first else {
                        return sema.types.anyType
                    }
                    return sema.types.make(.classType(ClassType(
                        classSymbol: sequenceSymbol,
                        args: [.out(sema.types.stringType)],
                        nullability: .nonNull
                    )))
                }()
                let resultType: TypeID = switch stringHOFCalleeStr {
                case "indexOfFirst", "indexOfLast": sema.types.intType
                case "takeWhile", "dropWhile",
                     "trim", "trimStart", "trimEnd": sema.types.stringType
                case "map", "mapIndexed", "mapNotNull": sema.types.anyType
                case "onEach", "onEachIndexed": sema.types.stringType
                case "splitToSequence": sequenceStringType
                case "ifBlank", "ifEmpty": sema.types.stringType
                default: sema.types.anyType
                }
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // Comparator member HOFs (STDLIB-176): thenBy/thenByDescending/thenDescending/thenComparator.
        // These need the Comparator<T> receiver type so the lambda gets the correct
        // contextual function signature before the general resolution path runs.
        if args.count == 2,
           ["thenBy", "thenByDescending"].contains(interner.resolve(calleeName)),
           let comparatorElementType = resolvedComparatorElementType(
               of: receiverType,
               sema: sema,
               interner: interner
           )
        {
            let keyComparatorType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            if let keyType = resolvedComparatorElementType(of: keyComparatorType, sema: sema, interner: interner) {
                if let lambdaExpr = ast.arena.expr(args[1].expr),
                   lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [comparatorElementType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            }
        }
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if let comparatorElementType = resolvedComparatorElementType(
                of: receiverType,
                sema: sema,
                interner: interner
            ) {
                guard let lambdaExpr = ast.arena.expr(args[0].expr),
                      lambdaExpr.isLambdaOrCallableRef
                else {
                    return nil
                }
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                switch calleeStr {
                case "thenBy", "thenByDescending":
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [comparatorElementType],
                        returnType: sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                case "thenComparator", "thenDescending":
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [comparatorElementType, comparatorElementType],
                        returnType: sema.types.intType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                default:
                    break
                }
            }
        }
        return nil
    }
}
