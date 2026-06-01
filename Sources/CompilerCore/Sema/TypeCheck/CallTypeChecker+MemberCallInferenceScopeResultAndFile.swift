// swiftlint:disable file_length function_body_length cyclomatic_complexity
import Foundation

extension CallTypeChecker {
    func tryInferMemberCallScopeResultAndFileSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let calleeName = request.calleeName
        let args = request.args
        let ctx = request.ctx
        let expectedType = request.expectedType
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        // --- Scope functions: let, run, apply, also (STDLIB-004) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct expected type (it vs. receiver this).
        // Skip interception when the receiver type defines a real member
        // with the same name (user-defined members take precedence).
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            let scopeKind: ScopeFunctionKind? = switch calleeStr {
            case "let": .scopeLet
            case "run": .scopeRun
            case "apply": .scopeApply
            case "also": .scopeAlso
            case "use" where isCloseableReceiver(receiverType, sema: sema, interner: interner): .scopeUse
            default: nil
            }
            let hasUserDefinedMember = if scopeKind != nil {
                !driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                ).isEmpty
            } else {
                false
            }
            if let scopeKind, !hasUserDefinedMember {
                let nonNullReceiverType = safeCall
                    ? sema.types.makeNonNullable(receiverType)
                    : receiverType

                switch scopeKind {
                case .scopeLet:
                    // let: lambda receives `it` parameter typed as T, returns R
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: expectedType ?? sema.types.anyType
                    )))
                    let lambdaType = driver.inferExpr(
                        args[0].expr, ctx: ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? sema.types.anyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeRun:
                    // run: lambda has receiver T as `this`, returns R
                    let receiverCtx = ctx.with(implicitReceiverType: nonNullReceiverType)
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        receiver: nonNullReceiverType,
                        params: [],
                        returnType: expectedType ?? sema.types.anyType
                    )))
                    let lambdaType = driver.inferExpr(
                        args[0].expr, ctx: receiverCtx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? sema.types.anyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeApply:
                    // apply: lambda has receiver T as `this`, returns T (receiver itself)
                    let receiverCtx = ctx.with(implicitReceiverType: nonNullReceiverType)
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        receiver: nonNullReceiverType,
                        params: [],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(
                        args[0].expr, ctx: receiverCtx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let finalType = safeCall
                        ? sema.types.makeNullable(nonNullReceiverType)
                        : nonNullReceiverType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    // Propagate collection marking: apply returns receiver unchanged,
                    // so chained member calls (e.g. .let { it.size }) must still see
                    // the collection type. (STDLIB-002-BUG-01)
                    if isCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                        sema.bindings.markCollectionExpr(id)
                    }
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeAlso:
                    // also: lambda receives `it` parameter typed as T, returns T
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(
                        args[0].expr, ctx: ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let finalType = safeCall
                        ? sema.types.makeNullable(nonNullReceiverType)
                        : nonNullReceiverType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    // Propagate collection marking: also returns receiver unchanged,
                    // so chained member calls (e.g. .let { it.size }) must still see
                    // the collection type. (STDLIB-002-BUG-01)
                    if isCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                        sema.bindings.markCollectionExpr(id)
                    }
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeUse:
                    // use: lambda receives `it` parameter typed as T, returns R.
                    // Semantically equivalent to `let` but wraps in try-finally { close() }.
                    // NOTE: The lambda inference below intentionally duplicates scopeLet logic.
                    // The duplication is deliberate — use and let share the same type inference
                    // semantics (receiver passed as `it`, lambda return type becomes call result)
                    // but differ in lowering (use emits try-finally with close()).
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: expectedType ?? sema.types.anyType
                    )))
                    let lambdaType = driver.inferExpr(
                        args[0].expr, ctx: ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? sema.types.anyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeWith:
                    break // with is handled in inferCallExpr (top-level function)

                case .scopeContext:
                    break // context is handled in inferCallExpr (top-level function)

                case .scopeTopLevelRun:
                    break // top-level run is handled in inferCallExpr
                }
            }
        }

        // --- Result member functions (STDLIB-590) ---
        // Result<T>.onSuccess/onFailure/getOrElse/getOrDefault/map/fold/recover
        // These require special handling because the generic type parameter T
        // needs to be extracted from the receiver's Result<out T> type and used
        // to construct the expected lambda parameter types.
        if args.count >= 1, args.count <= 2 {
            let calleeStr = interner.resolve(calleeName)
            let resultMemberNames: Set = [
                "onSuccess", "onFailure", "getOrElse", "getOrDefault", "map", "fold", "recover",
            ]
            if resultMemberNames.contains(calleeStr),
               let resultElementType = extractResultElementType(receiverType, sema: sema, interner: interner)
            {
                let throwableType = driver.helpers.throwableType(sema: sema, interner: interner) ?? sema.types.anyType
                let nonNullReceiverType = safeCall ? sema.types.makeNonNullable(receiverType) : receiverType

                switch calleeStr {
                case "onSuccess" where args.count == 1:
                    // onSuccess(action: (T) -> Unit): Result<T>
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let onSuccessSymbol = lookupResultMember("onSuccess", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: onSuccessSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "onFailure" where args.count == 1:
                    // onFailure(action: (Throwable) -> Unit): Result<T>
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let onFailureSymbol = lookupResultMember("onFailure", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: onFailureSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "getOrElse" where args.count == 1:
                    // getOrElse(onFailure: (Throwable) -> T): T
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: resultElementType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let getOrElseSymbol = lookupResultMember("getOrElse", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: getOrElseSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultElementType) : resultElementType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "getOrDefault" where args.count == 1:
                    // getOrDefault(defaultValue: T): T
                    let defaultExpectedType = resultElementType
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: defaultExpectedType)
                    if let getOrDefaultSymbol = lookupResultMember("getOrDefault", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: getOrDefaultSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultElementType) : resultElementType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "map" where args.count == 1:
                    // map(transform: (T) -> R): Result<R>
                    // Note: only intercept for Result receiver, not for collections
                    // expectedType is Result<R>, so extract R for the lambda return type
                    let lambdaReturnType = expectedType.flatMap { extractResultElementType($0, sema: sema, interner: interner) } ?? sema.types.anyType
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: lambdaReturnType
                    )))
                    let lambdaType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    let mappedType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    if let mapSymbol = lookupResultMember("map", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: mapSymbol,
                            substitutedTypeArguments: [resultElementType, mappedType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let mappedResultType = makeResultType(elementType: mappedType, sema: sema, interner: interner) ?? sema.types.anyType
                    let finalType = safeCall ? sema.types.makeNullable(mappedResultType) : mappedResultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "recover" where args.count == 1:
                    // recover(transform: (Throwable) -> T): Result<T>
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: resultElementType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let recoverSymbol = lookupResultMember("recover", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: recoverSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "fold" where args.count == 2:
                    // fold(onSuccess: (T) -> R, onFailure: (Throwable) -> R): R
                    let onSuccessExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: expectedType ?? sema.types.anyType
                    )))
                    let onSuccessType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: onSuccessExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    let foldReturnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: onSuccessType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    let onFailureExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: foldReturnType
                    )))
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: onFailureExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    if let foldSymbol = lookupResultMember("fold", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: foldSymbol,
                            substitutedTypeArguments: [resultElementType, foldReturnType],
                            parameterMapping: [0: 0, 1: 1]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(foldReturnType) : foldReturnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                default:
                    break
                }
            }
        }

        // --- takeIf / takeUnless (STDLIB-160) ---
        // T.takeIf((T) -> Boolean): T? / T.takeUnless((T) -> Boolean): T?
        // Inline-expanded by CallLowerer; no runtime call.
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            let takeKind: TakeIfTakeUnlessKind? = switch calleeStr {
            case "takeIf": .takeIf
            case "takeUnless": .takeUnless
            default: nil
            }
            let hasUserDefinedMember = if takeKind != nil {
                !driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                ).isEmpty
            } else {
                false
            }
            if let takeKind, !hasUserDefinedMember {
                let nonNullReceiverType = safeCall
                    ? sema.types.makeNonNullable(receiverType)
                    : receiverType
                let boolType = sema.types.make(.primitive(.boolean, .nonNull))
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [nonNullReceiverType],
                    returnType: boolType
                )))
                _ = driver.inferExpr(
                    args[0].expr, ctx: ctx, locals: &locals,
                    expectedType: lambdaExpectedType
                )
                let nullableReceiverType = sema.types.makeNullable(nonNullReceiverType)
                let finalType = nullableReceiverType
                sema.bindings.markTakeIfTakeUnlessExpr(id, kind: takeKind)
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // --- STDLIB-IO-FN-016: File.forEachBlock ---
        // forEachBlock(action: (ByteArray, Int) -> Unit)          -- 1 arg
        // forEachBlock(blockSize: Int, action: (ByteArray, Int) -> Unit) -- 2 args
        do {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "forEachBlock",
               isFileType(receiverType, sema: sema, interner: interner),
               args.count == 1 || args.count == 2
            {
                let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                let listOfIntType: TypeID = if let listSym = listSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: listSym,
                        args: [.out(sema.types.intType)],
                        nullability: .nonNull
                    )))
                } else { sema.types.anyType }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [listOfIntType, sema.types.intType],
                    returnType: sema.types.unitType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let lambdaArgIndex = args.count == 2 ? 1 : 0
                if args.count == 2 {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
                if let lambdaExpr = ast.arena.expr(args[lambdaArgIndex].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[lambdaArgIndex].expr)
                }
                _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let finalType = safeCall ? sema.types.makeNullable(sema.types.unitType) : sema.types.unitType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // --- File lambda-accepting methods: forEachLine, useLines (STDLIB-322) ---
        // These require the lambda to use the collection HOF closure ABI (closureRaw
        // prepended), and the lambda's implicit `it` must be correctly resolved.
        // STDLIB-IO-FN-040: also handles `BufferedReader.useLines { lines -> T }`
        // because the synthetic stub registers `useLines` on `java.io.BufferedReader`
        // with the same `(List<String>) -> Any` signature.
        // STDLIB-IO-FN-017: also handles `BufferedReader.forEachLine { line -> Unit }`
        // via the same HOF closure ABI — action receives `String`, returns `Unit`.
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            let isFileReceiver = isFileType(receiverType, sema: sema, interner: interner)
            let isBufferedReader = isBufferedReaderType(receiverType, sema: sema, interner: interner)
            let isReaderUseLines = !isFileReceiver
                && calleeStr == "useLines"
                && isBufferedReader
            let isReaderForEachLine = !isFileReceiver
                && calleeStr == "forEachLine"
                && isBufferedReader
            if (isFileReceiver && (calleeStr == "forEachLine" || calleeStr == "useLines"))
                || isReaderUseLines
                || isReaderForEachLine
            {
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                let lambdaParamType: TypeID
                let lambdaReturnType: TypeID
                let callReturnType: TypeID
                if calleeStr == "forEachLine" {
                    // forEachLine { line: String -> Unit }
                    lambdaParamType = sema.types.stringType
                    lambdaReturnType = sema.types.unitType
                    callReturnType = sema.types.unitType
                } else {
                    // useLines { lines: List<String> -> T }
                    let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                    lambdaParamType = if let listSym = listSymbol {
                        sema.types.make(.classType(ClassType(
                            classSymbol: listSym,
                            args: [.out(sema.types.stringType)],
                            nullability: .nonNull
                        )))
                    } else {
                        sema.types.anyType
                    }
                    lambdaReturnType = expectedType ?? sema.types.anyType
                    callReturnType = expectedType ?? sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [lambdaParamType],
                    returnType: lambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let inferredLambdaType = driver.inferExpr(
                    args[0].expr, ctx: ctx, locals: &locals,
                    expectedType: lambdaExpectedType
                )
                // For useLines, extract the actual return type from the lambda
                let finalReturnType: TypeID = if calleeStr == "useLines" {
                    if case let .functionType(fnType) = sema.types.kind(of: inferredLambdaType) {
                        fnType.returnType
                    } else {
                        callReturnType
                    }
                } else {
                    callReturnType
                }
                let finalType = safeCall ? sema.types.makeNullable(finalReturnType) : finalReturnType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // --- STDLIB-IO-PATH-FN-038: Path.useLines(charset?, block) ---
        // Path.useLines receives a `(Sequence<String>) -> T` block and can be called
        // as `path.useLines { lines -> ... }` (1 arg) or
        // `path.useLines(Charsets.UTF_8) { lines -> ... }` (2 args: charset + block).
        // The lambda argument is always the last one.
        if (args.count == 1 || args.count == 2),
           interner.resolve(calleeName) == "useLines",
           isPathType(receiverType, sema: sema, interner: interner)
        {
            let lambdaArgIndex = args.count - 1
            let lambdaArg = args[lambdaArgIndex]
            if let lambdaExpr = ast.arena.expr(lambdaArg.expr), case .lambdaLiteral = lambdaExpr {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArg.expr)
            }
            // The block receives Sequence<String>; materialize the type.
            let sequenceSymbol = sema.symbols.lookupByShortName(interner.intern("Sequence")).first
            let sequenceOfStringType: TypeID = if let seqSym = sequenceSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: seqSym,
                    args: [.out(sema.types.stringType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let lambdaReturnType = expectedType ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [sequenceOfStringType],
                returnType: lambdaReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            // Infer the non-lambda arg (charset) if present using the normal path.
            if args.count == 2 {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
            }
            let inferredLambdaType = driver.inferExpr(
                lambdaArg.expr, ctx: ctx, locals: &locals,
                expectedType: lambdaExpectedType
            )
            let finalReturnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: inferredLambdaType) {
                fnType.returnType
            } else {
                lambdaReturnType
            }
            let finalType = safeCall ? sema.types.makeNullable(finalReturnType) : finalReturnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        return nil
    }
}
