// swiftlint:disable file_length
import Foundation

// swiftlint:disable type_body_length
final class CallTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func inferCallExpr(
        _ id: ExprID,
        calleeID: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        let calleeExpr = ast.arena.expr(calleeID)
        let calleeName: InternedString? = if case let .nameRef(name, _) = calleeExpr {
            name
        } else {
            nil
        }
        let calleePath = qualifiedCalleePath(for: calleeID, ast: ast)
        if let customBuilderType = inferExperimentalBuilderCallExpr(
            id,
            calleeName: calleeName,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return customBuilderType
        }
        // --- Builder DSL functions (STDLIB-002) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct implicit receiver type.
        if let calleeName {
            if interner.resolve(calleeName) == "DeepRecursiveFunction",
               args.count == 1,
               explicitTypeArgs.count == 2,
               locals[calleeName] == nil
            {
                let kotlinPkg = [interner.intern("kotlin")]
                let functionFQName = kotlinPkg + [interner.intern("DeepRecursiveFunction")]
                let scopeFQName = kotlinPkg + [interner.intern("DeepRecursiveScope")]
                let ctorFQName = functionFQName + [interner.intern("<init>")]
                if let functionSymbol = sema.symbols.lookupAll(fqName: functionFQName).first,
                   let scopeSymbol = sema.symbols.lookupAll(fqName: scopeFQName).first
                {
                    let inputType = explicitTypeArgs[0]
                    let returnType = explicitTypeArgs[1]
                    let scopeType = sema.types.make(.classType(ClassType(
                        classSymbol: scopeSymbol,
                        args: [.invariant(inputType), .invariant(returnType)],
                        nullability: .nonNull
                    )))
                    let functionType = sema.types.make(.classType(ClassType(
                        classSymbol: functionSymbol,
                        args: [.invariant(inputType), .invariant(returnType)],
                        nullability: .nonNull
                    )))
                    let blockExpectedType = sema.types.make(.functionType(FunctionType(
                        receiver: scopeType,
                        params: [inputType],
                        returnType: returnType,
                        isSuspend: true,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(
                        args[0].expr,
                        ctx: ctx.with(implicitReceiverType: scopeType),
                        locals: &locals,
                        expectedType: blockExpectedType
                    )
                    if let ctorSymbol = sema.symbols.lookupAll(fqName: ctorFQName).first(where: { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.parameterTypes.count == 1
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: ctorSymbol,
                                substitutedTypeArguments: explicitTypeArgs,
                                parameterMapping: [0: 0]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(ctorSymbol))
                    }
                    sema.bindings.bindExprType(id, type: functionType)
                    return functionType
                }
            }
            if let builderKind = builderDSLKind(for: calleeName, interner: interner),
               shouldUseBuilderDSLSpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
            {
                let lambdaArgumentIndex: Int? = switch builderKind {
                case .buildString:
                    switch args.count {
                    case 1: 0
                    case 2: 1
                    default: nil
                    }
                case .buildList:
                    switch args.count {
                    case 1: 0
                    case 2: 1
                    default: nil
                    }
                case .buildSet, .buildMap:
                    args.count == 1 ? 0 : nil
                }
                guard let lambdaArgumentIndex else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                if builderKind == .buildList || builderKind == .buildString, args.count == 2 {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
                let argumentExprID = args[lambdaArgumentIndex].expr
                guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }

                let receiverType = builderDSLReceiverType(
                    kind: builderKind,
                    lambdaExprID: argumentExprID,
                    expectedType: expectedType,
                    ctx: ctx,
                    locals: locals,
                    sema: sema,
                    interner: interner
                )
                let returnType: TypeID = switch builderKind {
                case .buildString:
                    sema.types.stringType
                case .buildList:
                    builderDSLBuildListReturnType(receiverType: receiverType, sema: sema, interner: interner)
                case .buildSet:
                    builderDSLBuildSetReturnType(receiverType: receiverType, sema: sema, interner: interner)
                case .buildMap:
                    builderDSLBuildMapReturnType(receiverType: receiverType, sema: sema, interner: interner)
                }
                // Infer the lambda argument with the builder receiver as implicit `this`.
                var builderCtx = ctx.with(implicitReceiverType: receiverType)
                builderCtx.isBuilderLambdaScope = true
                builderCtx.builderKind = builderKind
                _ = driver.inferExpr(argumentExprID, ctx: builderCtx, locals: &locals)
                sema.bindings.markBuilderDSLExpr(id, kind: builderKind)
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
            }
        }

        // --- sequence { ... } builder (STDLIB-330) ---
        // Intercept before eager argument inference so the lambda is inferred
        // with a SequenceScope<T> implicit receiver and T can be recovered from
        // expected type or nested yield()/yieldAll() calls.
        if let calleeName,
           interner.resolve(calleeName) == "sequence",
           args.count == 1,
           shouldUseBuilderDSLSpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            let argumentExprID = args[0].expr
            guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let returnType = sequenceBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let receiverType = sequenceBuilderReceiverType(
                sequenceType: returnType,
                sema: sema,
                interner: interner
            )
            let lambdaExpectedType = sequenceBuilderLambdaType(
                receiverType: receiverType,
                sema: sema
            )
            _ = driver.inferExpr(
                argumentExprID,
                ctx: ctx.with(implicitReceiverType: receiverType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            let refinedReturnType = sequenceBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            if let chosen = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                interner.intern("sequence"),
            ]) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }

        // --- iterator { ... } builder (STDLIB-331/564) ---
        if let calleeName,
           interner.resolve(calleeName) == "iterator",
           args.count == 1,
           locals[calleeName] == nil
        {
            let argumentExprID = args[0].expr
            guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let returnType = iteratorBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let receiverType = sequenceBuilderReceiverType(
                sequenceType: returnType,
                sema: sema,
                interner: interner
            )
            let lambdaExpectedType = sequenceBuilderLambdaType(
                receiverType: receiverType,
                sema: sema
            )
            _ = driver.inferExpr(
                argumentExprID,
                ctx: ctx.with(implicitReceiverType: receiverType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            let refinedReturnType = iteratorBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            if let chosen = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                interner.intern("iterator"),
            ]) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }

        // --- produce { ... } builder (STDLIB-CORO-075) ---
        if let calleeName,
           calleeName == knownNames.produce,
           args.count == 1,
           locals[calleeName] == nil
        {
            let argumentExprID = args[0].expr
            guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let channelType = produceBuilderChannelType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let receiverType = produceBuilderReceiverType(
                channelType: channelType,
                sema: sema,
                interner: interner
            )
            let lambdaExpectedType = sequenceBuilderLambdaType(
                receiverType: receiverType,
                sema: sema
            )
            _ = driver.inferExpr(
                argumentExprID,
                ctx: ctx.with(implicitReceiverType: receiverType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            let refinedChannelType = produceBuilderChannelType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            if let chosen = sema.symbols.lookup(fqName: knownNames.kotlinxCoroutinesProduceFQName) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: refinedChannelType)
            return refinedChannelType
        }

        // --- Scope function: with(receiver, block) (STDLIB-004, STDLIB-061) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct implicit receiver type.
        // Intercept when no local or user-defined (non-synthetic) `with` shadows the stdlib helper.
        if let calleeName, args.count == 2,
           calleeName == knownNames.with,
           locals[calleeName] == nil,
           !ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
               guard let sym = ctx.cachedSymbol(candidate) else { return false }
               return !sym.flags.contains(.synthetic)
           })
        {
            // First arg is the receiver object
            let withReceiverType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            // Second arg is the lambda with receiver
            let receiverCtx = ctx.with(implicitReceiverType: withReceiverType)
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: withReceiverType,
                params: [],
                returnType: expectedType ?? sema.types.anyType
            )))
            let lambdaType = driver.inferExpr(
                args[1].expr, ctx: receiverCtx, locals: &locals,
                expectedType: lambdaExpectedType
            )
            let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[1].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeWith)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        // --- produce { ... } builder (CORO-075) ---
        if let calleeName,
           calleeName == knownNames.produce,
           args.count == 1,
           locals[calleeName] == nil
        {
            let argumentExprID = args[0].expr
            guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let channelType = produceBuilderChannelType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let receiverType = produceBuilderReceiverType(
                channelType: channelType,
                sema: sema,
                interner: interner
            )
            let lambdaExpectedType = sequenceBuilderLambdaType(
                receiverType: receiverType,
                sema: sema
            )
            _ = driver.inferExpr(
                argumentExprID,
                ctx: ctx.with(implicitReceiverType: receiverType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            let refinedChannelType = produceBuilderChannelType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            if let chosen = sema.symbols.lookup(fqName: knownNames.kotlinxCoroutinesProduceFQName) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: refinedChannelType)
            return refinedChannelType
        }

        // --- Scope function: top-level run(block) (STDLIB-401) ---
        // `run { expr }` simply executes the block lambda and returns the result.
        // Intercept when no local or user-defined (non-synthetic) `run` shadows the stdlib helper.
        // The single argument must be a lambda literal or callable reference;
        // otherwise (e.g. `run(123)`) fall through to normal call resolution.
        if isTopLevelRunCandidate(
            calleeName: calleeName,
            args: args,
            knownNames: knownNames,
            ast: ast,
            ctx: ctx,
            locals: locals
        ) {
            let lambdaExpectedType: TypeID? = if let expectedType {
                sema.types.make(.functionType(FunctionType(
                    params: [],
                    returnType: expectedType
                )))
            } else {
                nil
            }
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
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeTopLevelRun)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        // --- runCatching(block) (STDLIB-590) ---
        // `runCatching { expr }` executes the block lambda and wraps the result
        // in a Result<T>.  Similar to top-level `run`, but returns Result<T>.
        if let calleeName, args.count == 1,
           calleeName == knownNames.runCatching,
           locals[calleeName] == nil,
           isLambdaOrCallableRefArg(args[0].expr, ast: ast),
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "runCatching"], ctx: ctx)
        {
            let lambdaType = driver.inferExpr(
                args[0].expr, ctx: ctx, locals: &locals, expectedType: nil
            )
            let innerType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            // Build Result<T> type
            let resultType: TypeID = if let resultClassSymbol = sema.symbols.lookup(fqName: knownNames.kotlinResultFQName) {
                sema.types.make(.classType(ClassType(
                    classSymbol: resultClassSymbol,
                    args: [.out(innerType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            // Mark the lambda for closure ABI expansion in KIR
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            // Bind the call to the synthetic runCatching function symbol
            if let runCatchingSymbol = sema.symbols.lookup(fqName: knownNames.kotlinRunCatchingFQName) {
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: runCatchingSymbol,
                    substitutedTypeArguments: [innerType],
                    parameterMapping: [0: 0]
                ))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn ---
        // Special intrinsic used by coroutine lowering. The block is type-checked
        // as a regular function taking the current Continuation<T>.
        let suspendCoroutineIntrinsicFQName = knownNames.kotlinCoroutinesIntrinsicsFQName + [knownNames.suspendCoroutineUninterceptedOrReturn]
        let isSuspendCoroutineIntrinsic = if let calleeName {
            calleeName == knownNames.suspendCoroutineUninterceptedOrReturn
                && !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
                && isSyntheticStdlibSymbol(
                    calleeName,
                    fqComponents: ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"],
                    ctx: ctx
                )
        } else {
            calleePath == suspendCoroutineIntrinsicFQName
        }
        let isSuspendCoroutineShadowed = calleeName.map {
            isShadowedByNonSyntheticSymbol($0, locals: locals, ctx: ctx)
        } ?? false
        if isSuspendCoroutineIntrinsic,
           args.count == 1,
           !isSuspendCoroutineShadowed
        {
            let resultType = explicitTypeArgs.first ?? expectedType ?? sema.types.anyType
            let continuationType: TypeID = if let continuationSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCoroutinesFQName + [knownNames.continuation]) {
                sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(resultType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let blockExpectedType = sema.types.make(.functionType(FunctionType(
                params: [continuationType],
                returnType: sema.types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: blockExpectedType
            )
            if let chosen = sema.symbols.lookup(fqName: knownNames.kotlinCoroutinesIntrinsicsFQName + [knownNames.suspendCoroutineUninterceptedOrReturn]) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [resultType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .suspendCoroutineUninterceptedOrReturn)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- suspendCoroutine(block) ---
        // Keep this path separate from generic overload resolution so the
        // lambda parameter can be inferred from the coroutine result type.
        if let calleeName,
           calleeName == knownNames.suspendCoroutine,
           args.count == 1
        {
            let resultType = expectedType ?? explicitTypeArgs.first ?? sema.types.anyType
            let continuationType: TypeID = if let continuationSymbol = sema.symbols.lookup(fqName: knownNames.kotlinContinuationFQName) {
                sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(resultType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [continuationType],
                returnType: sema.types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            if let suspendCoroutineSymbol = sema.symbols.lookup(fqName: knownNames.kotlinSuspendCoroutineFQName) {
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: suspendCoroutineSymbol,
                    substitutedTypeArguments: [resultType],
                    parameterMapping: [0: 0]
                ))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- Flow builder function (CORO-003) ---
        // `flow { emit(...) }` is treated as a builtin cold stream factory.
        // We infer the lambda with a flow-builder scope so unqualified `emit`
        // resolves in Sema fallback.
        let flowFactoryNames: Set<InternedString> = [
            knownNames.flow,
            interner.intern("channelFlow"),
            interner.intern("callbackFlow"),
        ]
        if let calleeName,
           flowFactoryNames.contains(calleeName),
           args.count == 1,
           shouldUseBuiltinFlowFactorySpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            let flowLambdaExprID = args[0].expr
            guard isValidBuilderLambdaArgument(flowLambdaExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            var flowBuilderCtx = ctx.with(implicitReceiverType: sema.types.anyType)
            flowBuilderCtx.isFlowBuilderLambdaScope = true
            let flowLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.unitType,
                isSuspend: true,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                flowLambdaExprID,
                ctx: flowBuilderCtx,
                locals: &locals,
                expectedType: flowLambdaExpectedType
            )
            sema.bindings.markFlowExpr(id)
            if let explicitElementType = explicitTypeArgs.first {
                sema.bindings.bindFlowElementType(explicitElementType, forExpr: id)
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    sema.bindings.bindFlowElementType(type, forExpr: id)
                case .star:
                    break
                }
            }
            let flowElementType = sema.bindings.flowElementType(forExpr: id) ?? sema.types.anyType
            let flowExprType = driver.helpers.makeFlowType(
                elementType: flowElementType, sema: sema, interner: interner
            ) ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: flowExprType)
            return flowExprType
        }

        let fixedFlowFactoryNames: Set<InternedString> = [
            interner.intern("flowOf"),
            interner.intern("emptyFlow"),
        ]
        if let calleeName,
           fixedFlowFactoryNames.contains(calleeName),
           shouldUseBuiltinFlowFactorySpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            sema.bindings.markFlowExpr(id)
            if let explicitElementType = explicitTypeArgs.first {
                sema.bindings.bindFlowElementType(explicitElementType, forExpr: id)
            } else if calleeName == interner.intern("flowOf"), !args.isEmpty {
                let inferredArgTypes = args.map { driver.inferExpr($0.expr, ctx: ctx, locals: &locals) }
                let lub = sema.types.lub(inferredArgTypes)
                sema.bindings.bindFlowElementType(lub == sema.types.errorType ? sema.types.anyType : lub, forExpr: id)
            }
            let flowElementType = sema.bindings.flowElementType(forExpr: id) ?? sema.types.anyType
            let flowExprType = driver.helpers.makeFlowType(
                elementType: flowElementType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: flowExprType)
            return flowExprType
        }

        // --- Flow builder lambda calls (CORO-003) ---
        // Inside `flow { ... }`, unqualified `emit` resolves as a builtin
        // effect call and returns Unit.
        if ctx.isFlowBuilderLambdaScope,
           let calleeName,
           calleeName == knownNames.emit,
           args.count == 1,
           ctx.cachedScopeLookup(calleeName).isEmpty,
           locals[calleeName] == nil
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        if let calleeName,
           calleeName == knownNames.regexCtor,
           args.count == 1
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
            let regexType: TypeID = if let regexSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("text"),
                interner.intern("Regex"),
            ]) {
                sema.types.make(.classType(ClassType(
                    classSymbol: regexSymbol,
                    args: [],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            sema.bindings.bindExprType(id, type: regexType)
            return regexType
        }

        if let calleeName,
           interner.resolve(calleeName) == "generateSequence",
           args.count == 2
        {
            let rawSeedType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
            let seedType: TypeID = if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(rawSeedType)),
                                      functionType.params.isEmpty
            {
                sema.types.makeNonNullable(functionType.returnType)
            } else {
                rawSeedType
            }
            let nextExpectedType = sema.types.make(.functionType(FunctionType(
                params: [seedType],
                returnType: sema.types.makeNullable(seedType),
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: nextExpectedType)
            sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            sema.bindings.markCollectionExpr(id)
            let sequenceType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: seedType
            )
            sema.bindings.bindExprType(id, type: sequenceType)
            return sequenceType
        }

        // STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction: () -> T?)
        if let calleeName,
           interner.resolve(calleeName) == "generateSequence",
           args.count == 1
        {
            // Infer the no-arg function type; deduce element type T from its return type.
            let rawNextType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
            let elementType: TypeID = if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(rawNextType)) {
                sema.types.makeNonNullable(functionType.returnType)
            } else {
                sema.types.anyType
            }
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            sema.bindings.markCollectionExpr(id)
            let sequenceType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: elementType
            )
            sema.bindings.bindExprType(id, type: sequenceType)
            return sequenceType
        }

        // --- Stdlib repeat(times) { ... } (STDLIB-008) ---
        // Infer the lambda argument with the expected `(Int) -> Unit` type so
        // implicit `it` resolves to the loop index.
        if let calleeName,
           interner.resolve(calleeName) == "repeat",
           args.count == 2,
           shouldUseRepeatSpecialHandling(calleeName: calleeName, locals: locals)
        {
            let intType = sema.types.intType
            let unitType = sema.types.unitType
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let actionExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: unitType
            )))
            _ = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: actionExpectedType
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .repeatLoop)
            sema.bindings.bindExprType(id, type: unitType)
            return unitType
        }

        // --- Stdlib measureTimeMillis { ... } (STDLIB-131) ---
        if let calleeName,
           interner.resolve(calleeName) == "measureTimeMillis",
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let longType = sema.types.longType
            // Intentionally passing expectedType:nil — the block's return type is
            // not constrained here because KIR lowering discards the lambda result.
            // The synthetic stub already declares the parameter as () -> Unit,
            // which is enforced during overload resolution.
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureTimeMillis)
            sema.bindings.bindExprType(id, type: longType)
            return longType
        }

        // --- Stdlib measureNanoTime { ... } (STDLIB-550) ---
        if let calleeName,
           interner.resolve(calleeName) == "measureNanoTime",
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let longType = sema.types.longType
            // Intentionally passing expectedType:nil — same rationale as
            // measureTimeMillis above: KIR lowering discards the lambda result
            // and the synthetic stub enforces the () -> Unit contract.
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureNanoTime)
            sema.bindings.bindExprType(id, type: longType)
            return longType
        }

        // --- Stdlib kotlin.time.measureTime { ... } (STDLIB-585) ---
        // Verify both the name and that the resolved symbol is the synthetic
        // kotlin.time.measureTime (not a user-defined function with the same name).
        if let calleeName,
           interner.resolve(calleeName) == "measureTime",
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "time", "measureTime"], ctx: ctx)
        {
            // Infer the block argument with an expected function type () -> Unit
            // so non-callable arguments are caught during type checking.
            let blockType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: blockType
            )
            // Look up the synthetic Duration class to build the return type.
            let durationFQName = [interner.intern("kotlin"), interner.intern("time"), interner.intern("Duration")]
            let durationType: TypeID
            if let durationSymbol = sema.symbols.lookup(fqName: durationFQName) {
                durationType = sema.types.make(.classType(ClassType(
                    classSymbol: durationSymbol, args: [], nullability: .nonNull
                )))
            } else {
                durationType = sema.types.anyType
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureTime)
            sema.bindings.bindExprType(id, type: durationType)
            return durationType
        }

        // --- Stdlib kotlin.time.measureTimedValue { ... } (STDLIB-660) ---
        if let calleeName,
           calleeName == interner.intern("measureTimedValue"),
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "time", "measureTimedValue"], ctx: ctx)
        {
            // Infer the block argument with an expected function type () -> T
            // so non-callable arguments are caught during type checking.
            let blockType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: blockType
            )

            // Look up the TimedValue class to build the return type.
            let timedValueFQName = [interner.intern("kotlin"), interner.intern("time"), interner.intern("TimedValue")]
            let timedValueType: TypeID
            if let timedValueSymbol = sema.symbols.lookup(fqName: timedValueFQName) {
                timedValueType = sema.types.make(.classType(ClassType(
                    classSymbol: timedValueSymbol, args: [], nullability: .nonNull
                )))
            } else {
                timedValueType = sema.types.anyType
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureTimedValue)
            sema.bindings.bindExprType(id, type: timedValueType)
            return timedValueType
        }

        // --- Stdlib Array(size) { init } constructor (STDLIB-085/086, TYPE-103) ---
        if let calleeName,
           knownNames.isPrimitiveArrayConstructorTypeName(calleeName),
           args.count == 2 || (args.count == 1 && calleeName != knownNames.array),
           locals[calleeName] == nil
        {
            let intType = sema.types.intType
            let calleeNameStr = interner.resolve(calleeName)
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            if args.count == 1 {
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .arrayConstructor)
                sema.bindings.markCollectionExpr(id)
                let resultType: TypeID = if calleeNameStr == "Array" {
                    makeSyntheticArrayType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArgs.first ?? expectedType ?? sema.types.anyType
                    )
                } else {
                    makeSyntheticPrimitiveArrayType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        arrayName: calleeNameStr
                    )
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            // Determine the element type from the expected type annotation or
            // the init lambda's return type, avoiding erasure to Any.
            //
            // Only extract the generic argument from the expected type when:
            //   1. The callee is "Array" (not a primitive array like IntArray), AND
            //   2. The expected type is actually kotlin.Array<...> (not some unrelated
            //      generic type like List<String>).
            // Primitive arrays (IntArray, LongArray, etc.) have fixed element types
            // that must not be overridden by contextual expected types.
            let arrayFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("Array"),
            ]
            let kotlinArraySymbol = sema.symbols.lookup(fqName: arrayFQName)
            let isKotlinArray = calleeNameStr == "Array"
            let inferLambdaOnce: Bool
            let elementReturnType: TypeID
            if isKotlinArray,
               let explicitTypeArg = explicitTypeArgs.first
            {
                elementReturnType = explicitTypeArg
                inferLambdaOnce = true
            } else if isKotlinArray,
               let kotlinArraySymbol,
               let expectedType, expectedType != sema.types.errorType,
               case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
               expectedClassType.classSymbol == kotlinArraySymbol,
               let firstArg = expectedClassType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    elementReturnType = type
                case .star:
                    elementReturnType = sema.types.anyType
                }
                inferLambdaOnce = true
            } else if isKotlinArray {
                // No expected type and no explicit type argument for Array(size) { init }.
                // Infer the lambda with `it` constrained to Int, then extract the
                // actual body return type from bindings to avoid erasing to Any.
                let lambdaExpected = sema.types.make(.functionType(FunctionType(
                    params: [intType],
                    returnType: sema.types.makeNullable(sema.types.anyType)
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: lambdaExpected
                )
                // Read back the lambda body's actual inferred type.
                let bodyType: TypeID? = if case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(args[1].expr) {
                    sema.bindings.exprTypes[body]
                } else {
                    nil
                }
                let inferred = bodyType ?? sema.types.anyType
                elementReturnType = (inferred != sema.types.errorType) ? inferred : sema.types.anyType
                inferLambdaOnce = false
            } else {
                // For primitive array constructors, the element type is fixed.
                elementReturnType = switch calleeNameStr {
                case "IntArray": sema.types.intType
                case "LongArray": sema.types.longType
                case "ShortArray": sema.types.intType
                case "ByteArray": sema.types.intType
                case "UShortArray": sema.types.ushortType
                case "UByteArray": sema.types.ubyteType
                case "UIntArray": sema.types.uintType
                case "DoubleArray": sema.types.make(.primitive(.double, .nonNull))
                case "FloatArray": sema.types.make(.primitive(.float, .nonNull))
                case "BooleanArray": sema.types.booleanType
                case "CharArray": sema.types.make(.primitive(.char, .nonNull))
                default: sema.types.anyType
                }
                inferLambdaOnce = false
            }
            let initExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: elementReturnType
            )))
            if !inferLambdaOnce {
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: initExpectedType
                )
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .arrayConstructor)
            sema.bindings.markCollectionExpr(id)
            let resultType: TypeID
            if calleeNameStr == "Array" {
                resultType = makeSyntheticArrayType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: elementReturnType
                )
            } else {
                resultType = makeSyntheticPrimitiveArrayType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    arrayName: calleeNameStr
                )
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- STDLIB-REFLECT-066: typeOf<T>() — inline reified reflection ---
        if let calleeName,
           args.isEmpty,
           interner.resolve(calleeName) == "typeOf",
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            // Resolve the KType return type from the stub.
            let candidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
            if let stubSymbol = candidates.first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                return signature.reifiedTypeParameterIndices.contains(0)
            }), let signature = sema.symbols.functionSignature(for: stubSymbol) {
                let typeArg = explicitTypeArgs.first ?? sema.types.anyType
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: [typeArg],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .typeOf)
                sema.bindings.bindExprType(id, type: signature.returnType)
                return signature.returnType
            }
        }

        // --- STDLIB-CORO-INTRINSICS-001: suspendCoroutineUninterceptedOrReturn ---
        if let calleeName,
           args.count == 1,
           calleeName == knownNames.suspendCoroutineUninterceptedOrReturn,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(
               calleeName,
               fqComponents: ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"],
               ctx: ctx
           )
        {
            let resultType: TypeID = explicitTypeArgs.first ?? expectedType ?? sema.types.anyType
            let continuationType: TypeID = if let continuationSymbol = sema.symbols.lookup(
                fqName: knownNames.kotlinCoroutinesContinuationFQName
            ) {
                sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(resultType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let blockExpectedType = sema.types.make(.functionType(FunctionType(
                params: [continuationType],
                returnType: sema.types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: blockExpectedType
            )

            if let intrinsicSymbol = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.first(where: { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else {
                    return false
                }
                return symbol.flags.contains(.synthetic)
                    && symbol.fqName == knownNames.kotlinCoroutinesSuspendCoroutineUninterceptedOrReturnFQName
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: intrinsicSymbol,
                        substitutedTypeArguments: [resultType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(intrinsicSymbol))
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .suspendCoroutineUninterceptedOrReturn)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- Stdlib enumValues<T>() / enumValueOf<T>(name) (STDLIB-171) ---
        if let calleeName,
           let enumSpecialKind = enumStdlibSpecialCallKind(
               calleeName: calleeName,
               args: args,
               explicitTypeArgs: explicitTypeArgs,
               ctx: ctx,
               locals: locals,
               interner: interner,
               sema: sema,
               range: range
           )
        {
            switch enumSpecialKind {
            case let .enumValues(_, arrayType, stubSymbol):
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValues)
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: arrayType)
                return arrayType
            case let .enumValueOf(enumType, stubSymbol):
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValueOf)
                sema.bindings.bindExprType(id, type: enumType)
                return enumType
            case let .enumEntries(enumType, entriesType, stubSymbol):
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: [enumType],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumEntries)
                sema.bindings.bindExprType(id, type: entriesType)
                return entriesType
            }
        }

        if let calleeName,
           (args.count == 2 || args.count == 3)
        {
            // Infer the first argument without an expected type to determine the overload.
            let firstArgType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )

            // Resolve which numeric type this overload targets.
            let supportedNumericTypes = [sema.types.longType, sema.types.doubleType, sema.types.floatType, sema.types.intType]
            if let resolvedParamType = supportedNumericTypes.first(where: { firstArgType == $0 }) {
                var shouldUsePrimitiveComparisonFastPath = true
                if args.count == 3 {
                    var tentativeLocals = locals
                    let secondArgType = driver.inferExpr(
                        args[1].expr,
                        ctx: ctx,
                        locals: &tentativeLocals,
                        expectedType: nil
                    )
                    let thirdArgType = driver.inferExpr(
                        args[2].expr,
                        ctx: ctx,
                        locals: &tentativeLocals,
                        expectedType: nil
                    )
                    shouldUsePrimitiveComparisonFastPath = secondArgType == resolvedParamType && thirdArgType == resolvedParamType
                }

                if shouldUsePrimitiveComparisonFastPath,
                   let specialKind = comparisonSpecialCallKind(
                    for: calleeName,
                    argCount: args.count,
                    resolvedParamType: resolvedParamType,
                    ctx: ctx,
                    locals: locals
                ) {
                    let expectedType = resolvedParamType

                    // Emit subtype constraint for the first argument.
                    driver.emitSubtypeConstraint(
                        left: firstArgType,
                        right: expectedType,
                        range: ast.arena.exprRange(args[0].expr) ?? range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics
                    )

                    // Infer remaining arguments with the resolved type.
                    for i in 1 ..< args.count {
                        let argType = driver.inferExpr(
                            args[i].expr,
                            ctx: ctx,
                            locals: &locals,
                            expectedType: expectedType
                        )
                        driver.emitSubtypeConstraint(
                            left: argType,
                            right: expectedType,
                            range: ast.arena.exprRange(args[i].expr) ?? range,
                            solver: ConstraintSolver(),
                            sema: sema,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                    }

                    let paramTypes = Array(repeating: expectedType, count: args.count)
                    let chosen = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.first(where: { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate) else {
                            return false
                        }
                        return signature.parameterTypes == paramTypes
                    })
                    if let chosen,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
                        var paramMapping: [Int: Int] = [:]
                        for i in 0 ..< args.count {
                            paramMapping[i] = i
                        }
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [],
                                parameterMapping: paramMapping
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
                        sema.bindings.bindExprType(id, type: signature.returnType)
                        return signature.returnType
                    }
                    sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
                    sema.bindings.bindExprType(id, type: expectedType)
                    return expectedType
                }
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "contract",
           args.count == 1
        {
            let builderSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("contracts"),
                interner.intern("ContractBuilder"),
            ])
            let builderType = builderSymbol.map {
                sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
            } ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: builderType,
                params: [],
                returnType: sema.types.unitType
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx.with(implicitReceiverType: builderType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // --- kotlin.DeepRecursiveFunction<T, R> { ... } ---
        // Infer the block with a DeepRecursiveScope<T, R> implicit receiver so
        // unqualified callRecursive(...) resolves inside the lambda body.
        if let calleeName,
           interner.resolve(calleeName) == "DeepRecursiveFunction",
           args.count == 1
        {
            let functionFQName = [interner.intern("kotlin"), interner.intern("DeepRecursiveFunction")]
            let scopeFQName = [interner.intern("kotlin"), interner.intern("DeepRecursiveScope")]
            let inferredTypeArgs: [TypeID]?
            if explicitTypeArgs.count == 2 {
                inferredTypeArgs = explicitTypeArgs
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
                      sema.symbols.symbol(classType.classSymbol)?.fqName == functionFQName,
                      classType.args.count == 2
            {
                let unpacked = classType.args.compactMap { arg -> TypeID? in
                    switch arg {
                    case let .invariant(type), let .in(type), let .out(type):
                        type
                    case .star:
                        nil
                    }
                }
                inferredTypeArgs = unpacked.count == 2 ? unpacked : nil
            } else {
                inferredTypeArgs = nil
            }

            let functionSymbol = sema.symbols.lookup(fqName: functionFQName)
            let scopeSymbol = sema.symbols.lookup(fqName: scopeFQName)
            let ctorSymbol = sema.symbols.lookup(fqName: functionFQName + [interner.intern("<init>")])

            if let typeArgs = inferredTypeArgs,
               let functionSymbol,
               let scopeSymbol,
               let ctorSymbol
            {
                let argumentExprID = args[0].expr
                // DeepRecursiveFunction's block has signature DeepRecursiveScope<T,R>.(T) -> R,
                // so the lambda may declare 0 params (implicit `it`) or 1 explicit param.
                guard isValidLambdaArgument(argumentExprID, ast: ast, maxParams: 1) else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }

                let scopeType = sema.types.make(.classType(ClassType(
                    classSymbol: scopeSymbol,
                    args: [.invariant(typeArgs[0]), .invariant(typeArgs[1])],
                    nullability: .nonNull
                )))
                let resultType = sema.types.make(.classType(ClassType(
                    classSymbol: functionSymbol,
                    args: [.invariant(typeArgs[0]), .invariant(typeArgs[1])],
                    nullability: .nonNull
                )))
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    receiver: scopeType,
                    params: [typeArgs[0]],
                    returnType: typeArgs[1],
                    nullability: .nonNull
                )))
                _ = driver.inferExpr(
                    argumentExprID,
                    ctx: ctx.with(implicitReceiverType: scopeType),
                    locals: &locals,
                    expectedType: lambdaExpectedType
                )
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: ctorSymbol,
                        substitutedTypeArguments: typeArgs,
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(ctorSymbol))
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        // --- compareBy(selector1, selector2, ...) multi-selector overloads (STDLIB-613) ---
        if let calleeName,
           args.count == 2 || args.count == 3,
           interner.resolve(calleeName) == "compareBy",
           args.allSatisfy({ isLambdaOrCallableRefArg($0.expr, ast: ast) }),
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
                explicitT
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                params: [elementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            for arg in args {
                sema.bindings.markCollectionHOFLambdaExpr(arg.expr)
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
            }
            let resultType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
            let funcFQName = comparisonsPkg + [calleeName]
            let expectedExternalLink = args.count == 2
                ? "kk_comparator_from_multi_selectors"
                : "kk_comparator_from_multi_selectors3"
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                return sig.parameterTypes.count == args.count &&
                    sema.symbols.externalLinkName(for: candidate) == expectedExternalLink
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType],
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- compareBy/compareByDescending(comparator, selector) (STDLIB-COMP-004/005) ---
        if let calleeName,
           args.count == 2,
           ["compareBy", "compareByDescending"].contains(interner.resolve(calleeName)),
           !isLambdaOrCallableRefArg(args[0].expr, ast: ast),
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let calleeNameStr = interner.resolve(calleeName)
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
                explicitT
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let keyType: TypeID = if explicitTypeArgs.count >= 2 {
                explicitTypeArgs[1]
            } else {
                sema.types.anyType
            }
            let keyComparatorType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(keyType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: keyComparatorType)

            let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                params: [elementType],
                returnType: keyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), case .lambdaLiteral = lambdaExpr {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

            let resultType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
            let funcFQName = comparisonsPkg + [calleeName]
            let expectedExternalLink = calleeNameStr == "compareBy"
                ? "kk_comparator_from_comparator_selector"
                : "kk_comparator_from_comparator_selector_descending"
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                return sig.parameterTypes.count == 2 &&
                    sema.symbols.externalLinkName(for: candidate) == expectedExternalLink
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType, keyType],
                        parameterMapping: [0: 0, 1: 1]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- compareBy(vararg selectors) (STDLIB-COMP-006) ---
        if let calleeName,
           args.count >= 4,
           interner.resolve(calleeName) == "compareBy",
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
                explicitT
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                params: [elementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            for arg in args {
                if let lambdaExpr = ast.arena.expr(arg.expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(arg.expr)
                }
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
            }

            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            let resultType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }

            let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
            let funcFQName = comparisonsPkg + [calleeName]
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_comparator_from_multi_selectors_vararg"
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- Comparator factory functions: compareBy, compareByDescending (STDLIB-649) ---
        if let calleeName,
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let calleeNameStr = interner.resolve(calleeName)
            if calleeNameStr == "compareBy" || calleeNameStr == "compareByDescending" {
                // Resolve the Comparator<T> return type.
                // The lambda selector has signature (T) -> Comparable<*>.
                // T is inferred from explicit type args, calling context, or defaults to Any.
                let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
                    explicitT
                } else if let expectedType,
                    case let .classType(classType) = sema.types.kind(of: expectedType),
                    let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [elementType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
                let resultType: TypeID = if let comparatorSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }

                // Bind to the synthetic function symbol
                let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
                let funcFQName = comparisonsPkg + [calleeName]
                let primitiveCalleeName = calleeNameStr == "compareBy"
                    ? interner.intern("compareByPrimitive")
                    : interner.intern("compareByDescendingPrimitive")
                let primitiveFQName = comparisonsPkg + [primitiveCalleeName]
                let primitiveCompareKind: Bool = {
                    switch sema.types.kind(of: sema.types.makeNonNullable(elementType)) {
                    case .primitive(.int, _), .primitive(.ubyte, _), .primitive(.ushort, _),
                         .primitive(.long, _), .primitive(.uint, _), .primitive(.ulong, _),
                         .primitive(.boolean, _), .primitive(.char, _),
                         .primitive(.float, _), .primitive(.double, _):
                        return true
                    default:
                        return false
                    }
                }()
                if let chosen = (primitiveCompareKind
                    ? sema.symbols.lookupAll(fqName: primitiveFQName).first(where: { candidate in
                        guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                        return sig.parameterTypes.count == 1
                    })
                    : nil)
                    ?? sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                    return sig.parameterTypes.count == 1
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        // --- Comparator factory functions: naturalOrder, reverseOrder (STDLIB-649) ---
        if let calleeName,
           args.isEmpty,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let calleeNameStr = interner.resolve(calleeName)
            if calleeNameStr == "naturalOrder" || calleeNameStr == "reverseOrder" {
                let elementType: TypeID = if let explicitTypeArg = explicitTypeArgs.first {
                    explicitTypeArg
                } else if let expectedType,
                    case let .classType(classType) = sema.types.kind(of: expectedType),
                    let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }

                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
                let resultType: TypeID = if let comparatorSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }

                let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
                let funcFQName = comparisonsPkg + [calleeName]
                if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                    return sig.parameterTypes.isEmpty
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: [:]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        if let calleeName,
           calleeName == knownNames.channel,
           args.isEmpty
        {
            let visibleCandidates = ctx.cachedScopeLookup(calleeName)
            let channelSymbol = visibleCandidates.first { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function
                else {
                    return false
                }
                return sema.symbols.externalLinkName(for: candidate) == "kk_channel_create"
            } ?? visibleCandidates.compactMap { candidate -> SymbolID? in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .class,
                      sema.symbols.externalLinkName(for: candidate) == nil
                else {
                    return nil
                }
                let ctorFQName = symbol.fqName + [interner.intern("<init>")]
                return sema.symbols.lookupAll(fqName: ctorFQName).first { ctorID in
                    sema.symbols.externalLinkName(for: ctorID) == "kk_channel_create"
                }
            }.first
            if let channelSymbol {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: channelSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(channelSymbol))
                let resultType: TypeID = if let explicitTypeArg = explicitTypeArgs.first,
                                            let signature = sema.symbols.functionSignature(for: channelSymbol),
                                            case let .classType(classType) = sema.types.kind(of: signature.returnType)
                {
                    sema.types.make(.classType(ClassType(
                        classSymbol: classType.classSymbol,
                        args: [.invariant(explicitTypeArg)],
                        nullability: classType.nullability
                    )))
                } else {
                    sema.symbols.functionSignature(for: channelSymbol)?.returnType ?? sema.types.anyType
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "delay",
           args.count == 1
        {
            let delayArgType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.longType
            )
            if delayArgType == sema.types.intType,
               let argumentExpr = ast.arena.expr(args[0].expr),
               case .intLiteral = argumentExpr
            {
                sema.bindings.bindExprType(args[0].expr, type: sema.types.longType)
            } else {
                driver.emitSubtypeConstraint(
                    left: delayArgType,
                    right: sema.types.longType,
                    range: ast.arena.exprRange(args[0].expr) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        let coroutineLauncherName = calleeName.map { interner.resolve($0) }
        let coroutineLauncherExpectedLambdaType: TypeID?
        // STDLIB-CORO-072: Support launch(dispatcher) { } by checking both first and
        // second argument for a trailing lambda. When the first argument is a dispatcher
        // (non-lambda) and the second is a lambda, treat it as the block argument.
        let coroutineLauncherLambdaArgIndex: Int? = {
            guard let name = coroutineLauncherName,
                  ["runBlocking", "launch", "async", "coroutineScope"].contains(name)
            else { return nil }
            if let firstArgExpr = args.first.flatMap({ ast.arena.expr($0.expr) }),
               case .lambdaLiteral = firstArgExpr {
                return 0
            }
            if args.count >= 2,
               let secondArgExpr = ast.arena.expr(args[1].expr),
               case .lambdaLiteral = secondArgExpr {
                return 1
            }
            return nil
        }()
        if let coroutineLauncherName,
           let lambdaIndex = coroutineLauncherLambdaArgIndex,
           lambdaIndex < args.count
        {
            let lambdaReturnType: TypeID = switch coroutineLauncherName {
            case "launch":
                sema.types.unitType
            default:
                expectedType ?? sema.types.anyType
            }
            coroutineLauncherExpectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: lambdaReturnType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            coroutineLauncherExpectedLambdaType = nil
        }
        let withContextExpectedLambdaType: TypeID? = if let calleeName,
                                                        (calleeName == knownNames.withContext
                                                            || calleeName == knownNames.withTimeout
                                                            || calleeName == knownNames.withTimeoutOrNull),
                                                        args.count >= 2,
                                                        let secondArgExpr = ast.arena.expr(args[1].expr),
                                                        case .lambdaLiteral = secondArgExpr
        {
            sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: expectedType ?? sema.types.anyType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            nil
        }

        if let calleeName,
           let samCallType = inferSamConvertedCallExpr(
               id,
               calleeName: calleeName,
               args: args,
               range: range,
               ctx: ctx,
               locals: &locals,
               expectedType: expectedType,
               explicitTypeArgs: explicitTypeArgs
           )
        {
            sema.bindings.bindExprType(id, type: samCallType)
            return samCallType
        }

        var candidates: [SymbolID]
        var callInvisible: [SemanticSymbol] = []
        if let calleeName {
            let allCallCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            // @DslMarker restriction: filter out candidates that belong to an
            // outer receiver class that shares a DslMarker annotation with the
            // current implicit receiver.
            let dslBlockedCandidates = allCallCandidates.filter { ctx.isCandidateBlockedByDslMarker($0) }
            let dslFiltered = allCallCandidates.filter { !ctx.isCandidateBlockedByDslMarker($0) }
            let (vis, invis) = ctx.filterByVisibility(dslFiltered)
            candidates = vis
            callInvisible = invis
            // If all candidates were blocked by DslMarker, emit a specific diagnostic.
            if candidates.isEmpty, !dslBlockedCandidates.isEmpty {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-DSLMARKER",
                    "'@DslMarker' implicit access to '\(interner.resolve(calleeName))' from outer receiver is restricted. Use explicit receiver.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if candidates.isEmpty, let local = locals[calleeName] {
                if let sym = ctx.cachedSymbol(local.symbol), sym.kind == .function {
                    candidates = [local.symbol]
                }
            }
            if candidates.isEmpty {
                let classSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .class || symbol.kind == .enumClass || symbol.kind == .annotationClass || symbol.kind == .object
                }
                if let classSym = classSymbols.first, let classSymbol = ctx.cachedSymbol(classSym) {
                    // P5-112: Prohibit direct instantiation of abstract classes.
                    if classSymbol.flags.contains(.abstractType) {
                        let className = classSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-ABSTRACT",
                            "Cannot create an instance of abstract class '\(className)'.",
                            range: range
                        )
                        sema.bindings.bindExprType(id, type: sema.types.errorType)
                        return sema.types.errorType
                    }
                    let initName = interner.intern("<init>")
                    let ctorFQName = classSymbol.fqName + [initName]
                    let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                    if !ctorSymbols.isEmpty {
                        let (vis, invis) = ctx.filterByVisibility(ctorSymbols)
                        candidates = vis
                        callInvisible.append(contentsOf: invis)
                    }
                }
            }
            if candidates.isEmpty,
               calleeName == knownNames.suspendCoroutine,
               let suspendCoroutineSymbol = sema.symbols.lookup(fqName: knownNames.kotlinSuspendCoroutineFQName) {
                candidates = [suspendCoroutineSymbol]
            }
            // --- Typealias constructor calls ---
            // If the callee is a typealias (e.g. `typealias IntPair = Pair<Int, Int>`),
            // expand it to the underlying class and resolve its constructor.
            if candidates.isEmpty {
                let aliasSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .typeAlias
                }
                if let aliasSym = aliasSymbols.first {
                    let aliasTypeParameters = sema.symbols.typeAliasTypeParameters(for: aliasSym)
                    let aliasTypeArgs: [TypeArg] = if !explicitTypeArgs.isEmpty {
                        explicitTypeArgs.map { TypeArg.invariant($0) }
                    } else if !aliasTypeParameters.isEmpty,
                              let expectedType,
                              case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
                    {
                        Array(expectedClassType.args.prefix(aliasTypeParameters.count))
                    } else if !aliasTypeParameters.isEmpty {
                        Array(repeating: TypeArg.invariant(sema.types.anyType), count: aliasTypeParameters.count)
                    } else {
                        []
                    }
                    if let expanded = driver.helpers.expandTypeAlias(
                        aliasSym,
                        typeArgs: aliasTypeArgs,
                        sema: sema,
                        visited: [],
                        depth: 0,
                        diagnostics: ctx.semaCtx.diagnostics
                    ),
                       case let .classType(classType) = sema.types.kind(of: expanded),
                       let underlyingSymbol = ctx.cachedSymbol(classType.classSymbol)
                    {
                        let initName = interner.intern("<init>")
                        let ctorFQName = underlyingSymbol.fqName + [initName]
                        let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                        if !ctorSymbols.isEmpty {
                            let (vis, invis) = ctx.filterByVisibility(ctorSymbols)
                            candidates = vis
                            callInvisible.append(contentsOf: invis)
                        }
                    }
                }
            }
        } else {
            candidates = []
        }

        if let calleeName,
           interner.resolve(calleeName) == "callRecursive",
           args.count == 1,
           let receiverType = ctx.implicitReceiverType,
           case let .classType(scopeClass) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
           let scopeSymbol = sema.symbols.symbol(scopeClass.classSymbol),
           scopeSymbol.fqName.count == 2,
           interner.resolve(scopeSymbol.fqName[0]) == "kotlin",
           interner.resolve(scopeSymbol.fqName[1]) == "DeepRecursiveScope",
           scopeClass.args.count == 2
        {
            let inputType: TypeID?
            let returnType: TypeID?
            switch (scopeClass.args[0], scopeClass.args[1]) {
            case let (.invariant(input), .invariant(output)):
                inputType = input
                returnType = output
            case let (.out(input), .out(output)):
                inputType = input
                returnType = output
            case let (.out(input), .invariant(output)):
                inputType = input
                returnType = output
            case let (.invariant(input), .out(output)):
                inputType = input
                returnType = output
            default:
                inputType = nil
                returnType = nil
            }
            if let inputType, let returnType {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: inputType)
                let fqName = [interner.intern("kotlin"), interner.intern("DeepRecursiveScope"), interner.intern("callRecursive")]
                if let chosen = sema.symbols.lookupAll(fqName: fqName).first(where: { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.typeParameterSymbols.count == signature.classTypeParameterCount
                        && sema.symbols.externalLinkName(for: symbolID) == "kk_deep_recursive_scope_callRecursive"
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [inputType, returnType],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
            }
        }

        var expectedTypeOverrides: [Int: TypeID] = [:]
        if let launcherIndex = coroutineLauncherLambdaArgIndex,
           let coroutineLauncherExpectedLambdaType
        {
            expectedTypeOverrides[launcherIndex] = coroutineLauncherExpectedLambdaType
        }
        if let withContextExpectedLambdaType, args.count > 1 {
            expectedTypeOverrides[1] = withContextExpectedLambdaType
        }
        let preparedArgs = prepareCallArguments(
            args: args,
            candidates: candidates,
            expectedTypeOverrides: expectedTypeOverrides,
            explicitTypeArgs: explicitTypeArgs,
            ctx: ctx,
            locals: &locals
        )
        let argTypes = preparedArgs.argTypes
        if !candidates.isEmpty {
            let resolved = resolveCallRespectingLambdaReturnType(
                candidates: candidates,
                args: args,
                argTypes: argTypes,
                range: range,
                calleeName: calleeName ?? InternedString(),
                explicitTypeArgs: explicitTypeArgs,
                expectedType: expectedType,
                implicitReceiverType: ctx.implicitReceiverType,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                ctx: ctx
            )
            if let diagnostic = resolved.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0023",
                    "Unresolved function '\(nameStr)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            // ANNO-001: Check for @Deprecated annotation on the resolved callee.
            driver.helpers.checkDeprecation(
                for: chosen,
                sema: sema,
                interner: interner,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: chosen,
                ctx: ctx,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            let adjustedReturnType: TypeID = if let externalLinkName = sema.symbols.externalLinkName(for: chosen) {
                switch externalLinkName {
                case "kk_emptyList":
                    if let expectedType, expectedType != sema.types.errorType,
                       case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                       !expectedClassType.args.isEmpty
                    {
                        expectedType
                    } else if let explicitTypeArg = explicitTypeArgs.first,
                              let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                    {
                        sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.out(explicitTypeArg)],
                            nullability: .nonNull
                        )))
                    } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                        sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.out(sema.types.nothingType)],
                            nullability: .nonNull
                        )))
                    } else {
                        returnType
                    }

                case "kk_emptySet":
                    if let expectedType, expectedType != sema.types.errorType,
                       case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                       !expectedClassType.args.isEmpty
                    {
                        expectedType
                    } else if let explicitTypeArg = explicitTypeArgs.first,
                              let setSymbol = sema.symbols.lookupByShortName(interner.intern("Set")).first
                    {
                        sema.types.make(.classType(ClassType(
                            classSymbol: setSymbol,
                            args: [.out(explicitTypeArg)],
                            nullability: .nonNull
                        )))
                    } else if let setSymbol = sema.symbols.lookupByShortName(interner.intern("Set")).first {
                        sema.types.make(.classType(ClassType(
                            classSymbol: setSymbol,
                            args: [.out(sema.types.nothingType)],
                            nullability: .nonNull
                        )))
                    } else {
                        returnType
                    }

                case "kk_emptyMap":
                    if let expectedType, expectedType != sema.types.errorType,
                       case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                       expectedClassType.args.count == 2
                    {
                        expectedType
                    } else if explicitTypeArgs.count == 2,
                              let mapSymbol = sema.symbols.lookupByShortName(interner.intern("Map")).first
                    {
                        sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(explicitTypeArgs[0]), .out(explicitTypeArgs[1])],
                            nullability: .nonNull
                        )))
                    } else if let mapSymbol = sema.symbols.lookupByShortName(interner.intern("Map")).first {
                        sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(sema.types.nothingType), .out(sema.types.nothingType)],
                            nullability: .nonNull
                        )))
                    } else {
                        returnType
                    }

                default:
                    returnType
                }
            } else {
                returnType
            }
            if args.count == 2,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               ["kk_require_lazy", "kk_check_lazy", "kk_precondition_assert_lazy"].contains(externalLinkName)
            {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            applyContractEffects(
                chosen: chosen,
                args: args,
                argTypes: argTypes,
                ctx: ctx,
                locals: &locals
            )
            if let calleeName {
                let resolvedName = interner.resolve(calleeName)
                if KnownCompilerNames.stdlibCollectionFactoryNames.contains(resolvedName) {
                    sema.bindings.markCollectionExpr(id)
                }
            }
            if let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               [
                   "kk_op_rangeTo",
                   "kk_op_rangeUntil",
                   "kk_uint_rangeTo",
                   "kk_char_rangeTo",
                   "kk_int_progression_fromClosedRange",
                   "kk_long_progression_fromClosedRange",
                   "kk_uint_progression_fromClosedRange",
                   "kk_ulong_progression_fromClosedRange",
                   "kk_op_ulong_rangeUntil",
               ].contains(externalLinkName)
            {
                markRangeCallBindings(id, chosen: chosen, returnType: adjustedReturnType, sema: sema)
            }
            sema.bindings.bindExprType(id, type: adjustedReturnType)
            return adjustedReturnType
        }

        var callableTarget: CallableTarget?
        var callableCalleeType: TypeID?
        if let calleeName,
           let local = locals[calleeName]
        {
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(calleeName))' must be initialized before use.",
                    range: range
                )
            }
            sema.bindings.bindIdentifier(calleeID, symbol: local.symbol)
            sema.bindings.bindExprType(calleeID, type: local.type)
            let localSymbolKind = ctx.cachedSymbol(local.symbol)?.kind
            if localSymbolKind != .function {
                callableTarget = .localValue(local.symbol)
                callableCalleeType = local.type
            }
        } else if let calleeName {
            if !ctx.cachedScopeLookup(calleeName).isEmpty {
                callableCalleeType = driver.inferExpr(
                    calleeID,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: nil
                )
                callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
            }
        } else if calleeName == nil {
            let contextualCalleeType: TypeID?
            if let calleeExpr {
                switch calleeExpr {
                case .lambdaLiteral, .callableRef:
                    let contextualReturnType = expectedType ?? sema.types.anyType
                    contextualCalleeType = sema.types.make(.functionType(FunctionType(
                        params: argTypes,
                        returnType: contextualReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                default:
                    contextualCalleeType = nil
                }
            } else {
                contextualCalleeType = nil
            }
            callableCalleeType = driver.inferExpr(
                calleeID,
                ctx: ctx,
                locals: &locals,
                expectedType: contextualCalleeType
            )
            callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
        }

        if callableCalleeType == sema.types.errorType {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        if let callableCalleeType,
           let result = inferCallableValueInvocation(
               id, calleeType: callableCalleeType, callableTarget: callableTarget,
               args: args, argTypes: argTypes, range: range, ctx: ctx, expectedType: expectedType
           )
        {
            return result
        }

        // Invoke operator fallback: if callee is not a function type, check if
        // its type has an `operator fun invoke(...)` member and resolve through
        // the overload resolver as a member call.
        if let callableCalleeType {
            let invokeName = interner.intern("invoke")
            let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: invokeName,
                receiverType: callableCalleeType,
                sema: sema,
                interner: interner
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            if !invokeCandidates.isEmpty {
                let resolvedArgs = zip(args, argTypes).map { argument, type in
                    CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                }
                let resolved = ctx.resolver.resolveCall(
                    candidates: invokeCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: invokeName,
                        args: resolvedArgs,
                        explicitTypeArgs: explicitTypeArgs
                    ),
                    expectedType: expectedType,
                    implicitReceiverType: callableCalleeType,
                    ctx: ctx.semaCtx
                )
                if let diagnostic = resolved.diagnostic {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                if let chosen = resolved.chosenCallee {
                    let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                    applyContractEffects(
                        chosen: chosen,
                        args: args,
                        argTypes: argTypes,
                        ctx: ctx,
                        locals: &locals
                    )
                    sema.bindings.markInvokeOperatorCall(id)
                    sema.bindings.bindExprType(id, type: returnType)
                    return returnType
                }
            }
        }

        if let builtinType = driver.helpers.kxMiniCoroutineBuiltinReturnType(
            calleeName: calleeName,
            argumentCount: args.count,
            sema: sema,
            interner: interner
        ) {
            sema.bindings.bindExprType(id, type: builtinType)
            return builtinType
        }
        if let calleeName,
           interner.resolve(calleeName) == "println",
           args.count <= 1
        {
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }
        if let calleeName,
           interner.resolve(calleeName) == "compareValuesBy",
           args.count >= 3
        {
            for index in 2..<args.count {
                sema.bindings.markCollectionHOFLambdaExpr(args[index].expr)
            }
        }
        // Builder DSL member functions (STDLIB-002).
        // Inside builder lambdas, unqualified `append`/`add`/`put` resolve as
        // implicit-receiver member calls that return Unit.
        if let calleeName, ctx.isBuilderLambdaScope, let activeBuilderKind = ctx.builderKind {
            let name = interner.resolve(calleeName)
            let isBuilderMember: Bool = switch activeBuilderKind {
            case .buildString:
                (name == "append" && args.count == 1)
                    || (name == "appendLine" && args.count <= 1)
                    || (name == "appendRange" && args.count == 3)
            case .buildList, .buildSet:
                (name == "add" && args.count == 1) || (name == "addAll" && args.count == 1)
            case .buildMap: name == "put" && args.count == 2
            }
            if isBuilderMember {
                for argument in args {
                    _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                }
                sema.bindings.markBuilderDSLExpr(id, kind: activeBuilderKind)
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
        }
        // Collection literal factory functions (P5-84).
        if let calleeName {
            let name = interner.resolve(calleeName)
            if KnownCompilerNames.stdlibCollectionFactoryNames.contains(name) {
                sema.bindings.markCollectionExpr(id)
                let expectedCollectionArgs: [TypeID] = if let expectedType,
                                                      expectedType != sema.types.errorType,
                                                      case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
                {
                    expectedClassType.args.compactMap { arg in
                        switch arg {
                        case let .invariant(type), let .in(type), let .out(type):
                            type
                        case .star:
                            sema.types.anyType
                        }
                    }
                } else {
                    []
                }
                // Prefer the expected type from context (e.g. a type annotation
                // on the receiving variable) so that `val list: List<String?> =
                // listOf(...)` propagates the full generic type.
                // Only use expectedType if it is a generic ClassType (i.e. a
                // collection type like List<String?>), not a primitive or
                // unrelated type like Int.
                let collectionType: TypeID
                if let expectedType, expectedType != sema.types.errorType,
                   case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                   !expectedClassType.args.isEmpty
                {
                    collectionType = expectedType
                } else if let explicitTypeArg = explicitTypeArgs.first,
                          calleeName == knownNames.emptyListFn
                {
                    collectionType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArg
                    )
                } else if let explicitTypeArg = explicitTypeArgs.first,
                          name == "mutableListOf"
                {
                    collectionType = makeSyntheticMutableListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArg
                    )
                } else if calleeName == knownNames.emptyListFn {
                    collectionType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.nothingType
                    )
                } else if !argTypes.isEmpty,
                          name == "sequenceOf"
                {
                    let hasNullableElement = argTypes.contains { inferredType in
                        inferredType == sema.types.nullableNothingType
                            || sema.types.makeNonNullable(inferredType) != inferredType
                    }
                    let concreteTypes = argTypes.compactMap { inferredType -> TypeID? in
                        if inferredType == sema.types.nullableNothingType {
                            return nil
                        }
                        return sema.types.makeNonNullable(inferredType)
                    }
                    let baseType = concreteTypes.isEmpty ? sema.types.anyType : sema.types.lub(concreteTypes)
                    let elementType = hasNullableElement ? sema.types.makeNullable(baseType) : baseType
                    collectionType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else if let explicitTypeArg = explicitTypeArgs.first,
                          name == "sequenceOf"
                {
                    collectionType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArg
                    )
                } else if !argTypes.isEmpty,
                          name == "listOf" || name == "listOfNotNull" || calleeName == knownNames.emptyListFn || name == "mutableListOf"
                {
                    // Infer element type from arguments via LUB so that
                    // `listOf("a", null)` produces List<String?>.
                    let elementType = sema.types.lub(argTypes)
                    collectionType = if name == "mutableListOf" {
                        makeSyntheticMutableListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    } else {
                        makeSyntheticListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    }
                } else if let explicitTypeArg = explicitTypeArgs.first,
                          calleeName == knownNames.emptySetFn || name == "setOf"
                {
                    collectionType = makeSyntheticSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArg
                    )
                } else if let explicitTypeArg = explicitTypeArgs.first,
                          name == "mutableSetOf"
                {
                    collectionType = makeSyntheticMutableSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArg
                    )
                } else if calleeName == knownNames.emptySetFn {
                    collectionType = makeSyntheticSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.nothingType
                    )
                } else if !argTypes.isEmpty,
                          name == "setOf" || calleeName == knownNames.emptySetFn || name == "mutableSetOf"
                {
                    let elementType = sema.types.lub(argTypes)
                    collectionType = if name == "mutableSetOf" {
                        makeSyntheticMutableSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    } else {
                        makeSyntheticSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    }
                } else if let expectedType, expectedType != sema.types.errorType,
                          case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                          expectedClassType.args.count == 2,
                          name == "mapOf" || name == "mutableMapOf" || calleeName == knownNames.emptyMapFn
                {
                    collectionType = expectedType
                } else if explicitTypeArgs.count == 2,
                          name == "mapOf" || calleeName == knownNames.emptyMapFn
                {
                    collectionType = makeSyntheticMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: explicitTypeArgs[0],
                        valueType: explicitTypeArgs[1]
                    )
                } else if explicitTypeArgs.count == 2,
                          name == "mutableMapOf"
                {
                    collectionType = makeSyntheticMutableMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: explicitTypeArgs[0],
                        valueType: explicitTypeArgs[1]
                    )
                } else if let inferredMapTypes = inferSyntheticMapKeyValueTypes(
                    from: args,
                    ctx: ctx,
                    locals: &locals
                ),
                    name == "mapOf" || name == "mutableMapOf"
                {
                    collectionType = if name == "mutableMapOf" {
                        makeSyntheticMutableMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: inferredMapTypes.keyType,
                            valueType: inferredMapTypes.valueType
                        )
                    } else {
                        makeSyntheticMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: inferredMapTypes.keyType,
                            valueType: inferredMapTypes.valueType
                        )
                    }
                } else if calleeName == knownNames.emptyMapFn {
                    collectionType = makeSyntheticMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: sema.types.nothingType,
                        valueType: sema.types.nothingType
                    )
                } else if name == "mapOf" || calleeName == knownNames.emptyMapFn || name == "mutableMapOf" {
                    collectionType = if name == "mutableMapOf" {
                        makeSyntheticMutableMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: sema.types.anyType,
                            valueType: sema.types.anyType
                        )
                    } else {
                        makeSyntheticMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: sema.types.anyType,
                            valueType: sema.types.anyType
                        )
                    }
                // --- Type alias constructors: ArrayList, HashSet, LinkedHashSet, HashMap, LinkedHashMap ---
                // These constructors take capacity or collection args, NOT element varargs.
                // Always produce a mutable collection; use explicit type arg or Any? element type.
                } else if name == "ArrayList" {
                    if let explicitTypeArg = explicitTypeArgs.first {
                        collectionType = makeSyntheticMutableListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: explicitTypeArg
                        )
                    } else if !expectedCollectionArgs.isEmpty {
                        collectionType = makeSyntheticMutableListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: expectedCollectionArgs[0]
                        )
                    } else {
                        collectionType = makeSyntheticMutableListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: sema.types.anyType
                        )
                    }
                } else if name == "HashSet" || name == "LinkedHashSet" {
                    if let explicitTypeArg = explicitTypeArgs.first {
                        collectionType = makeSyntheticMutableSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: explicitTypeArg
                        )
                    } else if !expectedCollectionArgs.isEmpty {
                        collectionType = makeSyntheticMutableSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: expectedCollectionArgs[0]
                        )
                    } else {
                        collectionType = makeSyntheticMutableSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: sema.types.anyType
                        )
                    }
                } else if name == "HashMap" || name == "LinkedHashMap" {
                    if explicitTypeArgs.count == 2 {
                        collectionType = makeSyntheticMutableMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: explicitTypeArgs[0],
                            valueType: explicitTypeArgs[1]
                        )
                    } else if expectedCollectionArgs.count >= 2 {
                        collectionType = makeSyntheticMutableMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: expectedCollectionArgs[0],
                            valueType: expectedCollectionArgs[1]
                        )
                    } else {
                        collectionType = makeSyntheticMutableMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: sema.types.anyType,
                            valueType: sema.types.anyType
                        )
                    }
                } else if name == "generateSequence", args.count == 2 {
                    let rawSeedType = argTypes.first ?? sema.types.anyType
                    let seedType: TypeID = if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(rawSeedType)),
                                              functionType.params.isEmpty
                    {
                        sema.types.makeNonNullable(functionType.returnType)
                    } else {
                        rawSeedType
                    }
                    let nextExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [seedType],
                        returnType: sema.types.makeNullable(seedType),
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: nextExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    collectionType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: seedType
                    )
                // STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction: () -> T?)
                } else if name == "generateSequence", args.count == 1 {
                    let rawNextType = argTypes.first ?? sema.types.anyType
                    let elementType: TypeID = if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(rawNextType)) {
                        sema.types.makeNonNullable(functionType.returnType)
                    } else {
                        sema.types.anyType
                    }
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    collectionType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                // --- arrayOf / primitive array factories (TYPE-103) ---
                } else if name == "arrayOf" {
                    if let explicitTypeArg = explicitTypeArgs.first {
                        collectionType = makeSyntheticArrayType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: explicitTypeArg
                        )
                    } else if !argTypes.isEmpty {
                        let elementType = sema.types.lub(argTypes)
                        let inferredElementType = if elementType == sema.types.errorType {
                            sema.types.anyType
                        } else {
                            elementType
                        }
                        collectionType = makeSyntheticArrayType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: inferredElementType
                        )
                    } else if let expectedType,
                              expectedType != sema.types.errorType,
                              case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                              let arraySymbol = sema.symbols.lookup(
                                fqName: [interner.intern("kotlin"), interner.intern("Array")]
                              ),
                              expectedClassType.classSymbol == arraySymbol,
                              let firstArg = expectedClassType.args.first
                    {
                        let inferred = switch firstArg {
                        case let .invariant(type), let .in(type), let .out(type):
                            type
                        case .star:
                            sema.types.anyType
                        }
                        collectionType = makeSyntheticArrayType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: inferred
                        )
                    } else {
                        // arrayOf() with no args and no explicit type
                        collectionType = makeSyntheticArrayType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: sema.types.anyType
                        )
                    }
                } else {
                    let primitiveArrayFactories: [String: String] = [
                        "intArrayOf": "IntArray",
                        "longArrayOf": "LongArray",
                        "shortArrayOf": "ShortArray",
                        "byteArrayOf": "ByteArray",
                        "ushortArrayOf": "UShortArray",
                        "ubyteArrayOf": "UByteArray",
                        "uintArrayOf": "UIntArray",
                        "ulongArrayOf": "ULongArray",
                        "doubleArrayOf": "DoubleArray",
                        "floatArrayOf": "FloatArray",
                        "booleanArrayOf": "BooleanArray",
                        "charArrayOf": "CharArray",
                    ]
                    if let primitiveArrayName = primitiveArrayFactories[name] {
                        collectionType = makeSyntheticPrimitiveArrayType(
                            symbols: sema.symbols, types: sema.types, interner: interner,
                            arrayName: primitiveArrayName
                        )
                    } else {
                        collectionType = sema.types.anyType
                    }
                }
                sema.bindings.bindExprType(id, type: collectionType)
                return collectionType
            }

            switch name {
            case "Regex":
                guard args.count == 1 else {
                    break
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
                let regexType: TypeID = if let regexSymbol = sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("Regex"),
                ]) {
                    sema.types.make(.classType(ClassType(
                        classSymbol: regexSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }
                sema.bindings.bindExprType(id, type: regexType)
                return regexType
            case "ArrayDeque":
                // ArrayDeque() — zero-arg constructor
                let elementType: TypeID
                if let explicitTypeArg = explicitTypeArgs.first {
                    elementType = explicitTypeArg
                } else if let expectedType,
                          case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                          let firstArg = expectedClassType.args.first
                {
                    switch firstArg {
                    case let .invariant(type), let .in(type), let .out(type):
                        elementType = type
                    case .star:
                        elementType = sema.types.anyType
                    }
                } else {
                    elementType = sema.types.anyType
                }
                let arrayDequeType: TypeID = if let adSymbol = sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("ArrayDeque"),
                ]) {
                    sema.types.make(.classType(ClassType(
                        classSymbol: adSymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: arrayDequeType)
                return arrayDequeType
            case "StringBuilder":
                guard args.count <= 1 else {
                    break
                }
                // Skip stdlib treatment if shadowed by a local declaration
                if locals[calleeName] != nil {
                    break
                }
                if ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
                    guard let sym = ctx.cachedSymbol(candidate) else { return false }
                    return !sym.flags.contains(.synthetic)
                }) {
                    break
                }
                if args.count == 1 {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
                }
                let sbType: TypeID = if let sbSymbol = sema.symbols.lookup(fqName: knownNames.kotlinStringBuilderFQName) {
                    sema.types.make(.classType(ClassType(
                        classSymbol: sbSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }
                sema.bindings.bindExprType(id, type: sbType)
                return sbType
            default:
                break
            }
        }
        // STDLIB-004: Inside receiver lambdas (run/apply/with), unqualified
        // function calls resolve as member calls on the implicit receiver.
        if let calleeName, let receiverType = ctx.implicitReceiverType {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            let name = interner.resolve(calleeName)
            if name == "callRecursive",
               args.count == 1,
               case let .classType(scopeClass) = sema.types.kind(of: nonNullReceiver),
               let scopeSymbol = sema.symbols.symbol(scopeClass.classSymbol),
               scopeSymbol.fqName.count == 2,
               interner.resolve(scopeSymbol.fqName[0]) == "kotlin",
               interner.resolve(scopeSymbol.fqName[1]) == "DeepRecursiveScope",
               scopeClass.args.count == 2
            {
                let inputType: TypeID?
                let returnType: TypeID?
                switch (scopeClass.args[0], scopeClass.args[1]) {
                case let (.invariant(input), .invariant(output)):
                    inputType = input
                    returnType = output
                case let (.out(input), .out(output)):
                    inputType = input
                    returnType = output
                case let (.out(input), .invariant(output)):
                    inputType = input
                    returnType = output
                case let (.invariant(input), .out(output)):
                    inputType = input
                    returnType = output
                default:
                    inputType = nil
                    returnType = nil
                }
                if let inputType, let returnType {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: inputType)
                    let fqName = [interner.intern("kotlin"), interner.intern("DeepRecursiveScope"), interner.intern("callRecursive")]
                    if let chosen = sema.symbols.lookupAll(fqName: fqName).first(where: { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.typeParameterSymbols.count == signature.classTypeParameterCount
                            && sema.symbols.externalLinkName(for: symbolID) == "kk_deep_recursive_scope_callRecursive"
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [inputType, returnType],
                                parameterMapping: [0: 0]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    sema.bindings.bindExprType(id, type: returnType)
                    return returnType
                }
            }

            // String stdlib methods (STDLIB-006) via implicit receiver
            if sema.types.isSubtype(nonNullReceiver, sema.types.stringType) {
                let listCharType = makeSyntheticListType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: sema.types.make(.primitive(.char, .nonNull))
                )
                let pairCharCharType: TypeID = {
                    let pairFQName: [InternedString] = [
                        interner.intern("kotlin"),
                        interner.intern("Pair"),
                    ]
                    guard let pairSymbol = sema.symbols.lookup(fqName: pairFQName) else {
                        return sema.types.anyType
                    }
                    let charType = sema.types.make(.primitive(.char, .nonNull))
                    return sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.out(charType), .out(charType)],
                        nullability: .nonNull
                    )))
                }()
                let listPairCharCharType = makeSyntheticListType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: pairCharCharType
                )
                let iterableCharType = makeSyntheticIterableType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: sema.types.make(.primitive(.char, .nonNull))
                )
                let charArrayType = makeSyntheticNominalType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    fqName: [interner.intern("kotlin"), interner.intern("CharArray")]
                )
                if name == "zipWithNext" {
                    let charType = sema.types.make(.primitive(.char, .nonNull))
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [charType, charType],
                        returnType: sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    let lambdaType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let lambdaReturnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? sema.types.anyType
                    }
                    let resultType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: lambdaReturnType
                    )
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
                var stringResultType: TypeID?
                if args.isEmpty {
                    stringResultType = switch name {
                    case "trim": sema.types.stringType
                    case "uppercase": sema.types.stringType
                    case "lowercase": sema.types.stringType
                    case "toInt": sema.types.intType
                    case "toIntOrNull": sema.types.make(.primitive(.int, .nullable))
                    case "toDouble": sema.types.make(.primitive(.double, .nonNull))
                    case "toDoubleOrNull": sema.types.make(.primitive(.double, .nullable))
                    case "indexOf", "lastIndexOf": sema.types.intType
                    case "reversed": sema.types.stringType
                    case "toList": listCharType
                    case "zipWithNext": listPairCharCharType
                    case "toCharArray": charArrayType
                    case "asIterable": iterableCharType
                    default: nil
                    }
                } else if args.count == 1 {
                    stringResultType = switch name {
                    case "startsWith", "endsWith", "contains":
                        sema.types.make(.primitive(.boolean, .nonNull))
                    case "split": sema.types.anyType
                    case "repeat", "drop", "take", "takeLast", "dropLast":
                        sema.types.stringType
                    default: nil
                    }
                } else if args.count == 2, name == "replace" {
                    stringResultType = sema.types.stringType
                }
                if let resultType = stringResultType {
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
            }
            if sema.types.isSubtype(nonNullReceiver, sema.types.charType),
               args.isEmpty,
               let member = syntheticCharMemberSpec(named: name)
            {
                let resultType = member.returnKind.typeID(in: sema.types)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }

            // Boolean.not() / Boolean.and(other) / Boolean.or(other) / Boolean.xor(other) (STDLIB-308)
            if sema.types.isSubtype(nonNullReceiver, sema.types.booleanType) {
                let resultType = sema.types.booleanType
                let finalType = receiverType == nonNullReceiver
                    ? resultType
                    : sema.types.makeNullable(resultType)
                switch name {
                case "not" where args.isEmpty:
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                case "and" where args.count == 1,
                     "or" where args.count == 1,
                     "xor" where args.count == 1:
                    for arg in args {
                        _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
                    }
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                default:
                    break
                }
            }

            // General member function lookup via implicit receiver
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: nonNullReceiver,
                sema: sema,
                interner: interner
            )
            if !memberCandidates.isEmpty {
                // Eagerly infer argument types for overload resolution.
                let memberArgTypes = args.map { argument in
                    driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                }
                let resolvedArgs = zip(args, memberArgTypes).map { argument, type in
                    CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                }
                let resolved = ctx.resolver.resolveCall(
                    candidates: memberCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: calleeName,
                        args: resolvedArgs,
                        explicitTypeArgs: explicitTypeArgs
                    ),
                    expectedType: expectedType,
                    implicitReceiverType: receiverType,
                    ctx: ctx.semaCtx
                )
                if let chosen = resolved.chosenCallee {
                    let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                } else if let bestCandidate = memberCandidates.first,
                          let sig = sema.symbols.functionSignature(for: bestCandidate)
                {
                    // Fallback: bind directly if resolver could not pick (single candidate).
                    var mapping: [Int: Int] = [:]
                    for i in args.indices { mapping[i] = i }
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: bestCandidate,
                            substitutedTypeArguments: [],
                            parameterMapping: mapping
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(bestCandidate))
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    let resultType = sig.returnType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
            }
        }

        if let firstInvisible = callInvisible.first, let calleeName {
            driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
        } else {
            let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0023",
                "Unresolved function '\(nameStr)'.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    private func makeSyntheticListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    /// Shared helper for synthesizing `Iterable<T>` types.
    /// Falls back to `Any` if `kotlin.collections.Iterable` is not registered.
    func makeSyntheticIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableSymbol = symbols.lookup(fqName: iterableFQName) else {
            // Fall back to Any rather than List<Char> to avoid granting
            // list-only members (e.g. get()) to the iterable result type.
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    /// Build `Array<elementType>` -- generic array with preserved element type.
    private func makeSyntheticArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Array"),
        ]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    /// Build a primitive array type (`IntArray`, `LongArray`, etc.) by name.
    private func makeSyntheticPrimitiveArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        arrayName: String
    ) -> TypeID {
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern(arrayName),
        ]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticNominalType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner _: StringInterner,
        fqName: [InternedString]
    ) -> TypeID {
        guard let symbol = symbols.lookup(fqName: fqName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func makeSyntheticSequenceType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let sequenceFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]
        guard let sequenceSymbol = symbols.lookup(fqName: sequenceFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func inferSyntheticMapKeyValueTypes(
        from args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> (keyType: TypeID, valueType: TypeID)? {
        let sema = ctx.sema
        let interner = ctx.interner
        let ast = ctx.ast
        var keyTypes: [TypeID] = []
        var valueTypes: [TypeID] = []

        for argument in args {
            guard let expr = ast.arena.expr(argument.expr) else { return nil }
            switch expr {
            case let .memberCall(receiver, callee, _, pairArgs, _)
                where callee == KnownCompilerNames(interner: interner).to && pairArgs.count == 1:
                let keyType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
                let valueType = driver.inferExpr(pairArgs[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                keyTypes.append(keyType)
                valueTypes.append(valueType)
            case let .call(calleeExpr, _, pairArgs, _):
                guard pairArgs.count == 2,
                      let callee = ast.arena.expr(calleeExpr),
                      case let .nameRef(name, _) = callee,
                      name == KnownCompilerNames(interner: interner).to
                else {
                    return nil
                }
                let keyType = driver.inferExpr(pairArgs[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                let valueType = driver.inferExpr(pairArgs[1].expr, ctx: ctx, locals: &locals, expectedType: nil)
                keyTypes.append(keyType)
                valueTypes.append(valueType)
            default:
                return nil
            }
        }

        guard !keyTypes.isEmpty, !valueTypes.isEmpty else {
            return nil
        }
        return (sema.types.lub(keyTypes), sema.types.lub(valueTypes))
    }

    private func makeSyntheticMutableListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let mutableListFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableList"),
        ]
        guard let mutableListSymbol = symbols.lookup(fqName: mutableListFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let setFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Set"),
        ]
        guard let setSymbol = symbols.lookup(fqName: setFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticMutableSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let mutableSetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableSet"),
        ]
        guard let mutableSetSymbol = symbols.lookup(fqName: mutableSetFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]
        guard let mapSymbol = symbols.lookup(fqName: mapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticMutableMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableMap"),
        ]
        guard let mapSymbol = symbols.lookup(fqName: mapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
    }

    private func applyContractEffects(
        chosen: SymbolID,
        args: [CallArgument],
        argTypes: [TypeID],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        guard let effect = sema.symbols.contractNonNullEffect(for: chosen),
              effect.appliesOnAnyReturn,
              let parameterIndex = sema.symbols.functionSignature(for: chosen)?
              .valueParameterSymbols.firstIndex(of: effect.parameterSymbol),
              parameterIndex < args.count,
              parameterIndex < argTypes.count
        else {
            return
        }
        let conditionExpr = args[parameterIndex].expr
        let branch = ctx.dataFlow.branchOnCondition(
            conditionExpr,
            base: ctx.flowState,
            locals: locals,
            ast: ctx.ast,
            sema: sema,
            interner: ctx.interner,
            scope: ctx.scope
        )
        driver.exprChecker.applyFlowStateToLocals(
            branch.trueState,
            locals: &locals,
            sema: sema
        )
    }

    func inferMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: expectedType, explicitTypeArgs: explicitTypeArgs,
            safeCall: false
        )
    }

    func inferSafeMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: expectedType, explicitTypeArgs: explicitTypeArgs,
            safeCall: true
        )
    }

    private func shouldUseBuiltinFlowFactorySpecialHandling(
        calleeName: InternedString,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        if locals[calleeName] != nil {
            return false
        }
        let visibleCandidates = ctx.cachedScopeLookup(calleeName)
        if visibleCandidates.isEmpty {
            return true
        }
        let hasConflictingUserDefinedCandidate = visibleCandidates.contains { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function
            else {
                return false
            }
            let flowPkgPrefix = [
                ctx.interner.intern("kotlinx"),
                ctx.interner.intern("coroutines"),
                ctx.interner.intern("flow"),
            ]
            return !symbol.fqName.starts(with: flowPkgPrefix)
        }
        return !hasConflictingUserDefinedCandidate
    }

    // MARK: - Top-level run helpers (STDLIB-401)

    /// Returns true when the call site looks like a top-level `run { ... }` or
    /// `run(::ref)` that should be intercepted by the scope-function path.
    private func isTopLevelRunCandidate(
        calleeName: InternedString?,
        args: [CallArgument],
        knownNames: KnownCompilerNames,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        guard let calleeName, args.count == 1,
              calleeName == knownNames.run,
              locals[calleeName] == nil
        else {
            return false
        }
        return isLambdaOrCallableRefArg(args[0].expr, ast: ast)
            && !isShadowedByUserDefinedRun(calleeName, ctx: ctx)
    }

    /// Returns true when `exprID` is a lambda literal or callable reference.
    private func isLambdaOrCallableRefArg(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let argExpr = ast.arena.expr(exprID) else { return false }
        switch argExpr {
        case .lambdaLiteral, .callableRef:
            return true
        default:
            return false
        }
    }

    /// Returns true when a non-synthetic (user-defined) `run` shadows the
    /// synthetic stdlib helper.
    /// KNOWN LIMITATION: This treats any non-synthetic symbol named `run` as
    /// shadowing, regardless of whether it is a top-level or extension overload.
    /// A more precise check would compare signatures/receiver types.
    private func isShadowedByUserDefinedRun(
        _ calleeName: InternedString,
        ctx: TypeInferenceContext
    ) -> Bool {
        ctx.cachedScopeLookup(calleeName).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            return !sym.flags.contains(.synthetic)
        }
    }

    /// Returns true when `name` is shadowed by a non-synthetic (user-defined) symbol,
    /// either as a local variable binding or as a scope-visible declaration.
    /// Used to guard stdlib special-call paths (measureTimeMillis, measureNanoTime, etc.)
    /// so that user-defined functions with the same name are not misidentified as stdlib intrinsics.
    private func isShadowedByNonSyntheticSymbol(
        _ name: InternedString,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> Bool {
        if locals[name] != nil { return true }
        return ctx.cachedScopeLookup(name).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            return !sym.flags.contains(.synthetic)
        }
    }

    /// Returns true when there is a synthetic symbol visible under `name` whose
    /// fully-qualified name matches `fqComponents`.  Used to guard stdlib
    /// special-call paths so that identically-named user or third-party
    /// functions are not misclassified as stdlib intrinsics.
    private func isSyntheticStdlibSymbol(
        _ name: InternedString,
        fqComponents: [String],
        ctx: TypeInferenceContext
    ) -> Bool {
        let interner = ctx.interner
        let internedFQ = fqComponents.map { interner.intern($0) }
        return ctx.cachedScopeLookup(name).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate),
                  sym.flags.contains(.synthetic)
            else { return false }
            return sym.fqName == internedFQ
        }
    }

    /// Returns the fully qualified path of a callee expression when it is
    /// composed of dotted names like `kotlin.coroutines.foo`.
    private func qualifiedCalleePath(for exprID: ExprID, ast: ASTModule) -> [InternedString]? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case let .nameRef(name, _):
            return [name]
        case let .memberCall(receiver, member, _, _, _):
            guard let receiverPath = qualifiedCalleePath(for: receiver, ast: ast) else {
                return nil
            }
            return receiverPath + [member]
        case let .callableRef(receiver, member, _):
            if let receiver {
                guard let receiverPath = qualifiedCalleePath(for: receiver, ast: ast) else {
                    return nil
                }
                return receiverPath + [member]
            }
            return [member]
        default:
            return nil
        }
    }

}

// swiftlint:enable type_body_length
