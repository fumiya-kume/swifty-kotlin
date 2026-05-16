import Foundation

/// Main member-call dispatcher.
///
/// Specialized lowering families live in adjacent `CallLowerer+*MemberCall*.swift` files.
extension CallLowerer {
    func lowerMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        driver: KIRLoweringDriver,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let propertyConstantInitializers = shared.propertyConstantInitializers

        if let lateinitStatus = tryLowerLateinitIsInitialized(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return lateinitStatus
        }

        // ── KProperty<*>.name → kk_kproperty_stub_name(receiver) ────────
        if let kPropertyResult = tryLowerKPropertyMemberAccess(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return kPropertyResult
        }

        // ── KFunction<*>.name/returnType/parameters/... → kk_kfunction_get_*(receiver) ──
        if let kFunctionResult = tryLowerKFunctionMemberAccess(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return kFunctionResult
        }

        // ── KFunction<*>.call(...) → kk_kfunction_call_N(receiver, args...) ──
        if let kFunctionCallResult = tryLowerKFunctionCallInvocation(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return kFunctionCallResult
        }

        let callee = interner.resolve(calleeName)
        let isFlowReceiver = if sema.bindings.isFlowExpr(receiverExpr) {
            true
        } else if sema.bindings.flowElementType(forExpr: receiverExpr) != nil {
            true
        } else if case .nameRef = ast.arena.expr(receiverExpr),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverExpr),
                  sema.bindings.flowElementType(forSymbol: receiverSymbol) != nil
        {
            true
        } else {
            false
        }
        if isFlowReceiver {
            if callee == "transform", args.count == 1 {
                let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
                let result = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boundType
                )
                let loweredReceiver = driver.lowerExpr(
                    receiverExpr,
                    shared: shared,
                    emit: &instructions
                )
                let loweredLambda = driver.lowerExpr(
                    args[0].expr,
                    shared: shared,
                    emit: &instructions
                )
                // RuntimeFlowTag.transform = 11
                let transformTag: Int64 = 11
                let tagExpr = arena.appendExpr(.intLiteral(transformTag), type: sema.types.intType)
                instructions.append(.constValue(result: tagExpr, value: .intLiteral(transformTag)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_flow_emit"),
                    arguments: [loweredReceiver, loweredLambda, tagExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if callee == "single", args.isEmpty {
                let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
                let result = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boundType
                )
                let loweredReceiver = driver.lowerExpr(
                    receiverExpr,
                    shared: shared,
                    emit: &instructions
                )
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_flow_single"),
                    arguments: [loweredReceiver, zeroExpr],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // `CoroutineContext.cancel()` is a context-wide cancellation entrypoint
        // and must lower directly to the dedicated runtime ABI.
        if callee == "cancel",
           let receiverType = sema.bindings.exprTypes[receiverExpr],
           isCoroutineContextReceiverType(receiverType, sema: sema, interner: interner)
        {
            let receiverID = driver.lowerExpr(
                receiverExpr,
                shared: shared,
                emit: &instructions
            )
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.unitType
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: resultType
            )
            let loweredArgs: [KIRExprID]
            switch args.count {
            case 0:
                loweredArgs = []
            case 1:
                loweredArgs = [
                    driver.lowerExpr(
                        args[0].expr,
                        shared: shared,
                        emit: &instructions
                    ),
                ]
            default:
                loweredArgs = []
            }
            let runtimeCallee = interner.intern(args.isEmpty ? "kk_context_cancel_no_cause" : "kk_context_cancel")
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [receiverID] + loweredArgs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // ── T::class.simpleName / T::class.qualifiedName ──────────────
        if case let .callableRef(classRefReceiver, refMember, _) = ast.arena.expr(receiverExpr),
           refMember == KnownCompilerNames(interner: interner).className,
           let classRefTargetType = sema.bindings.classRefTargetType(for: receiverExpr)
        {
            let callee = interner.resolve(calleeName)
            if callee == "simpleName" || callee == "qualifiedName" {
                return lowerClassRefPropertyAccess(
                    exprID,
                    classRefExprID: receiverExpr,
                    classRefReceiver: classRefReceiver,
                    classRefTargetType: classRefTargetType,
                    propertyName: callee,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions.instructions
                )
            }
            // REFL-005: KClass.isInstance(value), members, constructors
            // STDLIB-REFLECT-061: properties, memberProperties, functions, memberFunctions, declaredMemberProperties, declaredMemberFunctions
            // STDLIB-REFLECT-060 / STDLIB-REFLECT-064: basic metadata and primaryConstructor
            // STDLIB-REFLECT-065: annotations, findAnnotation
            let kclassCallees: Set<String> = [
                "isInstance", "cast", "safeCast", "members", "constructors", "primaryConstructor",
                "properties", "memberProperties", "declaredMemberProperties",
                "functions", "memberFunctions", "declaredMemberFunctions",
                "isFinal", "isOpen", "isAbstract", "visibility",
                "typeParameters", "supertypes",
                "annotations", "findAnnotation", "findAssociatedObject",
            ]
            if kclassCallees.contains(callee) {
                return lowerKClassReflectMemberCall(
                    exprID,
                    classRefTargetType: classRefTargetType,
                    memberName: callee,
                    args: args,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions.instructions
                )
            }
        }

        // REFL-005: KClass-typed variable receiver — dogClass.isInstance(dog) / dogClass.members / dogClass.constructors
        // STDLIB-REFLECT-061: properties, memberProperties, functions, memberFunctions, declaredMemberProperties, declaredMemberFunctions
        // STDLIB-REFLECT-060 / STDLIB-REFLECT-064: basic metadata and primaryConstructor
        // STDLIB-REFLECT-065: annotations, findAnnotation
        if let receiverType = sema.bindings.exprTypes[receiverExpr],
           case .kClassType = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        {
            let callee = interner.resolve(calleeName)
            let kclassVarCallees: Set<String> = [
                "isInstance", "cast", "safeCast", "members", "constructors", "primaryConstructor",
                "properties", "memberProperties", "declaredMemberProperties",
                "functions", "memberFunctions", "declaredMemberFunctions",
                "isFinal", "isOpen", "isAbstract", "visibility",
                "typeParameters", "supertypes",
                "annotations", "findAnnotation", "findAssociatedObject",
            ]
            if kclassVarCallees.contains(callee) {
                return lowerKClassVarReflectMemberCall(
                    exprID,
                    receiverExpr: receiverExpr,
                    memberName: callee,
                    args: args,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions.instructions
                )
            }
        }

        // --- takeIf / takeUnless (STDLIB-160) ---
        if let takeResult = tryTakeIfTakeUnlessLowering(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return takeResult
        }

        // --- Scope functions: let, run, apply, also (STDLIB-004) ---
        if let scopeResult = tryScopeFunctionLowering(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return scopeResult
        }

        // Receiver-lambda invocation: `receiver.localVar()` where localVar has
        // a function-with-receiver type (e.g. `sb.action()` with action: StringBuilder.() -> Unit).
        // Some frontends may also encode the receiver as the first parameter of a regular
        // function type (`(StringBuilder) -> Unit`), so we mirror the type-checker
        // fallback here when needed.
        if let callableBinding = sema.bindings.callableValueCalls[exprID],
           case let .functionType(fnType) = sema.types.kind(of: callableBinding.functionType),
           case let .localValue(localSym) = callableBinding.target,
           let receiverExprType = sema.bindings.exprType(for: receiverExpr) {
            let maybeReceiverFnType: (FunctionType, Bool)
            if fnType.receiver != nil {
                maybeReceiverFnType = (fnType, fnType.params.count == args.count)
            } else if !fnType.params.isEmpty && args.count == fnType.params.count - 1 {
                let syntheticReceiverType = fnType.params[0]
                let syntheticFunction = FunctionType(
                    receiver: syntheticReceiverType,
                    params: Array(fnType.params.dropFirst()),
                    returnType: fnType.returnType,
                    isSuspend: fnType.isSuspend,
                    nullability: fnType.nullability
                )
                maybeReceiverFnType = (syntheticFunction, true)
            } else {
                maybeReceiverFnType = (FunctionType(
                    params: fnType.params,
                    returnType: fnType.returnType,
                    isSuspend: fnType.isSuspend,
                    nullability: fnType.nullability
                ), false)
            }
            if maybeReceiverFnType.1,
               let receiverType = maybeReceiverFnType.0.receiver,
               sema.types.isSubtype(
                   sema.types.makeNonNullable(receiverExprType),
                   receiverType
               )
            {
                let effectiveFnType = maybeReceiverFnType.0
                let boundType = sema.bindings.exprTypes[exprID] ?? effectiveFnType.returnType
                let loweredReceiver = driver.lowerExpr(receiverExpr, shared: shared, emit: &instructions)
                let loweredArgIDs = args.map { argument in
                    driver.lowerExpr(argument.expr, shared: shared, emit: &instructions)
                }
                let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
                if let localExprID = driver.ctx.localValue(for: localSym),
                   let info = driver.ctx.callableValueInfo(for: localExprID)
                {
                    var allArgs = info.captureArguments
                    allArgs.append(loweredReceiver)
                    allArgs.append(contentsOf: loweredArgIDs)
                    instructions.append(.call(
                        symbol: info.symbol,
                        callee: info.callee,
                        arguments: allArgs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    let allArgs = [loweredReceiver] + loweredArgIDs
                    instructions.append(.call(
                        symbol: localSym,
                        callee: calleeName,
                        arguments: allArgs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                return result
            }
        }

        let effectiveCalleeName = if sema.bindings.isInvokeOperatorCall(exprID) {
            interner.intern("invoke")
        } else {
            calleeName
        }
        if let objProp = tryLowerObjectMemberPropertyRead(
            exprID, args: args, sema: sema, arena: arena, interner: interner,
            instructions: &instructions.instructions
        ) { return objProp }
        return lowerMemberLikeCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: effectiveCalleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            requireNonNullableReceiverForConstFold: false,
            prependReceiverForUnresolvedCollectionCall: true,
            instructions: &instructions.instructions
        )
    }
}
