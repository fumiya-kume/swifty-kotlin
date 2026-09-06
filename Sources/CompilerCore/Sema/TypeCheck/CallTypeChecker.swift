// swiftlint:disable file_length

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
        if let calleeName,
           calleeName == interner.intern("contextOf"),
           args.isEmpty,
           locals[calleeName] == nil,
           !ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
               shadowsStdlibContextHelper(
                   candidate,
                   named: "contextOf",
                   argumentCount: 0,
                   explicitTypeArgumentCount: explicitTypeArgs.count,
                   ctx: ctx,
                   sema: sema,
                   interner: interner
               )
           })
        {
            let contextOfFQName = [interner.intern("kotlin"), calleeName]
            if let contextOfSymbol = sema.symbols.lookup(fqName: contextOfFQName) {
                let inferredType = explicitTypeArgs.first
                    ?? expectedType
                    ?? (ctx.contextReceiverTypes.count == 1 ? ctx.contextReceiverTypes[0] : sema.types.anyType)
                driver.helpers.checkOptIn(
                    for: contextOfSymbol,
                    ctx: ctx,
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                let nonNullInferredType = sema.types.makeNonNullable(inferredType)
                let hasMatchingContextReceiver = ctx.contextReceiverTypes.contains { receiverType in
                    let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                    return sema.types.isSubtype(nonNullReceiverType, nonNullInferredType)
                        || sema.types.isSubtype(nonNullInferredType, nonNullReceiverType)
                }
                if !hasMatchingContextReceiver {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-CTX-001",
                        "No context receiver is available for contextOf<\(sema.types.renderType(inferredType))>().",
                        range: range
                    )
                }
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: contextOfSymbol,
                        substitutedTypeArguments: [inferredType],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(contextOfSymbol))
                sema.bindings.bindExprType(id, type: inferredType)
                return inferredType
            }
        }
        if let customBuilderType = inferExperimentalBuilderCallExpr(
            id,
            calleeName: calleeName,
            args: args,
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
            if let builderKind = builderDSLKind(for: calleeName, interner: interner),
               shouldUseBuilderDSLSpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
            {
                let lambdaArgumentIndex: Int? = switch builderKind {
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
                if builderKind == .buildList,
                    args.count == 2
                {
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
            sema.bindings.markCollectionHOFLambdaExpr(argumentExprID)
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

        // --- Context helper: context(with, block) (STDLIB-KOTLIN-ROOT-CTX-001) ---
        // The helper makes the first argument available as a context receiver
        // for the block type, but does not make it an implicit receiver.
        let contextHelperName = interner.intern("context")
        if let calleeName, args.count >= 2, args.count <= 23,
           calleeName == contextHelperName,
           locals[calleeName] == nil,
           !ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
               shadowsStdlibContextHelper(
                   candidate,
                   named: "context",
                   argumentCount: args.count,
                   explicitTypeArgumentCount: explicitTypeArgs.count,
                   ctx: ctx,
                   sema: sema,
                   interner: interner
               )
           })
        {
            let contextValueArgs = Array(args.dropLast())
            let blockArg = args[args.count - 1]
            let contextValueTypes = contextValueArgs.map {
                driver.inferExpr($0.expr, ctx: ctx, locals: &locals)
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                contextReceivers: contextValueTypes,
                params: [],
                returnType: expectedType ?? sema.types.anyType
            )))
            let lambdaType = driver.inferExpr(
                blockArg.expr,
                ctx: ctx,
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[blockArg.expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            // Refine the call result type using the lambda body's concrete type,
            // but ONLY when no expected type was provided (i.e. expected was
            // anyType, the placeholder for "unconstrained") — mirrors the
            // `use`/`usePinned`/`useContents` refinement above. Needed when the
            // `context(...) { ... }` call itself isn't in a target-typed
            // position, e.g. as an operand of `+`:
            //   context("one") { contextOf<String>() } + context(...) { ... }
            let refinedReturnType: TypeID = {
                guard returnType == sema.types.anyType else { return returnType }
                guard let lambdaExpr = ast.arena.expr(blockArg.expr),
                      case let .lambdaLiteral(_, bodyExprID, _, _) = lambdaExpr,
                      let bodyType = sema.bindings.exprTypes[bodyExprID],
                      bodyType != sema.types.anyType
                else { return returnType }
                return bodyType
            }()
            if let contextSymbol = ctx.cachedScopeLookup(calleeName).first(where: { candidate in
                guard isStdlibContextHelper(candidate, named: "context", ctx: ctx, interner: interner),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count
                else {
                    return false
                }
                return true
            }) {
                driver.helpers.checkOptIn(
                    for: contextSymbol,
                    ctx: ctx,
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: contextSymbol,
                        substitutedTypeArguments: contextValueTypes + [refinedReturnType],
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(contextSymbol))
            }
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeContext)
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }

        // --- produce { ... } builder (CORO-075) ---
        if let calleeName,
           calleeName == knownNames.produce,
           args.count == 1,
           locals[calleeName] == nil
        {
            let argumentExprID = args[0].expr
            // See the coroutineLauncherLambdaExprIDs doc comment: produce{}'s
            // captures are forwarded via CoroutineLoweringPass+LauncherSupport's
            // launcher-continuation rewrite (BUG-049), not the generic
            // escaping-callable-value (kk_function_create_N) ABI.
            sema.bindings.markCoroutineLauncherLambdaExpr(argumentExprID)
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

        // KSP-674: flowOf / emptyFlow are Kotlin source (kotlinx.coroutines.flow),
        // so they resolve through normal overload resolution to their bundled
        // declarations. The former builtin fixed-flow special-casing (which only
        // bound a Flow type without a callable target) was removed; missing the
        // import now yields a proper unresolved-reference diagnostic, matching
        // kotlinx.coroutines.

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

        // --- Stdlib Array(size) { init } constructor (STDLIB-085/086, TYPE-103) ---
        // A visible source-backed top-level function with the same name and applicable
        // arity owns the overload. For one-argument primitive arrays, compare
        // the inferred argument type as well: UByteArray(ByteArray) must not
        // hide the compiler-provided UByteArray(Int) allocation form.
        let sourceBackedArrayConstructors: [(symbol: SymbolID, signature: FunctionSignature)] = if let calleeName {
            ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.compactMap { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.receiverType == nil,
                      signature.parameterTypes.count == args.count,
                      !signature.valueParameterIsVararg.contains(true)
                else {
                    return nil
                }
                return (candidate, signature)
            }
        } else {
            []
        }
        let hasSourceBackedArrayConstructor: Bool = {
            if args.count == 1,
               let calleeName,
               knownNames.isPrimitiveArrayConstructorTypeName(calleeName),
               !sourceBackedArrayConstructors.isEmpty
            {
                let argumentType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                return sourceBackedArrayConstructors.contains { _, signature in
                    guard let parameterType = signature.parameterTypes.first else {
                        return false
                    }
                    return sema.types.isSubtype(argumentType, parameterType)
                }
            }
            return !sourceBackedArrayConstructors.isEmpty
        }()
        if let calleeName,
           knownNames.isPrimitiveArrayConstructorTypeName(calleeName),
           args.count == 2 || (args.count == 1 && calleeName != knownNames.array),
           locals[calleeName] == nil,
           !hasSourceBackedArrayConstructor
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
                case "ShortArray": sema.types.shortType
                case "ByteArray": sema.types.byteType
                case "UByteArray": sema.types.ubyteType
                case "UShortArray": sema.types.ushortType
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

        if let calleeName,
           (args.count == 1 || args.count == 2),
           interner.resolve(calleeName) == "AtomicIntArray",
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           let arraySymbol = syntheticAtomicArrayClassSymbol(
               calleeName,
               className: "AtomicIntArray",
               ctx: ctx
           )
        {
            let intType = sema.types.intType
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
            if args.count == 2 {
                let initExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [intType],
                    returnType: intType
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: initExpectedType
                )
            }
            let resultType = sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [],
                nullability: .nonNull
            )))
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .atomicIntArrayFactory)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        if let calleeName,
           (args.count == 1 || args.count == 2),
           interner.resolve(calleeName) == "AtomicLongArray",
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           let arraySymbol = syntheticAtomicArrayClassSymbol(
               calleeName,
               className: "AtomicLongArray",
               ctx: ctx
           )
        {
            let intType = sema.types.intType
            let longType = sema.types.longType
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
            if args.count == 2 {
                let initExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [intType],
                    returnType: longType
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: initExpectedType
                )
            }
            let resultType = sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [],
                nullability: .nonNull
            )))
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .atomicLongArrayFactory)
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

        // --- Primitive numeric minOf/maxOf fast path (STDLIB-COMP-001/002) ---
        // Only apply to the stdlib comparison functions with value arguments;
        // lambda/callable-ref arguments (e.g. compareBy selectors or comparators)
        // must go through general overload resolution where an expected function
        // type is available, otherwise implicit `it` cannot be resolved.
        let maxOfMinOfNames: Set<String> = ["maxOf", "minOf"]
        if let calleeName,
           maxOfMinOfNames.contains(interner.resolve(calleeName)),
           args.count == 2 || args.count == 3,
           !args.contains(where: { isLambdaOrCallableRefArg($0.expr, ast: ast) })
        {
            // Infer the first argument without an expected type to determine the overload.
            let firstArgType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )

            // Resolve which numeric type this overload targets.
            let resolvedName = interner.resolve(calleeName)
            let supportedNumericTypes = [
                sema.types.longType,
                sema.types.doubleType,
                sema.types.floatType,
                sema.types.intType,
            ] + (resolvedName == "minOf" ? [sema.types.byteType, sema.types.shortType] : [])
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
                    let matchingCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.filter { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate) else {
                            return false
                        }
                        return signature.parameterTypes == paramTypes
                    }
                    // Prefer the fixed-arity overload over a vararg one declaring the same
                    // parameter types (e.g. minOf(Int, Int) vs minOf(Int, vararg Int)), matching
                    // Kotlin's preference for non-vararg signatures during overload resolution.
                    let chosen = matchingCandidates.first(where: { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate) else {
                            return false
                        }
                        return !signature.valueParameterIsVararg.contains(true)
                    }) ?? matchingCandidates.first
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

        // --- compareBy(selector1, selector2, ...) multi-selector overloads (STDLIB-613) ---
        if let calleeName,
           args.count == 2 || args.count == 3,
           interner.resolve(calleeName) == "compareBy",
           args.allSatisfy({ isLambdaOrCallableRefArg($0.expr, ast: ast) }),
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", "compareBy"],
               ctx: ctx
           ) != nil
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
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                guard let sig = sema.symbols.functionSignature(for: candidate),
                      sema.symbols.isSourceBackedSymbol(candidate)
                else { return false }
                return sig.parameterTypes.count == args.count &&
                    !sig.valueParameterIsVararg.contains(true) &&
                    sig.parameterTypes.allSatisfy { paramType in
                        if case .functionType = sema.types.kind(of: paramType) { return true }
                        return false
                    }
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
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", interner.resolve(calleeName)],
               ctx: ctx
           ) != nil
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
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                guard let sig = sema.symbols.functionSignature(for: candidate),
                      sema.symbols.isSourceBackedSymbol(candidate)
                else { return false }
                return sig.parameterTypes.count == 2
                    && !sig.valueParameterIsVararg.contains(true)
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
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", "compareBy"],
               ctx: ctx
           ) != nil
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
                guard let sig = sema.symbols.functionSignature(for: candidate),
                      sema.symbols.isSourceBackedSymbol(candidate)
                else { return false }
                return sig.valueParameterIsVararg == [true]
            }) {
                var mapping: [Int: Int] = [:]
                for index in args.indices {
                    mapping[index] = 0
                }
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType],
                        parameterMapping: mapping
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
           locals[calleeName] == nil
        {
            let calleeNameStr = interner.resolve(calleeName)
            if (calleeNameStr == "compareBy" || calleeNameStr == "compareByDescending"),
               sourceOrSyntheticStdlibFunctionSymbol(
                   calleeName,
                   fqComponents: ["kotlin", "comparisons", calleeNameStr],
                   ctx: ctx
               ) != nil {
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
                    returnType: sema.types.nullableAnyType,
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

                // Bind to the bundled Kotlin source symbol.
                let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
                let funcFQName = comparisonsPkg + [calleeName]
                if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                    return sig.parameterTypes.count == 1
                        && sig.valueParameterIsVararg != [true]
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
           locals[calleeName] == nil
        {
            let calleeNameStr = interner.resolve(calleeName)
            if (calleeNameStr == "naturalOrder" || calleeNameStr == "reverseOrder"),
               sourceOrSyntheticStdlibFunctionSymbol(
                   calleeName,
                   fqComponents: ["kotlin", "comparisons", calleeNameStr],
                   ctx: ctx
               ) != nil {
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

        // KSP-678: `Channel()` / `Channel(capacity)` resolve through the bundled
        // Kotlin factory functions (Channels.kt) via normal overload resolution.

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
                  ["runBlocking", "launch", "async", "coroutineScope", "supervisorScope"].contains(name)
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
        // Mark lambda arguments passed to KIR-level coroutine launchers so
        // LambdaLowerer skips the generic escaping-callable-value
        // materialization path for them: CoroutineLoweringPass+
        // LauncherSupport.swift's rewriteLauncherCall expects their captures
        // forwarded via its own launcher-continuation convention (BUG-049),
        // not bundled into a kk_function_create_N closure object. `produce`
        // has its own dedicated builder branch above (CORO-075) with an early
        // return, so it never reaches this general path and is marked there
        // instead.
        if let coroutineLauncherName,
           ["runBlocking", "launch", "async"].contains(coroutineLauncherName)
        {
            if let firstArgExpr = args.first, case .lambdaLiteral = ast.arena.expr(firstArgExpr.expr) {
                sema.bindings.markCoroutineLauncherLambdaExpr(firstArgExpr.expr)
            } else if args.count >= 2, case .lambdaLiteral = ast.arena.expr(args[1].expr) {
                sema.bindings.markCoroutineLauncherLambdaExpr(args[1].expr)
            }
        }
        let withContextExpectedLambdaType: TypeID? = if let calleeName,
                                                        calleeName == knownNames.withContext
                                                            || calleeName == knownNames.withTimeout
                                                            || calleeName == knownNames.withTimeoutOrNull,
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
            if interner.resolve(calleeName) == "toList",
               let implicitReceiverType = ctx.implicitReceiverType
            {
                candidates = preferCollectionToListCandidates(
                    candidates,
                    receiverType: implicitReceiverType,
                    sema: sema,
                    interner: interner
                )
            }
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
            var resolvedFromLocalShadow = false
            if let local = locals[calleeName],
               let sym = ctx.cachedSymbol(local.symbol),
               sym.kind == .function
            {
                // Local function declarations shadow imported and top-level functions
                // of the same name, so use the local symbol as the sole candidate.
                candidates = [local.symbol]
                resolvedFromLocalShadow = true
            }
            // KSP-CAP-006: a class/enum/annotation-class/object may coexist
            // with a top-level function of the same name (e.g. `class Random`
            // + top-level `fun Random(seed: Long): Random`, the real
            // kotlin-stdlib factory-function idiom). Merge that type's
            // constructors into the candidate set instead of only using them
            // as an empty-candidates fallback, so overload resolution can
            // choose between the function(s) and the constructor(s) by
            // argument type -- the same way it already does between two
            // overloaded functions of the same name. Skipped when a local
            // variable already shadows the name (resolvedFromLocalShadow).
            if !resolvedFromLocalShadow {
                let classSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .class || symbol.kind == .enumClass || symbol.kind == .annotationClass || symbol.kind == .object
                }
                if let classSym = classSymbols.first, let classSymbol = ctx.cachedSymbol(classSym) {
                    if classSymbol.flags.contains(.abstractType) {
                        // P5-112: Prohibit direct instantiation of abstract classes,
                        // but only when there is no other viable candidate (e.g. a
                        // coexisting top-level factory function): an abstract
                        // class's own constructor is never itself a usable call
                        // target, so it must not blot out a real candidate.
                        if candidates.isEmpty {
                            let className = classSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                            ctx.semaCtx.diagnostics.error(
                                "KSWIFTK-SEMA-ABSTRACT",
                                "Cannot create an instance of abstract class '\(className)'.",
                                range: range
                            )
                            sema.bindings.bindExprType(id, type: sema.types.errorType)
                            return sema.types.errorType
                        }
                    } else {
                        let initName = interner.intern("<init>")
                        let ctorFQName = classSymbol.fqName + [initName]
                        let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                        if !ctorSymbols.isEmpty {
                            let (ctorVis, ctorInvis) = ctx.filterByVisibility(ctorSymbols)
                            // Some synthetic stdlib types register a class
                            // constructor whose signature exactly duplicates a
                            // coexisting top-level factory function's signature
                            // (e.g. kotlin.io.path.Path's synthetic
                            // `<init>(String)` alongside the top-level `fun
                            // Path(pathString: String): Path`). Without this
                            // filter the duplicate becomes a second,
                            // indistinguishable overload candidate and every
                            // call to that name falsely resolves as ambiguous.
                            let newCtorVis = ctorVis.filter { ctorID in
                                guard let ctorSignature = sema.symbols.functionSignature(for: ctorID) else {
                                    return true
                                }
                                return !candidates.contains { existingID in
                                    sema.symbols.functionSignature(for: existingID)?.parameterTypes == ctorSignature.parameterTypes
                                }
                            }
                            candidates.append(contentsOf: newCtorVis)
                            callInvisible.append(contentsOf: ctorInvis)
                        }
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
        } else if let calleePath, calleePath.count > 1 {
            // FQN call: e.g. kotlin.math.abs(x) — look up directly by fully qualified name
            let fqnCandidates = sema.symbols.lookupAll(fqName: calleePath).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            let (vis, invis) = ctx.filterByVisibility(fqnCandidates)
            candidates = vis
            callInvisible.append(contentsOf: invis)
        } else {
            candidates = []
        }

        if let calleeName,
           interner.resolve(calleeName) == "compareValuesBy",
           args.count >= 4,
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", "compareValuesBy"],
               ctx: ctx
           ) != nil
        {
            let firstType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let secondType = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals)
            let comparatorArgType = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals)
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                let nonNullComparatorArgType = sema.types.makeNonNullable(comparatorArgType)
                let inferredKeyType: TypeID? = if case let .classType(classType) = sema.types.kind(of: nonNullComparatorArgType),
                                                  classType.classSymbol == comparatorSymbol,
                                                  let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(type), let .out(type), let .in(type): type
                    case .star: sema.types.anyType
                    }
                } else {
                    nil
                }

                if let inferredKeyType {
                    let elementCandidates = [firstType, secondType].filter { $0 != sema.types.errorType }.map {
                        sema.types.makeNonNullable($0)
                    }
                    let elementType = explicitTypeArgs.first
                        ?? (elementCandidates.isEmpty ? sema.types.anyType : sema.types.lub(elementCandidates))
                    let keyType = explicitTypeArgs.count >= 2 ? explicitTypeArgs[1] : inferredKeyType
                    let comparatorType = sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(keyType)],
                        nullability: .nonNull
                    )))
                    let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [elementType],
                        returnType: keyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: comparatorType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[3].expr)
                    _ = driver.inferExpr(args[3].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

                    if let chosen = candidates.first(where: { candidate in
                        guard let sig = sema.symbols.functionSignature(for: candidate),
                              sema.symbols.isSourceBackedSymbol(candidate)
                        else { return false }
                        return sig.parameterTypes.count == 4 && sig.typeParameterSymbols.count == 2
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [elementType, keyType],
                                parameterMapping: [0: 0, 1: 1, 2: 2, 3: 3]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
            }
            if args.count >= 4 {
                let elementCandidates = [firstType, secondType].filter { $0 != sema.types.errorType }.map {
                    sema.types.makeNonNullable($0)
                }
                let elementType = explicitTypeArgs.first
                    ?? (elementCandidates.isEmpty ? sema.types.anyType : sema.types.lub(elementCandidates))
                let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [elementType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                for index in 2..<args.count {
                    _ = driver.inferExpr(args[index].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
                }

                // 3 selectors resolve to the fixed-arity overload; 4+ to the vararg one.
                let usesVararg = args.count > 5
                if let chosen = candidates.first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate),
                          sema.symbols.isSourceBackedSymbol(candidate)
                    else { return false }
                    // The comparator overload has the same arity as the two
                    // selector one, so match on its second type parameter (`K`).
                    return usesVararg
                        ? sig.valueParameterIsVararg == [false, false, true]
                        : (sig.parameterTypes.count == args.count
                            && sig.typeParameterSymbols.count == 1
                            && !sig.valueParameterIsVararg.contains(true))
                }) {
                    var mapping: [Int: Int] = [0: 0, 1: 1]
                    for index in 2..<args.count {
                        mapping[index] = usesVararg ? 2 : index
                    }
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: mapping
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: sema.types.intType)
                return sema.types.intType
            }
        }

        var expectedTypeOverrides: [Int: TypeID] = [:]
        var lambdaContextOverrides: [Int: TypeInferenceContext] = [:]
        if let launcherIndex = coroutineLauncherLambdaArgIndex,
           let coroutineLauncherExpectedLambdaType
        {
            expectedTypeOverrides[launcherIndex] = coroutineLauncherExpectedLambdaType
            var builderContext = ctx
            builderContext.isCoroutineBuilderLambdaScope = true
            if let coroutineScopeType = coroutineScopeType(sema: sema, interner: interner) {
                builderContext = builderContext.with(implicitReceiverType: coroutineScopeType)
            }
            lambdaContextOverrides[launcherIndex] = builderContext
        }
        if let withContextExpectedLambdaType, args.count > 1 {
            expectedTypeOverrides[1] = withContextExpectedLambdaType
        }
        let preparedArgs = prepareCallArguments(
            args: args,
            candidates: candidates,
            expectedTypeOverrides: expectedTypeOverrides,
            explicitTypeArgs: explicitTypeArgs,
            lambdaContextOverrides: lambdaContextOverrides,
            ctx: ctx,
            locals: &locals
        )
        let argTypes = preparedArgs.argTypes

        func sourceBackedCollectionFactoryType(
            name: String
        ) -> (type: TypeID, typeArgs: [TypeID])? {
            func typeArgs(from type: TypeID) -> [TypeID] {
                guard case let .classType(classType) = sema.types.kind(of: type) else {
                    return []
                }
                return classType.args.map { arg in
                    switch arg {
                    case let .invariant(type), let .in(type), let .out(type):
                        type
                    case .star:
                        sema.types.anyType
                    }
                }
            }

            func expectedCollectionType(withArity arity: Int) -> TypeID? {
                guard let expectedType,
                      expectedType != sema.types.errorType,
                      case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                      expectedClassType.args.count >= arity
                else {
                    return nil
                }
                return expectedType
            }

            switch name {
            case "emptyList", "listOf", "listOfNotNull", "mutableListOf", "arrayListOf":
                if let expectedType = expectedCollectionType(withArity: 1) {
                    return (expectedType, typeArgs(from: expectedType))
                }
                let elementTypes = name == "listOfNotNull"
                    ? argTypes.compactMap { type -> TypeID? in
                        type == sema.types.nullableNothingType ? nil : sema.types.makeNonNullable(type)
                    }
                    : argTypes
                let elementType = explicitTypeArgs.first
                    ?? (elementTypes.isEmpty ? sema.types.nothingType : sema.types.lub(elementTypes))
                let resultType = name == "mutableListOf" || name == "arrayListOf"
                    ? makeSyntheticMutableListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                    : makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                return (resultType, [elementType])

            case "emptySet", "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf":
                if let expectedType = expectedCollectionType(withArity: 1) {
                    return (expectedType, typeArgs(from: expectedType))
                }
                let elementTypes = name == "setOfNotNull"
                    ? argTypes.compactMap { type -> TypeID? in
                        type == sema.types.nullableNothingType ? nil : sema.types.makeNonNullable(type)
                    }
                    : argTypes
                let elementType = explicitTypeArgs.first
                    ?? (elementTypes.isEmpty ? sema.types.nothingType : sema.types.lub(elementTypes))
                let resultType: TypeID
                if name == "linkedSetOf" {
                    resultType = makeSyntheticLinkedHashSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else if name == "hashSetOf" {
                    resultType = makeSyntheticHashSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else if name == "mutableSetOf" {
                    resultType = makeSyntheticMutableSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else {
                    resultType = makeSyntheticSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                }
                return (resultType, [elementType])

            case "emptyMap", "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf":
                if let expectedType = expectedCollectionType(withArity: 2) {
                    return (expectedType, typeArgs(from: expectedType))
                }
                let keyType: TypeID
                let valueType: TypeID
                if explicitTypeArgs.count == 2 {
                    keyType = explicitTypeArgs[0]
                    valueType = explicitTypeArgs[1]
                } else if let inferred = inferSyntheticMapKeyValueTypes(from: argTypes, ctx: ctx) {
                    keyType = inferred.keyType
                    valueType = inferred.valueType
                } else {
                    keyType = sema.types.nothingType
                    valueType = sema.types.nothingType
                }
                let resultType = name == "mapOf" || name == "emptyMap"
                    ? makeSyntheticMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                    : makeSyntheticMutableMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                return (resultType, [keyType, valueType])

            default:
                return nil
            }
        }

        func isKotlinCollectionsFactorySymbol(_ symbol: SemanticSymbol, named name: InternedString) -> Bool {
            guard symbol.kind == .function,
                  symbol.name == name,
                  symbol.fqName.count >= 3
            else {
                return false
            }
            return interner.resolve(symbol.fqName[0]) == "kotlin"
                && interner.resolve(symbol.fqName[1]) == "collections"
        }

        func hasNonStdlibCollectionFactoryShadow(
            _ name: InternedString,
            locals: LocalBindings,
            ctx: TypeInferenceContext
        ) -> Bool {
            if locals[name] != nil {
                return true
            }
            return ctx.cachedScopeLookup(name).contains { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      !symbol.flags.contains(.synthetic)
                else {
                    return false
                }
                return !isKotlinCollectionsFactorySymbol(symbol, named: name)
            }
        }

        if let calleeName {
            let resolvedName = interner.resolve(calleeName)
            // mapOf has both fixed-arity and vararg source declarations. Let the
            // regular resolver distinguish them for non-empty calls instead of
            // binding the first collection-factory candidate unconditionally.
            if !(resolvedName == "mapOf" && !args.isEmpty),
               let sourceBackedFactory = sourceBackedCollectionFactoryType(name: resolvedName),
               !hasNonStdlibCollectionFactoryShadow(calleeName, locals: locals, ctx: ctx),
               let chosen = candidates.first(where: { candidate in
                   guard let symbol = ctx.cachedSymbol(candidate),
                         isKotlinCollectionsFactorySymbol(symbol, named: calleeName)
                   else {
                       return false
                   }
                   if resolvedName == "listOfNotNull" {
                       // The fixed-arity and vararg overloads share the same
                       // source shape. Select the fixed overload for one
                       // argument and the vararg overload for zero or multiple
                       // arguments so lowering receives the correct packing
                       // contract.
                       let isVararg = sema.symbols.functionSignature(for: candidate)?
                           .valueParameterIsVararg.first ?? false
                       return isVararg == (args.count != 1)
                   }
                   return args.isEmpty || (sema.symbols.functionSignature(for: candidate)?.parameterTypes.isEmpty == false)
               })
            {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: sourceBackedFactory.typeArgs,
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, 0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: sourceBackedFactory.type)
                return sourceBackedFactory.type
            }

            // The collection aliases and the concrete LinkedHashSet class are
            // type declarations (Stdlib/kotlin/collections/CollectionAliases.kt)
            // rather than factory functions, so their constructor calls are typed
            // here; CollectionLiteralLoweringPass rewrites the resulting calls to
            // the matching runtime bridge.
            let expectedCollectionArgs: [TypeID] = if let expectedType,
                                                       expectedType != sema.types.errorType,
                                                       case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
            {
                expectedClassType.args.map { arg in
                    switch arg {
                    case let .invariant(type), let .in(type), let .out(type): type
                    case .star: sema.types.anyType
                    }
                }
            } else {
                []
            }
            let constructorElementType = explicitTypeArgs.first
                ?? expectedCollectionArgs.first
                ?? (resolvedName == "HashSet" ? argTypes.first.flatMap { argumentType in
                    guard case let .classType(argumentClassType) = sema.types.kind(
                        of: sema.types.makeNonNullable(argumentType)
                    ),
                    let firstArgument = argumentClassType.args.first
                    else {
                        return nil
                    }
                    return switch firstArgument {
                    case let .invariant(type), let .in(type), let .out(type): type
                    case .star: sema.types.anyType
                    }
                } : nil)
                ?? sema.types.anyType
            switch resolvedName {
            case "ArrayList":
                let resultType = makeSyntheticListConstructorType(
                    name: resolvedName,
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: constructorElementType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            case "HashSet":
                let resultType = makeSyntheticHashSetType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: constructorElementType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            case "LinkedHashSet":
                let resultType = makeSyntheticLinkedHashSetType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: constructorElementType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            case "HashMap", "LinkedHashMap":
                let inferredMapTypes = inferMapTypeArgumentsFromConstructorArgument(from: argTypes, ctx: ctx)
                let keyType = explicitTypeArgs.first
                    ?? expectedCollectionArgs.first
                    ?? inferredMapTypes?.keyType
                    ?? sema.types.anyType
                let valueType = explicitTypeArgs.dropFirst().first
                    ?? expectedCollectionArgs.dropFirst().first
                    ?? inferredMapTypes?.valueType
                    ?? sema.types.anyType
                let resultType = resolvedName == "HashMap"
                    ? makeSourceBackedHashMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                    : makeSyntheticMutableMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            default:
                break
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "atomicArrayOf",
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           let chosen = candidates.first(where: { candidate in
               sema.symbols.externalLinkName(for: candidate) == "kk_atomic_ref_array_of"
           }),
           let atomicArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("concurrent"),
               interner.intern("atomics"),
               interner.intern("AtomicArray"),
           ])
        {
            let expectedElementType: TypeID? = if let expectedType,
                                                  expectedType != sema.types.errorType,
                                                  case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                                                  expectedClassType.classSymbol == atomicArraySymbol,
                                                  let firstArg = expectedClassType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                nil
            }
            func arrayElementType(from type: TypeID) -> TypeID {
                let nonNullType = sema.types.makeNonNullable(type)
                guard let (classType, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
                      symbol.name == knownNames.array,
                      let firstArg = classType.args.first
                else {
                    return sema.types.anyType
                }
                return switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            }
            let argumentElementTypes = zip(args, argTypes).map { argument, type in
                argument.isSpread ? arrayElementType(from: type) : type
            }
            let inferredElementType: TypeID
            if let explicitTypeArg = explicitTypeArgs.first {
                inferredElementType = explicitTypeArg
            } else if let expectedElementType {
                inferredElementType = expectedElementType
            } else if !argumentElementTypes.isEmpty {
                let lub = sema.types.lub(argumentElementTypes)
                inferredElementType = lub == sema.types.errorType ? sema.types.anyType : lub
            } else {
                inferredElementType = sema.types.anyType
            }
            let returnType = sema.types.make(.classType(ClassType(
                classSymbol: atomicArraySymbol,
                args: [.invariant(inferredElementType)],
                nullability: .nonNull
            )))
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
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [inferredElementType],
                    parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, 0) })
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }
        // KSP-979: an implicit receiver call must keep the most-specific
        // source-backed owner for the Iterable index family. Existing bundled
        // List bodies use an unqualified indexOf call in contains(); once the
        // generic Iterable overload is added, resolve this owner before the
        // ordinary top-level overload resolver reports an ambiguity.
        if let calleeName,
           let implicitReceiverType = ctx.implicitReceiverType,
           ["indexOf", "indexOfFirst", "indexOfLast"].contains(interner.resolve(calleeName))
        {
            let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
            let nonNullReceiver = sema.types.makeNonNullable(implicitReceiverType)
            let preferListReceiver: Bool? = if receiverClassifier.isConcreteListLikeType(nonNullReceiver) {
                true
            } else if !receiverClassifier.isCollectionLikeType(nonNullReceiver),
                      receiverClassifier.isNominalIterableType(nonNullReceiver)
            {
                false
            } else {
                nil
            }
            if let preferListReceiver {
                let preferredCandidates = candidates.filter { candidate in
                    guard sema.symbols.isSourceBackedSymbol(candidate),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType
                    else {
                        return false
                    }
                    if preferListReceiver {
                        return receiverClassifier.isConcreteListLikeType(declaredReceiver)
                    }
                    return !receiverClassifier.isCollectionLikeType(declaredReceiver)
                        && receiverClassifier.isNominalIterableType(declaredReceiver)
                }
                if !preferredCandidates.isEmpty {
                    candidates = preferredCandidates
                }
            }
        }
        if !candidates.isEmpty {
            // STDLIB-CORO-BUG-02: withContext is registered with a hardcoded
            // Any return type (see HeaderHelpers+SyntheticCoroutineRegistry.swift)
            // rather than made generic over the block's return type, because a
            // real type parameter there hangs the constraint solver. When the
            // call site
            // has a concrete expectedType (e.g. a declared function return
            // type), Any fails the return-type-vs-expectedType compatibility
            // check and every candidate is rejected ("no viable overload").
            // Resolve with expectedType relaxed to nil instead -- the same path
            // already picks the right overload correctly via argument matching
            // when there is no expected type -- then restore expectedType as
            // the call's result type below. The lambda body itself was already
            // checked against expectedType via coroutineLauncherExpectedLambdaType
            // / withContextExpectedLambdaType above.
            //
            // Matched by FQName + the synthetic flag (not just the short name)
            // so a user-defined function that happens to also be named
            // "withContext" doesn't get its return type silently overridden --
            // registerSyntheticCoroutineTopLevelFunction doesn't set an
            // externalLinkName for withContext (the runtime callee swap happens
            // later, in CoroutineLoweringPass, purely by name), so externalLinkName
            // isn't available here to disambiguate instead.
            let coroutinesWithContextFQName = [
                interner.intern("kotlinx"), interner.intern("coroutines"), interner.intern("withContext"),
            ]
            let isCoroutineBuilderWithHardcodedAnyReturn = !candidates.isEmpty && candidates.allSatisfy { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.flags.contains(.synthetic) && symbol.fqName == coroutinesWithContextFQName
            }
            let resolved = resolveCallRespectingLambdaReturnType(
                candidates: candidates,
                args: args,
                argTypes: argTypes,
                range: range,
                calleeName: calleeName ?? InternedString(),
                explicitTypeArgs: explicitTypeArgs,
                expectedType: isCoroutineBuilderWithHardcodedAnyReturn ? nil : expectedType,
                implicitReceiverType: ctx.implicitReceiverType,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: ctx
            )
            if let diagnostic = resolved.diagnostic {
                if let calleeName,
                   let recovered = tryBindImplicitReceiverMemberCallForInapplicableScopeCandidates(
                       id,
                       calleeName: calleeName,
                       args: args,
                       argTypes: argTypes,
                       range: range,
                       explicitTypeArgs: explicitTypeArgs,
                       expectedType: expectedType,
                       scopeCandidates: candidates,
                       ctx: ctx
                   )
                {
                    return recovered
                }
                if let calleeName,
                   let receiverType = ctx.implicitReceiverType,
                   let recovered = tryBindImplicitReceiverSyntheticExtensionCall(
                       id,
                       calleeName: calleeName,
                       receiverType: receiverType,
                       args: args,
                       range: range,
                       ctx: ctx,
                       locals: &locals,
                       expectedType: expectedType,
                       explicitTypeArgs: explicitTypeArgs
                   )
                {
                    return recovered
                }
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
            var adjustedReturnType: TypeID = if let coroutineLauncherName,
                let launcherIndex = coroutineLauncherLambdaArgIndex,
                ["async", "coroutineScope", "supervisorScope"].contains(coroutineLauncherName),
                args.indices.contains(launcherIndex)
            {
                coroutineBuilderNarrowedReturnType(
                    id: id,
                    launcherName: coroutineLauncherName,
                    lambdaArgExpr: args[launcherIndex].expr,
                    fallback: returnType,
                    ast: ast,
                    sema: sema
                )
            } else {
                returnType
            }
            // STDLIB-CORO-BUG-02: restore the real expectedType as the result
            // of withContext calls -- see the matching comment above
            // resolveCallRespectingLambdaReturnType.
            if isCoroutineBuilderWithHardcodedAnyReturn,
               let expectedType, expectedType != sema.types.errorType
            {
                adjustedReturnType = expectedType
            }
            if let implicitReceiverType = ctx.implicitReceiverType {
                markCoroutineScopeImplicitReceiverCallIfNeeded(
                    id,
                    chosenCallee: chosen,
                    receiverType: implicitReceiverType,
                    ctx: ctx
                )
            }
            applyContractEffects(
                chosen: chosen,
                args: args,
                ctx: ctx,
                locals: &locals
            )
            if let calleeName {
                let resolvedName = interner.resolve(calleeName)
                if KnownCompilerNames.stdlibCollectionFactoryNames.contains(resolvedName),
                   !KnownCompilerNames.arrayFactoryFunctionNames.contains(resolvedName)
                {
                    sema.bindings.markCollectionExpr(id)
                }
            }
            if let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               [
                   "kk_op_rangeTo",
                   "__kk_op_rangeUntil",
                   "kk_uint_rangeTo",
                   "kk_char_rangeTo",
                   "__kk_int_progression_fromClosedRange",
                   "__kk_long_progression_fromClosedRange",
                   "__kk_uint_progression_fromClosedRange",
                   "__kk_ulong_progression_fromClosedRange",
                   "__kk_op_ulong_rangeUntil",
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
        // Builder DSL member functions (STDLIB-002).
        // Inside builder lambdas, unqualified `append`/`add`/`put` resolve as
        // implicit-receiver member calls that return Unit.
        if let calleeName, ctx.isBuilderLambdaScope, let activeBuilderKind = ctx.builderKind {
            let name = interner.resolve(calleeName)
            let isBuilderMember: Bool = switch activeBuilderKind {
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
        // STDLIB-004: Inside receiver lambdas (run/apply/with), unqualified
        // function calls resolve as member calls on the implicit receiver.
        if let calleeName, let receiverType = ctx.implicitReceiverType {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            let name = interner.resolve(calleeName)
            if sema.types.isSubtype(nonNullReceiver, sema.types.charType),
               args.isEmpty,
               let member = syntheticCharMemberSpec(named: name)
            {
                let resultType = member.returnKind.typeID(
                    in: sema.types,
                    symbols: sema.symbols,
                    interner: interner
                )
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

            if let resultType = inferSequenceScopeYieldAllImplicitReceiverCall(
                id,
                calleeName: calleeName,
                args: args,
                ctx: ctx,
                locals: &locals,
                explicitTypeArgs: explicitTypeArgs
            ) {
                return resultType
            }

            // General member function lookup via implicit receiver
            var memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: nonNullReceiver,
                sema: sema,
                interner: interner
            )
            if interner.resolve(calleeName) == "toList" {
                memberCandidates = preferCollectionToListCandidates(
                    memberCandidates,
                    receiverType: nonNullReceiver,
                    sema: sema,
                    interner: interner
                )
            }
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
                    expectedType: overloadResolutionExpectedType(from: expectedType, sema: sema),
                    implicitReceiverType: receiverType,
                    ctx: ctx.semaCtx
                )
                if let chosen = resolved.chosenCallee {
                    let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    markCoroutineScopeImplicitReceiverCallIfNeeded(
                        id,
                        chosenCallee: chosen,
                        receiverType: receiverType,
                        ctx: ctx
                    )
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                } else if memberCandidates.count == 1,
                          let bestCandidate = memberCandidates.first,
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
            if let fallbackType = tryBindImplicitReceiverSyntheticExtensionCall(
                id, calleeName: calleeName, receiverType: nonNullReceiver, args: args,
                range: range, ctx: ctx, locals: &locals, expectedType: expectedType,
                explicitTypeArgs: explicitTypeArgs
            ) { return fallbackType }
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

    /// Build `List<elementType>` for synthetic stdlib member-call inference.
    /// Falls back to `Any` when `kotlin.collections.List` is not registered.

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

    /// True when `candidate` is the stdlib `kotlin.context` / `kotlin.contextOf`
    /// intrinsic declaration (KSP-603: bundled Kotlin source, previously a
    /// synthetic stub).
    private func isStdlibContextHelper(
        _ candidate: SymbolID,
        named name: String,
        ctx: TypeInferenceContext,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = ctx.cachedSymbol(candidate) else { return false }
        return symbol.fqName.map { interner.resolve($0) } == ["kotlin", name]
    }

    /// True when `candidate` is a non-stdlib declaration that is applicable to the
    /// call, so it takes precedence over the `context` / `contextOf` intrinsic
    /// handling. Declarations with a different arity — or without the type
    /// parameters the call spells out explicitly — are not applicable and leave
    /// the intrinsic path in charge.
    private func shadowsStdlibContextHelper(
        _ candidate: SymbolID,
        named name: String,
        argumentCount: Int,
        explicitTypeArgumentCount: Int,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard !isStdlibContextHelper(candidate, named: name, ctx: ctx, interner: interner) else {
            return false
        }
        guard let signature = sema.symbols.functionSignature(for: candidate) else {
            return true
        }
        return signature.parameterTypes.count == argumentCount
            && (explicitTypeArgumentCount == 0
                || signature.typeParameterSymbols.count == explicitTypeArgumentCount)
    }
}

// swiftlint:enable type_body_length
