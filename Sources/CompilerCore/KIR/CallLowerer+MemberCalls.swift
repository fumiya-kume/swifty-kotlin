// swiftlint:disable file_length
import Foundation

struct MemberCallReceiver {
    let expr: ExprID
    let loweredID: KIRExprID
}

extension CallLowerer {
    static let unresolvedCoroutineHandleMemberNames: Set<String> = [
        "await", "join", "awaitCompletion",
        "cancel", "complete", "completeExceptionally",
        "isActive", "isCompleted", "isCancelled"
    ]
    private static let unresolvedChannelMemberNames: Set<String> = ["send", "receive", "close", "isClosedForReceive", "isClosedForSend"]

    private enum PrimitiveCompareABIKind: Int32 {
        case int = 0
        case long = 1
        case uint = 2
        case ulong = 3
        case boolean = 4
        case char = 5
        case float = 6
        case double = 7
    }

    private func primitiveCompareABIKind(for type: TypeID, sema: SemaModule) -> PrimitiveCompareABIKind? {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.int, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return .int
        case .primitive(.long, _):
            return .long
        case .primitive(.uint, _):
            return .uint
        case .primitive(.ulong, _):
            return .ulong
        case .primitive(.boolean, _):
            return .boolean
        case .primitive(.char, _):
            return .char
        case .primitive(.float, _):
            return .float
        case .primitive(.double, _):
            return .double
        default:
            return nil
        }
    }

    func anyFallbackTag(for type: TypeID, sema: SemaModule) -> Int64 {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.boolean, _):
            2
        case .primitive(.string, _):
            3
        case .primitive(.char, _):
            4
        case .primitive(.float, _):
            5
        case .primitive(.double, _):
            6
        default:
            1
        }
    }

    private func isCoroutineHandleReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isCoroutineHandleSymbol(symbol)
    }

    private func isChannelReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isChannelSymbol(symbol)
    }

    func isCoroutineContextReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        guard interner.resolve(symbol.name) == "CoroutineContext" else {
            return false
        }
        let kotlinxCoroutinesPkg: [InternedString] = [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
        ]
        let kotlinCoroutinesPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
        ]
        return symbol.fqName.starts(with: kotlinxCoroutinesPkg)
            || symbol.fqName.starts(with: kotlinCoroutinesPkg)
    }

    private func wrapLateinitReadIfNeeded(
        _ valueExpr: KIRExprID,
        symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let symbolInfo = sema.symbols.symbol(symbol),
              symbolInfo.flags.contains(.lateinitProperty)
        else {
            return valueExpr
        }
        let propertyNameExpr = arena.appendExpr(
            .stringLiteral(symbolInfo.name),
            type: sema.types.make(.primitive(.string, .nonNull))
        )
        instructions.append(.constValue(result: propertyNameExpr, value: .stringLiteral(symbolInfo.name)))
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: arena.exprType(valueExpr) ?? sema.types.anyType
        )
        let thrownResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: sema.types.nullableAnyType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_lateinit_get_or_throw"),
            arguments: [valueExpr, propertyNameExpr],
            result: result,
            canThrow: true,
            thrownResult: thrownResult
        ))
        return result
    }

    private static let unresolvedCollectionMemberNames: Set<String> = [
        "size", "get", "contains", "containsAll", "containsKey", "containsValue",
        "isEmpty", "first", "last", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast",
        "count", "iterator",
        "map", "filter", "filterNot", "mapNotNull", "mapIndexedNotNullTo", "firstNotNullOf", "firstNotNullOfOrNull", "filterNotNull", "requireNoNulls", "forEach", "flatMap",
        "any", "none", "all",
        "fold", "foldIndexed", "foldRight", "foldRightIndexed",
        "reduce", "reduceRight", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "reduceIndexed", "reduceIndexedOrNull",
        "scan", "scanIndexed", "runningFold", "runningFoldIndexed",
        "runningReduce", "runningReduceIndexed",
        "groupBy", "groupingBy", "sortedBy", "find", "findLast", "associateBy", "associateWith", "associate", "zip", "zipWithNext", "unzip",
        "eachCount", "eachCountTo", "aggregate", "aggregateTo",
        "withIndex", "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues",
        "getValue", "getOrDefault", "getOrElse", "getOrPut", "getOrNull", "elementAtOrNull", "elementAt", "elementAtOrElse",
        "putAll", "addAll",
        "maxBy", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull", "maxOrNull", "minOrNull",
        "plus", "plusElement", "minus", "minusElement",
        "asSequence", "asIterable", "toList", "toSet", "toMap", "toCollection", "toMutableList", "toMutableSet", "toTypedArray",
        "toBooleanArray", "toShortArray", "toDoubleArray", "toFloatArray", "toIntArray", "toLongArray", "toByteArray", "toUByteArray", "toUShortArray", "toUIntArray", "toULongArray",
        "take", "takeLast", "drop", "reversed", "asReversed", "sorted", "distinct", "flatten", "chunked", "windowed", "collect", "subList",
        "sortedDescending", "sortedByDescending", "sortedWith", "partition",
        "sortedArrayWith",
        "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
        "maxOf", "minOf",
        "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
        "replaceFirstChar",
        "sort", "sortWith", "sortBy", "sortByDescending",
        "onEach", "onEachIndexed",
        "copyOf", "copyOfRange", "fill", "replaceAll", "removeIf",
        "firstOrNull", "lastOrNull", "singleOrNull",
        "addAll", "removeAll", "retainAll",
        "intersect", "union", "subtract",
        "toHashSet",
        "containsAll", "binarySearch", "average",
        "addFirst", "addLast",
        "sum", "sumOf", "sumBy", "sumByDouble",
        "to", // FUNC-002
    ]

    // MARK: - KProperty member access lowering (PROP-007)

    /// Checks if the receiver type is a `kotlin.reflect.KProperty` (or related reflect interface)
    /// and the callee is a known property like `name`, and if so emits the runtime call.
    private func isKPropertyReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let resolvedName = interner.resolve(symbol.name)
        return resolvedName == "KProperty" || resolvedName == "KProperty0"
            || resolvedName == "KProperty1" || resolvedName == "KCallable"
            || resolvedName == "KMutableProperty" || resolvedName == "KMutableProperty0"
            || resolvedName == "KMutableProperty1"
    }

    private func tryLowerKPropertyMemberAccess(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard calleeStr == "name" else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKPropertyReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        // Lower the receiver expression.
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID]
            ?? sema.types.make(.primitive(.string, .nonNull))
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: resultType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kproperty_stub_name"),
            arguments: [receiverID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    // MARK: - KFunction member access lowering (STDLIB-REFLECT-063)

    /// Checks if the receiver type is a `kotlin.reflect.KFunction` (or related reflect interface)
    /// so that member accesses like `.name`, `.returnType`, `.parameters`, `.isSuspend` can be lowered.
    private func isKFunctionReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        // Check for KFunction class types.
        if case let .classType(classType) = sema.types.kind(of: nonNullType),
           let symbol = sema.symbols.symbol(classType.classSymbol)
        {
            let resolvedName = interner.resolve(symbol.name)
            return resolvedName == "KFunction" || resolvedName == "KFunction0"
                || resolvedName == "KFunction1" || resolvedName == "KFunction2"
                || resolvedName == "KFunction3" || resolvedName == "KCallable"
        }
        // Also check function types — callable references (`::foo`) have function types
        // but are tagged as KFunction at runtime.
        if case .functionType = sema.types.kind(of: nonNullType) {
            return false // Plain function types are not KFunction; only tagged callable refs are.
        }
        return false
    }

    /// Known KFunction member names and their corresponding runtime function.
    private static let kFunctionMemberMap: [String: String] = [
        "name": "kk_kfunction_get_name",
        "returnType": "kk_kfunction_get_return_type",
        "parameters": "kk_kfunction_get_parameters",
        "valueParameters": "kk_kfunction_get_value_parameters",
        "isSuspend": "kk_kfunction_is_suspend",
        "type": "kk_kfunction_get_type",
    ]

    private func tryLowerKFunctionMemberAccess(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard let runtimeFunc = Self.kFunctionMemberMap[calleeStr] else { return nil }

        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKFunctionReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        // Lower the receiver expression.
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: resultType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeFunc),
            arguments: [receiverID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    /// Lowers KFunction.call() with arguments to the appropriate arity-specific runtime call.
    private func tryLowerKFunctionCallInvocation(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard calleeStr == "call" else { return nil }

        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKFunctionReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        // Lower the receiver expression (the KFunction handle).
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // Lower all arguments.
        var argExprs: [KIRExprID] = []
        for arg in args {
            let argExpr = driver.exprLowerer.lowerExpr(
                arg.expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            argExprs.append(argExpr)
        }

        // Choose the appropriate arity-specific call.
        let callCallee: String
        switch argExprs.count {
        case 0: callCallee = "kk_kfunction_call_0"
        case 1: callCallee = "kk_kfunction_call_1"
        case 2: callCallee = "kk_kfunction_call_2"
        case 3: callCallee = "kk_kfunction_call_3"
        default: callCallee = "kk_kfunction_call_vararg"
        }

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType

        if argExprs.count <= 3 {
            // Direct arity-specific call: kk_kfunction_call_N(handle, arg1, ..., outThrown)
            let thrownResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.nullableAnyType
            )
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: resultType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(callCallee),
                arguments: [receiverID] + argExprs,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return result
        } else {
            // Vararg path: pack args into a list, call kk_kfunction_call_vararg.
            // First, create a runtime list with the args.
            let listExpr = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_list_of"),
                arguments: argExprs,
                result: listExpr,
                canThrow: false,
                thrownResult: nil
            ))
            let thrownResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.nullableAnyType
            )
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: resultType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(callCallee),
                arguments: [receiverID, listExpr],
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return result
        }
    }

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

    func lowerSafeMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
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
            instructions: &instructions
        ) {
            return lateinitStatus
        }

        // --- takeIf / takeUnless with safe call (STDLIB-160) ---
        if sema.bindings.takeIfTakeUnlessKind(for: exprID) != nil {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
            )
            let loweredReceiver = driver.lowerExpr(
                receiverExpr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfNotNull(value: loweredReceiver, target: nonNullLabel))
            let nullVal = arena.appendExpr(.unit, type: boundType)
            instructions.append(.constValue(result: nullVal, value: .null))
            instructions.append(.copy(from: nullVal, to: result))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nonNullLabel))
            if let takeResult = tryTakeIfTakeUnlessLowering(
                exprID,
                receiverExpr: receiverExpr,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions,
                precomputedReceiver: loweredReceiver
            ) {
                instructions.append(.copy(from: takeResult, to: result))
            }
            instructions.append(.label(endLabel))
            return result
        }

        // --- Scope functions with safe call: ?.let, ?.run, etc. (STDLIB-004) ---
        // For safe-call (?.let etc.), we need a null guard: if receiver is null,
        // skip the lambda and produce null; otherwise invoke normally.
        if sema.bindings.scopeFunctionKind(for: exprID) != nil {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nullableResultType = sema.types.makeNullable(boundType)
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: nullableResultType
            )
            // Lower receiver first for null check
            let loweredReceiver = driver.lowerExpr(
                receiverExpr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            // Jump to nonNullLabel if receiver is not null
            instructions.append(.jumpIfNotNull(value: loweredReceiver, target: nonNullLabel))
            // Null path: produce null result
            let nullVal = arena.appendExpr(.unit, type: nullableResultType)
            instructions.append(.constValue(result: nullVal, value: .null))
            instructions.append(.copy(from: nullVal, to: result))
            instructions.append(.jump(endLabel))
            // Non-null path: invoke the scope function
            instructions.append(.label(nonNullLabel))
            if let scopeResult = tryScopeFunctionLowering(
                exprID,
                receiverExpr: receiverExpr,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions,
                precomputedReceiver: loweredReceiver
            ) {
                instructions.append(.copy(from: scopeResult, to: result))
            }
            instructions.append(.label(endLabel))
            return result
        }

        let effectiveCalleeName = if sema.bindings.isInvokeOperatorCall(exprID) {
            interner.intern("invoke")
        } else {
            calleeName
        }
        let safeReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullSafeReceiverType = sema.types.makeNonNullable(safeReceiverType)
        let safeBooleanCallee = interner.resolve(effectiveCalleeName)
        if sema.types.isSubtype(nonNullSafeReceiverType, sema.types.booleanType) {
            let boolRuntimeCallee: InternedString? = switch safeBooleanCallee {
            case "not" where args.isEmpty:
                interner.intern("kk_op_not")
            case "and" where args.count == 1:
                interner.intern("kk_bitwise_and")
            case "or" where args.count == 1:
                interner.intern("kk_bitwise_or")
            case "xor" where args.count == 1:
                interner.intern("kk_bitwise_xor")
            default:
                nil
            }
            if let boolRuntimeCallee {
                let boundType = sema.types.makeNullable(sema.types.booleanType)
                let result = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boundType
                )
                let loweredReceiver = driver.lowerExpr(
                    receiverExpr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let nonNullLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiver, target: nonNullLabel))
                let nullVal = arena.appendExpr(.unit, type: boundType)
                instructions.append(.constValue(result: nullVal, value: .null))
                instructions.append(.copy(from: nullVal, to: result))
                instructions.append(.jump(endLabel))
                instructions.append(.label(nonNullLabel))
                let nonNullResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.booleanType)
                let loweredArgIDs = args.map { argument in
                    driver.lowerExpr(
                        argument.expr,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                }
                let callArguments = [loweredReceiver] + loweredArgIDs
                instructions.append(.call(
                    symbol: nil,
                    callee: boolRuntimeCallee,
                    arguments: callArguments,
                    result: nonNullResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                instructions.append(.copy(from: nonNullResult, to: result))
                instructions.append(.label(endLabel))
                return result
            }
        }

        // Int/Long/Double/Float.coerceIn(range) safe-call: null guard + range decomposition (STDLIB-525, STDLIB-CONV-006)
        // The generic lowerMemberLikeCallExpr path does not emit a null guard for
        // safe-call receivers, so we must handle coerceIn(range) here.
        if args.count == 1, interner.resolve(effectiveCalleeName) == "coerceIn" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                let argExprID = args[0].expr
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if let rangeElementType = coerceInRangeElementType(
                    for: argExprID,
                    sema: sema,
                    interner: interner
                ),
                rangeElementType == nonNullReceiverType
                {
                    let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.nullableAnyType
                    let result = arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: boundType
                    )
                    let loweredReceiver = driver.lowerExpr(
                        receiverExpr,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    let loweredRangeArg = driver.lowerExpr(
                        argExprID,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    let callLabel = driver.ctx.makeLoopLabel()
                    let endLabel = driver.ctx.makeLoopLabel()
                    instructions.append(.jumpIfNotNull(value: loweredReceiver, target: callLabel))
                    let nullExpr = arena.appendExpr(.null, type: boundType)
                    instructions.append(.constValue(result: nullExpr, value: .null))
                    instructions.append(.copy(from: nullExpr, to: result))
                    instructions.append(.jump(endLabel))
                    instructions.append(.label(callLabel))
                    emitCoerceInRange(
                        prefix: prefix,
                        receiverType: receiverType,
                        loweredReceiverID: loweredReceiver,
                        loweredRangeArgID: loweredRangeArg,
                        result: result,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    instructions.append(.label(endLabel))
                    return result
                }
            }
        }

        // Int/Long/Double/Float.coerceIn(min, max) safe-call: null guard (STDLIB-150, STDLIB-500)
        if args.count == 2, interner.resolve(effectiveCalleeName) == "coerceIn" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.nullableAnyType
                let result = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boundType
                )
                let loweredReceiver = driver.lowerExpr(
                    receiverExpr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let loweredArgIDs = args.map { argument in
                    driver.lowerExpr(
                        argument.expr,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                }
                let callLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiver, target: callLabel))
                let nullExpr = arena.appendExpr(.null, type: boundType)
                instructions.append(.constValue(result: nullExpr, value: .null))
                instructions.append(.copy(from: nullExpr, to: result))
                instructions.append(.jump(endLabel))
                instructions.append(.label(callLabel))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(prefix + "_coerceIn"),
                    arguments: [loweredReceiver, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                instructions.append(.label(endLabel))
                return result
            }
        }

        // General safe-call: emit null guard around the member call so that
        // when the receiver is null the entire expression short-circuits to null.
        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.nullableAnyType
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: boundType
        )
        let loweredReceiver = driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let callLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        instructions.append(.jumpIfNotNull(value: loweredReceiver, target: callLabel))
        let nullExpr = arena.appendExpr(.null, type: boundType)
        instructions.append(.constValue(result: nullExpr, value: .null))
        instructions.append(.copy(from: nullExpr, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(callLabel))
        let innerResult = lowerMemberLikeCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: effectiveCalleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            requireNonNullableReceiverForConstFold: true,
            prependReceiverForUnresolvedCollectionCall: false,
            instructions: &instructions
        )
        instructions.append(.copy(from: innerResult, to: result))
        instructions.append(.label(endLabel))
        return result
    }

    private func tryLowerLateinitIsInitialized(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers _: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              calleeName == KnownCompilerNames(interner: interner).isInitialized,
              case .callableRef = ast.arena.expr(receiverExpr),
              let propertySymbol = sema.bindings.identifierSymbol(for: receiverExpr),
              let propertyInfo = sema.symbols.symbol(propertySymbol),
              propertyInfo.kind == .property,
              propertyInfo.flags.contains(.lateinitProperty)
        else {
            return nil
        }

        let storageExpr: KIRExprID
        if let parentSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let parentInfo = sema.symbols.symbol(parentSymbol),
           parentInfo.kind != .package,
           parentInfo.kind != .object
        {
            guard let receiverExpr = driver.ctx.activeImplicitReceiverExprID(),
                  let fieldOffset = sema.symbols.nominalLayout(for: parentSymbol)?.fieldOffsets[
                      sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
                  ]
            else {
                return nil
            }
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let loaded = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: propertyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExpr, offsetExpr],
                result: loaded,
                canThrow: false,
                thrownResult: nil
            ))
            storageExpr = loaded
        } else {
            let storageSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            let storageType = sema.symbols.propertyType(for: storageSymbol)
                ?? sema.symbols.propertyType(for: propertySymbol)
                ?? sema.types.anyType
            let loaded = arena.appendExpr(.symbolRef(storageSymbol), type: storageType)
            instructions.append(.loadGlobal(result: loaded, symbol: storageSymbol))
            storageExpr = loaded
        }

        let resultType = sema.bindings.exprType(for: exprID)
            ?? sema.types.make(.primitive(.boolean, .nonNull))
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_lateinit_is_initialized"),
            arguments: [storageExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    private func isRegexLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isRegexSymbol(symbol)
    }

    private func isStringBuilderLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isStringBuilderSymbol(symbol)
    }

    /// Check whether a type is Sequence-like (for member-call and operator
    /// lowering decisions).  Shared across `CallLowerer+MemberCalls` and
    /// `CallLowerer+Operators`; kept `internal` to avoid exposing it beyond
    /// the `CallLowerer` extensions.
    func isSequenceLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isSequenceSymbol(symbol)
    }

    private func isIterableOrCollectionInterfaceType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let symbolName = interner.resolve(symbol.name)
        return symbolName == "Iterable" || symbolName == "Collection"
    }

    private func toMutableListRuntimeCalleeForSequenceOrIterableFallback(
        chosenCallee: SymbolID?,
        useIterableFallback: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        if useIterableFallback,
           let chosenCallee,
           let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
           externalLinkName == "kk_collection_toMutableList" || externalLinkName == "kk_iterable_toMutableList"
        {
            return interner.intern(externalLinkName)
        }
        return interner.intern(useIterableFallback ? "kk_iterable_toMutableList" : "kk_sequence_toMutableList")
    }

    private func isGroupingLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isGroupingSymbol(symbol)
    }

    func isConcreteListLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol)
    }

    private func collectionElementPrimitiveCompareKind(
        of receiverType: TypeID,
        sema: SemaModule
    ) -> PrimitiveCompareABIKind? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let firstArg = classType.args.first
        else {
            return nil
        }
        let elementType: TypeID = switch firstArg {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            sema.types.anyType
        }
        return primitiveCompareABIKind(for: elementType, sema: sema)
    }

    private func arraySizeRuntimeCallee(
        for receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return interner.intern("kk_array_size")
        }
        let knownNames = KnownCompilerNames(interner: interner)
        switch symbol.name {
        case knownNames.intArray:
            return interner.intern("kk_intArray_size")
        case knownNames.longArray:
            return interner.intern("kk_longArray_size")
        case knownNames.byteArray:
            return interner.intern("kk_byteArray_size")
        case knownNames.shortArray:
            return interner.intern("kk_shortArray_size")
        case knownNames.uintArray:
            return interner.intern("kk_uIntArray_size")
        case knownNames.ulongArray:
            return interner.intern("kk_uLongArray_size")
        case knownNames.doubleArray:
            return interner.intern("kk_doubleArray_size")
        case knownNames.floatArray:
            return interner.intern("kk_floatArray_size")
        case knownNames.booleanArray:
            return interner.intern("kk_booleanArray_size")
        case knownNames.charArray:
            return interner.intern("kk_charArray_size")
        case knownNames.ubyteArray:
            return interner.intern("kk_uByteArray_size")
        case knownNames.ushortArray:
            return interner.intern("kk_uShortArray_size")
        default:
            return interner.intern("kk_array_size")
        }
    }

    private func collectionSelectorPrimitiveCompareKind(
        of selectorExpr: ExprID?,
        sema: SemaModule
    ) -> PrimitiveCompareABIKind? {
        guard let selectorExpr,
              let selectorType = sema.bindings.exprTypes[selectorExpr]
        else {
            return nil
        }
        switch sema.types.kind(of: sema.types.makeNonNullable(selectorType)) {
        case let .functionType(functionType):
            return primitiveCompareABIKind(for: functionType.returnType, sema: sema)
        default:
            return nil
        }
    }

    private func isMutableListLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.name == knownNames.mutableList
            || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName
    }

    private func isMutableSetLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMutableSetSymbol(symbol)
    }

    private func isMapLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMapLikeSymbol(symbol)
    }

    private func isArrayDequeLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isArrayDequeSymbol(symbol)
    }

    private func isConcreteCollectionLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isCollectionLikeSymbol(symbol)
    }

    private func isConcreteArrayLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isArrayLikeName(symbol.name)
    }

    private func isGenericArrayLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.name == knownNames.array && classType.args.count == 1
    }

    private func arrayBinarySearchRuntimeName(
        for receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let runtimeName: String
        switch symbol.name {
        case knownNames.array: runtimeName = "kk_array_binarySearch"
        case knownNames.intArray: runtimeName = "kk_intArray_binarySearch"
        case knownNames.longArray: runtimeName = "kk_longArray_binarySearch"
        case knownNames.byteArray: runtimeName = "kk_byteArray_binarySearch"
        case knownNames.shortArray: runtimeName = "kk_shortArray_binarySearch"
        case knownNames.uintArray: runtimeName = "kk_uIntArray_binarySearch"
        case knownNames.ulongArray: runtimeName = "kk_uLongArray_binarySearch"
        case knownNames.doubleArray: runtimeName = "kk_doubleArray_binarySearch"
        case knownNames.floatArray: runtimeName = "kk_floatArray_binarySearch"
        case knownNames.booleanArray: runtimeName = "kk_booleanArray_binarySearch"
        case knownNames.charArray: runtimeName = "kk_charArray_binarySearch"
        case knownNames.ubyteArray: runtimeName = "kk_uByteArray_binarySearch"
        case knownNames.ushortArray: runtimeName = "kk_uShortArray_binarySearch"
        default: return nil
        }
        return interner.intern(runtimeName)
    }

    private func isArrayBinarySearchRuntimeCallee(
        _ callee: InternedString,
        interner: StringInterner
    ) -> Bool {
        let names = [
            "kk_array_binarySearch",
            "kk_intArray_binarySearch",
            "kk_longArray_binarySearch",
            "kk_byteArray_binarySearch",
            "kk_shortArray_binarySearch",
            "kk_uIntArray_binarySearch",
            "kk_uLongArray_binarySearch",
            "kk_doubleArray_binarySearch",
            "kk_floatArray_binarySearch",
            "kk_booleanArray_binarySearch",
            "kk_charArray_binarySearch",
            "kk_uByteArray_binarySearch",
            "kk_uShortArray_binarySearch",
        ]
        return names.contains { callee == interner.intern($0) }
    }

    private func isSetLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isSetLikeSymbol(symbol)
    }

    /// Returns `true` when the receiver type is `Iterable<Char>` (the type produced by `String.asIterable()`).
    /// This allows routing `.toList()` and `.iterator()` to the specialised string-iterable runtime functions.
    private func isStringIterableType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNull),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard symbol.fqName == iterableFQName else {
            return false
        }
        // Verify the type argument is Char
        guard let firstArg = classType.args.first else {
            return false
        }
        let elementType: TypeID = switch firstArg {
        case let .invariant(t), let .out(t), let .in(t): t
        case .star: sema.types.anyType
        }
        return sema.types.makeNonNullable(elementType) == sema.types.make(.primitive(.char, .nonNull))
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// This shared lowering path still centralizes legacy stdlib/member special cases.
    private func lowerMemberLikeCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        requireNonNullableReceiverForConstFold: Bool,
        prependReceiverForUnresolvedCollectionCall: Bool,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // swiftlint:enable cyclomatic_complexity function_body_length
        if let foldedConst = tryFoldConstMemberProperty(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            requireNonNullableReceiver: requireNonNullableReceiverForConstFold,
            sema: sema,
            arena: arena,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return foldedConst
        }
        if let constValue = sema.bindings.constExprValue(for: exprID) {
            let constResult = arena.appendExpr(
                constValue,
                type: sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            )
            instructions.append(.constValue(result: constResult, value: constValue))
            return constResult
        }
        if let staticMemberValue = tryLowerClassNameMemberValueExpr(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            instructions: &instructions
        ) {
            return staticMemberValue
        }

        let boundType = sema.bindings.exprTypes[exprID]
        let loweredReceiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let argInstructionStart = instructions.count
        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let normalizedArgIDs: [KIRExprID] = {
            guard isCollectionHOFCallee(calleeName, interner: interner) else {
                return loweredArgIDs
            }
            let closureAdapted = addCollectionHOFClosureArguments(
                loweredArgIDs: loweredArgIDs,
                argExprIDs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return adaptComparatorFactoryArgumentsForCollectionHOF(
                calleeName: calleeName,
                loweredArgIDs: closureAdapted,
                argExprIDs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        if args.count == 1,
           interner.resolve(calleeName) == "withDefault"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if isMapLikeType(receiverType, sema: sema, interner: interner) {
                let runtimeArguments: [KIRExprID]
                if normalizedArgIDs.count >= 2 {
                    runtimeArguments = [loweredReceiverID, normalizedArgIDs[0], normalizedArgIDs[1]]
                } else if let defaultValueArg = normalizedArgIDs.first {
                    let split = splitCallableLambdaArgument(
                        defaultValueArg,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    runtimeArguments = [loweredReceiverID, split.fnPtrExpr, split.envPtrExpr]
                } else {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    runtimeArguments = [loweredReceiverID, zeroExpr, zeroExpr]
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_map_withDefault"),
                    arguments: runtimeArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
        let chosenBase64Callee: SymbolID? = {
            guard let selected = sema.bindings.callBindings[exprID]?.chosenCallee, selected != .invalid else {
                return nil
            }
            return selected
        }()

        if tryLowerBase64MemberCall(
            receiverExpr: receiverExpr,
            loweredReceiverID: loweredReceiverID,
            calleeName: calleeName,
            chosenCallee: chosenBase64Callee,
            argExprIDs: args.map(\.expr),
            loweredArgIDs: loweredArgIDs,
            argInstructionStart: argInstructionStart,
            result: result,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return result
        }

        if args.count == 1,
           interner.resolve(calleeName) == "sortedWith"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let isComparatorLambdaArg = ast.arena.expr(args[0].expr)?.isLambdaOrCallableRef ?? false
            if isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner),
               !isComparatorLambdaArg
            {
                let sortedWithArguments = adaptComparatorBackedCollectionArguments(
                    loweredCallee: interner.intern("kk_list_sortedWith"),
                    finalArguments: [loweredReceiverID] + normalizedArgIDs,
                    sourceArgExprs: args.map(\.expr),
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_list_sortedWith"),
                    arguments: sortedWithArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                ))
                return result
            }
        }

        if args.count == 1,
           interner.resolve(calleeName) == "sortedArrayWith"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isGenericArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee = interner.intern("kk_array_sortedArrayWith")
                let sortedArrayWithArguments = adaptComparatorBackedCollectionArguments(
                    loweredCallee: runtimeCallee,
                    finalArguments: [loweredReceiverID] + normalizedArgIDs,
                    sourceArgExprs: args.map(\.expr),
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: sortedArrayWithArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                ))
                return result
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let runtimeCallee: InternedString? = switch interner.resolve(calleeName) {
            case "any":
                if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_array_any")
                } else if isSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_set_any")
                } else if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_list_any")
                } else {
                    nil
                }
            case "none":
                if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_array_none")
                } else if isSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_set_none")
                } else if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_list_none")
                } else {
                    nil
                }
            default:
                nil
            }
            if let runtimeCallee {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                instructions.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [loweredReceiverID, zeroExpr, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let isRangeLikeReceiver = sema.bindings.isRangeExpr(receiverExpr) || {
                guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    return false
                }
                let name = interner.resolve(symbol.name)
                return name == "IntProgression"
                    || name == "LongProgression"
                    || name == "LongRange"
                    || name == "CharProgression"
                    || name == "UIntRange"
                    || name == "UIntProgression"
                    || name == "ULongProgression"
            }()
            let isLongRange = nonNullReceiverType == sema.types.longType
            if isRangeLikeReceiver {
                let runtimeGetter: InternedString? = switch interner.resolve(calleeName) {
                case "start":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_first"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_first"
                            : (isLongRange ? "kk_long_range_first" : "kk_range_first")))
                case "end":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_last"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_last"
                            : (isLongRange ? "kk_long_range_last" : "kk_range_last")))
                case "endExclusive":
                    interner.intern("kk_range_endExclusive")
                case "first":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_first"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_first"
                            : (isLongRange ? "kk_long_range_first" : "kk_range_first")))
                case "last":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_last"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_last"
                            : (isLongRange ? "kk_long_range_last" : "kk_range_last")))
                case "step":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_step"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_step"
                            : (isLongRange ? "kk_long_range_step" : "kk_range_step")))
                default:
                    nil
                }
                if let runtimeGetter {
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeGetter,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        if let storedObjectProperty = tryLowerObjectLiteralStoredPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return storedObjectProperty
        }

        if let enumEntryProperty = tryLowerEnumEntryPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return enumEntryProperty
        }

        if let externalMemberProperty = tryLowerExternalMemberPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return externalMemberProperty
        }

        if let storedMemberProperty = tryLowerStoredMemberPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return storedMemberProperty
        }

        if args.isEmpty,
           calleeName == interner.intern("step")
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let runtimeCallee: InternedString = if sema.bindings.isULongRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.ulongType
            {
                interner.intern("kk_ulong_range_step")
            } else if sema.bindings.isUIntRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.uintType
            {
                interner.intern("kk_uint_range_step")
            } else {
                interner.intern("kk_range_step")
            }
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Primitive member function: Int/Long.inv() → kk_op_inv (P5-103)
        if calleeName == interner.intern("inv"),
           args.isEmpty,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_inv"),
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Int.countOneBits() / countLeadingZeroBits() / countTrailingZeroBits() (STDLIB-501)
        // STDLIB-BIT-007: Additional bit manipulation functions
        // NOTE: This bit-count lowering logic is intentionally duplicated in
        // CallLowerer+SafeMemberCalls.swift for the safe-call (?.) path.
        // If you change the callee-name -> runtime-name mapping here, update
        // the other file as well. Consider extracting a shared helper if the
        // number of bit-operation intrinsics grows further.
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "countOneBits" || calleeStr == "countLeadingZeroBits" || calleeStr == "countTrailingZeroBits" ||
               calleeStr == "highestOneBit" || calleeStr == "lowestOneBit" || calleeStr == "takeHighestOneBit" || calleeStr == "takeLowestOneBit" {
                let intType = sema.types.intType
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if nonNullReceiverType == intType {
                    let runtimeName: String
                    switch calleeStr {
                    case "countOneBits": runtimeName = "kk_int_countOneBits"
                    case "countLeadingZeroBits": runtimeName = "kk_int_countLeadingZeroBits"
                    case "countTrailingZeroBits": runtimeName = "kk_int_countTrailingZeroBits"
                    case "highestOneBit": runtimeName = "kk_int_highestOneBit"
                    case "lowestOneBit": runtimeName = "kk_int_lowestOneBit"
                    case "takeHighestOneBit": runtimeName = "kk_int_takeHighestOneBit"
                    case "takeLowestOneBit": runtimeName = "kk_int_takeLowestOneBit"
                    default: fatalError("unreachable: calleeStr already guarded to bit operation functions")
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Int.rotateLeft() / rotateRight() (STDLIB-BIT-007)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "rotateLeft" || calleeStr == "rotateRight" {
                let intType = sema.types.intType
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if nonNullReceiverType == intType {
                    let runtimeName: String
                    switch calleeStr {
                    case "rotateLeft": runtimeName = "kk_int_rotateLeft"
                    case "rotateRight": runtimeName = "kk_int_rotateRight"
                    default: fatalError("unreachable: calleeStr already guarded to rotate functions")
                    }
                    let loweredArgID = driver.lowerExpr(
                        args[0].expr,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeName),
                        arguments: [loweredReceiverID, loweredArgID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Long bit manipulation functions (STDLIB-BIT-007)
        let longType = sema.types.longType
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)

        if nonNullReceiverType == longType {
            let calleeStr = interner.resolve(calleeName)

            // Zero-argument functions
            if args.isEmpty {
                let runtimeName: String?
                switch calleeStr {
                case "highestOneBit": runtimeName = "kk_long_highestOneBit"
                case "lowestOneBit": runtimeName = "kk_long_lowestOneBit"
                case "takeHighestOneBit": runtimeName = "kk_long_takeHighestOneBit"
                case "takeLowestOneBit": runtimeName = "kk_long_takeLowestOneBit"
                default: runtimeName = nil
                }

                if let name = runtimeName {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(name),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }

            // Single-argument functions (rotate)
            if args.count == 1 {
                let runtimeName: String?
                switch calleeStr {
                case "rotateLeft": runtimeName = "kk_long_rotateLeft"
                case "rotateRight": runtimeName = "kk_long_rotateRight"
                default: runtimeName = nil
                }

                if let name = runtimeName {
                    let loweredArgID = driver.lowerExpr(
                        args[0].expr,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(name),
                        arguments: [loweredReceiverID, loweredArgID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Boolean.not() → kk_op_not (STDLIB-308)
        if calleeName == interner.intern("not"),
           args.isEmpty
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.booleanType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_not"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Boolean.and(other) / Boolean.or(other) / Boolean.xor(other) (STDLIB-308)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.booleanType) {
                let boolCallee: InternedString? = switch interner.resolve(calleeName) {
                case "and":
                    interner.intern("kk_bitwise_and")
                case "or":
                    interner.intern("kk_bitwise_or")
                case "xor":
                    interner.intern("kk_bitwise_xor")
                default:
                    nil
                }
                if let boolCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: boolCallee,
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Float.mod(other) / Double.mod(other): Kotlin mod uses floor-style
        // modulo, while rem/% use truncating remainder.
        if args.count == 1,
           interner.resolve(calleeName) == "mod"
        {
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let rhsType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rhsType)
            let isFloatingReceiver = nonNullReceiverType == floatType || nonNullReceiverType == doubleType
            let isFloatingRhs = nonNullRhsType == floatType || nonNullRhsType == doubleType
            if isFloatingReceiver, isFloatingRhs {
                let resultType = nonNullReceiverType == doubleType || nonNullRhsType == doubleType ? doubleType : floatType
                var lhs = loweredReceiverID
                var rhs = loweredArgIDs[0]
                if resultType == doubleType {
                    if nonNullReceiverType == floatType {
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: doubleType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_float_to_double_bits"),
                            arguments: [lhs],
                            result: converted,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        lhs = converted
                    }
                    if nonNullRhsType == floatType {
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: doubleType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_float_to_double_bits"),
                            arguments: [rhs],
                            result: converted,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        rhs = converted
                    }
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(resultType == doubleType ? "kk_op_dfloor_mod" : "kk_op_ffloor_mod"),
                    arguments: [lhs, rhs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Primitive arithmetic/infix member functions on numeric receivers.
        if args.count == 1,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let rawRhsType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rawRhsType)
            let isShiftReceiver = nonNullReceiverType == intType || nonNullReceiverType == longType || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
            let isUnsignedReceiver = nonNullReceiverType == uintType || nonNullReceiverType == ulongType || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
            let primitiveCallee: InternedString? = switch interner.resolve(calleeName) {
            case "plus":
                interner.intern("kk_op_add")
            case "minus":
                interner.intern("kk_op_sub")
            case "times":
                interner.intern("kk_op_mul")
            case "div":
                isUnsignedReceiver ? interner.intern("kk_op_udiv") : interner.intern("kk_op_div")
            case "floorDiv":
                isUnsignedReceiver ? interner.intern("kk_op_udiv") : interner.intern("kk_op_floor_div")
            case "rem":
                isUnsignedReceiver ? interner.intern("kk_op_urem") : interner.intern("kk_op_mod")
            case "mod":
                isUnsignedReceiver
                    ? interner.intern("kk_op_urem")
                    : interner.intern(nonNullReceiverType == longType || nonNullRhsType == longType ? "kk_op_lfloor_mod" : "kk_op_floor_mod")
            case "and":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_and") : nil
            case "or":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_or") : nil
            case "xor":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_xor") : nil
            case "shl":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shl") : nil
            case "shr":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shr") : nil
            case "ushr":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_ushr") : nil
            default:
                nil
            }
            if let primitiveCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: primitiveCallee,
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Int/Long/Byte/Short/UByte/UShort/UInt/ULong.coerceIn(min, max) (STDLIB-150, STDLIB-500)
        if interner.resolve(calleeName) == "coerceIn", args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(prefix + "_coerceIn"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Int/Long/UInt/ULong.coerceIn(range) — single ClosedRange argument (STDLIB-525, STDLIB-CONV-006)
        // Decompose the range into first/last and delegate to kk_{int,long,uint,ulong}_coerceIn.
        // The shared emitCoerceInRange helper types the extracted bounds as the non-nullable
        // receiver type and kk_range_first/kk_range_last return the range's element type.
        if interner.resolve(calleeName) == "coerceIn", args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let intType = sema.types.intType
            let longType = sema.types.longType
            let uintType = sema.types.uintType
            let ulongType = sema.types.ulongType
            let supportsRangeCoercion = receiverType == intType || receiverType == longType
                || receiverType == uintType || receiverType == ulongType
            if supportsRangeCoercion,
               let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                let argExprID = args[0].expr
                let argType = sema.bindings.exprTypes[argExprID] ?? sema.types.anyType
                if sema.bindings.isRangeExpr(argExprID)
                    || nominalRangeElementType(for: argType, sema: sema, interner: interner) != nil
                {
                    emitCoerceInRange(
                        prefix: prefix,
                        receiverType: receiverType,
                        loweredReceiverID: loweredReceiverID,
                        loweredRangeArgID: loweredArgIDs[0],
                        result: result,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return result
                }
            }
        }

        // Int/Long/Double/Float/Byte/Short/UByte/UShort/UInt/ULong.coerceAtLeast(min)
        // / coerceAtMost(max) (STDLIB-150, STDLIB-500)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "coerceAtLeast" || calleeStr == "coerceAtMost" {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                    // Check if this is range-based coercion (single range argument)
                    if args.count == 1 {
                        let argExprID = args[0].expr
                        if sema.bindings.isRangeExpr(argExprID) {
                            // Use range-based coercion functions
                            let suffix = calleeStr == "coerceAtLeast" ? "_coerceAtLeast_range" : "_coerceAtMost_range"
                            instructions.append(.call(
                                symbol: nil,
                                callee: interner.intern(prefix + suffix),
                                arguments: [loweredReceiverID, loweredArgIDs[0]],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            return result
                        }
                    }
                    // Fallback to single-value coercion
                    let suffix = calleeStr == "coerceAtLeast" ? "_coerceAtLeast" : "_coerceAtMost"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(prefix + suffix),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Primitive member function: Int/Long.toString() → kk_any_to_string
        // and Int/Long.toString(radix: Int) → kk_int_toString_radix (EXPR-003)
        if calleeName == interner.intern("toString"),
           args.count <= 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                if args.isEmpty {
                    let tagID = arena.appendExpr(.intLiteral(1), type: intType)
                    instructions.append(.constValue(result: tagID, value: .intLiteral(1)))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_any_to_string"),
                        arguments: [loweredReceiverID, tagID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_int_toString_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                return result
            }
        }

        let anyFallbackReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullAnyFallbackReceiverType = sema.types.makeNonNullable(anyFallbackReceiverType)
        let allowsAnyFallback: Bool = switch sema.types.kind(of: nonNullAnyFallbackReceiverType) {
        case .primitive(.string, _):
            false
        case .primitive:
            true
        case .typeParam:
            // All type parameters have an implicit upper bound of Any? in Kotlin,
            // so Any methods (toString, hashCode, equals) are always available on
            // type parameter receivers (STDLIB-GEN-055).
            true
        default:
            nonNullAnyFallbackReceiverType == sema.types.anyType
        }
        // Any.toString(): String — no-arg fallback via kk_any_to_string (STDLIB-306)
        if args.isEmpty, interner.resolve(calleeName) == "toString", allowsAnyFallback {
            let tag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
            instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [loweredReceiverID, tagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Any.hashCode(): Int — via kk_any_hashCode (STDLIB-306)
        if args.isEmpty, interner.resolve(calleeName) == "hashCode", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_hashCode"),
                arguments: [loweredReceiverID, receiverTagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Any.equals(other: Any?): Boolean — via kk_any_equals (STDLIB-306)
        if args.count == 1, interner.resolve(calleeName) == "equals", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let argType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let argTag = anyFallbackTag(for: argType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            let argTagID = arena.appendExpr(.intLiteral(argTag), type: intType)
            instructions.append(.constValue(result: argTagID, value: .intLiteral(argTag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_equals"),
                arguments: [loweredReceiverID, receiverTagID, loweredArgIDs[0], argTagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong(),
        // toFloat(), toByte(), toShort() (TYPE-005)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let charType = sema.types.charType
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            let calleeStr = interner.resolve(calleeName)
            let conversionCallee: InternedString? = switch (calleeStr, nonNullReceiverType, nonNullResultType) {
            case ("toInt", uintType, intType): interner.intern("kk_uint_to_int")
            case ("toInt", ulongType, intType): interner.intern("kk_ulong_to_int")
            case ("toInt", ubyteType, intType): interner.intern("kk_ubyte_to_int")
            case ("toInt", ushortType, intType): interner.intern("kk_ushort_to_int")
            case ("toInt", doubleType, intType): interner.intern("kk_double_to_int")
            case ("toInt", floatType, intType): interner.intern("kk_float_to_int")
            case ("toInt", longType, intType): interner.intern("kk_long_to_int")
            case ("toInt", charType, intType): nil // identity (Char is stored as Int)
            case ("toInt", intType, intType): nil // identity
            case ("toChar", intType, charType): nil // identity (Char is stored as Int)
            case ("toUInt", intType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", longType, uintType): interner.intern("kk_long_to_uint")
            case ("toUInt", ubyteType, uintType): interner.intern("kk_ubyte_to_uint")
            case ("toUInt", ushortType, uintType): interner.intern("kk_ushort_to_uint")
            case ("toUInt", charType, uintType): interner.intern("kk_char_to_uint")
            case ("toUInt", uintType, uintType), ("toUInt", ulongType, uintType): nil // identity
            case ("toLong", intType, longType): interner.intern("kk_int_to_long")
            case ("toLong", uintType, longType): interner.intern("kk_uint_to_long")
            case ("toLong", ubyteType, longType): interner.intern("kk_ubyte_to_long")
            case ("toLong", ushortType, longType): interner.intern("kk_ushort_to_long")
            case ("toLong", doubleType, longType): interner.intern("kk_double_to_long")
            case ("toLong", floatType, longType): interner.intern("kk_float_to_long")
            case ("toLong", charType, longType): interner.intern("kk_char_to_long")
            case ("toLong", longType, longType), ("toLong", ulongType, longType): nil // identity
            case ("toULong", intType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", longType, ulongType): interner.intern("kk_long_to_ulong")
            case ("toULong", uintType, ulongType): interner.intern("kk_uint_to_ulong")
            case ("toULong", ubyteType, ulongType): interner.intern("kk_ubyte_to_ulong")
            case ("toULong", ushortType, ulongType): interner.intern("kk_ushort_to_ulong")
            case ("toULong", charType, ulongType): interner.intern("kk_char_to_ulong")
            case ("toULong", ulongType, ulongType): nil // identity
            case ("toFloat", intType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", longType, floatType): interner.intern("kk_long_to_float")
            case ("toFloat", doubleType, floatType): interner.intern("kk_double_to_float")
            case ("toFloat", floatType, floatType): nil // identity
            case ("toDouble", intType, doubleType): interner.intern("kk_int_to_double_bits")
            case ("toDouble", longType, doubleType): interner.intern("kk_long_to_double")
            case ("toDouble", floatType, doubleType): interner.intern("kk_float_to_double_bits")
            case ("toDouble", doubleType, doubleType): nil // identity
            case ("toByte", intType, intType): interner.intern("kk_int_to_byte")
            case ("toByte", longType, intType): interner.intern("kk_long_to_byte")
            case ("toShort", intType, intType): interner.intern("kk_int_to_short")
            case ("toShort", longType, intType): interner.intern("kk_long_to_short")
            case ("toUByte", intType, ubyteType): interner.intern("kk_int_to_ubyte")
            case ("toUByte", longType, ubyteType): interner.intern("kk_long_to_ubyte")
            case ("toUByte", uintType, ubyteType): interner.intern("kk_uint_to_ubyte")
            case ("toUByte", ulongType, ubyteType): interner.intern("kk_ulong_to_ubyte")
            case ("toUShort", intType, ushortType): interner.intern("kk_int_to_ushort")
            case ("toUShort", longType, ushortType): interner.intern("kk_long_to_ushort")
            case ("toUShort", uintType, ushortType): interner.intern("kk_uint_to_ushort")
            case ("toUShort", ulongType, ushortType): interner.intern("kk_ulong_to_ushort")
            case ("toChar", longType, charType): interner.intern("kk_long_to_char")
            case ("toChar", uintType, charType): interner.intern("kk_uint_to_char")
            case ("toChar", ulongType, charType): interner.intern("kk_ulong_to_char")
            case ("toChar", ubyteType, charType): interner.intern("kk_ubyte_to_char")
            case ("toChar", ushortType, charType): interner.intern("kk_ushort_to_char")
            case ("toChar", charType, charType): nil // identity
            default: nil
            }
            if let callee = conversionCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: callee,
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            let isRepresentationPreservingConversion =
                (calleeStr == "toLong" && nonNullReceiverType == ulongType && nonNullResultType == longType)
                    || (calleeStr == "toUInt" && nonNullReceiverType == ulongType && nonNullResultType == uintType)
                    || (calleeStr == "toULong" && nonNullReceiverType == longType && nonNullResultType == ulongType)
                    || (calleeStr == "toInt" && nonNullReceiverType == charType && nonNullResultType == intType)
                    || (calleeStr == "toChar" && nonNullReceiverType == intType && nonNullResultType == charType)
            if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toUByte", "toUShort", "toChar"].contains(calleeStr),
               nonNullReceiverType == nonNullResultType || isRepresentationPreservingConversion,
               nonNullReceiverType == intType || nonNullReceiverType == longType
               || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
               || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
               || nonNullReceiverType == floatType || nonNullReceiverType == doubleType
               || nonNullReceiverType == charType
            {
                instructions.append(.copy(from: loweredReceiverID, to: result))
                return result
            }
        }

        if args.isEmpty, interner.resolve(calleeName) == "length" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_length"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Char.digitToInt() / Char.digitToIntOrNull() (STDLIB-083)
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == sema.types.charType {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "digitToInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToInt"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "digitToIntOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToIntOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // Char.code → identity (Char is stored as its Int code point) (STDLIB-305)
                if calleeStr == "code" {
                    instructions.append(.copy(from: loweredReceiverID, to: result))
                    return result
                }
            }
        }

        // STDLIB-003-ABI-001: Char.digitToInt(radix: Int) — 1-arg overload
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == sema.types.charType, interner.resolve(calleeName) == "digitToInt" {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_char_digitToInt_radix"),
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // filterIsInstance<R>() — encode type token from result type (STDLIB-114)
        if args.isEmpty, interner.resolve(calleeName) == "filterIsInstance" {
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            // Extract element type from List<R>
            let elementType: TypeID = if case let .classType(classType) = sema.types.kind(of: nonNullResultType),
                                         let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let encodedToken = RuntimeTypeCheckToken.encode(type: elementType, sema: sema, interner: interner)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_list_filterIsInstance"),
                arguments: [loweredReceiverID, tokenExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // filterIsInstanceTo<R>(destination) — encode type token from result type (STDLIB-021)
        if args.count == 1, interner.resolve(calleeName) == "filterIsInstanceTo" {
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            // Extract element type from MutableCollection<R>
            let elementType: TypeID = if case let .classType(classType) = sema.types.kind(of: nonNullResultType),
                                         let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let encodedToken = RuntimeTypeCheckToken.encode(type: elementType, sema: sema, interner: interner)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_list_filterIsInstanceTo"),
                arguments: [loweredReceiverID, loweredArgIDs[0], tokenExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // String stdlib: nullable-receiver 0-arg methods (NULL-002)
        // isNullOrEmpty/isNullOrBlank pass the raw (potentially null) receiver pointer to C runtime.
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if sema.bindings.callBindings[exprID] == nil,
               calleeStr == "isNullOrEmpty" || calleeStr == "isNullOrBlank"
            {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if calleeStr == "isNullOrEmpty",
                   let runtimeCallee = collectionIsNullOrEmptyRuntimeCallee(
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                   )
                {
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    let runtimeCallee = calleeStr == "isNullOrEmpty"
                        ? "kk_string_isNullOrEmpty"
                        : "kk_string_isNullOrBlank"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            // STDLIB-532/533/534, STDLIB-SEQ-011: orEmpty() on nullable receivers
            if sema.bindings.callBindings[exprID] == nil, calleeStr == "orEmpty" {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_list_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_sequence_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if isMapLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_map_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }
        // String stdlib: 0-arg methods (STDLIB-006)
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "trim" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_trim"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "lowercase" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_lowercase"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "uppercase" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_uppercase"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toInt"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toIntOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toIntOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toDouble" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toDouble"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toDoubleOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toDoubleOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "reversed" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_reversed"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toList" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toList"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "asIterable" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_asIterable"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toCharArray" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toCharArray"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toRegex" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toRegex"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "lines" || calleeStr == "lineSequence" {
                    let rtName = calleeStr == "lineSequence"
                        ? "kk_string_lineSequence" : "kk_string_lines"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(rtName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "first" || calleeStr == "last" || calleeStr == "single" {
                    let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
                    let kkName = calleeStr == "first" ? "kk_string_first"
                        : calleeStr == "last" ? "kk_string_last"
                        : "kk_string_single"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID, thrownExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "firstOrNull" || calleeStr == "lastOrNull" || calleeStr == "singleOrNull" {
                    let kkName = calleeStr == "firstOrNull" ? "kk_string_firstOrNull"
                        : calleeStr == "lastOrNull" ? "kk_string_lastOrNull"
                        : "kk_string_singleOrNull"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeName == interner.intern("zipWithNext") {
                    // String.zipWithNext overload dispatch: no-arg → kk_string_zipWithNext,
                    // transform → kk_string_zipWithNextTransform.
                    let runtimeCallee = args.isEmpty ? "kk_string_zipWithNext" : "kk_string_zipWithNextTransform"
                    let callArguments = args.isEmpty ? [loweredReceiverID] : [loweredReceiverID] + normalizedArgIDs
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: callArguments,
                        result: result,
                        canThrow: !args.isEmpty,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "asSequence" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_asSequence"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "asIterable" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_asIterable"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: 1-arg methods (STDLIB-006)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            let isCharSequenceTextHelper = calleeStr == "ifBlank"
                || calleeStr == "ifEmpty"
                || calleeStr == "chunkedSequence"
                || calleeStr == "firstNotNullOf"
                || calleeStr == "firstNotNullOfOrNull"
                || calleeStr == "reduceRightIndexed"
                || calleeStr == "reduceRightIndexedOrNull"
                || calleeStr == "reduceRightOrNull"
                || calleeStr == "sumBy"
                || calleeStr == "sumByDouble"
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
                || (isCharSequenceTextHelper && isCharSequenceReceiver)
            {
                if calleeStr == "firstNotNullOf"
                    || calleeStr == "firstNotNullOfOrNull"
                    || calleeStr == "reduceRightIndexed"
                    || calleeStr == "reduceRightIndexedOrNull"
                    || calleeStr == "reduceRightOrNull"
                    || calleeStr == "sumBy"
                    || calleeStr == "sumByDouble"
                {
                    let originalCallBinding = sema.bindings.callBindings[exprID]
                    let originalChosen: SymbolID? = if let chosen = originalCallBinding?.chosenCallee, chosen != .invalid {
                        chosen
                    } else {
                        nil
                    }
                    let normalizedOriginalArgs = driver.callSupportLowerer.normalizedCallArguments(
                        providedArguments: loweredArgIDs,
                        callBinding: originalCallBinding,
                        chosenCallee: originalChosen,
                        spreadFlags: args.map(\.isSpread),
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    ).arguments
                    let transformArg = normalizedOriginalArgs.first ?? loweredArgIDs[0]
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        transformArg,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    let runtimeCallee = switch calleeStr {
                    case "firstNotNullOf": "kk_string_firstNotNullOf"
                    case "firstNotNullOfOrNull": "kk_string_firstNotNullOfOrNull"
                    case "reduceRightIndexed": "kk_string_reduceRightIndexed"
                    case "reduceRightIndexedOrNull": "kk_string_reduceRightIndexedOrNull"
                    case "sumBy": "kk_string_sumBy"
                    case "sumByDouble": "kk_string_sumByDouble"
                    default: "kk_string_reduceRightOrNull"
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID, fnPtrExpr, envPtrExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toInt_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "substring" {
                    let hasEndExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: hasEndExpr, value: .intLiteral(0)))
                    let endExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: endExpr, value: .intLiteral(0)))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_substring"),
                        arguments: [loweredReceiverID, loweredArgIDs[0], endExpr, hasEndExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "windowed" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_windowed_default"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let stringGetThrownExpr: KIRExprID?
                if calleeStr == "get" {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    stringGetThrownExpr = zeroExpr
                } else {
                    stringGetThrownExpr = nil
                }
                let runtimeCall: (callee: String, arguments: [KIRExprID])? = switch calleeStr {
                case "split":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        ("kk_string_split_regex", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        ("kk_string_split", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "startsWith":
                    ("kk_string_startsWith", [loweredReceiverID, loweredArgIDs[0]])
                case "endsWith":
                    ("kk_string_endsWith", [loweredReceiverID, loweredArgIDs[0]])
                case "contains":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        ("kk_string_contains_regex", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        ("kk_string_contains_str", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "indexOf":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_indexOf_from", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_indexOf", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "lastIndexOf":
                    ("kk_string_lastIndexOf", [loweredReceiverID, loweredArgIDs[0]])
                case "get":
                    ("kk_string_get", [loweredReceiverID, loweredArgIDs[0], stringGetThrownExpr!])
                case "compareTo":
                    ("kk_string_compareTo_member", [loweredReceiverID, loweredArgIDs[0]])
                case "matches":
                    ("kk_string_matches_regex", [loweredReceiverID, loweredArgIDs[0]])
                case "repeat":
                    ("kk_string_repeat", [loweredReceiverID, loweredArgIDs[0]])
                case "replaceFirstChar":
                    ("kk_string_replaceFirstChar", [loweredReceiverID] + normalizedArgIDs)
                case "mapIndexed":
                    ("kk_string_mapIndexed", [loweredReceiverID] + normalizedArgIDs)
                case "mapNotNull":
                    ("kk_string_mapNotNull", [loweredReceiverID] + normalizedArgIDs)
                case "filterIndexed":
                    ("kk_string_filterIndexed", [loweredReceiverID] + normalizedArgIDs)
                case "filterNot":
                    ("kk_string_filterNot", [loweredReceiverID] + normalizedArgIDs)
                case "indexOfFirst":
                    ("kk_string_indexOfFirst", [loweredReceiverID] + normalizedArgIDs)
                case "indexOfLast":
                    ("kk_string_indexOfLast", [loweredReceiverID] + normalizedArgIDs)
                case "takeWhile":
                    ("kk_string_takeWhile", [loweredReceiverID] + normalizedArgIDs)
                case "dropWhile":
                    ("kk_string_dropWhile", [loweredReceiverID] + normalizedArgIDs)
                case "trim":
                    ("kk_string_trim_predicate", [loweredReceiverID] + normalizedArgIDs)
                case "trimStart":
                    ("kk_string_trimStart_predicate", [loweredReceiverID] + normalizedArgIDs)
                case "trimEnd":
                    ("kk_string_trimEnd_predicate", [loweredReceiverID] + normalizedArgIDs)
                case "splitToSequence":
                    ("kk_string_splitToSequence", [loweredReceiverID] + normalizedArgIDs)
                case "find":
                    ("kk_string_find", [loweredReceiverID] + normalizedArgIDs)
                case "findLast":
                    ("kk_string_findLast", [loweredReceiverID] + normalizedArgIDs)
                case "partition":
                    ("kk_string_partition", [loweredReceiverID] + normalizedArgIDs)
                case "ifBlank":
                    ("kk_string_ifBlank", [loweredReceiverID] + normalizedArgIDs)
                case "ifEmpty":
                    ("kk_string_ifEmpty", [loweredReceiverID] + normalizedArgIDs)
                case "take":
                    ("kk_string_take", [loweredReceiverID, loweredArgIDs[0]])
                case "drop":
                    ("kk_string_drop", [loweredReceiverID, loweredArgIDs[0]])
                case "takeLast":
                    ("kk_string_takeLast", [loweredReceiverID, loweredArgIDs[0]])
                case "dropLast":
                    ("kk_string_dropLast", [loweredReceiverID, loweredArgIDs[0]])
                case "chunked":
                    ("kk_string_chunked", [loweredReceiverID, loweredArgIDs[0]])
                case "chunkedSequence":
                    ("kk_string_chunked_sequence", [loweredReceiverID, loweredArgIDs[0]])
                case "encodeToByteArray", "toByteArray":
                    if loweredArgIDs.count == 1 {
                        ("kk_string_encodeToByteArray_charset", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        ("kk_string_encodeToByteArray_range", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    }
                case "commonPrefixWith":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_commonPrefixWith_ignoreCase", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_commonPrefixWith", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "commonSuffixWith":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_commonSuffixWith_ignoreCase", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_commonSuffixWith", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "padStart":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_padStart", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_padStart_default", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "padEnd":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_padEnd", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_padEnd_default", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "removePrefix":
                    ("kk_string_removePrefix", [loweredReceiverID, loweredArgIDs[0]])
                case "removeSuffix":
                    ("kk_string_removeSuffix", [loweredReceiverID, loweredArgIDs[0]])
                case "removeSurrounding":
                    ("kk_string_removeSurrounding", [loweredReceiverID, loweredArgIDs[0]])
                default:
                    nil
                }
                if let runtimeCall {
                    let stringHOFCanThrow = calleeStr == "repeat"
                        || calleeStr == "replaceFirstChar"
                        || calleeStr == "indexOfFirst"
                        || calleeStr == "indexOfLast"
                        || calleeStr == "partition"
                        || calleeStr == "ifBlank"
                        || calleeStr == "ifEmpty"
                        || calleeStr == "trim"
                        || calleeStr == "trimStart"
                        || calleeStr == "trimEnd"
                        || calleeStr == "take"
                        || calleeStr == "drop"
                        || calleeStr == "takeLast"
                        || calleeStr == "dropLast"
                    // Only `partition` captures the thrown result into a register so the
                    // caller can inspect it.  All other HOFs propagate exceptions through
                    // the standard thrown-channel codegen path (thrownResult == nil),
                    // which emits an early return when the channel is non-zero.  Setting
                    // thrownResult to non-nil for those HOFs would silently swallow the
                    // exception instead of propagating it.
                    let stringHOFThrownResult: KIRExprID? = calleeStr == "partition"
                        ? arena.appendExpr(
                            .temporary(Int32(arena.expressions.count)),
                            type: sema.types.nullableAnyType
                        )
                        : nil
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCall.callee),
                        arguments: runtimeCall.arguments,
                        result: result,
                        canThrow: stringHOFCanThrow,
                        thrownResult: stringHOFThrownResult
                    ))
                    return result
                }
            }
        }

        // STDLIB-TEXT-EDGE-001: split(delimiter, limit) — 2-arg overload
        if args.count == 2, interner.resolve(calleeName) == "split" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let secondArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(firstArgType, sema.types.stringType),
               sema.types.isSubtype(secondArgType, sema.types.intType)
            {
                let falseExpr = arena.appendExpr(.intLiteral(0), type: sema.types.booleanType)
                instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split_limit"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], falseExpr, loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // STDLIB-TEXT-EDGE-001: split(delimiter, ignoreCase) — 2-arg overload
        if args.count == 2, interner.resolve(calleeName) == "split" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let secondArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(firstArgType, sema.types.stringType),
               sema.types.isSubtype(secondArgType, sema.types.booleanType)
            {
                // limit = 0 means "no limit" for Kotlin's split overload.
                let zeroLimitExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroLimitExpr, value: .intLiteral(0)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split_limit"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], zeroLimitExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // STDLIB-TEXT-EDGE-001: split(delimiter, ignoreCase, limit) — 3-arg overload
        if args.count == 3, interner.resolve(calleeName) == "split" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let secondArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
            )
            let thirdArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[2].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(firstArgType, sema.types.stringType),
               sema.types.isSubtype(secondArgType, sema.types.booleanType),
               sema.types.isSubtype(thirdArgType, sema.types.intType)
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split_limit"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: 2-arg overloads (STDLIB-009, STDLIB-549)
        // KNOWN LIMITATION: The dispatch below matches purely on function name + receiver
        // type (String). User-defined extension functions with the same name (e.g.
        // `fun String.windowed(...)`) will be incorrectly intercepted. A future fix
        // should check the resolved symbol's origin (synthetic vs user-defined) before
        // rewriting to the runtime call.
        if args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            if (sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver),
               calleeStr == "chunkedSequence",
               normalizedArgIDs.count >= 3
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_chunked_sequence_transform"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "indexOf",
               sema.types.isSubtype(firstArgType, sema.types.stringType)
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_indexOf_from"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "windowed"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_windowed"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if (sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver),
               calleeStr == "chunkedSequence"
            {
                let lambdaArgIndex = args.indices.first { index in
                    ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
                        || sema.bindings.isCollectionHOFLambdaExpr(args[index].expr)
                }
                let sizeArgIndex = args.indices.first { index in
                    if let lambdaArgIndex {
                        return index != lambdaArgIndex
                    }
                    return false
                }
                let callArguments: [KIRExprID]
                let originalCallBinding = sema.bindings.callBindings[exprID]
                let originalChosen: SymbolID? = if let chosen = originalCallBinding?.chosenCallee, chosen != .invalid {
                    chosen
                } else {
                    nil
                }
                let normalizedOriginalArgs = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredArgIDs,
                    callBinding: originalCallBinding,
                    chosenCallee: originalChosen,
                    spreadFlags: args.map(\.isSpread),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ).arguments
                if normalizedOriginalArgs.count == 2 {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedOriginalArgs[1],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    callArguments = [loweredReceiverID, normalizedOriginalArgs[0], fnPtrExpr, envPtrExpr]
                } else if let lambdaArgIndex,
                          let sizeArgIndex,
                          lambdaArgIndex < loweredArgIDs.count,
                          sizeArgIndex < loweredArgIDs.count
                {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        loweredArgIDs[lambdaArgIndex],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    callArguments = [loweredReceiverID, loweredArgIDs[sizeArgIndex], fnPtrExpr, envPtrExpr]
                } else {
                    callArguments = [loweredReceiverID] + normalizedArgIDs
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_chunked_sequence_transform"),
                    arguments: callArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "compareTo"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_compareToIgnoreCase"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // STDLIB-575/576: commonPrefixWith / commonSuffixWith (ignoreCase overloads)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "commonPrefixWith" || calleeStr == "commonSuffixWith"
            {
                let runtimeName = calleeStr == "commonPrefixWith"
                    ? "kk_string_commonPrefixWith_ignoreCase"
                    : "kk_string_commonSuffixWith_ignoreCase"
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(runtimeName),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "substring" || calleeStr == "padStart" || calleeStr == "padEnd"
            {
                if calleeStr == "padStart" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_padStart"),
                        arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "padEnd" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_padEnd"),
                        arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let hasEndExpr = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                instructions.append(.constValue(result: hasEndExpr, value: .intLiteral(1)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_substring"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], hasEndExpr],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: 2-arg removeSurrounding(prefix, suffix) (STDLIB-TEXT-EDGE-010 / STDLIB-185)
        if args.count == 2, interner.resolve(calleeName) == "removeSurrounding" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_removeSurrounding_pair"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: windowed(size, step, partialWindows) — STDLIB-549
        // NOTE: Same name-based matching limitation as the 2-arg case above.
        if args.count == 3 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "windowed"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_windowed_partial"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            if (sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver),
               calleeStr == "windowedSequence"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_windowedSequence_partial"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 4 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            if (sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver),
               calleeStr == "windowedSequence"
            {
                let lambdaArgIndex = args.indices.first { index in
                    ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
                        || sema.bindings.isCollectionHOFLambdaExpr(args[index].expr)
                }
                let originalCallBinding = sema.bindings.callBindings[exprID]
                let originalChosen: SymbolID? = if let chosen = originalCallBinding?.chosenCallee, chosen != .invalid {
                    chosen
                } else {
                    nil
                }
                let normalizedOriginalArgs = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredArgIDs,
                    callBinding: originalCallBinding,
                    chosenCallee: originalChosen,
                    spreadFlags: args.map(\.isSpread),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ).arguments
                let callArguments: [KIRExprID]?
                if normalizedOriginalArgs.count == 4 {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedOriginalArgs[3],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    callArguments = [
                        loweredReceiverID,
                        normalizedOriginalArgs[0],
                        normalizedOriginalArgs[1],
                        normalizedOriginalArgs[2],
                        fnPtrExpr,
                        envPtrExpr,
                    ]
                } else if let lambdaArgIndex,
                          lambdaArgIndex < loweredArgIDs.count
                {
                    let scalarArgIDs = args.indices
                        .filter { $0 != lambdaArgIndex }
                        .compactMap { index -> KIRExprID? in
                            guard index < loweredArgIDs.count else { return nil }
                            return loweredArgIDs[index]
                        }
                    if scalarArgIDs.count == 3 {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            loweredArgIDs[lambdaArgIndex],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        callArguments = [loweredReceiverID] + scalarArgIDs + [fnPtrExpr, envPtrExpr]
                    } else {
                        callArguments = nil
                    }
                } else {
                    callArguments = nil
                }
                if let callArguments {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_windowedSequence_transform"),
                        arguments: callArguments,
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: replaceFirst(oldValue, newValue) (STDLIB-188)
        // Skip when first arg is a Regex — handled by the STDLIB-REGEX-094 block below.
        if args.count == 2, interner.resolve(calleeName) == "replaceFirst" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgIsRegex = isRegexLikeType(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType,
                sema: sema,
                interner: interner
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType), !firstArgIsRegex {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceFirst"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: removeRange(startIndex, endIndex) (STDLIB-TEXT-EDGE-008)
        if args.count == 2, interner.resolve(calleeName) == "removeRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_removeRange"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: removeRange(range) (STDLIB-TEXT-EDGE-008)
        if args.count == 1, interner.resolve(calleeName) == "removeRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_removeRange_range"),
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replaceRange(range, replacement) (STDLIB-188)
        if args.count == 2, interner.resolve(calleeName) == "replaceRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceRange"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replace(old, new) (STDLIB-006)
        if args.count == 2, interner.resolve(calleeName) == "replace" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let runtimeCallee = if isRegexLikeType(
                    sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType,
                    sema: sema,
                    interner: interner
                ) {
                    "kk_string_replace_regex"
                } else {
                    "kk_string_replace"
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replaceFirst(regex, replacement) (STDLIB-REGEX-094)
        if args.count == 2, interner.resolve(calleeName) == "replaceFirst" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               isRegexLikeType(
                   sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType,
                   sema: sema,
                   interner: interner
               ) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceFirst_regex"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Sequence joinToString (STDLIB-275): 0-3 args, non-HOF, non-throwing
        if args.count <= 3, interner.resolve(calleeName) == "joinToString" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let stringType = sema.types.stringType
                let paramNames = ["separator", "prefix", "postfix"]
                let defaults = [", ", "", ""]
                // Build a 3-element array mapping each parameter to its lowered arg or a default
                var resolved: [KIRExprID?] = [nil, nil, nil]
                for (argIdx, arg) in args.enumerated() {
                    if let label = arg.label,
                       let paramIdx = paramNames.firstIndex(of: interner.resolve(label))
                    {
                        resolved[paramIdx] = loweredArgIDs[argIdx]
                    } else {
                        // Positional argument: fill first unresolved slot
                        if let slot = resolved.firstIndex(where: { $0 == nil }), slot <= argIdx {
                            resolved[slot] = loweredArgIDs[argIdx]
                        } else {
                            resolved[argIdx] = loweredArgIDs[argIdx]
                        }
                    }
                }
                var joinArgs: [KIRExprID] = []
                for paramIndex in 0 ..< 3 {
                    if let existing = resolved[paramIndex] {
                        joinArgs.append(existing)
                    } else {
                        let interned = interner.intern(defaults[paramIndex])
                        let exprID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                        instructions.append(.constValue(result: exprID, value: .stringLiteral(interned)))
                        joinArgs.append(exprID)
                    }
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_sequence_joinToString"),
                    arguments: [loweredReceiverID] + joinArgs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 1,
           calleeName == interner.intern("plusElement") || calleeName == interner.intern("minusElement")
        {
            let chosenLinkName = chosenBase64Callee.flatMap { sema.symbols.externalLinkName(for: $0) }
            let returnsList = boundType.map { resultType in
                guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(resultType)),
                      let resultSymbol = sema.symbols.symbol(classType.classSymbol)
                else { return false }
                return interner.resolve(resultSymbol.name) == "List"
            } ?? false
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let receiverIsIterable = {
                guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                      let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                else { return false }
                return receiverSymbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Iterable"),
                ]
            }()
            let runtimeCallee = calleeName == interner.intern("plusElement")
                ? "kk_list_plus_element"
                : "kk_list_minus_element"
            if chosenLinkName == runtimeCallee || returnsList || receiverIsIterable {
                instructions.append(.call(
                    symbol: chosenBase64Callee,
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "get" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get"),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "contains" {
                    let listExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: nil)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_toList"),
                        arguments: [loweredReceiverID],
                        result: listExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_list_contains"),
                        arguments: [listExpr] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let runtimeCallee: String? = switch calleeStr {
                case "map":
                    "kk_array_map"
                case "filter":
                    "kk_array_filter"
                case "forEach":
                    "kk_array_forEach"
                case "any":
                    "kk_array_any"
                case "none":
                    "kk_array_none"
                case "count":
                    "kk_array_count"
                case "fill":
                    "kk_array_fill"
                default:
                    nil
                }
                if let runtimeCallee {
                    let canThrow = runtimeCallee == "kk_list_partition"
                        || runtimeCallee == "kk_list_zipWithNextTransform"
                    let thrownResult = canThrow
                        ? arena.appendExpr(
                            .temporary(Int32(arena.expressions.count)),
                            type: sema.types.nullableAnyType
                        )
                        : nil
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return result
                }
            }
            let useSequenceRuntimeForCollectionFallback = isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
            let useIterableRuntimeForCollectionFallback = (sema.bindings.isCollectionExpr(receiverExpr)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
                && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            if useSequenceRuntimeForCollectionFallback || useIterableRuntimeForCollectionFallback {
                let runtimeCallee: String?
                let mapName = interner.intern("map")
                let filterName = interner.intern("filter")
                let takeName = interner.intern("take")
                let forEachName = interner.intern("forEach")
                let flatMapName = interner.intern("flatMap")
                let flatMapIndexedName = interner.intern("flatMapIndexed")
                let dropName = interner.intern("drop")
                let zipName = interner.intern("zip")
                let takeWhileName = interner.intern("takeWhile")
                let dropWhileName = interner.intern("dropWhile")
                let sortedByName = interner.intern("sortedBy")
                let sumOfName = interner.intern("sumOf")
                let sumByName = interner.intern("sumBy")
                let sumByDoubleName = interner.intern("sumByDouble")
                let firstNotNullOfName = interner.intern("firstNotNullOf")
                let firstNotNullOfOrNullName = interner.intern("firstNotNullOfOrNull")
                let associateName = interner.intern("associate")
                let associateByName = interner.intern("associateBy")
                let associateWithName = interner.intern("associateWith")
                let associateToName = interner.intern("associateTo")
                let associateByToName = interner.intern("associateByTo")
                let associateWithToName = interner.intern("associateWithTo")
                let groupByToName = interner.intern("groupByTo")
                let containsName = interner.intern("contains")
                let indexOfName = interner.intern("indexOf")
                let elementAtName = interner.intern("elementAt")
                let elementAtOrNullName = interner.intern("elementAtOrNull")
                let findLastName = interner.intern("findLast")
                let lastName = interner.intern("last")
                let partitionName = interner.intern("partition")
                let minByOrNullName = interner.intern("minByOrNull")
                let maxByOrNullName = interner.intern("maxByOrNull")
                let minOfName = interner.intern("minOf")
                let maxOfName = interner.intern("maxOf")
                if calleeName == mapName {
                    runtimeCallee = "kk_sequence_map"
                } else if calleeName == filterName {
                    runtimeCallee = "kk_sequence_filter"
                } else if calleeName == takeName {
                    runtimeCallee = "kk_sequence_take"
                } else if calleeName == forEachName {
                    runtimeCallee = "kk_sequence_forEach"
                } else if calleeName == flatMapName {
                    runtimeCallee = "kk_sequence_flatMap"
                } else if calleeName == flatMapIndexedName {
                    runtimeCallee = "kk_sequence_flatMapIndexed"
                } else if calleeName == dropName {
                    runtimeCallee = "kk_sequence_drop"
                } else if calleeName == zipName {
                    runtimeCallee = "kk_sequence_zip"
                } else if calleeName == takeWhileName {
                    runtimeCallee = "kk_sequence_takeWhile"
                } else if calleeName == dropWhileName {
                    runtimeCallee = "kk_sequence_dropWhile"
                } else if calleeName == sortedByName {
                    runtimeCallee = "kk_sequence_sortedBy"
                } else if calleeName == sumOfName {
                    runtimeCallee = "kk_sequence_sumOf"
                } else if calleeName == sumByName {
                    runtimeCallee = "kk_sequence_sumBy"
                } else if calleeName == sumByDoubleName {
                    runtimeCallee = "kk_sequence_sumByDouble"
                } else if calleeName == firstNotNullOfName {
                    runtimeCallee = "kk_sequence_firstNotNullOf"
                } else if calleeName == firstNotNullOfOrNullName {
                    runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
                } else if calleeName == associateName {
                    runtimeCallee = "kk_sequence_associate"
                } else if calleeName == associateByName {
                    runtimeCallee = "kk_sequence_associateBy"
                } else if calleeName == associateWithName {
                    runtimeCallee = "kk_sequence_associateWith"
                } else if calleeName == associateToName {
                    runtimeCallee = "kk_sequence_associateTo"
                } else if calleeName == associateByToName {
                    runtimeCallee = "kk_sequence_associateByTo"
                } else if calleeName == associateWithToName {
                    runtimeCallee = "kk_sequence_associateWithTo"
                } else if calleeName == groupByToName {
                    runtimeCallee = "kk_sequence_groupByTo"
                } else if calleeName == containsName {
                    runtimeCallee = "kk_sequence_contains"
                } else if calleeName == indexOfName {
                    runtimeCallee = "kk_sequence_indexOf"
                } else if calleeName == elementAtName {
                    runtimeCallee = "kk_sequence_elementAt"
                } else if calleeName == elementAtOrNullName {
                    runtimeCallee = "kk_sequence_elementAtOrNull"
                } else if calleeName == lastName {
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "kk_iterable_last" : "kk_sequence_last"
                } else if calleeName == findLastName {
                    runtimeCallee = "kk_sequence_findLast"
                } else if calleeName == partitionName {
                    runtimeCallee = "kk_sequence_partition"
                } else if calleeName == minByOrNullName {
                    runtimeCallee = "kk_sequence_minByOrNull"
                } else if calleeName == maxByOrNullName {
                    runtimeCallee = "kk_sequence_maxByOrNull"
                } else if calleeName == minOfName {
                    runtimeCallee = "kk_sequence_minOf"
                } else if calleeName == maxOfName {
                    runtimeCallee = "kk_sequence_maxOf"
                } else if calleeName == interner.intern("find") {
                    runtimeCallee = "kk_sequence_find"
                } else if calleeName == interner.intern("findLast") {
                    runtimeCallee = "kk_sequence_findLast"
                } else if calleeName == interner.intern("any") {
                    runtimeCallee = "kk_sequence_any"
                } else if calleeName == interner.intern("all") {
                    runtimeCallee = "kk_sequence_all"
                } else if calleeName == interner.intern("none") {
                    runtimeCallee = "kk_sequence_none"
                } else if calleeName == interner.intern("mapNotNull") {
                    runtimeCallee = "kk_sequence_mapNotNull"
                } else if calleeName == interner.intern("firstNotNullOf") {
                    runtimeCallee = "kk_sequence_firstNotNullOf"
                } else if calleeName == interner.intern("firstNotNullOfOrNull") {
                    runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
                } else if calleeName == interner.intern("requireNoNulls") {
                    runtimeCallee = "kk_sequence_requireNoNulls"
                } else if calleeName == interner.intern("mapIndexed") {
                    runtimeCallee = "kk_sequence_mapIndexed"
                } else if calleeName == interner.intern("flatMapIndexed") {
                    runtimeCallee = "kk_sequence_flatMapIndexed"
                } else if calleeName == interner.intern("windowed"), args.count == 4 {
                    runtimeCallee = "kk_sequence_windowed_transform"
                } else if calleeName == interner.intern("chunked") {
                    runtimeCallee = args.count == 2
                        ? "kk_sequence_chunked_transform"
                        : "kk_sequence_chunked"
                } else if calleeName == interner.intern("onEach") {
                    runtimeCallee = "kk_sequence_onEach"
                } else if calleeName == interner.intern("onEachIndexed") {
                    runtimeCallee = "kk_sequence_onEachIndexed"
                } else if calleeName == interner.intern("plus") || calleeName == interner.intern("plusElement") {
                    runtimeCallee = "kk_sequence_plus_element"
                } else if calleeName == interner.intern("minus") || calleeName == interner.intern("minusElement") {
                    runtimeCallee = "kk_sequence_minus"
                } else if calleeName == interner.intern("runningReduceIndexed") {
                    runtimeCallee = "kk_sequence_runningReduceIndexed"
                } else if calleeName == interner.intern("shuffled") {
                    switch normalizedArgIDs.count {
                    case 0: runtimeCallee = "kk_sequence_shuffled"
                    case 1: runtimeCallee = "kk_sequence_shuffled_random"
                    default: runtimeCallee = nil
                    }
                } else if calleeName == interner.intern("ifEmpty") {
                    runtimeCallee = "kk_sequence_ifEmpty"
                } else if calleeName == interner.intern("forEachIndexed") {
                    runtimeCallee = "kk_sequence_forEachIndexed"
                } else if calleeName == interner.intern("zipWithNext") {
                    // Overload dispatch: no-arg → kk_sequence_zipWithNext, with transform → kk_sequence_zipWithNextTransform
                    runtimeCallee = normalizedArgIDs.isEmpty ? "kk_sequence_zipWithNext" : "kk_sequence_zipWithNextTransform"
                } else {
                    runtimeCallee = nil
                }
                if let runtimeCallee {
                    let canThrow = runtimeCallee == "kk_sequence_sortedBy"
                        || runtimeCallee == "kk_sequence_sumOf"
                        || runtimeCallee == "kk_sequence_sumBy"
                        || runtimeCallee == "kk_sequence_sumByDouble"
                        || runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_sequence_associate"
                        || runtimeCallee == "kk_sequence_associateBy"
                        || runtimeCallee == "kk_sequence_associateTo"
                        || runtimeCallee == "kk_sequence_associateByTo"
                        || runtimeCallee == "kk_sequence_associateWithTo"
                        || runtimeCallee == "kk_sequence_associateWith"
                        || runtimeCallee == "kk_sequence_groupByTo"
                        || runtimeCallee == "kk_sequence_find"
                        || runtimeCallee == "kk_sequence_findLast"
                        || runtimeCallee == "kk_sequence_elementAt"
                        || runtimeCallee == "kk_sequence_last"
                        || runtimeCallee == "kk_iterable_last"
                        || runtimeCallee == "kk_sequence_minByOrNull"
                        || runtimeCallee == "kk_sequence_maxByOrNull"
                        || runtimeCallee == "kk_sequence_minOf"
                        || runtimeCallee == "kk_sequence_maxOf"
                        || runtimeCallee == "kk_sequence_partition"
                        || runtimeCallee == "kk_sequence_any"
                        || runtimeCallee == "kk_sequence_all"
                        || runtimeCallee == "kk_sequence_none"
                        || runtimeCallee == "kk_sequence_mapNotNull"
                        || runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_sequence_mapIndexed"
                        || runtimeCallee == "kk_sequence_chunked_transform"
                        || runtimeCallee == "kk_sequence_windowed_transform"
                        || runtimeCallee == "kk_sequence_onEach"
                        || runtimeCallee == "kk_sequence_onEachIndexed"
                        || runtimeCallee == "kk_sequence_runningReduceIndexed"
                        || runtimeCallee == "kk_sequence_ifEmpty"
                        || runtimeCallee == "kk_sequence_zipWithNextTransform"
                    var runtimeArguments = [loweredReceiverID] + normalizedArgIDs
                    if (runtimeCallee == "kk_sequence_sumBy"
                        || runtimeCallee == "kk_sequence_sumByDouble"),
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if (runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"),
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: runtimeArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                let primitiveSelectorKind = collectionSelectorPrimitiveCompareKind(of: args.first?.expr, sema: sema)
                let runtimeCallee: String? = switch calleeStr {
                case "sortedBy":
                    primitiveSelectorKind != nil ? "kk_list_sortedBy_primitive" : "kk_list_sortedBy"
                case "sortedByDescending":
                    primitiveSelectorKind != nil ? "kk_list_sortedByDescending_primitive" : "kk_list_sortedByDescending"
                case "distinctBy":
                    "kk_list_distinctBy"
                case "sortedWith":
                    "kk_list_sortedWith"
                case "maxOf":
                    "kk_list_maxOf"
                case "minOf":
                    "kk_list_minOf"
                case "maxWith":
                    "kk_list_maxWith"
                case "maxWithOrNull":
                    "kk_list_maxWithOrNull"
                case "minWith":
                    "kk_list_minWith"
                case "minWithOrNull":
                    "kk_list_minWithOrNull"
                case "maxOfWith":
                    "kk_list_maxOfWith"
                case "maxOfWithOrNull":
                    "kk_list_maxOfWithOrNull"
                case "minOfWith":
                    "kk_list_minOfWith"
                case "minOfWithOrNull":
                    "kk_list_minOfWithOrNull"
                case "indexOf":
                    "kk_list_indexOf"
                case "lastIndexOf":
                    "kk_list_lastIndexOf"
                case "partition":
                    "kk_list_partition"
                case "zipWithNext":
                    "kk_list_zipWithNextTransform"
                case "getOrNull":
                    "kk_list_getOrNull"
                case "elementAtOrNull":
                    "kk_list_elementAtOrNull"
                case "elementAt":
                    "kk_list_elementAt"
                case "containsAll":
                    "kk_list_containsAll"
                case "intersect":
                    "kk_list_intersect"
                default:
                    nil
                }
                if let runtimeCallee {
                    var callArguments = [loweredReceiverID] + normalizedArgIDs
                    if let primitiveSelectorKind,
                       runtimeCallee == "kk_list_sortedBy_primitive" || runtimeCallee == "kk_list_sortedByDescending_primitive"
                    {
                        let kindExpr = arena.appendExpr(.intLiteral(Int64(primitiveSelectorKind.rawValue)), type: sema.types.intType)
                        instructions.append(.constValue(result: kindExpr, value: .intLiteral(Int64(primitiveSelectorKind.rawValue))))
                        callArguments.append(kindExpr)
                    }
                    let canThrow = runtimeCallee == "kk_list_elementAt"
                        || runtimeCallee == "kk_list_distinctBy"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: callArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isRegexLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                let runtimeCallee: String? = switch calleeStr {
                case "find":
                    "kk_regex_find"
                case "findAll":
                    "kk_regex_findAll"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            // StringBuilder member calls with 1 arg (STDLIB-255/256/257)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.append {
                    "kk_string_builder_append_obj"
                } else if calleeName == sbNames.appendLine {
                    "kk_string_builder_append_line_obj"
                } else if calleeName == sbNames.deleteCharAt {
                    "kk_string_builder_deleteCharAt"
                } else if calleeName == sbNames.deleteAt {
                    "kk_string_builder_deleteAt"
                } else if calleeName == sbNames.get {
                    "kk_string_builder_get"
                } else if calleeName == sbNames.ensureCapacity {
                    "kk_string_builder_ensureCapacity"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "copyOf"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_copyOf_newSize"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                if interner.resolve(calleeName) == "copyOf" {
                    let fnPtrExpr: KIRExprID
                    let envPtrExpr: KIRExprID
                    if normalizedArgIDs.count >= 3 {
                        fnPtrExpr = normalizedArgIDs[1]
                        envPtrExpr = normalizedArgIDs[2]
                    } else {
                        let split = splitCallableLambdaArgument(
                            normalizedArgIDs[1],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        fnPtrExpr = split.fnPtrExpr
                        envPtrExpr = split.envPtrExpr
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_copyOf_newSize_init"),
                        arguments: [loweredReceiverID, normalizedArgIDs[0], fnPtrExpr, envPtrExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if interner.resolve(calleeName) == "copyOfRange" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_copyOfRange"),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            // List.elementAtOrElse(index, defaultValue) — 2 args (STDLIB-214)
            if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "elementAtOrElse"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_list_elementAtOrElse"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // StringBuilder 2-arg member calls (STDLIB-255/256/257)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.insert {
                    "kk_string_builder_insert_obj"
                } else if calleeName == sbNames.delete {
                    "kk_string_builder_delete_obj"
                } else if calleeName == sbNames.deleteRange {
                    "kk_string_builder_deleteRange"
                } else if calleeName == sbNames.setCharAt {
                    "kk_string_builder_setCharAt"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // StringBuilder 3-arg member calls (STDLIB-580 / STDLIB-STR-123)
        if args.count == 3 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.appendRange {
                    "kk_string_builder_appendRange_obj"
                } else if calleeName == sbNames.replace {
                    "kk_string_builder_replace_obj"
                } else if calleeName == sbNames.setRange {
                    "kk_string_builder_setRange"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // StringBuilder 4-arg member calls (STDLIB-TEXT-BUILDER-003)
        if args.count == 4 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.insertRange {
                    "kk_string_builder_insertRange_obj"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        let hasHOFLambdaArg = args.last.map { ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false

        // Sequence windowed: 1-3 args (size, step=1, partialWindows=false) — STDLIB-276
        // Lambda-bearing `windowed` calls use the synthetic iterable HOF overload
        // and must not be rewritten to the sequence ABI here.
        if !hasHOFLambdaArg,
           (1...3).contains(args.count),
           calleeName == interner.intern("windowed")
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let sizeArg = normalizedArgIDs[0]
                let stepArg: KIRExprID
                if args.count >= 2 {
                    stepArg = normalizedArgIDs[1]
                } else {
                    stepArg = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                    instructions.append(.constValue(result: stepArg, value: .intLiteral(1)))
                }
                let partialArg: KIRExprID
                if args.count >= 3 {
                    partialArg = normalizedArgIDs[2]
                } else {
                    partialArg = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: partialArg, value: .intLiteral(0)))
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_sequence_windowed"),
                    arguments: [loweredReceiverID, sizeArg, stepArg, partialArg],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee: String? = switch interner.resolve(calleeName) {
                case "toList":
                    "kk_array_toList"
                case "toMutableList":
                    "kk_array_toMutableList"
                case "toTypedArray":
                    "kk_array_copyOf"
                case "copyOf":
                    "kk_array_copyOf"
                case "concatToString":
                    "kk_chararray_concatToString"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            // String Iterable<Char> — route toList/iterator to specialised runtime (STDLIB-317)
            if isStringIterableType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee: String? = switch interner.resolve(calleeName) {
                case "toList":
                    "kk_string_iterable_toList"
                case "iterator":
                    "kk_string_iterable_iterator"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            let useSequenceRuntimeForTerminalFallback = isSequenceLikeType(
                nonNullReceiverType,
                sema: sema,
                interner: interner
            )
            let useIterableRuntimeForTerminalFallback = (sema.bindings.isCollectionExpr(receiverExpr)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
                && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            if useSequenceRuntimeForTerminalFallback || useIterableRuntimeForTerminalFallback {
                let toListID = interner.intern("toList")
                let constrainOnceID = interner.intern("constrainOnce")
                let distinctID = interner.intern("distinct")
                let sortedID = interner.intern("sorted")
                let sortedDescendingID = interner.intern("sortedDescending")
                let filterNotNullID = interner.intern("filterNotNull")
                let requireNoNullsID = interner.intern("requireNoNulls")
                let asIterableID = interner.intern("asIterable")
                let withIndexID = interner.intern("withIndex")
                let firstID = interner.intern("first")
                let firstOrNullID = interner.intern("firstOrNull")
                let lastID = interner.intern("last")
                let lastOrNullID = interner.intern("lastOrNull")
                let countID = interner.intern("count")
                let sumID = interner.intern("sum")
                let averageID = interner.intern("average")
                let toMutableListID = interner.intern("toMutableList")
                let toMutableSetID = interner.intern("toMutableSet")
                let toHashSetID = interner.intern("toHashSet")
                let unzipID = interner.intern("unzip")
                let anyID = interner.intern("any")
                let noneID = interner.intern("none")

                let seqFirstCallee = interner.intern("kk_sequence_first")
                let seqFirstOrNullCallee = interner.intern("kk_sequence_firstOrNull")
                let seqLastCallee = interner.intern("kk_sequence_last")
                let iterableLastCallee = interner.intern("kk_iterable_last")
                let seqLastOrNullCallee = interner.intern("kk_sequence_lastOrNull")
                let seqCountCallee = interner.intern("kk_sequence_count")
                let seqAnyCallee = interner.intern("kk_sequence_any")
                let seqNoneCallee = interner.intern("kk_sequence_none")
                let seqToListCallee = interner.intern("kk_sequence_to_list")

                let runtimeCallee: InternedString? = switch calleeName {
                case toListID:
                    seqToListCallee
                case constrainOnceID:
                    interner.intern("kk_sequence_constrainOnce")
                case distinctID:
                    interner.intern("kk_sequence_distinct")
                case sortedID:
                    interner.intern("kk_sequence_sorted")
                case sortedDescendingID:
                    interner.intern("kk_sequence_sortedDescending")
                case interner.intern("shuffled") where args.isEmpty:
                    interner.intern("kk_sequence_shuffled")
                case filterNotNullID:
                    interner.intern("kk_sequence_filterNotNull")
                case requireNoNullsID:
                    interner.intern("kk_sequence_requireNoNulls")
                case asIterableID:
                    interner.intern("kk_sequence_asIterable")
                case withIndexID:
                    interner.intern("kk_sequence_withIndex")
                case firstID:
                    seqFirstCallee
                case firstOrNullID:
                    seqFirstOrNullCallee
                case lastID:
                    useIterableRuntimeForTerminalFallback ? iterableLastCallee : seqLastCallee
                case lastOrNullID:
                    seqLastOrNullCallee
                case countID:
                    seqCountCallee
                case sumID:
                    interner.intern("kk_sequence_sum")
                case averageID:
                    interner.intern("kk_sequence_average")
                case toMutableListID:
                    toMutableListRuntimeCalleeForSequenceOrIterableFallback(
                        chosenCallee: sema.bindings.callBindings[exprID]?.chosenCallee,
                        useIterableFallback: useIterableRuntimeForTerminalFallback,
                        sema: sema,
                        interner: interner
                    )
                case toMutableSetID:
                    interner.intern("kk_sequence_toMutableSet")
                case toHashSetID:
                    interner.intern("kk_sequence_toHashSet")
                case unzipID:
                    interner.intern("kk_sequence_unzip")
                case anyID:
                    seqAnyCallee
                case noneID:
                    seqNoneCallee
                default:
                    nil
                }
                if let runtimeCallee {
                    // any()/none() with no predicate: pass fnPtr=0, closure=0 sentinel
                    if runtimeCallee == seqAnyCallee || runtimeCallee == seqNoneCallee {
                        let zeroExpr = arena.appendExpr(.intLiteral(0), type: nil)
                        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                        instructions.append(.call(
                            symbol: nil,
                            callee: runtimeCallee,
                            arguments: [loweredReceiverID, zeroExpr, zeroExpr],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        return result
                    }
                    let canThrow = runtimeCallee == seqFirstCallee
                        || runtimeCallee == seqFirstOrNullCallee
                        || runtimeCallee == seqLastCallee
                        || runtimeCallee == iterableLastCallee
                        || runtimeCallee == seqLastOrNullCallee
                        || runtimeCallee == seqCountCallee
                        || runtimeCallee == seqToListCallee
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isRegexLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "pattern"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_regex_pattern"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // StringBuilder 0-arg member calls and properties (STDLIB-255/256/257)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.toString {
                    "kk_string_builder_toString"
                } else if calleeName == sbNames.clear {
                    "kk_string_builder_clear"
                } else if calleeName == sbNames.reverse {
                    "kk_string_builder_reverse"
                } else if calleeName == sbNames.appendLine {
                    "kk_string_builder_append_line_noarg_obj"
                } else if calleeName == sbNames.length {
                    "kk_string_builder_length_prop"
                } else if calleeName == sbNames.capacity {
                    "kk_string_builder_capacity"
                } else if calleeName == sbNames.trimToSize {
                    "kk_string_builder_trimToSize"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: format(vararg args) (STDLIB-006)
        if interner.resolve(calleeName) == "format",
           let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_format"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                func boxedFormatArgument(_ argExpr: ExprID, loweredArgID: KIRExprID) -> KIRExprID {
                    let argType = sema.bindings.exprTypes[argExpr] ?? sema.types.anyType
                    let nonNullArgType = sema.types.makeNonNullable(argType)
                    let boxCallee: String? = switch sema.types.kind(of: nonNullArgType) {
                    case .primitive(.int, _), .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
                        "kk_box_int"
                    case .primitive(.boolean, _):
                        "kk_box_bool"
                    case .primitive(.long, _), .primitive(.ulong, _):
                        "kk_box_long"
                    case .primitive(.float, _):
                        "kk_box_float"
                    case .primitive(.double, _):
                        "kk_box_double"
                    case .primitive(.char, _):
                        "kk_box_char"
                    default:
                        nil
                    }

                    let boxedArg = arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                    if let boxCallee {
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern(boxCallee),
                            arguments: [loweredArgID],
                            result: boxedArg,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    } else {
                        instructions.append(.copy(from: loweredArgID, to: boxedArg))
                    }
                    return boxedArg
                }

                let boxedArgIDs = zip(args, loweredArgIDs).map { arg, loweredArgID in
                    boxedFormatArgument(arg.expr, loweredArgID: loweredArgID)
                }

                let packedArgs: KIRExprID
                if boxedArgIDs.count == 1, args.first?.isSpread == true {
                    packedArgs = boxedArgIDs[0]
                } else {
                    packedArgs = driver.callSupportLowerer.packVarargArguments(
                        argIndices: Array(boxedArgIDs.indices),
                        providedArguments: boxedArgIDs,
                        spreadFlags: args.map(\.isSpread),
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.nullableAnyType,
                        instructions: &instructions
                    )
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_format"),
                    arguments: [loweredReceiverID, packedArgs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // StringBuilder: append(vararg value: String? / Any?) (STDLIB-TEXT-EDGE-012)
        if interner.resolve(calleeName) == "append",
           let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_builder_append_vararg_obj"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                let packedArgs: KIRExprID
                if loweredArgIDs.count == 1, args.first?.isSpread == true {
                    packedArgs = loweredArgIDs[0]
                } else {
                    packedArgs = driver.callSupportLowerer.packVarargArguments(
                        argIndices: Array(loweredArgIDs.indices),
                        providedArguments: loweredArgIDs,
                        spreadFlags: args.map(\.isSpread),
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.nullableAnyType,
                        instructions: &instructions
                    )
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_builder_append_vararg_obj"),
                    arguments: [loweredReceiverID, packedArgs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)

        // Extract qualified super type information for super<Interface> calls
        var qualifiedSuperType: SymbolID? = nil
        if isSuperCall, case let .superRef(interfaceQualifier, _) = ast.arena.expr(receiverExpr) {
            if let qualifier = interfaceQualifier {
                // Find the interface symbol that matches the qualifier
                if let currentReceiverType = sema.bindings.exprTypes[receiverExpr],
                   case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(currentReceiverType)) {
                    let classSymbol = classType.classSymbol
                    let directSupertypes = sema.symbols.directSupertypes(for: classSymbol)
                    let qualifierStr = interner.resolve(qualifier)
                    for superID in directSupertypes {
                        guard let superSym = sema.symbols.symbol(superID) else { continue }
                        if superSym.kind == SymbolKind.interface && interner.resolve(superSym.name) == qualifierStr {
                            qualifiedSuperType = superID
                            break
                        }
                    }
                }
            }
        }

        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            argumentExprs: args.map(\.expr),
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
        if qualifiedSuperType == nil,
           isSuperCall,
           case let .superRef(interfaceQualifier?, _) = ast.arena.expr(receiverExpr),
           let chosenCallee = callBinding?.chosenCallee,
           chosenCallee != .invalid,
           let ownerSymbol = sema.symbols.parentSymbol(for: chosenCallee),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .interface,
           interner.resolve(ownerInfo.name) == interner.resolve(interfaceQualifier)
        {
            qualifiedSuperType = ownerSymbol
        }
        let chosen: SymbolID? = if let chosenCallee = callBinding?.chosenCallee, chosenCallee != .invalid {
            chosenCallee
        } else {
            SymbolID?.none
        }
        let normalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: normalizedArgIDs,
            callBinding: callBinding,
            chosenCallee: chosen,
            spreadFlags: args.map(\.isSpread),
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        var finalArguments = normalized.arguments
        appendReceiverToMemberArguments(
            loweredReceiverID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            chosenCallee: chosen,
            prependReceiverForUnresolvedCollectionCall: prependReceiverForUnresolvedCollectionCall,
            sema: sema,
            interner: interner,
            arguments: &finalArguments
        )
        emitMemberCallInstruction(
            normalized: normalized,
            callBinding: callBinding,
            chosenCallee: chosen,
            calleeName: calleeName,
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: loweredReceiverID),
            result: result,
            isSuperCall: isSuperCall,
            qualifiedSuperType: qualifiedSuperType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: finalArguments,
            sourceArgExprs: args.map(\.expr),
            sourceArgLabels: args.map(\.label)
        )
        return result
    }

    private func isCollectionHOFCallee(
        _ calleeName: InternedString,
        interner: StringInterner
    ) -> Bool {
        [
            "map", "filter", "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull", "forEach", "flatMap",
            "any", "none", "all", "fold", "foldRight", "reduce", "reduceRight", "scan", "scanIndexed",
            "runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed", "groupBy", "groupingBy",
            "aggregate", "aggregateTo",
            "sortedBy", "count", "first", "last", "find", "distinctBy",
            "associateBy", "associateWith", "associate",
            "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed", "sumOf", "sumBy", "sumByDouble", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues",
            "getOrElse", "elementAtOrElse", "getOrPut",
            "maxBy", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull",
            "maxOf", "minOf",
            "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
            "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
            "indexOfFirst", "indexOfLast", "binarySearch", "binarySearchBy", "reduceIndexed", "reduceIndexedOrNull", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "foldIndexed", "foldRightIndexed",
            "sortedByDescending", "sortedWith", "partition", "zipWithNext",
            "sortedArrayWith",
            "takeWhile", "dropWhile", "filterNot", "findLast", "replaceAll", "removeIf",
            "replaceFirstChar",
            "trim", "trimStart", "trimEnd",
            "sortWith", "sortBy", "sortByDescending",
            "onEach", "onEachIndexed",
            "ifEmpty",
            "ifBlank",
            "chunked", "chunkedSequence", "windowed", "copyOf",
            "toComponents",
            "onSuccess", "onFailure", "recover",
        ].contains(interner.resolve(calleeName))
    }

    private func addCollectionHOFClosureArguments(
        loweredArgIDs: [KIRExprID],
        argExprIDs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard loweredArgIDs.count == argExprIDs.count else {
            return loweredArgIDs
        }
        var finalArgs: [KIRExprID] = []
        finalArgs.reserveCapacity(loweredArgIDs.count + 1)

        for (loweredArgID, argExprID) in zip(loweredArgIDs, argExprIDs) {
            let callableInfo: KIRCallableValueInfo? = {
                if sema.bindings.isCollectionHOFLambdaExpr(argExprID) {
                    return driver.ctx.callableValueInfo(for: loweredArgID) ?? {
                        guard case let .symbolRef(symbol)? = arena.expr(loweredArgID) else {
                            return nil
                        }
                        return KIRCallableValueInfo(
                            symbol: symbol,
                            callee: interner.intern(""),
                            captureArguments: arena.lambdaCaptureArgsBySymbol[symbol] ?? [],
                            hasClosureParam: true
                        )
                    }()
                }
                guard let loweredCallable = driver.ctx.callableValueInfo(for: loweredArgID),
                      !loweredCallable.hasClosureParam,
                      let adapted = makeCollectionHOFCallableAdapter(
                          callableInfo: loweredCallable,
                          loweredArgID: loweredArgID,
                          argExprID: argExprID,
                          sema: sema,
                          arena: arena,
                          interner: interner
                      )
                else {
                    return nil
                }
                return adapted
            }()
            guard let callableInfo else {
                finalArgs.append(loweredArgID)
                continue
            }

            let fnPtrExpr = arena.appendExpr(
                .symbolRef(callableInfo.symbol),
                type: arena.exprType(loweredArgID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
            finalArgs.append(fnPtrExpr)
            if callableInfo.captureArguments.count >= 2 {
                // Multi-capture: pack captures into a closure object.
                // The lambda has been generated to unpack them via kk_array_get_inbounds.
                let intType = sema.types.intType
                let anyType = sema.types.anyType
                let kkObjectNew = interner.intern("kk_object_new")
                let kkArraySet = interner.intern("kk_array_set")

                let slotCount = Int64(2 + callableInfo.captureArguments.count)
                let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
                instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))

                let classIDExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))

                let closureObjExpr = arena.appendExpr(
                    .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: kkObjectNew,
                    arguments: [slotCountExpr, classIDExpr],
                    result: closureObjExpr,
                    canThrow: false,
                    thrownResult: nil
                ))

                for (captureIndex, captureArg) in callableInfo.captureArguments.enumerated() {
                    let fieldOffset = Int64(captureIndex + 2)
                    let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
                    let unusedResult = arena.appendExpr(
                        .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: kkArraySet,
                        arguments: [closureObjExpr, offsetExpr, captureArg],
                        result: unusedResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }

                finalArgs.append(closureObjExpr)
            } else if let closureRaw = callableInfo.captureArguments.first {
                finalArgs.append(closureRaw)
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArgs.append(zeroExpr)
            }
        }

        return finalArgs
    }

    func comparatorTrampolineName(
        comparatorExprID: ExprID?,
        loweredComparatorID: KIRExprID,
        sema: SemaModule,
        interner: StringInterner,
        instructions: [KIRInstruction]
    ) -> String? {
        func primitiveCompareKind(
            for comparatorExprID: ExprID?,
            loweredComparatorID: KIRExprID
        ) -> PrimitiveCompareABIKind? {
            func comparatorElementType(from type: TypeID) -> TypeID? {
                let nonNullType = sema.types.makeNonNullable(type)
                guard case let .classType(classType) = sema.types.kind(of: nonNullType),
                      let symbol = sema.symbols.symbol(classType.classSymbol),
                      interner.resolve(symbol.name) == "Comparator",
                      let firstArg = classType.args.first
                else {
                    return nil
                }
                switch firstArg {
                case let .invariant(type), let .out(type), let .in(type):
                    return type
                case .star:
                    return sema.types.anyType
                }
            }

            if let comparatorExprID,
               let exprType = sema.bindings.exprType(for: comparatorExprID),
               let elementType = comparatorElementType(from: exprType),
               let kind = primitiveCompareABIKind(for: elementType, sema: sema)
            {
                return kind
            }
            return nil
        }

        func trampolineName(for externalLinkName: String) -> String? {
            switch externalLinkName {
            case "kk_comparator_from_selector":
                return "kk_comparator_from_selector_trampoline"
            case "kk_comparator_from_selector_descending":
                return "kk_comparator_from_selector_descending_trampoline"
            case "kk_comparator_from_selector_primitive":
                return "kk_comparator_from_selector_primitive_trampoline"
            case "kk_comparator_from_multi_selectors",
                 "kk_comparator_from_multi_selectors3",
                 "kk_comparator_from_multi_selectors_vararg":
                return "kk_comparator_from_multi_selectors_trampoline"
            case "kk_comparator_nulls_first":
                return "kk_comparator_nulls_first_trampoline"
            case "kk_comparator_nulls_last":
                return "kk_comparator_nulls_last_trampoline"
            case "kk_comparator_then_by":
                return "kk_comparator_then_by_trampoline"
            case "kk_comparator_then_by_comparator_selector":
                return "kk_comparator_then_by_comparator_selector_trampoline"
            case "kk_comparator_then_by_descending":
                return "kk_comparator_then_by_descending_trampoline"
            case "kk_comparator_then_by_descending_comparator_selector":
                return "kk_comparator_then_by_descending_comparator_selector_trampoline"
            case "kk_comparator_then_descending":
                return "kk_comparator_then_descending_trampoline"
            case "kk_comparator_then_comparator":
                return "kk_comparator_then_comparator_trampoline"
            case "kk_comparator_reversed":
                return "kk_comparator_reversed_trampoline"
            case "kk_comparator_natural_order":
                return "kk_comparator_natural_order_trampoline"
            case "kk_comparator_reverse_order":
                return "kk_comparator_reverse_order_trampoline"
            default:
                return nil
            }
        }

        func trampolineName(for comparatorSymbol: SymbolID) -> String? {
            guard let symbol = sema.symbols.symbol(comparatorSymbol) else {
                return nil
            }
            switch interner.resolve(symbol.name) {
            case "compareBy":
                return "kk_comparator_from_selector_trampoline"
            case "compareByPrimitive":
                return "kk_comparator_from_selector_primitive_trampoline"
            case "compareByDescending":
                return "kk_comparator_from_selector_descending_trampoline"
            case "compareByDescendingPrimitive":
                return "kk_comparator_from_selector_primitive_descending_trampoline"
            case "thenBy":
                return "kk_comparator_then_by_trampoline"
            case "thenByDescending":
                return "kk_comparator_then_by_descending_trampoline"
            case "thenDescending":
                return "kk_comparator_then_descending_trampoline"
            case "thenComparator":
                return "kk_comparator_then_comparator_trampoline"
            case "nullsFirst":
                return "kk_comparator_nulls_first_trampoline"
            case "nullsLast":
                return "kk_comparator_nulls_last_trampoline"
            case "reversed":
                return "kk_comparator_reversed_trampoline"
            case "naturalOrder":
                return "kk_comparator_natural_order_trampoline"
            case "reverseOrder":
                return "kk_comparator_reverse_order_trampoline"
            default:
                return nil
            }
        }

        if let comparatorExprID,
           let chosenCallee = sema.bindings.callBinding(for: comparatorExprID)?.chosenCallee
        {
            if let primitiveKind = primitiveCompareKind(
                for: comparatorExprID,
                loweredComparatorID: loweredComparatorID
            ) {
                if let symbol = sema.symbols.symbol(chosenCallee) {
                    switch interner.resolve(symbol.name) {
                    case "compareBy":
                        return "kk_comparator_from_selector_primitive_trampoline"
                    case "compareByDescending":
                        return "kk_comparator_from_selector_primitive_descending_trampoline"
                    default:
                        break
                    }
                }
                if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee) {
                    switch externalLinkName {
                    case "kk_comparator_from_selector":
                        _ = primitiveKind
                        return "kk_comparator_from_selector_primitive_trampoline"
                    case "kk_comparator_from_selector_descending":
                        _ = primitiveKind
                        return "kk_comparator_from_selector_primitive_descending_trampoline"
                    default:
                        break
                    }
                }
            }
            if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
               let trampolineName = trampolineName(for: externalLinkName)
            {
                return trampolineName
            }
            if let trampolineName = trampolineName(for: chosenCallee) {
                return trampolineName
            }
        }

        for instruction in instructions.reversed() {
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  result == loweredComparatorID,
                  let trampolineName = trampolineName(for: interner.resolve(callee))
            else {
                continue
            }
            return trampolineName
        }
        return nil
    }

    private func makeComparatorTrampolineArgument(
        comparatorExprID: ExprID?,
        loweredComparatorID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID]? {
        let trampolineName = comparatorTrampolineName(
            comparatorExprID: comparatorExprID,
            loweredComparatorID: loweredComparatorID,
            sema: sema,
            interner: interner,
            instructions: instructions
        )
        guard let trampolineName else {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return [loweredComparatorID, zeroExpr]
        }

        let fnPtrExpr = arena.appendExpr(
            .temporary(Int32(clamping: arena.expressions.count)),
            type: sema.types.intType
        )
        instructions.append(.constValue(
            result: fnPtrExpr,
            value: .externSymbolAddress(interner.intern(trampolineName))
        ))
        return [fnPtrExpr, loweredComparatorID]
    }

    private func adaptComparatorFactoryArgumentsForCollectionHOF(
        calleeName: InternedString,
        loweredArgIDs: [KIRExprID],
        argExprIDs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        let comparatorOnlyHOFNames: Set<String> = [
            "sortWith", "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
        ]
        guard comparatorOnlyHOFNames.contains(interner.resolve(calleeName)),
              loweredArgIDs.count == 1,
              let comparatorArgID = loweredArgIDs.first,
              let comparatorExprID = argExprIDs.first,
              let comparatorArgs = makeComparatorTrampolineArgument(
                  comparatorExprID: comparatorExprID,
                  loweredComparatorID: comparatorArgID,
                  sema: sema,
                  arena: arena,
                  interner: interner,
                  instructions: &instructions
              )
        else {
            return loweredArgIDs
        }
        return comparatorArgs
    }

    private func adaptComparatorBackedCollectionArguments(
        loweredCallee: InternedString,
        finalArguments: [KIRExprID],
        sourceArgExprs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        let comparatorOnlyCallees: Set<InternedString> = [
            interner.intern("kk_list_maxWith"),
            interner.intern("kk_list_maxWithOrNull"),
            interner.intern("kk_list_minWith"),
            interner.intern("kk_list_minWithOrNull"),
            interner.intern("kk_array_sortedArrayWith"),
            interner.intern("kk_mutable_list_sortWith"),
        ]
        if comparatorOnlyCallees.contains(loweredCallee),
           finalArguments.count == 2,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: sourceArgExprs.first,
               loweredComparatorID: finalArguments[1],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return [finalArguments[0]] + comparatorArgs
        }

        if loweredCallee == interner.intern("kk_list_binarySearch_comparator"),
           finalArguments.count == 5,
           sourceArgExprs.count >= 2,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: sourceArgExprs[1],
               loweredComparatorID: finalArguments[2],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            var adapted: [KIRExprID] = [finalArguments[0], finalArguments[1]]
            adapted.append(contentsOf: comparatorArgs)
            adapted.append(contentsOf: finalArguments[3...])
            return adapted
        }

        let arrayBinarySearchCallee = interner.intern("kk_array_binarySearch_compare")
        if loweredCallee == arrayBinarySearchCallee,
           finalArguments.count >= 3,
           sourceArgExprs.count >= 2,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: sourceArgExprs[1],
               loweredComparatorID: finalArguments[2],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            var adapted: [KIRExprID] = [finalArguments[0], finalArguments[1]]
            adapted.append(contentsOf: comparatorArgs)
            if finalArguments.count > 3 {
                adapted.append(contentsOf: finalArguments.dropFirst(3))
            }
            return adapted
        }

        let comparatorSelectorCallees: Set<InternedString> = [
            interner.intern("kk_list_maxOfWith"),
            interner.intern("kk_list_maxOfWithOrNull"),
            interner.intern("kk_list_minOfWith"),
            interner.intern("kk_list_minOfWithOrNull"),
        ]
        if comparatorSelectorCallees.contains(loweredCallee),
           sourceArgExprs.count == 2
        {
            let hasReceiver = finalArguments.count >= 4
            let receiverArg = hasReceiver ? finalArguments[0] : nil
            let comparatorIndex = hasReceiver ? 1 : 0
            let selectorStartIndex = hasReceiver ? 2 : 1
            guard finalArguments.count >= selectorStartIndex + 2,
                  let comparatorArgs = makeComparatorTrampolineArgument(
                      comparatorExprID: sourceArgExprs.first,
                      loweredComparatorID: finalArguments[comparatorIndex],
                      sema: sema,
                      arena: arena,
                      interner: interner,
                      instructions: &instructions
                  )
            else {
                return finalArguments
            }

            var adapted: [KIRExprID] = []
            if let receiverArg {
                adapted.append(receiverArg)
            }
            adapted.append(contentsOf: comparatorArgs)
            adapted.append(contentsOf: finalArguments[selectorStartIndex...])
            return adapted
        }

        let arrayBinarySearchComparatorCallees: Set<InternedString> = [
            interner.intern("kk_array_binarySearch_compare"),
        ]
        if arrayBinarySearchComparatorCallees.contains(loweredCallee),
           sourceArgExprs.count == 4,
           finalArguments.count >= 5,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: sourceArgExprs[1],
               loweredComparatorID: finalArguments[2],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            var adapted: [KIRExprID] = [finalArguments[0], finalArguments[1]]
            adapted.append(contentsOf: comparatorArgs)
            adapted.append(contentsOf: finalArguments.dropFirst(3))
            return adapted
        }

        return finalArguments
    }

    private func makeCollectionHOFCallableAdapter(
        callableInfo: KIRCallableValueInfo,
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> KIRCallableValueInfo? {
        let callableType = arena.exprType(loweredArgID) ?? sema.bindings.exprTypes[argExprID] ?? sema.types.anyType
        let nonNullCallableType = sema.types.makeNonNullable(callableType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCallableType) else {
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_hof_adapter_\(argExprID.rawValue)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        // Build value parameters including the receiver (if present).
        // For receiver-bearing function types like `DeepRecursiveScope<T,R>.(T) -> R`,
        // the receiver is stored in `functionType.receiver` and must be forwarded
        // as an explicit parameter so the adapter's ABI matches the runtime call site.
        var allValueTypes: [TypeID] = []
        if let receiverType = functionType.receiver {
            allValueTypes.append(receiverType)
        }
        allValueTypes.append(contentsOf: functionType.params)
        let valueParams: [KIRParameter] = allValueTypes.enumerated().map { index, type in
            KIRParameter(
                symbol: SymbolID(rawValue: Int32(clamping: -700_000 - Int64(argExprID.rawValue) * 16 - Int64(index))),
                type: type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        var callArguments: [KIRExprID] = []
        if callableInfo.captureArguments.count >= 2 {
            let kkArrayGet = interner.intern("kk_array_get_inbounds")
            for (captureIndex, captureExpr) in callableInfo.captureArguments.enumerated() {
                let captureType = arena.exprType(captureExpr) ?? sema.types.anyType
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
                let loadedExpr = arena.appendExpr(
                    .temporary(Int32(clamping: arena.expressions.count)),
                    type: captureType
                )
                body.append(.call(
                    symbol: nil,
                    callee: kkArrayGet,
                    arguments: [closureExpr, offsetExpr],
                    result: loadedExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                callArguments.append(loadedExpr)
            }
        } else if !callableInfo.captureArguments.isEmpty {
            callArguments.append(closureExpr)
        }

        for param in valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            callArguments.append(paramExpr)
        }

        let callResult = arena.appendExpr(
            .temporary(Int32(clamping: arena.expressions.count)),
            type: functionType.returnType
        )
        body.append(.call(
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            arguments: callArguments,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        switch sema.types.kind(of: functionType.returnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: adapterSymbol,
                    name: adapterName,
                    params: [closureParam] + valueParams,
                    returnType: functionType.returnType,
                    body: body,
                    isSuspend: functionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        return KIRCallableValueInfo(
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: callableInfo.captureArguments,
            hasClosureParam: true
        )
    }

    private func tryLowerObjectMemberPropertyRead(
        _ exprID: ExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let chosenSym = sema.bindings.callBindings[exprID]?.chosenCallee
        let valueSym = chosenSym ?? sema.bindings.identifierSymbol(for: exprID)
        guard let valueSym,
              let info = sema.symbols.symbol(valueSym),
              info.kind == .property,
              let parent = sema.symbols.parentSymbol(for: valueSym),
              sema.symbols.symbol(parent)?.kind == .object
        else { return nil }
        if info.flags.contains(.constValue),
           let constant = sema.symbols.constValueExprKind(for: valueSym)
        {
            let propType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSym)
                ?? sema.types.anyType
            let id = arena.appendExpr(constant, type: propType)
            instructions.append(.constValue(result: id, value: constant))
            return id
        }
        let knownNames = KnownCompilerNames(interner: interner)
        if let parentInfo = sema.symbols.symbol(parent),
           parentInfo.name == knownNames.dispatchers
        {
            let runtimeCallee: InternedString
            switch interner.resolve(info.name) {
            case "Default":
                runtimeCallee = interner.intern("kk_dispatcher_default")
            case "IO":
                runtimeCallee = interner.intern("kk_dispatcher_io")
            case "Main":
                runtimeCallee = interner.intern("kk_dispatcher_main")
            default:
                return nil
            }
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.bindings.exprTypes[exprID]
                    ?? sema.symbols.propertyType(for: valueSym)
                    ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        // STDLIB-581: Charsets.UTF_8 / ISO_8859_1 / US_ASCII / UTF_16 / ...
        if let parentInfo = sema.symbols.symbol(parent),
           parentInfo.name == knownNames.charsets
        {
            let runtimeCallee = interner.intern("kk_charset_\(interner.resolve(info.name).lowercased())")
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.bindings.exprTypes[exprID]
                    ?? sema.symbols.propertyType(for: valueSym)
                    ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        if let parentInfo = sema.symbols.symbol(parent),
           interner.resolve(parentInfo.name) == "NormalizationForms"
        {
            let runtimeCallee = interner.intern("kk_normalization_form_\(interner.resolve(info.name).lowercased())")
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.bindings.exprTypes[exprID]
                    ?? sema.symbols.propertyType(for: valueSym)
                    ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        let propType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: valueSym)
            ?? sema.types.anyType
        let id = arena.appendExpr(.symbolRef(valueSym), type: propType)
        instructions.append(.loadGlobal(result: id, symbol: valueSym))
        return wrapLateinitReadIfNeeded(
            id,
            symbol: valueSym,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func tryLowerObjectLiteralStoredPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              sema.bindings.isObjectLiteralPropertySymbol(propertySymbol)
        else {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
        if objectLiteralPropertyUsesAccessor(propertySymbol, ast: ast, sema: sema) {
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: propertySymbol,
                callee: interner.intern("get"),
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        guard let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[propertySymbol]
        else {
            return nil
        }

        let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
        instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [loweredReceiverID, offsetExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return wrapLateinitReadIfNeeded(
            result,
            symbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func tryLowerStoredMemberPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              let ownerInfo = sema.symbols.symbol(ownerSymbol),
              ownerInfo.kind == .class || ownerInfo.kind == .interface
              || ownerInfo.kind == .object,
              let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                  sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
              ]
        else {
            return nil
        }

        // Array-like types (Array, IntArray, LongArray, etc.) expose
        // properties such as `size` via runtime helper functions rather than
        // object field layout, so let the collection fallback lower them.
        let knownNames = KnownCompilerNames(interner: interner)
        if knownNames.isArrayLikeName(ownerInfo.name) {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: propertySymbol)
            ?? sema.types.anyType
        let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
        instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [loweredReceiverID, offsetExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return wrapLateinitReadIfNeeded(
            result,
            symbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func tryLowerEnumEntryPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        receiverExpr _: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let calleeStr = interner.resolve(calleeName)
        guard calleeStr == "name" || calleeStr == "ordinal" else { return nil }
        guard case let .symbolRef(entrySym) = arena.expr(loweredReceiverID),
              isEnumEntryField(entrySym, sema: sema),
              let entryInfo = sema.symbols.symbol(entrySym)
        else { return nil }
        let entryName = interner.resolve(entryInfo.name)
        let helperSuffix = calleeStr == "name" ? "$enumName" : "$enumOrdinal"
        let helperName = interner.intern(entryName + helperSuffix)
        let resultType = sema.bindings.exprTypes[exprID]
            ?? (calleeStr == "name"
                ? sema.types.make(.primitive(.string, .nonNull))
                : sema.types.make(.primitive(.int, .nonNull)))
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: helperName,
            arguments: [],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    private func tryLowerExternalMemberPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              let externalLinkName = sema.symbols.externalLinkName(for: propertySymbol),
              !externalLinkName.isEmpty
        else {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: propertySymbol)
            ?? sema.types.anyType
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
        instructions.append(.call(
            symbol: propertySymbol,
            callee: interner.intern(externalLinkName),
            arguments: [loweredReceiverID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return wrapLateinitReadIfNeeded(
            result,
            symbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func objectLiteralPropertyUsesAccessor(
        _ propertySymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule
    ) -> Bool {
        for rawDecl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(rawDecl))
            guard sema.bindings.declSymbols[declID] == propertySymbol,
                  let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            return propertyDecl.getter != nil || propertyDecl.delegateExpression != nil
        }
        return false
    }

    private func tryLowerClassNameMemberValueExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              sema.bindings.callBindings[exprID] == nil,
              let receiverExprNode = ast.arena.expr(receiverExpr),
              case .nameRef = receiverExprNode,
              let receiverSymbolID = sema.bindings.identifierSymbol(for: receiverExpr),
              let receiverSymbol = sema.symbols.symbol(receiverSymbolID)
        else {
            return nil
        }
        guard receiverSymbol.kind == .class || receiverSymbol.kind == .interface || receiverSymbol.kind == .enumClass,
              let valueSymbolID = sema.bindings.identifierSymbol(for: exprID),
              let valueSymbol = sema.symbols.symbol(valueSymbolID)
        else {
            return nil
        }

        switch valueSymbol.kind {
        case .property where valueSymbol.flags.contains(.constValue):
            guard let constant = sema.symbols.constValueExprKind(for: valueSymbolID) else {
                return nil
            }
            let valueType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSymbolID)
                ?? sema.types.anyType
            let valueID = arena.appendExpr(constant, type: valueType)
            instructions.append(.constValue(result: valueID, value: constant))
            return valueID

        case .field:
            guard isEnumEntryField(valueSymbolID, sema: sema) else {
                return nil
            }
            let valueType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSymbolID)
                ?? sema.types.anyType
            let valueID = arena.appendExpr(.symbolRef(valueSymbolID), type: valueType)
            instructions.append(.constValue(result: valueID, value: .symbolRef(valueSymbolID)))
            return valueID

        case .object:
            let valueType = sema.bindings.exprTypes[exprID] ?? sema.types.make(.classType(ClassType(
                classSymbol: valueSymbolID,
                args: [],
                nullability: .nonNull
            )))
            let valueID = arena.appendExpr(.symbolRef(valueSymbolID), type: valueType)
            instructions.append(.constValue(result: valueID, value: .symbolRef(valueSymbolID)))
            return valueID

        default:
            return nil
        }
    }

    private func isEnumEntryField(_ fieldSymbol: SymbolID, sema: SemaModule) -> Bool {
        if let parentSymbol = sema.symbols.parentSymbol(for: fieldSymbol),
           sema.symbols.symbol(parentSymbol)?.kind == .enumClass
        {
            return true
        }
        guard let field = sema.symbols.symbol(fieldSymbol),
              field.kind == .field,
              field.fqName.count >= 2
        else {
            return false
        }
        let ownerFQName = Array(field.fqName.dropLast())
        return sema.symbols.lookupAll(fqName: ownerFQName).contains { candidate in
            sema.symbols.symbol(candidate)?.kind == .enumClass
        }
    }

    private func tryFoldConstMemberProperty(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        requireNonNullableReceiver: Bool,
        sema: SemaModule,
        arena: KIRArena,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let callBinding = sema.bindings.callBindings[exprID]
        guard let chosen = callBinding?.chosenCallee,
              let symInfo = sema.symbols.symbol(chosen),
              symInfo.flags.contains(.constValue)
        else {
            return nil
        }
        let constant = propertyConstantInitializers[chosen] ?? sema.symbols.constValueExprKind(for: chosen)
        guard let constant else { return nil }
        if requireNonNullableReceiver {
            guard let receiverType = sema.bindings.exprTypes[receiverExpr],
                  receiverType == sema.types.makeNonNullable(receiverType)
            else {
                return nil
            }
        }
        let boundType = sema.bindings.exprTypes[exprID]
        let id = arena.appendExpr(constant, type: boundType ?? sema.types.anyType)
        instructions.append(.constValue(result: id, value: constant))
        return id
    }

    private func shouldLowerPrimitiveInv(
        receiverExpr: ExprID,
        sema: SemaModule,
        nullableReceiverAllowed: Bool
    ) -> Bool {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let uintType = sema.types.make(.primitive(.uint, .nonNull))
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
        let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
        let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
        var receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        if nullableReceiverAllowed {
            receiverType = sema.types.makeNonNullable(receiverType)
        }
        return receiverType == intType || receiverType == longType || receiverType == uintType || receiverType == ulongType || receiverType == ubyteType || receiverType == ushortType
    }

    private func appendReceiverToMemberArguments(
        _ loweredReceiverID: KIRExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        chosenCallee: SymbolID?,
        prependReceiverForUnresolvedCollectionCall: Bool,
        sema: SemaModule,
        interner: StringInterner,
        arguments: inout [KIRExprID]
    ) {
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let calleeText = interner.resolve(calleeName)
        if sema.bindings.isRangeExpr(receiverExpr) {
            let rangeMembers: Set<String> = [
                "first", "last", "endExclusive", "step", "contains", "isEmpty", "sum", "count",
                "toList", "forEach", "map", "mapIndexed", "mapNotNull",
                "filter", "filterIndexed", "filterNot", "reduce", "reduceIndexed",
                "fold", "foldIndexed", "find", "findLast", "firstOrNull",
                "lastOrNull", "any", "all", "none", "chunked", "windowed",
                "reversed",
                "take", "drop", "average", "sorted",
                "random",
            ]
            if rangeMembers.contains(calleeText) {
                arguments.insert(loweredReceiverID, at: 0)
                return
            }
        }
        if let chosenCallee,
           let signature = sema.symbols.functionSignature(for: chosenCallee),
           signature.receiverType != nil
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        guard chosenCallee == nil,
              prependReceiverForUnresolvedCollectionCall
        else {
            return
        }
        if Self.unresolvedCollectionMemberNames.contains(calleeText) {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        // String.length: extension needs receiver even when chosenCallee is nil
        // (e.g. mapIndexed { _, v -> v.length } where type inference may not bind).
        // Always prepend receiver for "length" — codegen maps to kk_string_length when
        // receiver is String; other types would be a type error at use site.
        if calleeText == "length" {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        let isCoroutineHandleReceiver = isCoroutineHandleReceiverType(
            receiverType,
            sema: sema,
            interner: interner
        )
        if isCoroutineHandleReceiver,
           Self.unresolvedCoroutineHandleMemberNames.contains(calleeText)
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        let isChannelReceiver = isChannelReceiverType(
            receiverType,
            sema: sema,
            interner: interner
        )
        if isChannelReceiver,
           Self.unresolvedChannelMemberNames.contains(calleeText)
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        // removeFirst/removeLast are scoped to ArrayDeque receivers only;
        // they must NOT go through the general unresolvedCollectionMemberNames
        // path because MutableList also has these methods and would get
        // incorrect callee mapping.
        if (calleeText == "removeFirst" || calleeText == "removeLast"),
           isArrayDequeLikeType(receiverType, sema: sema, interner: interner)
        {
            arguments.insert(loweredReceiverID, at: 0)
        }
    }

    func emitMemberCallInstruction(
        normalized: NormalizedCallResult,
        callBinding: CallBinding?,
        chosenCallee: SymbolID?,
        calleeName: InternedString,
        receiver: MemberCallReceiver,
        result: KIRExprID,
        isSuperCall: Bool,
        qualifiedSuperType: SymbolID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: [KIRExprID],
        sourceArgExprs: [ExprID] = [],
        sourceArgLabels: [InternedString?] = []
    ) {
        var finalArguments = arguments
        let hasHOFLambdaArg = sourceArgExprs.contains { sema.bindings.isCollectionHOFLambdaExpr($0) }
        if normalized.defaultMask != 0,
           let chosenCallee,
           let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
           externalLinkName == "kk_list_joinToString"
            || externalLinkName == "kk_iterable_joinTo"
            || externalLinkName == "kk_iterable_joinToString"
        {
            materializeJoinToStringDefaultArguments(
                normalized.defaultMask,
                firstDefaultParameterIndex: externalLinkName == "kk_iterable_joinTo" ? 1 : 0,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if normalized.defaultMask != 0,
           let chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee)?.isEmpty ?? true
        {
            appendReifiedTypeTokens(
                chosenCallee: chosenCallee,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArguments
            )
            appendDefaultMaskArgument(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArguments
            )
            let stubName = interner.intern(interner.resolve(calleeName) + "$default")
            let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: chosenCallee)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: isSuperCall,
                qualifiedSuperType: qualifiedSuperType
            ))
            return
        }

        appendReifiedTypeTokens(
            chosenCallee: chosenCallee,
            callBinding: callBinding,
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions,
            arguments: &finalArguments
        )

        var loweredCallee = loweredMemberCalleeName(
            chosenCallee: chosenCallee,
            fallback: calleeName,
            receiverExpr: receiver.expr,
            argumentCount: finalArguments.count,
            sourceArgumentCount: sourceArgExprs.count,
            hasHOFLambdaArg: hasHOFLambdaArg,
            sema: sema,
            interner: interner
        )
        if loweredCallee == interner.intern("kk_random_nextLong_until"),
           sourceArgExprs.count == 1,
           sema.bindings.isRangeExpr(sourceArgExprs[0])
        {
            loweredCallee = interner.intern("kk_random_nextLong_rangeObject")
        }
        if loweredCallee == interner.intern("kk_random_nextInt_until"),
           sourceArgExprs.count == 1,
           (sema.bindings.isRangeExpr(sourceArgExprs[0])
            || nominalRangeElementType(
                for: sema.bindings.exprTypes[sourceArgExprs[0]] ?? sema.types.anyType,
                sema: sema,
                interner: interner
            ) == sema.types.intType)
        {
            loweredCallee = interner.intern("kk_random_nextInt_rangeObject")
        }
        if loweredCallee == interner.intern("kk_list_binarySearch_comparator") {
            materializeBinarySearchDefaultArguments(
                normalized.defaultMask,
                receiverExpr: receiver.expr,
                loweredReceiverID: receiver.loweredID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments,
                sourceArgLabels: sourceArgLabels
            )
        }
        if let primitiveSelectorKind = collectionSelectorPrimitiveCompareKind(of: sourceArgExprs.first, sema: sema),
           finalArguments.count >= 3
        {
            switch loweredCallee {
            case interner.intern("kk_mutable_list_sortBy"):
                loweredCallee = interner.intern("kk_mutable_list_sortBy_primitive")
            case interner.intern("kk_mutable_list_sortByDescending"):
                loweredCallee = interner.intern("kk_mutable_list_sortByDescending_primitive")
            default:
                break
            }
            if loweredCallee == interner.intern("kk_mutable_list_sortBy_primitive")
                || loweredCallee == interner.intern("kk_mutable_list_sortByDescending_primitive")
            {
                let kindExpr = arena.appendExpr(.intLiteral(Int64(primitiveSelectorKind.rawValue)), type: sema.types.intType)
                instructions.append(.constValue(result: kindExpr, value: .intLiteral(Int64(primitiveSelectorKind.rawValue))))
                finalArguments.append(kindExpr)
            }
        }
        finalArguments = adaptComparatorBackedCollectionArguments(
            loweredCallee: loweredCallee,
            finalArguments: finalArguments,
            sourceArgExprs: sourceArgExprs,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if (loweredCallee == interner.intern("kk_comparator_then_by_comparator_selector")
            || loweredCallee == interner.intern("kk_comparator_then_by_descending_comparator_selector")),
           finalArguments.count == 3,
           sourceArgExprs.count == 2,
           let primaryComparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: receiver.expr,
               loweredComparatorID: finalArguments[0],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            let (selectorFnExpr, selectorEnvExpr) = splitCallableLambdaArgument(
                finalArguments[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = primaryComparatorArgs + [finalArguments[1], selectorFnExpr, selectorEnvExpr]
        }
        if normalized.defaultMask != 0,
           loweredCallee == interner.intern("kk_array_binarySearch_compare")
        {
            materializeArrayBinarySearchDefaultArguments(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if normalized.defaultMask != 0,
           loweredCallee == interner.intern("kk_array_copyInto")
        {
            materializeArrayCopyIntoDefaultArguments(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if loweredCallee == interner.intern("kk_list_windowed_transform") {
            let originalArgumentCount = finalArguments.count
            if originalArgumentCount >= 3 {
                let lambdaArgIndex = originalArgumentCount - 1
                let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                    finalArguments[lambdaArgIndex],
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                finalArguments[lambdaArgIndex] = fnPtrExpr
                finalArguments.append(envPtrExpr)
            }
            if originalArgumentCount == 3 {
                // `windowed(size, transform)` expands to `windowed(size, 1, false, transform)`.
                let oneExpr = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                instructions.append(.constValue(result: oneExpr, value: .intLiteral(1)))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArguments.insert(oneExpr, at: 2)
                finalArguments.insert(zeroExpr, at: 3)
            } else if originalArgumentCount == 4 {
                // `windowed(size, step, transform)` expands to
                // `windowed(size, step, false, transform)`.
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArguments.insert(zeroExpr, at: 3)
            }
        }
        if loweredCallee == interner.intern("kk_sequence_windowed"),
           hasHOFLambdaArg
        {
            loweredCallee = interner.intern("kk_sequence_windowed_transform")
            let originalArgumentCount = finalArguments.count
            if originalArgumentCount == 4 {
                // `windowed(size, transform)` expands to `windowed(size, 1, false, transform)`.
                let oneExpr = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                instructions.append(.constValue(result: oneExpr, value: .intLiteral(1)))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArguments.insert(oneExpr, at: 2)
                finalArguments.insert(zeroExpr, at: 3)
            } else if originalArgumentCount == 5 {
                // `windowed(size, step, transform)` expands to
                // `windowed(size, step, false, transform)`.
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArguments.insert(zeroExpr, at: 3)
            }
        }
        if loweredCallee == interner.intern("kk_sequence_chunked"),
           hasHOFLambdaArg,
           finalArguments.count == 3
        {
            loweredCallee = interner.intern("kk_sequence_chunked_transform")
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments[2] = fnPtrExpr
            finalArguments.append(envPtrExpr)
        }
        if (loweredCallee == interner.intern("kk_sequence_firstNotNullOf")
            || loweredCallee == interner.intern("kk_sequence_firstNotNullOfOrNull")),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if (loweredCallee == interner.intern("kk_iterable_firstNotNullOf")
            || loweredCallee == interner.intern("kk_iterable_firstNotNullOfOrNull")),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if (loweredCallee == interner.intern("kk_list_sumOf")
            || loweredCallee == interner.intern("kk_list_sumBy")
            || loweredCallee == interner.intern("kk_list_sumByDouble")
            || loweredCallee == interner.intern("kk_sequence_sumBy")
            || loweredCallee == interner.intern("kk_sequence_sumByDouble")),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if loweredCallee == interner.intern("kk_array_copyOf_newSize_init"),
           finalArguments.count == 3
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], finalArguments[1], fnPtrExpr, envPtrExpr]
        }
        if let primitiveKind = collectionElementPrimitiveCompareKind(
            of: sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType,
            sema: sema
        ) {
            let primitiveSortCallees: Set<InternedString> = [
                interner.intern("kk_list_sorted_primitive"),
                interner.intern("kk_list_sortedDescending_primitive"),
                interner.intern("kk_mutable_list_sort_primitive"),
                interner.intern("kk_mutable_list_sortDescending_primitive"),
            ]
            if primitiveSortCallees.contains(loweredCallee),
               finalArguments.count == 1
            {
                let kindExpr = arena.appendExpr(.intLiteral(Int64(primitiveKind.rawValue)), type: sema.types.intType)
                instructions.append(.constValue(result: kindExpr, value: .intLiteral(Int64(primitiveKind.rawValue))))
                finalArguments.append(kindExpr)
            }
        }
        if isArrayBinarySearchRuntimeCallee(loweredCallee, interner: interner) {
            let receiverType = sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType
            let sizeRuntimeCallee = arraySizeRuntimeCallee(
                for: receiverType,
                sema: sema,
                interner: interner
            )
            let memberArgumentCount = finalArguments.count - 1
            if memberArgumentCount == 1 || memberArgumentCount == 2 {
                let sizeExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.intType)
                instructions.append(.call(
                    symbol: nil,
                    callee: sizeRuntimeCallee,
                    arguments: [receiver.loweredID],
                    result: sizeExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                if memberArgumentCount == 1 {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    finalArguments.append(zeroExpr)
                }
                finalArguments.append(sizeExpr)
            }
        }
        let comparatorOnlyCallees: Set<InternedString> = [
            interner.intern("kk_list_maxWith"),
            interner.intern("kk_list_maxWithOrNull"),
            interner.intern("kk_list_minWith"),
            interner.intern("kk_list_minWithOrNull"),
            interner.intern("kk_list_sortedWith"),
            interner.intern("kk_array_sortedArrayWith"),
        ]
        if comparatorOnlyCallees.contains(loweredCallee),
           finalArguments.count == 2,
           let comparatorArgs = makeComparatorTrampolineArgument(
               comparatorExprID: nil,
               loweredComparatorID: finalArguments[1],
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            finalArguments = [finalArguments[0]] + comparatorArgs
        }
        if loweredCallee == interner.intern("kk_channel_send")
            || loweredCallee == interner.intern("kk_channel_receive")
            || loweredCallee == interner.intern("kk_mutex_lock")
            || loweredCallee == interner.intern("kk_semaphore_acquire")
        {
            let continuationExpr = arena.appendExpr(
                .intLiteral(0),
                type: sema.types.intType
            )
            instructions.append(.constValue(result: continuationExpr, value: .intLiteral(0)))
            finalArguments.append(continuationExpr)
        }
        // kk_mutex_withLock(handle, actionFnPtr, actionEnvPtr, continuation): split the lambda
        // argument at index 1 into a function pointer and environment pointer,
        // following the standard closure-conversion ABI used by collection HOFs.
        // A zero continuation placeholder is appended as the 4th argument because the
        // current runtime path blocks on contention and keeps the ABI shape aligned
        // with the suspend-aware mutex entry point.
        if loweredCallee == interner.intern("kk_mutex_withLock"),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let continuationExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: continuationExpr, value: .intLiteral(0)))
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr, continuationExpr]
        }
        // kk_lock_withLock(handle, actionFnPtr, actionEnvPtr),
        // kk_read_write_lock_read(handle, actionFnPtr, actionEnvPtr), and
        // kk_read_write_lock_write(handle, actionFnPtr, actionEnvPtr): split the
        // lambda argument at index 1 into a function pointer and environment pointer.
        if loweredCallee == interner.intern("kk_lock_withLock")
            || loweredCallee == interner.intern("kk_read_write_lock_read")
            || loweredCallee == interner.intern("kk_read_write_lock_write"),
           finalArguments.count == 2
        {
            let lambdaID = finalArguments[1]
            let fnPtrExpr: KIRExprID
            let envPtrExpr: KIRExprID
            if let callableInfo = driver.ctx.callableValueInfo(for: lambdaID) {
                fnPtrExpr = arena.appendExpr(
                    .symbolRef(callableInfo.symbol),
                    type: sema.types.anyType
                )
                instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
                if callableInfo.captureArguments.count >= 2 {
                    // Multi-capture: pack captures into a closure object.
                    // The lambda has been generated to unpack them via kk_array_get_inbounds.
                    let intType = sema.types.intType
                    let anyType = sema.types.anyType
                    let kkObjectNew = interner.intern("kk_object_new")
                    let kkArraySet = interner.intern("kk_array_set")
                    let slotCount = Int64(2 + callableInfo.captureArguments.count)
                    let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
                    instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
                    let classIDExpr = arena.appendExpr(.intLiteral(0), type: intType)
                    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
                    let closureObjExpr = arena.appendExpr(
                        .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: kkObjectNew,
                        arguments: [slotCountExpr, classIDExpr],
                        result: closureObjExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    for (captureIndex, captureArg) in callableInfo.captureArguments.enumerated() {
                        let fieldOffset = Int64(captureIndex + 2)
                        let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: intType)
                        instructions.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
                        let unusedResult = arena.appendExpr(
                            .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: kkArraySet,
                            arguments: [closureObjExpr, offsetExpr, captureArg],
                            result: unusedResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                    envPtrExpr = closureObjExpr
                } else if let closureRaw = callableInfo.captureArguments.first {
                    envPtrExpr = closureRaw
                } else {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    envPtrExpr = zeroExpr
                }
            } else {
                // Fallback when callableValueInfo is unavailable (e.g. stored lambda /
                // function reference): treat lambdaID as the function pointer and pass
                // zero as the environment pointer so the argument count always matches
                // the 3-parameter ABI (handle, actionFnPtr, actionEnvPtr).
                fnPtrExpr = lambdaID
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                envPtrExpr = zeroExpr
            }
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        // ReentrantReadWriteLock.read(handle, actionFnPtr, actionEnvPtr): split the lambda in
        // the same way as kk_mutex_withLock, but leave the continuation out because the call
        // is synchronous and throw-only.
        if loweredCallee == interner.intern("kk_reentrant_read_write_lock_read"),
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if let inst = tryEmitVirtualDispatch(
            chosenCallee: chosenCallee, calleeName: loweredCallee,
            receiverExpr: receiver.expr, loweredReceiverID: receiver.loweredID,
            isSuperCall: isSuperCall, finalArguments: finalArguments,
            result: result, sema: sema
        ) {
            instructions.append(inst)
            return
        }
        var callArguments = finalArguments
        if loweredCallee == interner.intern("kk_system_currentTimeMillis")
            || loweredCallee == interner.intern("kk_system_nanoTime")
            || loweredCallee == interner.intern("kk_system_process_start_nanos")
            || loweredCallee == interner.intern("kk_system_gc")
            || loweredCallee == interner.intern("kk_runtime_getRuntime")
            || loweredCallee == interner.intern("kk_runtime_totalMemory")
            || loweredCallee == interner.intern("kk_runtime_freeMemory")
            || loweredCallee == interner.intern("kk_runtime_maxMemory")
            || loweredCallee == interner.intern("kk_instant_now")
            || loweredCallee == interner.intern("kk_clock_system_now") {
            callArguments = []
        }
        // Result HOF functions accept an outThrown parameter but we don't need
        // the codegen to generate conditional thrown-check branches. Instead,
        // append a zero (null) pointer argument so the runtime receives the
        // expected parameter count, and keep canThrow=false to avoid control-
        // flow complexity.
        let resultHOFCallees: Set = [
            interner.intern("kk_result_onSuccess"),
            interner.intern("kk_result_onFailure"),
            interner.intern("kk_result_getOrElse"),
            interner.intern("kk_result_map"),
            interner.intern("kk_result_fold"),
            interner.intern("kk_result_recover"),
            interner.intern("kk_result_recoverCatching"),
            interner.intern("kk_result_mapCatching"),
            interner.intern("kk_result_flatMap"),
            interner.intern("kk_result_flatMapCatching"),
        ]
        if resultHOFCallees.contains(loweredCallee) {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            callArguments.append(zeroExpr)
        }
        let throwingCallees = Self.throwingMemberCalleeNames(interner: interner)
        let canThrow = throwingCallees.contains(loweredCallee)
        instructions.append(.call(
            symbol: chosenCallee,
            callee: loweredCallee,
            arguments: callArguments,
            result: result,
            canThrow: canThrow,
            thrownResult: nil,
            isSuperCall: isSuperCall,
            qualifiedSuperType: qualifiedSuperType
        ))
    }

    /// Cached set of runtime callee names whose `.call` should be emitted
    /// with `canThrow: true`. Hoisted from per-call `interner.intern()`
    /// invocations to avoid repeated interning in the hot lowering path.
    private static func throwingMemberCalleeNames(interner: StringInterner) -> Set<InternedString> {
        Set([
            interner.intern("kk_base64_decode_default"),
            interner.intern("kk_base64_decode_urlsafe"),
            interner.intern("kk_base64_decode_mime"),
            interner.intern("kk_base64_decodeFromByteArray_default"),
            interner.intern("kk_base64_decodeFromByteArray_urlsafe"),
            interner.intern("kk_base64_decodeFromByteArray_mime"),
            interner.intern("kk_base64_decode_instance"),
            interner.intern("kk_base64_decodeFromByteArray_instance"),
            interner.intern("kk_list_random"),
            interner.intern("kk_list_elementAt"),
            interner.intern("kk_list_take"),
            interner.intern("kk_list_takeLast"),
            interner.intern("kk_list_drop"),
            interner.intern("kk_list_maxOf"),
            interner.intern("kk_list_minOf"),
            interner.intern("kk_list_maxBy"),
            interner.intern("kk_list_maxWith"),
            interner.intern("kk_list_minWith"),
            interner.intern("kk_list_maxOfWith"),
            interner.intern("kk_list_minOfWith"),
            interner.intern("kk_list_fold"),
            interner.intern("kk_list_foldRight"),
            interner.intern("kk_list_reduce"),
            interner.intern("kk_list_reduceRight"),
            interner.intern("kk_list_reduceRightIndexed"),
            interner.intern("kk_list_reduceRightIndexedOrNull"),
            interner.intern("kk_list_reduceRightOrNull"),
            interner.intern("kk_list_reduceOrNull"),
            interner.intern("kk_list_scan"),
            interner.intern("kk_list_runningFold"),
            interner.intern("kk_list_runningReduce"),
            interner.intern("kk_list_scanReduce"),
            interner.intern("kk_list_filterIndexed"),
            interner.intern("kk_list_foldIndexed"),
            interner.intern("kk_list_foldRightIndexed"),
            interner.intern("kk_list_reduceIndexed"),
            interner.intern("kk_list_reduceIndexedOrNull"),
            interner.intern("kk_list_runningFoldIndexed"),
            interner.intern("kk_list_runningReduceIndexed"),
            interner.intern("kk_list_scanIndexed"),
            interner.intern("kk_list_sumOf"),
            interner.intern("kk_list_sumBy"),
            interner.intern("kk_list_sumByDouble"),
            interner.intern("kk_list_distinctBy"),
            interner.intern("kk_iterable_firstNotNullOf"),
            interner.intern("kk_iterable_firstNotNullOfOrNull"),
            interner.intern("kk_iterable_requireNoNulls"),
            interner.intern("kk_kclass_cast"),
            interner.intern("kk_range_first_predicate"),
            interner.intern("kk_range_last_predicate"),
            interner.intern("kk_range_random"),
            interner.intern("kk_range_random_random"),
            interner.intern("kk_random_nextInt_rangeObject"),
            interner.intern("kk_range_reduce"),
            interner.intern("kk_range_reduceIndexed"),
            interner.intern("kk_long_range_random"),
            interner.intern("kk_long_range_random_random"),
            interner.intern("kk_uint_range_random"),
            interner.intern("kk_uint_range_random_random"),
            interner.intern("kk_ulong_range_random"),
            interner.intern("kk_ulong_range_random_random"),
            interner.intern("kk_int_progression_fromClosedRange"),
            interner.intern("kk_long_progression_fromClosedRange"),
            interner.intern("kk_uint_progression_fromClosedRange"),
            interner.intern("kk_ulong_progression_fromClosedRange"),
            interner.intern("kk_sequence_foldIndexed"),
            interner.intern("kk_sequence_reduceIndexed"),
            interner.intern("kk_sequence_reduceIndexedOrNull"),
            interner.intern("kk_long_range_random"),
            interner.intern("kk_random_nextLong_rangeObject"),
            interner.intern("kk_uint_range_random"),
            interner.intern("kk_ulong_range_random"),
            interner.intern("kk_sequence_runningReduceIndexed"),
            interner.intern("kk_sequence_sortedBy"),
            interner.intern("kk_sequence_sumOf"),
            interner.intern("kk_sequence_sumBy"),
            interner.intern("kk_sequence_sumByDouble"),
            interner.intern("kk_sequence_firstNotNullOf"),
            interner.intern("kk_sequence_firstNotNullOfOrNull"),
            interner.intern("kk_sequence_associate"),
            interner.intern("kk_sequence_associateBy"),
            interner.intern("kk_sequence_associateTo"),
            interner.intern("kk_sequence_associateByTo"),
            interner.intern("kk_map_getValue"),
            interner.intern("kk_map_mapKeysTo"),
            interner.intern("kk_map_mapValuesTo"),
            interner.intern("kk_sequence_mapNotNull"),
            interner.intern("kk_sequence_firstNotNullOf"),
            interner.intern("kk_sequence_firstNotNullOfOrNull"),
            interner.intern("kk_sequence_mapIndexed"),
            interner.intern("kk_sequence_findLast"),
            interner.intern("kk_sequence_elementAt"),
            interner.intern("kk_sequence_minByOrNull"),
            interner.intern("kk_sequence_maxByOrNull"),
            interner.intern("kk_sequence_minOf"),
            interner.intern("kk_sequence_maxOf"),
            interner.intern("kk_sequence_partition"),
            interner.intern("kk_sequence_associateWith"),
            interner.intern("kk_sequence_associateWithTo"),
            interner.intern("kk_sequence_groupByTo"),
            interner.intern("kk_sequence_ifEmpty"),
            interner.intern("kk_string_ifBlank"),
            interner.intern("kk_string_ifEmpty"),
            interner.intern("kk_string_chunked_sequence_transform"),
            interner.intern("kk_sequence_first"),
            interner.intern("kk_sequence_last"),
            interner.intern("kk_sequence_firstOrNull"),
            interner.intern("kk_sequence_count"),
            interner.intern("kk_string_firstNotNullOf"),
            interner.intern("kk_string_firstNotNullOfOrNull"),
            interner.intern("kk_string_reduceRightIndexed"),
            interner.intern("kk_string_reduceRightIndexedOrNull"),
            interner.intern("kk_string_reduceRightOrNull"),
            interner.intern("kk_string_sumBy"),
            interner.intern("kk_string_sumByDouble"),
            interner.intern("kk_string_zipWithNextTransform"),
            interner.intern("kk_string_chunked_sequence_transform"),
            interner.intern("kk_string_windowedSequence_transform"),
            interner.intern("kk_sequence_to_list"),
            interner.intern("kk_list_windowed_transform"),
            interner.intern("kk_sequence_chunked_transform"),
            interner.intern("kk_sequence_runningFoldIndexed"),
            interner.intern("kk_array_copyOf_newSize_init"),
            interner.intern("kk_mutable_list_replaceAll"),
            interner.intern("kk_mutable_list_removeIf"),
            interner.intern("kk_list_binarySearch_compare"),
            interner.intern("kk_list_binarySearch_comparator"),
            interner.intern("kk_array_binarySearch_compare"),
            interner.intern("kk_array_sortedArrayWith"),
            interner.intern("kk_list_binarySearchBy"),
            interner.intern("kk_list_binarySearchBy_fromIndex"),
            interner.intern("kk_list_binarySearchBy_range"),
            interner.intern("kk_result_getOrThrow"),
            interner.intern("kk_reentrant_read_write_lock_read"),
        ])
    }

    private func tryLowerBase64MemberCall(
        receiverExpr: ExprID,
        loweredReceiverID: KIRExprID,
        calleeName: InternedString,
        chosenCallee: SymbolID?,
        argExprIDs: [ExprID],
        loweredArgIDs: [KIRExprID],
        argInstructionStart: Int,
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> Bool {
        let isResolvedBase64SyntheticMember = chosenCallee.map {
            isBase64SyntheticMemberSymbol(
                $0,
                sema: sema,
                interner: interner
            )
        } ?? true
        guard loweredArgIDs.count == 1,
              isResolvedBase64SyntheticMember,
              let receiverType = sema.bindings.exprTypes[receiverExpr],
              let receiverKind = base64RuntimeReceiverKind(
                  for: receiverType,
                  loweredReceiverID: loweredReceiverID,
                  arena: arena,
                  sema: sema,
                  interner: interner
              )
        else {
            return false
        }

        let callee = interner.resolve(calleeName)
        if callee == "withPadding" {
            let paddingArg: KIRExprID
            let rawPaddingValue = argExprIDs.first.flatMap {
                base64PaddingOptionRawValue(forExpr: $0, sema: sema, interner: interner)
            } ?? {
                guard case let .symbolRef(symbolID) = arena.expr(loweredArgIDs[0]) else {
                    return nil
                }
                return base64PaddingOptionRawValue(forSymbol: symbolID, sema: sema, interner: interner)
            }()
            if let rawValue = rawPaddingValue {
                if argInstructionStart < instructions.count {
                    instructions.removeSubrange(argInstructionStart ..< instructions.count)
                }
                paddingArg = arena.appendExpr(.intLiteral(Int64(rawValue)), type: sema.types.intType)
                instructions.append(.constValue(result: paddingArg, value: .intLiteral(Int64(rawValue))))
            } else {
                paddingArg = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.intType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_unbox_int"),
                    arguments: [loweredArgIDs[0]],
                    result: paddingArg,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            switch receiverKind {
            case .variant(let suffix):
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_base64_withPadding_\(suffix)"),
                    arguments: [paddingArg],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            case .instance:
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_base64_withPadding_instance"),
                    arguments: [loweredReceiverID, paddingArg],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return true
        }

        let operation: String
        let canThrow: Bool
        switch callee {
        case "encode":
            operation = "encode"
            canThrow = false
        case "decode":
            operation = "decode"
            canThrow = true
        case "encodeToByteArray":
            operation = "encodeToByteArray"
            canThrow = false
        case "decodeFromByteArray":
            operation = "decodeFromByteArray"
            canThrow = true
        default:
            return false
        }

        switch receiverKind {
        case .variant(let suffix):
            let paddingPresent = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: paddingPresent, value: .intLiteral(0)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_base64_\(operation)_\(suffix)"),
                arguments: [loweredArgIDs[0], paddingPresent],
                result: result,
                canThrow: canThrow,
                thrownResult: nil
            ))
        case .instance:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_base64_\(operation)_instance"),
                arguments: [loweredReceiverID, loweredArgIDs[0]],
                result: result,
                canThrow: canThrow,
                thrownResult: nil
            ))
        }
        return true
    }

    private func isBase64SyntheticMemberSymbol(
        _ symbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbolInfo = sema.symbols.symbol(symbol),
              symbolInfo.flags.contains(.synthetic),
              let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
              let ownerInfo = sema.symbols.symbol(ownerSymbol),
              ownerInfo.kind == .class || ownerInfo.kind == .object,
              let externalLink = sema.symbols.externalLinkName(for: symbol),
              externalLink.hasPrefix("kk_base64_"),
              !externalLink.hasSuffix("_fn")
        else {
            return false
        }

        let ownerFQName = ownerInfo.fqName.map { interner.resolve($0) }
        let base64FQName = ["kotlin", "io", "encoding", "Base64"]
        return ownerFQName == base64FQName
            || (ownerFQName.count == base64FQName.count + 1
                && Array(ownerFQName.prefix(base64FQName.count)) == base64FQName)
    }

    private enum Base64RuntimeReceiverKind {
        case variant(String)
        case instance
    }

    private func base64RuntimeReceiverKind(
        for receiverType: TypeID,
        loweredReceiverID: KIRExprID,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner
    ) -> Base64RuntimeReceiverKind? {
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        switch sema.types.kind(of: nonNullReceiver) {
        case let .classType(classType):
            guard let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return nil
            }

            let fqName = symbol.fqName.map { interner.resolve($0) }
            let base64FQName = ["kotlin", "io", "encoding", "Base64"]
            if fqName == base64FQName {
                return .instance
            }
            if let suffix = base64RuntimeVariantSuffix(forSymbol: classType.classSymbol, sema: sema, interner: interner) {
                return .variant(suffix)
            }
            return nil
        case let .typeParam(typeParam):
            guard let base64Symbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
            ]),
                  let base64Info = sema.symbols.symbol(base64Symbol),
                  base64Info.kind == .class
            else {
                return nil
            }
            let base64Type = sema.types.make(.classType(ClassType(
                classSymbol: base64Symbol,
                args: [],
                nullability: .nonNull
            )))
            guard sema.symbols.typeParameterUpperBounds(for: typeParam.symbol).contains(where: {
                sema.types.isSubtype(sema.types.makeNonNullable($0), base64Type)
            }) else {
                return nil
            }
            return .instance
        default:
            return nil
        }
    }

    private func base64RuntimeVariantSuffix(
        forSymbol symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return nil
        }
        let fqName = symbol.fqName.map { interner.resolve($0) }
        let base64FQName = ["kotlin", "io", "encoding", "Base64"]
        guard fqName.count == base64FQName.count + 1,
              Array(fqName.prefix(base64FQName.count)) == base64FQName
        else {
            return nil
        }

        switch fqName.last {
        case "Default":
            return "default"
        case "UrlSafe":
            return "urlsafe"
        case "Mime", "Pem":
            return "mime"
        default:
            return nil
        }
    }

    private func base64PaddingOptionRawValue(
        forExpr exprID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int? {
        guard let symbolID = sema.bindings.identifierSymbol(for: exprID)
        else {
            return nil
        }
        return base64PaddingOptionRawValue(forSymbol: symbolID, sema: sema, interner: interner)
    }

    private func base64PaddingOptionRawValue(
        forSymbol symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int? {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return nil
        }
        let fqName = symbol.fqName.map { interner.resolve($0) }
        guard fqName.count == 6,
              Array(fqName.prefix(5)) == ["kotlin", "io", "encoding", "Base64", "PaddingOption"]
        else {
            return nil
        }
        switch fqName.last {
        case "PRESENT":
            return 0
        case "ABSENT":
            return 1
        case "PRESENT_OPTIONAL":
            return 2
        case "ABSENT_OPTIONAL":
            return 3
        default:
            return nil
        }
    }

    private func splitCallableLambdaArgument(
        _ lambdaID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (fnPtrExpr: KIRExprID, envPtrExpr: KIRExprID) {
        let fnPtrExpr: KIRExprID
        let envPtrExpr: KIRExprID
        if let callableInfo = driver.ctx.callableValueInfo(for: lambdaID) {
            fnPtrExpr = arena.appendExpr(
                .symbolRef(callableInfo.symbol),
                type: sema.types.anyType
            )
            instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
            if callableInfo.captureArguments.count >= 2 {
                // Multi-capture: pack captures into a closure object.
                let intType = sema.types.intType
                let anyType = sema.types.anyType
                let kkObjectNew = interner.intern("kk_object_new")
                let kkArraySet = interner.intern("kk_array_set")
                let slotCount = Int64(2 + callableInfo.captureArguments.count)
                let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
                instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
                let classIDExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
                let closureObjExpr = arena.appendExpr(
                    .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: kkObjectNew,
                    arguments: [slotCountExpr, classIDExpr],
                    result: closureObjExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                for (captureIndex, captureArg) in callableInfo.captureArguments.enumerated() {
                    let fieldOffset = Int64(captureIndex + 2)
                    let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
                    let unusedResult = arena.appendExpr(
                        .temporary(Int32(clamping: arena.expressions.count)), type: anyType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: kkArraySet,
                        arguments: [closureObjExpr, offsetExpr, captureArg],
                        result: unusedResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                envPtrExpr = closureObjExpr
            } else if let closureRaw = callableInfo.captureArguments.first {
                envPtrExpr = closureRaw
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                envPtrExpr = zeroExpr
            }
        } else {
            // Fallback when callableValueInfo is unavailable (e.g. stored lambda /
            // function reference): treat lambdaID as the function pointer and pass
            // zero as the environment pointer so the argument count always matches
            // the closure-conversion ABI.
            fnPtrExpr = lambdaID
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            envPtrExpr = zeroExpr
        }
        return (fnPtrExpr, envPtrExpr)
    }

    private func materializeJoinToStringDefaultArguments(
        _ defaultMask: Int64,
        firstDefaultParameterIndex: Int = 0,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        let defaults = [", ", "", ""]
        let stringType = sema.types.stringType
        for (offset, defaultValue) in defaults.enumerated() {
            let paramIndex = firstDefaultParameterIndex + offset
            let maskBit = Int64(1) << paramIndex
            guard (defaultMask & maskBit) != 0 else { continue }
            let argumentIndex = paramIndex + 1
            guard argumentIndex < arguments.count else { continue }
            let interned = interner.intern(defaultValue)
            let exprID = arena.appendExpr(.stringLiteral(interned), type: stringType)
            instructions.append(.constValue(result: exprID, value: .stringLiteral(interned)))
            arguments[argumentIndex] = exprID
        }
    }

    private func materializeBinarySearchDefaultArguments(
        _ defaultMask: Int64,
        receiverExpr: ExprID,
        loweredReceiverID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID],
        sourceArgLabels: [InternedString?]
    ) {
        let intType = sema.types.intType
        var cachedZeroExpr: KIRExprID?
        var cachedSizeExpr: KIRExprID?

        func makeZeroExpr() -> KIRExprID {
            if let cachedZeroExpr {
                return cachedZeroExpr
            }
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            cachedZeroExpr = zeroExpr
            return zeroExpr
        }

        func makeSizeExpr() -> KIRExprID {
            if let cachedSizeExpr {
                return cachedSizeExpr
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let sizeCallee = unresolvedCollectionMemberCallee(
                memberName: "size",
                receiverType: receiverType,
                sema: sema,
                interner: interner
            ) ?? interner.intern("kk_list_size")
            let sizeExpr = arena.appendExpr(
                .temporary(Int32(clamping: arena.expressions.count)),
                type: intType
            )
            instructions.append(.call(
                symbol: nil,
                callee: sizeCallee,
                arguments: [loweredReceiverID],
                result: sizeExpr,
                canThrow: false,
                thrownResult: nil
            ))
            cachedSizeExpr = sizeExpr
            return sizeExpr
        }

        if defaultMask == 0 {
            if arguments.count <= 3 {
                arguments.append(makeZeroExpr())
                arguments.append(makeSizeExpr())
            } else if arguments.count == 4 {
                let explicitLabel = sourceArgLabels.last ?? nil
                if let explicitLabel, interner.resolve(explicitLabel) == "toIndex" {
                    arguments.insert(makeZeroExpr(), at: 3)
                } else {
                    arguments.append(makeSizeExpr())
                }
            }
            return
        }

        if (defaultMask & (Int64(1) << 2)) != 0,
           arguments.count > 3
        {
            arguments[3] = makeZeroExpr()
        }

        if (defaultMask & (Int64(1) << 3)) != 0,
           arguments.count > 4
        {
            arguments[4] = makeSizeExpr()
        }
    }

    private func materializeArrayBinarySearchDefaultArguments(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard arguments.count >= 6 else {
            return
        }

        let intType = sema.types.intType
        let fromIndexMaskBit = Int64(1) << 2
        let toIndexMaskBit = Int64(1) << 3
        if (defaultMask & fromIndexMaskBit) != 0 {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            arguments[4] = zeroExpr
        }

        if (defaultMask & toIndexMaskBit) != 0 {
            let sizeExpr = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_size"),
                arguments: [arguments[0]],
                result: sizeExpr,
                canThrow: false,
                thrownResult: nil
            ))
            arguments[5] = sizeExpr
        }
    }

    private func materializeArrayCopyIntoDefaultArguments(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard arguments.count >= 5 else {
            return
        }

        let intType = sema.types.intType
        let destinationOffsetMaskBit = Int64(1) << 1
        let startIndexMaskBit = Int64(1) << 2
        let endIndexMaskBit = Int64(1) << 3
        if (defaultMask & destinationOffsetMaskBit) != 0 {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            arguments[2] = zeroExpr
        }

        if (defaultMask & startIndexMaskBit) != 0 {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            arguments[3] = zeroExpr
        }

        if (defaultMask & endIndexMaskBit) != 0 {
            let sizeExpr = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_size"),
                arguments: [arguments[0]],
                result: sizeExpr,
                canThrow: false,
                thrownResult: nil
            ))
            arguments[4] = sizeExpr
        }
    }

    /// Callees with an externalLinkName (C runtime functions such as
    /// kk_array_get) are never dispatched virtually.
    private func tryEmitVirtualDispatch(
        chosenCallee: SymbolID?,
        calleeName: InternedString,
        receiverExpr: ExprID,
        loweredReceiverID: KIRExprID,
        isSuperCall: Bool,
        finalArguments: [KIRExprID],
        result: KIRExprID,
        sema: SemaModule
    ) -> KIRInstruction? {
        guard !isSuperCall, let chosenCallee else { return nil }
        let hasExternalLink = sema.symbols.externalLinkName(for: chosenCallee)
            .map { !$0.isEmpty } ?? false
        guard !hasExternalLink else { return nil }
        let receiverTypeForDispatch = sema.bindings.exprTypes[receiverExpr]
        guard let dispatchKind = resolveVirtualDispatch(
            callee: chosenCallee, receiverTypeID: receiverTypeForDispatch, sema: sema
        ) else { return nil }
        var vcArguments = finalArguments
        if let sig = sema.symbols.functionSignature(for: chosenCallee),
           sig.receiverType != nil, !vcArguments.isEmpty
        {
            vcArguments.removeFirst()
        }
        return .virtualCall(
            symbol: chosenCallee,
            callee: calleeName,
            receiver: loweredReceiverID,
            arguments: vcArguments,
            result: result,
            canThrow: false,
            thrownResult: nil,
            dispatch: dispatchKind
        )
    }

    private func loweredMemberCalleeName(
        chosenCallee: SymbolID?,
        fallback: InternedString,
        receiverExpr: ExprID,
        argumentCount: Int,
        sourceArgumentCount: Int? = nil,
        hasHOFLambdaArg: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        let callArgumentCount = sourceArgumentCount ?? argumentCount
        let fallbackName = interner.resolve(fallback)
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let isCharRange = sema.bindings.isCharRangeExpr(receiverExpr)
        var isCharProgressionReceiver = false
        let isProgressionReceiver: Bool = {
            guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            let name = interner.resolve(symbol.name)
            isCharProgressionReceiver = name == "CharProgression"
            return name == "IntProgression"
                || name == "LongProgression"
                || name == "LongRange"
                || name == "CharProgression"
                || name == "UIntRange"
                || name == "UIntProgression"
                || name == "ULongProgression"
        }()

        if (sema.bindings.isRangeExpr(receiverExpr) || isProgressionReceiver),
           fallbackName == "step",
           callArgumentCount <= 1
        {
            if isCharRange || isCharProgressionReceiver {
                return interner.intern("kk_char_range_step")
            }
            if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                return interner.intern("kk_ulong_range_step")
            }
            if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                return interner.intern("kk_uint_range_step")
            }
            if nonNullReceiverType == sema.types.longType {
                return interner.intern("kk_long_range_step")
            }
            return interner.intern("kk_range_step")
        }

        if (sema.bindings.isRangeExpr(receiverExpr) || isProgressionReceiver),
           !hasHOFLambdaArg
        {
            switch fallbackName {
            case "random":
                if isCharRange {
                    return callArgumentCount == 1
                        ? interner.intern("kk_char_range_random_random")
                        : interner.intern("kk_range_random")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return callArgumentCount == 1
                        ? interner.intern("kk_ulong_range_random_random")
                        : interner.intern("kk_ulong_range_random")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return callArgumentCount == 1
                        ? interner.intern("kk_uint_range_random_random")
                        : interner.intern("kk_uint_range_random")
                }
                if nonNullReceiverType == sema.types.longType {
                    return callArgumentCount == 1
                        ? interner.intern("kk_long_range_random_random")
                        : interner.intern("kk_long_range_random")
                }
                return callArgumentCount == 1
                    ? interner.intern("kk_range_random_random")
                    : interner.intern("kk_range_random")
            case "firstOrNull":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_firstOrNull")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_firstOrNull")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_firstOrNull")
                }
                return interner.intern("kk_range_firstOrNull")
            case "lastOrNull":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_lastOrNull")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_lastOrNull")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_lastOrNull")
                }
                return interner.intern("kk_range_lastOrNull")
            case "randomOrNull":
                if isCharRange {
                    return callArgumentCount == 1
                        ? interner.intern("kk_char_range_randomOrNull_random")
                        : interner.intern("kk_char_range_randomOrNull")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return callArgumentCount == 1
                        ? interner.intern("kk_ulong_range_randomOrNull_random")
                        : interner.intern("kk_ulong_range_randomOrNull")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return callArgumentCount == 1
                        ? interner.intern("kk_uint_range_randomOrNull_random")
                        : interner.intern("kk_uint_range_randomOrNull")
                }
                if nonNullReceiverType == sema.types.longType {
                    return callArgumentCount == 1
                        ? interner.intern("kk_long_range_randomOrNull_random")
                        : interner.intern("kk_long_range_randomOrNull")
                }
                return callArgumentCount == 1
                    ? interner.intern("kk_range_randomOrNull_random")
                    : interner.intern("kk_range_randomOrNull")
            default:
                break
            }
        }

        if let chosenCallee {
            if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
               !externalLinkName.isEmpty
            {
                if let closedRangeRuntimeName = closedRangeInterfaceRuntimeName(
                    memberName: fallbackName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                ) {
                    return closedRangeRuntimeName
                }
                if callArgumentCount == 1,
                   (externalLinkName == "kk_op_step"
                    || externalLinkName == "kk_uint_step"
                    || externalLinkName == "kk_ulong_step")
                {
                    if externalLinkName == "kk_ulong_step"
                        || sema.bindings.isULongRangeExpr(receiverExpr)
                        || nonNullReceiverType == sema.types.ulongType
                    {
                        return interner.intern("kk_ulong_range_step")
                    }
                    if nonNullReceiverType == sema.types.longType {
                        return interner.intern("kk_long_range_step")
                    }
                    return interner.intern("kk_range_step")
                }
                if externalLinkName == "kk_list_binarySearch" {
                    // STDLIB-547: When the element-based binarySearch overload was
                    // recovered but the call actually has a HOF lambda argument,
                    // redirect to the comparison-based runtime function.
                    if hasHOFLambdaArg && argumentCount == 2 {
                        return interner.intern("kk_list_binarySearch_compare")
                    }
                    if argumentCount > 2 {
                        return interner.intern("kk_list_binarySearch_comparator")
                    }
                }
                if (externalLinkName == "kk_list_binarySearch" || externalLinkName == "kk_array_binarySearch"),
                   isGenericArrayLikeType(nonNullReceiverType, sema: sema, interner: interner),
                   argumentCount == 5
                {
                    return interner.intern("kk_array_binarySearch_compare")
                }
                if (externalLinkName == "kk_list_binarySearch" || externalLinkName == "kk_array_binarySearch"),
                   isGenericArrayLikeType(nonNullReceiverType, sema: sema, interner: interner),
                   argumentCount == 5
                {
                    return interner.intern("kk_array_binarySearch_compare")
                }
                return interner.intern(externalLinkName)
            }
            if let unresolvedSynthetic = unresolvedSyntheticMemberCallee(
                memberName: fallbackName,
                receiverExpr: receiverExpr,
                receiverType: receiverType,
                argumentCount: callArgumentCount,
                hasHOFLambdaArg: hasHOFLambdaArg,
                sema: sema,
                interner: interner
            ) {
                return unresolvedSynthetic
            }
            // Collection interface members (size property, isEmpty function)
            // resolved on a concrete receiver (List, Array, Map, Set) must be
            // lowered to the matching runtime function instead of virtual dispatch.
            if let collectionProperty = unresolvedCollectionMemberCallee(
                memberName: fallbackName,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            ) {
                return collectionProperty
            }
            return fallback
        }

        if isCoroutineHandleReceiverType(receiverType, sema: sema, interner: interner) {
            switch fallbackName {
            case "await":
                return interner.intern("kk_kxmini_async_await")
            case "join":
                return interner.intern("kk_job_join")
            case "awaitCompletion":
                return interner.intern("kk_job_await_completion")
            case "cancel":
                return argumentCount > 1
                    ? interner.intern("kk_job_cancel_with_cause")
                    : interner.intern("kk_job_cancel")
            case "complete":
                return interner.intern("kk_job_complete")
            case "completeExceptionally":
                return interner.intern("kk_job_complete_exceptionally")
            case "isActive":
                return interner.intern("kk_job_is_active")
            case "isCompleted":
                return interner.intern("kk_job_is_completed")
            case "isCancelled":
                return interner.intern("kk_job_is_cancelled")
            default:
                break
            }
        }
        if isChannelReceiverType(receiverType, sema: sema, interner: interner) {
            switch fallbackName {
            case "send":
                return interner.intern("kk_channel_send")
            case "receive":
                return interner.intern("kk_channel_receive")
            case "close":
                return interner.intern("kk_channel_close")
            case "isClosedForReceive":
                return interner.intern("kk_channel_is_closed_for_receive")
            case "isClosedForSend":
                return interner.intern("kk_channel_is_closed_for_send")
            default:
                break
            }
        }
        if let collectionProperty = unresolvedCollectionMemberCallee(
            memberName: fallbackName,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) {
            return collectionProperty
        }
        if let mapMember = unresolvedMapMemberCallee(
            memberName: fallbackName,
            receiverType: receiverType,
            argumentCount: argumentCount,
            sema: sema,
            interner: interner
        ) {
            return mapMember
        }
        if let unresolvedSynthetic = unresolvedSyntheticMemberCallee(
            memberName: fallbackName,
            receiverExpr: receiverExpr,
            receiverType: receiverType,
            argumentCount: argumentCount,
            hasHOFLambdaArg: hasHOFLambdaArg,
            sema: sema,
            interner: interner
        ) {
            return unresolvedSynthetic
        }
        return fallback
    }

    private func closedRangeInterfaceRuntimeName(
        memberName: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
              let closedRangeSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlin"),
                  interner.intern("ranges"),
                  interner.intern("ClosedRange"),
              ]),
              let liftedArgs = sema.types.liftedNominalSupertypeArgs(
                  from: classType.classSymbol,
                  childArgs: classType.args,
                  to: closedRangeSymbol
              ),
              let typeArg = liftedArgs.first
        else {
            return nil
        }
        let elementType: TypeID
        switch typeArg {
        case let .invariant(type), let .out(type), let .in(type):
            elementType = type
        case .star:
            return nil
        }
        switch memberName {
        case "contains":
            if elementType == sema.types.longType {
                return interner.intern("kk_long_range_contains")
            }
            if elementType == sema.types.uintType {
                return interner.intern("kk_uint_range_contains")
            }
            if elementType == sema.types.ulongType {
                return interner.intern("kk_ulong_range_contains")
            }
            return nil
        case "isEmpty":
            if elementType == sema.types.longType {
                return interner.intern("kk_long_range_isEmpty")
            }
            if elementType == sema.types.uintType {
                return interner.intern("kk_uint_range_isEmpty")
            }
            if elementType == sema.types.ulongType {
                return interner.intern("kk_ulong_range_isEmpty")
            }
            return nil
        default:
            return nil
        }
    }

    // swiftlint:disable cyclomatic_complexity
    private func unresolvedSyntheticMemberCallee(
        memberName: String,
        receiverExpr: ExprID,
        receiverType: TypeID,
        argumentCount: Int,
        hasHOFLambdaArg: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let isCharProgressionReceiver: Bool = {
            guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            return interner.resolve(symbol.name) == "CharProgression"
        }()
        if sema.bindings.isRangeExpr(receiverExpr) || isCharProgressionReceiver {
            switch memberName {
            case "random":
                if argumentCount == 1 {
                    if sema.bindings.isCharRangeExpr(receiverExpr) || isCharProgressionReceiver {
                        return interner.intern("kk_char_range_random_random")
                    }
                    if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                        return interner.intern("kk_ulong_range_random_random")
                    }
                    if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                        return interner.intern("kk_uint_range_random_random")
                    }
                    if nonNullReceiverType == sema.types.longType {
                        return interner.intern("kk_long_range_random_random")
                    }
                    return interner.intern("kk_range_random_random")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern(argumentCount > 0 ? "kk_ulong_range_random_random" : "kk_ulong_range_random")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern(argumentCount > 0 ? "kk_uint_range_random_random" : "kk_uint_range_random")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern(argumentCount > 0 ? "kk_long_range_random_random" : "kk_long_range_random")
                }
                return interner.intern(argumentCount > 0 ? "kk_range_random_random" : "kk_range_random")
            case "contains":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_contains")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_contains")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_contains")
                }
                return interner.intern("kk_op_contains")
            case "isEmpty":
                if sema.bindings.isCharRangeExpr(receiverExpr) || isCharProgressionReceiver {
                    return interner.intern("kk_char_range_isEmpty")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_isEmpty")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_isEmpty")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_isEmpty")
                }
                return interner.intern("kk_range_isEmpty")
            case "endExclusive":
                return interner.intern("kk_range_endExclusive")
            case "sum":
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_sum")
                }
                return interner.intern("kk_range_sum")
            case "count":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_count")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_count")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_count")
                }
                return interner.intern("kk_range_count")
            case "toList":
                if sema.bindings.isCharRangeExpr(receiverExpr) || isCharProgressionReceiver {
                    return interner.intern("kk_char_range_toList")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_toList")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_toList")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_toList")
                }
                return interner.intern("kk_range_toList")
            case "toUIntArray":
                return interner.intern("kk_uint_range_toUIntArray")
            case "toULongArray":
                return interner.intern("kk_ulong_range_toULongArray")
            case "toLongArray":
                return interner.intern("kk_long_range_toLongArray")
            case "iterator":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_iterator")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_iterator")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_iterator")
                }
                return interner.intern("kk_range_iterator")
            case "forEach":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_forEach")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_forEach")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_forEach")
                }
                return interner.intern("kk_range_forEach")
            case "map":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_map")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_map")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_map")
                }
                return interner.intern("kk_range_map")
            case "mapIndexed":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_mapIndexed")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_mapIndexed")
                }
                return interner.intern("kk_range_mapIndexed")
            case "mapNotNull":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_mapNotNull")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_mapNotNull")
                }
                return interner.intern("kk_range_mapNotNull")
            case "filter":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_filter")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_filter")
                }
                return interner.intern("kk_range_filter")
            case "filterIndexed":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_filterIndexed")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_filterIndexed")
                }
                return interner.intern("kk_range_filterIndexed")
            case "filterNot":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_filterNot")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_filterNot")
                }
                return interner.intern("kk_range_filterNot")
            case "reduce":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_reduce")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_reduce")
                }
                return interner.intern("kk_range_reduce")
            case "reduceIndexed":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_reduceIndexed")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_reduceIndexed")
                }
                return interner.intern("kk_range_reduceIndexed")
            case "fold":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_fold")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_fold")
                }
                return interner.intern("kk_range_fold")
            case "foldIndexed":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_foldIndexed")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_foldIndexed")
                }
                return interner.intern("kk_range_foldIndexed")
            case "find":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_find")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_find")
                }
                return interner.intern("kk_range_find")
            case "findLast":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_findLast")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_findLast")
                }
                return interner.intern("kk_range_findLast")
            case "first":
                if argumentCount > 1 {
                    if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                        return interner.intern("kk_ulong_range_first_predicate")
                    }
                    if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                        return interner.intern("kk_uint_range_first_predicate")
                    }
                    return interner.intern("kk_range_first_predicate")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_first")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_first")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_first")
                }
                return interner.intern("kk_range_first")
            case "start":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_first")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_first")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_first")
                }
                return interner.intern("kk_range_first")
            case "firstOrNull":
                if argumentCount == 0 {
                    if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                        return interner.intern("kk_ulong_range_firstOrNull")
                    }
                    if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                        return interner.intern("kk_uint_range_firstOrNull")
                    }
                    return interner.intern("kk_range_firstOrNull")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_firstOrNull_predicate")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_firstOrNull_predicate")
                }
                return interner.intern("kk_range_firstOrNull_predicate")
            case "last":
                if argumentCount > 1 {
                    if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                        return interner.intern("kk_ulong_range_last_predicate")
                    }
                    if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                        return interner.intern("kk_uint_range_last_predicate")
                    }
                    return interner.intern("kk_range_last_predicate")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_last")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_last")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_last")
                }
                return interner.intern("kk_range_last")
            case "end":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_last")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_last")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_last")
                }
                return interner.intern("kk_range_last")
            case "lastOrNull":
                if argumentCount == 0 {
                    if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                        return interner.intern("kk_ulong_range_lastOrNull")
                    }
                    if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                        return interner.intern("kk_uint_range_lastOrNull")
                    }
                    return interner.intern("kk_range_lastOrNull")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_lastOrNull_predicate")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_lastOrNull_predicate")
                }
                return interner.intern("kk_range_lastOrNull_predicate")
            case "any":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_any")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_any")
                }
                return interner.intern("kk_range_any")
            case "all":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_all")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_all")
                }
                return interner.intern("kk_range_all")
            case "none":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_none")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_none")
                }
                return interner.intern("kk_range_none")
            case "chunked":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_chunked")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_chunked")
                }
                return interner.intern("kk_range_chunked")
            case "windowed":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_windowed")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_windowed")
                }
                return interner.intern("kk_range_windowed")
            case "take":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_take")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_take")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_take")
                }
                if sema.bindings.isCharRangeExpr(receiverExpr) {
                    return interner.intern("kk_char_range_take")
                }
                return interner.intern("kk_range_take")
            case "drop":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_drop")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_drop")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_drop")
                }
                if sema.bindings.isCharRangeExpr(receiverExpr) {
                    return interner.intern("kk_char_range_drop")
                }
                return interner.intern("kk_range_drop")
            case "average":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_average")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_average")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_average")
                }
                return interner.intern("kk_range_average")
            case "sorted":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_sorted")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_sorted")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_sorted")
                }
                if sema.bindings.isCharRangeExpr(receiverExpr) {
                    return interner.intern("kk_char_range_sorted")
                }
                return interner.intern("kk_range_sorted")
            case "reversed":
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_range_reversed")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_range_reversed")
                }
                if nonNullReceiverType == sema.types.longType {
                    return interner.intern("kk_long_range_reversed")
                }
                return interner.intern("kk_range_reversed")
            case "step":
                if argumentCount <= 1 {
                    if sema.bindings.isCharRangeExpr(receiverExpr) || isCharProgressionReceiver {
                        return interner.intern("kk_char_range_step")
                    }
                    if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                        return interner.intern("kk_ulong_range_step")
                    }
                    if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                        return interner.intern("kk_uint_range_step")
                    }
                    if nonNullReceiverType == sema.types.longType {
                        return interner.intern("kk_long_range_step")
                    }
                    return interner.intern("kk_range_step")
                }
                if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
                    return interner.intern("kk_ulong_step")
                }
                if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
                    return interner.intern("kk_uint_step")
                }
                if sema.bindings.isCharRangeExpr(receiverExpr) || isCharProgressionReceiver {
                    return interner.intern("kk_char_range_step")
                }
                return interner.intern("kk_op_step")
            default:
                break
            }
        }
        if memberName == "toString",
           argumentCount == 0,
           isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner)
        {
            return interner.intern("kk_string_builder_toString")
        }

        if memberName == "length",
           sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
        {
            return interner.intern("kk_string_length")
        }

        if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
            switch memberName {
            case "compareTo":
                return interner.intern("kk_string_compareTo_member")
            case "get":
                return interner.intern("kk_string_get")
            case "lines":
                return interner.intern("kk_string_lines")
            case "lineSequence":
                return interner.intern("kk_string_lineSequence")
            case "toRegex":
                return interner.intern("kk_string_toRegex")
            default:
                break
            }
        }

        if memberName == "binarySearch",
           let runtimeName = arrayBinarySearchRuntimeName(
               for: nonNullReceiverType,
               sema: sema,
               interner: interner
           )
        {
            if argumentCount == 5,
               isGenericArrayLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                return interner.intern("kk_array_binarySearch_compare")
            }
            return runtimeName
        }

        if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "sorted":
                if collectionElementPrimitiveCompareKind(of: nonNullReceiverType, sema: sema) != nil {
                    return interner.intern("kk_list_sorted_primitive")
                }
                return interner.intern("kk_list_sorted")
            case "sortedDescending":
                if collectionElementPrimitiveCompareKind(of: nonNullReceiverType, sema: sema) != nil {
                    return interner.intern("kk_list_sortedDescending_primitive")
                }
                return interner.intern("kk_list_sortedDescending")
            case "sortedBy":
                return interner.intern("kk_list_sortedBy")
            case "distinctBy":
                return interner.intern("kk_list_distinctBy")
            case "sortedByDescending":
                return interner.intern("kk_list_sortedByDescending")
            case "firstOrNull":
                return interner.intern("kk_list_firstOrNull")
            case "lastOrNull":
                return interner.intern("kk_list_lastOrNull")
            case "single":
                return interner.intern("kk_list_single")
            case "singleOrNull":
                return interner.intern("kk_list_singleOrNull")
            case "sortedWith":
                return interner.intern("kk_list_sortedWith")
            case "indexOf":
                return interner.intern("kk_list_indexOf")
            case "lastIndexOf":
                return interner.intern("kk_list_lastIndexOf")
            case "indexOfFirst":
                return interner.intern("kk_list_indexOfFirst")
            case "indexOfLast":
                return interner.intern("kk_list_indexOfLast")
            case "maxBy":
                return interner.intern("kk_list_maxBy")
            case "maxByOrNull":
                return interner.intern("kk_list_maxByOrNull")
            case "minByOrNull":
                return interner.intern("kk_list_minByOrNull")
            case "maxOf":
                return interner.intern("kk_list_maxOf")
            case "minOf":
                return interner.intern("kk_list_minOf")
            case "maxWith":
                return interner.intern("kk_list_maxWith")
            case "maxWithOrNull":
                return interner.intern("kk_list_maxWithOrNull")
            case "minWith":
                return interner.intern("kk_list_minWith")
            case "minWithOrNull":
                return interner.intern("kk_list_minWithOrNull")
            case "maxOfWith":
                return interner.intern("kk_list_maxOfWith")
            case "maxOfWithOrNull":
                return interner.intern("kk_list_maxOfWithOrNull")
            case "minOfWith":
                return interner.intern("kk_list_minOfWith")
            case "minOfWithOrNull":
                return interner.intern("kk_list_minOfWithOrNull")
            case "any":
                return interner.intern("kk_list_any")
            case "all":
                return interner.intern("kk_list_all")
            case "none":
                return interner.intern("kk_list_none")
            case "onEach":
                return interner.intern("kk_list_onEach")
            case "onEachIndexed":
                return interner.intern("kk_list_onEachIndexed")
            case "partition":
                return interner.intern("kk_list_partition")
            case "zipWithNext":
                return interner.intern(hasHOFLambdaArg
                    ? "kk_list_zipWithNextTransform"
                    : "kk_list_zipWithNext")
            case "getOrNull":
                return interner.intern("kk_list_getOrNull")
            case "elementAtOrNull":
                return interner.intern("kk_list_elementAtOrNull")
            case "elementAt":
                return interner.intern("kk_list_elementAt")
            case "elementAtOrElse":
                return interner.intern("kk_list_elementAtOrElse")
            case "getOrElse":
                return interner.intern("kk_list_getOrElse")
            case "subList":
                return interner.intern("kk_list_subList")
            case "containsAll":
                return interner.intern("kk_list_containsAll")
            case "binarySearch":
                if hasHOFLambdaArg && argumentCount == 2 {
                    return interner.intern("kk_list_binarySearch_compare")
                }
                if argumentCount > 2 {
                    return interner.intern("kk_list_binarySearch_comparator")
                }
                return interner.intern("kk_list_binarySearch")
            case "binarySearchBy":
                switch argumentCount {
                case 2:
                    return interner.intern("kk_list_binarySearchBy")
                case 3:
                    return interner.intern("kk_list_binarySearchBy_fromIndex")
                case 4:
                    return interner.intern("kk_list_binarySearchBy_range")
                default:
                    break
                }
            case "reduceIndexedOrNull":
                return interner.intern("kk_list_reduceIndexedOrNull")
            case "foldRight":
                return interner.intern("kk_list_foldRight")
            case "foldRightIndexed":
                return interner.intern("kk_list_foldRightIndexed")
            case "reduceRight":
                return interner.intern("kk_list_reduceRight")
            case "reduceRightIndexed":
                return interner.intern("kk_list_reduceRightIndexed")
            case "reduceRightIndexedOrNull":
                return interner.intern("kk_list_reduceRightIndexedOrNull")
            case "reduceRightOrNull":
                return interner.intern("kk_list_reduceRightOrNull")
            case "runningFold":
                return interner.intern("kk_list_runningFold")
            case "runningReduce":
                return interner.intern("kk_list_runningReduce")
            case "scan":
                return interner.intern("kk_list_scan")
            case "runningFoldIndexed":
                return interner.intern("kk_list_runningFoldIndexed")
            case "runningReduceIndexed":
                return interner.intern("kk_list_runningReduceIndexed")
            case "scanIndexed":
                return interner.intern("kk_list_scanIndexed")
            default:
                break
            }
        }

        if isMutableSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "addAll":
                return interner.intern("kk_mutable_set_addAll")
            case "removeAll":
                return interner.intern("kk_mutable_set_removeAll")
            case "retainAll":
                return interner.intern("kk_mutable_set_retainAll")
            default:
                break
            }
        }

        if isMutableListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "sort":
                if collectionElementPrimitiveCompareKind(of: nonNullReceiverType, sema: sema) != nil {
                    return interner.intern("kk_mutable_list_sort_primitive")
                }
                return interner.intern("kk_mutable_list_sort")
            case "sortWith":
                return interner.intern("kk_mutable_list_sortWith")
            case "sortBy":
                return interner.intern("kk_mutable_list_sortBy")
            case "sortByDescending":
                return interner.intern("kk_mutable_list_sortByDescending")
            case "sortDescending":
                if collectionElementPrimitiveCompareKind(of: nonNullReceiverType, sema: sema) != nil {
                    return interner.intern("kk_mutable_list_sortDescending_primitive")
                }
                return interner.intern("kk_mutable_list_sortDescending")
            case "add" where argumentCount == 1:
                return interner.intern("kk_mutable_list_add")
            case "addAll":
                return interner.intern("kk_mutable_list_addAll")
            case "removeAll":
                return interner.intern("kk_mutable_list_removeAll")
            case "retainAll":
                return interner.intern("kk_mutable_list_retainAll")
            case "fill":
                return interner.intern("kk_mutable_list_fill")
            case "replaceAll":
                return interner.intern("kk_mutable_list_replaceAll")
            case "removeIf":
                return interner.intern("kk_mutable_list_removeIf")
            case "removeFirst":
                return interner.intern("kk_mutable_list_removeFirst")
            case "removeFirstOrNull":
                return interner.intern("kk_mutable_list_removeFirstOrNull")
            case "removeLast":
                return interner.intern("kk_mutable_list_removeLast")
            case "removeLastOrNull":
                return interner.intern("kk_mutable_list_removeLastOrNull")
            default:
                break
            }
        }

        if isArrayDequeLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "addFirst":
                return interner.intern("kk_arraydeque_addFirst")
            case "addLast":
                return interner.intern("kk_arraydeque_addLast")
            case "removeFirst":
                return interner.intern("kk_arraydeque_removeFirst")
            case "removeLast":
                return interner.intern("kk_arraydeque_removeLast")
            case "first":
                return interner.intern("kk_arraydeque_first")
            case "last":
                return interner.intern("kk_arraydeque_last")
            case "size":
                return interner.intern("kk_arraydeque_size")
            case "isEmpty":
                return interner.intern("kk_arraydeque_isEmpty")
            case "toString":
                return interner.intern("kk_arraydeque_toString")
            default:
                break
            }
        }

        if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "get":
                return interner.intern("kk_array_get")
            case "map":
                return interner.intern("kk_array_map")
            case "filter":
                return interner.intern("kk_array_filter")
            case "toList":
                return interner.intern("kk_array_toList")
            case "toMutableList":
                return interner.intern("kk_array_toMutableList")
            case "toTypedArray":
                return interner.intern("kk_array_copyOf")
            case "forEach":
                return interner.intern("kk_array_forEach")
            case "any":
                return interner.intern("kk_array_any")
            case "none":
                return interner.intern("kk_array_none")
            case "count":
                return interner.intern("kk_array_count")
            case "copyOf":
                switch argumentCount {
                case 0:
                    return interner.intern("kk_array_copyOf")
                case 1:
                    return interner.intern("kk_array_copyOf_newSize")
                case 2:
                    return interner.intern("kk_array_copyOf_newSize_init")
                default:
                    break
                }
            case "fill":
                return interner.intern("kk_array_fill")
            case "binarySearch":
                return arrayBinarySearchRuntimeName(
                    for: nonNullReceiverType,
                    sema: sema,
                    interner: interner
                )
            case "sortedArrayWith":
                return interner.intern("kk_array_sortedArrayWith")
            default:
                break
            }
        }

        // Set receivers: sorted/toList/contains route to set-specific runtime
        if isSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "sorted":
                return interner.intern("kk_set_sorted")
            case "sortedDescending":
                return interner.intern("kk_set_sortedDescending")
            case "toList":
                return interner.intern("kk_set_toList")
            case "contains":
                return interner.intern("kk_set_contains")
            case "containsAll":
                return interner.intern("kk_set_containsAll")
            case "first":
                return interner.intern("kk_set_first")
            case "firstOrNull":
                return interner.intern("kk_set_firstOrNull")
            case "last":
                return interner.intern("kk_set_last")
            case "lastOrNull":
                return interner.intern("kk_set_lastOrNull")
            case "singleOrNull":
                return interner.intern("kk_set_singleOrNull")
            case "any":
                return interner.intern("kk_set_any")
            case "all":
                return interner.intern("kk_set_all")
            case "none":
                return interner.intern("kk_set_none")
            default:
                break
            }
        }

        switch memberName {
        case "sorted":
            return interner.intern("kk_list_sorted")
        case "sortedDescending":
            return interner.intern("kk_list_sortedDescending")
        case "sortedBy":
            return interner.intern("kk_list_sortedBy")
        case "distinctBy":
            return interner.intern("kk_list_distinctBy")
        case "sortedByDescending":
            return interner.intern("kk_list_sortedByDescending")
        case "partition":
            return interner.intern("kk_list_partition")
        case "zipWithNext":
            return interner.intern(hasHOFLambdaArg
                ? "kk_list_zipWithNextTransform"
                : "kk_list_zipWithNext")
        case "indexOf":
            return interner.intern("kk_list_indexOf")
        case "lastIndexOf":
            return interner.intern("kk_list_lastIndexOf")
        case "indexOfFirst":
            return interner.intern("kk_list_indexOfFirst")
        case "indexOfLast":
            return interner.intern("kk_list_indexOfLast")
        case "maxBy":
            return interner.intern("kk_list_maxBy")
        case "maxByOrNull":
            return interner.intern("kk_list_maxByOrNull")
        case "minByOrNull":
            return interner.intern("kk_list_minByOrNull")
        case "maxOf":
            return interner.intern("kk_list_maxOf")
        case "minOf":
            return interner.intern("kk_list_minOf")
        case "maxWith":
            return interner.intern("kk_list_maxWith")
        case "maxWithOrNull":
            return interner.intern("kk_list_maxWithOrNull")
        case "minWith":
            return interner.intern("kk_list_minWith")
        case "minWithOrNull":
            return interner.intern("kk_list_minWithOrNull")
        case "maxOfWith":
            return interner.intern("kk_list_maxOfWith")
        case "maxOfWithOrNull":
            return interner.intern("kk_list_maxOfWithOrNull")
        case "minOfWith":
            return interner.intern("kk_list_minOfWith")
        case "minOfWithOrNull":
            return interner.intern("kk_list_minOfWithOrNull")
        case "any":
            return interner.intern("kk_list_any")
        case "all":
            return interner.intern("kk_list_all")
        case "none":
            return interner.intern("kk_list_none")
        case "onEach":
            return interner.intern("kk_list_onEach")
        case "onEachIndexed":
            return interner.intern("kk_list_onEachIndexed")
        case "firstOrNull":
            return interner.intern("kk_list_firstOrNull")
        case "lastOrNull":
            return interner.intern("kk_list_lastOrNull")
        case "single":
            return interner.intern("kk_list_single")
        case "singleOrNull":
            return interner.intern("kk_list_singleOrNull")
        case "sortedWith":
            return interner.intern("kk_list_sortedWith")
        case "getOrNull":
            return interner.intern("kk_list_getOrNull")
        case "elementAtOrNull":
            return interner.intern("kk_list_elementAtOrNull")
        case "elementAt":
            return interner.intern("kk_list_elementAt")
        case "elementAtOrElse":
            return interner.intern("kk_list_elementAtOrElse")
        case "getOrElse":
            return interner.intern("kk_list_getOrElse")
        case "containsAll":
            return interner.intern("kk_list_containsAll")
        case "binarySearch":
            if argumentCount == 5,
               isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                return interner.intern("kk_array_binarySearch_compare")
            }
            if hasHOFLambdaArg && argumentCount == 2 {
                return interner.intern("kk_list_binarySearch_compare")
            }
            if argumentCount > 2 {
                return interner.intern("kk_list_binarySearch_comparator")
            }
            return interner.intern("kk_list_binarySearch")
        case "groupingBy" where isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner)
            || isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            || sema.bindings.isCollectionExpr(receiverExpr):
            return interner.intern("kk_list_groupingBy")
        default:
            break
        }

        if isGroupingLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "eachCount":
                return interner.intern("kk_grouping_eachCount")
            case "eachCountTo":
                return interner.intern("kk_grouping_eachCountTo")
            case "aggregate":
                return interner.intern("kk_grouping_aggregate")
            case "aggregateTo":
                return interner.intern("kk_grouping_aggregateTo")
            case "fold":
                return interner.intern(argumentCount >= 4
                    ? "kk_grouping_fold_initialValueSelector"
                    : "kk_grouping_fold")
            case "foldTo":
                return interner.intern(hasHOFLambdaArg
                    ? "kk_grouping_foldTo_selector"
                    : "kk_grouping_foldTo")
            case "reduce":
                return interner.intern("kk_grouping_reduce")
            case "reduceTo":
                return interner.intern("kk_grouping_reduceTo")
            default:
                break
            }
        }

        let useSequenceRuntimeForCollectionFallback = isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
        let useIterableRuntimeForCollectionFallback = (sema.bindings.isCollectionExpr(receiverExpr)
            || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
            && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
        if useSequenceRuntimeForCollectionFallback || useIterableRuntimeForCollectionFallback {
            let internedMemberName = interner.intern(memberName)
            let mapName = interner.intern("map")
            let filterName = interner.intern("filter")
            let takeName = interner.intern("take")
            let toListName = interner.intern("toList")
            let forEachName = interner.intern("forEach")
            let flatMapName = interner.intern("flatMap")
            let flatMapIndexedName = interner.intern("flatMapIndexed")
            let dropName = interner.intern("drop")
            let distinctName = interner.intern("distinct")
            let zipName = interner.intern("zip")
            let takeWhileName = interner.intern("takeWhile")
            let dropWhileName = interner.intern("dropWhile")
            let sortedName = interner.intern("sorted")
            let sortedByName = interner.intern("sortedBy")
            let sortedDescendingName = interner.intern("sortedDescending")
            let joinToStringName = interner.intern("joinToString")
            let sumOfName = interner.intern("sumOf")
            let sumByName = interner.intern("sumBy")
            let sumByDoubleName = interner.intern("sumByDouble")
            let firstNotNullOfName = interner.intern("firstNotNullOf")
            let firstNotNullOfOrNullName = interner.intern("firstNotNullOfOrNull")
            let associateName = interner.intern("associate")
            let associateByName = interner.intern("associateBy")
            let firstName = interner.intern("first")
            let firstOrNullName = interner.intern("firstOrNull")
            let lastName = interner.intern("last")
            let countName = interner.intern("count")
            switch internedMemberName {
            case mapName:
                return interner.intern("kk_sequence_map")
            case filterName:
                return interner.intern("kk_sequence_filter")
            case takeName:
                return interner.intern("kk_sequence_take")
            case toListName:
                return interner.intern("kk_sequence_to_list")
            case interner.intern("constrainOnce"):
                return interner.intern("kk_sequence_constrainOnce")
            case forEachName:
                return interner.intern("kk_sequence_forEach")
            case flatMapName:
                return interner.intern("kk_sequence_flatMap")
            case flatMapIndexedName:
                return interner.intern("kk_sequence_flatMapIndexed")
            case dropName:
                return interner.intern("kk_sequence_drop")
            case distinctName:
                return interner.intern("kk_sequence_distinct")
            case zipName:
                return interner.intern("kk_sequence_zip")
            case takeWhileName:
                return interner.intern("kk_sequence_takeWhile")
            case dropWhileName:
                return interner.intern("kk_sequence_dropWhile")
            case sortedName:
                return interner.intern("kk_sequence_sorted")
            case sortedByName:
                return interner.intern("kk_sequence_sortedBy")
            case sortedDescendingName:
                return interner.intern("kk_sequence_sortedDescending")
            case interner.intern("shuffled"):
                switch argumentCount {
                case 0:
                    return interner.intern("kk_sequence_shuffled")
                case 1:
                    return interner.intern("kk_sequence_shuffled_random")
                default:
                    return nil
                }
            case joinToStringName:
                return interner.intern("kk_sequence_joinToString")
            case sumOfName:
                return interner.intern("kk_sequence_sumOf")
            case sumByName:
                return interner.intern("kk_sequence_sumBy")
            case sumByDoubleName:
                return interner.intern("kk_sequence_sumByDouble")
            case firstNotNullOfName:
                return interner.intern("kk_sequence_firstNotNullOf")
            case firstNotNullOfOrNullName:
                return interner.intern("kk_sequence_firstNotNullOfOrNull")
            case associateName:
                return interner.intern("kk_sequence_associate")
            case associateByName:
                return interner.intern("kk_sequence_associateBy")
            case interner.intern("associateTo"):
                return interner.intern("kk_sequence_associateTo")
            case interner.intern("associateByTo"):
                return interner.intern("kk_sequence_associateByTo")
            case interner.intern("associateWith"):
                return interner.intern("kk_sequence_associateWith")
            case interner.intern("associateWithTo"):
                return interner.intern("kk_sequence_associateWithTo")
            case interner.intern("groupByTo"):
                return interner.intern("kk_sequence_groupByTo")
            case interner.intern("contains"):
                return interner.intern("kk_sequence_contains")
            case interner.intern("indexOf"):
                return interner.intern("kk_sequence_indexOf")
            case interner.intern("elementAt"):
                return interner.intern("kk_sequence_elementAt")
            case interner.intern("elementAtOrNull"):
                return interner.intern("kk_sequence_elementAtOrNull")
            case interner.intern("findLast"):
                return interner.intern("kk_sequence_findLast")
            case interner.intern("find"):
                return interner.intern("kk_sequence_find")
            case interner.intern("findLast"):
                return interner.intern("kk_sequence_findLast")
            case interner.intern("any"):
                return interner.intern("kk_sequence_any")
            case interner.intern("all"):
                return interner.intern("kk_sequence_all")
            case interner.intern("none"):
                return interner.intern("kk_sequence_none")
            case interner.intern("mapNotNull"):
                return interner.intern("kk_sequence_mapNotNull")
            case interner.intern("firstNotNullOf"):
                return interner.intern("kk_sequence_firstNotNullOf")
            case interner.intern("firstNotNullOfOrNull"):
                return interner.intern("kk_sequence_firstNotNullOfOrNull")
            case interner.intern("filterNot"):
                return interner.intern("kk_sequence_filterNot")
            case interner.intern("filterNotNull"):
                return interner.intern("kk_sequence_filterNotNull")
            case interner.intern("requireNoNulls"):
                return interner.intern("kk_sequence_requireNoNulls")
            case interner.intern("asIterable"):
                return interner.intern("kk_sequence_asIterable")
            case interner.intern("mapIndexed"):
                return interner.intern("kk_sequence_mapIndexed")
            case interner.intern("flatMapIndexed"):
                return interner.intern("kk_sequence_flatMapIndexed")
            case interner.intern("withIndex"):
                return interner.intern("kk_sequence_withIndex")
            case interner.intern("chunked"):
                return interner.intern(hasHOFLambdaArg
                    ? "kk_sequence_chunked_transform"
                    : "kk_sequence_chunked")
            case interner.intern("windowed"):
                return interner.intern("kk_sequence_windowed")
            case interner.intern("onEach"):
                return interner.intern("kk_sequence_onEach")
            case interner.intern("onEachIndexed"):
                return interner.intern("kk_sequence_onEachIndexed")
            case interner.intern("plus"), interner.intern("plusElement"):
                return interner.intern("kk_sequence_plus_element")
            case interner.intern("minus"), interner.intern("minusElement"):
                return interner.intern("kk_sequence_minus")
            case interner.intern("ifEmpty"):
                return interner.intern("kk_sequence_ifEmpty")
            case firstName:
                return interner.intern("kk_sequence_first")
            case firstOrNullName:
                return interner.intern("kk_sequence_firstOrNull")
            case lastName:
                return interner.intern(useIterableRuntimeForCollectionFallback ? "kk_iterable_last" : "kk_sequence_last")
            case interner.intern("lastOrNull"):
                return interner.intern("kk_sequence_lastOrNull")
            case countName:
                return interner.intern("kk_sequence_count")
            case interner.intern("sum"):
                return interner.intern("kk_sequence_sum")
            case interner.intern("average"):
                return interner.intern("kk_sequence_average")
            case interner.intern("toCollection"):
                return interner.intern("kk_sequence_toCollection")
            case interner.intern("toMutableList"):
                return toMutableListRuntimeCalleeForSequenceOrIterableFallback(
                    chosenCallee: nil,
                    useIterableFallback: useIterableRuntimeForCollectionFallback,
                    sema: sema,
                    interner: interner
                )
            case interner.intern("toMutableSet"):
                return interner.intern("kk_sequence_toMutableSet")
            case interner.intern("toHashSet"):
                return interner.intern("kk_sequence_toHashSet")
            case interner.intern("partition"):
                return interner.intern("kk_sequence_partition")
            case interner.intern("minByOrNull"):
                return interner.intern("kk_sequence_minByOrNull")
            case interner.intern("maxByOrNull"):
                return interner.intern("kk_sequence_maxByOrNull")
            case interner.intern("minOf"):
                return interner.intern("kk_sequence_minOf")
            case interner.intern("maxOf"):
                return interner.intern("kk_sequence_maxOf")
            case interner.intern("unzip"):
                return interner.intern("kk_sequence_unzip")
            case interner.intern("foldIndexed"):
                return interner.intern("kk_sequence_foldIndexed")
            case interner.intern("runningFoldIndexed"):
                return interner.intern("kk_sequence_runningFoldIndexed")
            case interner.intern("scanIndexed"):
                return interner.intern("kk_sequence_scanIndexed")
            case interner.intern("reduceIndexed"):
                return interner.intern("kk_sequence_reduceIndexed")
            case interner.intern("reduceIndexedOrNull"):
                return interner.intern("kk_sequence_reduceIndexedOrNull")
            case interner.intern("runningReduceIndexed"):
                return interner.intern("kk_sequence_runningReduceIndexed")
            default:
                break
            }
        }

        return nil
    }

    // swiftlint:enable cyclomatic_complexity

    /// Resolves collection-level accessor members (`size`, `isEmpty`) to
    /// their concrete runtime callee by mapping receiver kind to the
    /// corresponding runtime symbol (e.g. `.list` -> `kk_list_size`).
    private func unresolvedCollectionMemberCallee(
        memberName: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard memberName == "size"
              || memberName == "isEmpty"
              || memberName == "isNotEmpty"
              || memberName == "firstNotNullOf"
              || memberName == "firstNotNullOfOrNull"
              || memberName == "requireNoNulls",
              case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        switch memberName {
        case "size":
            switch knownNames.collectionKind(of: symbol) {
            case .map?:
                return interner.intern("kk_map_size")
            case .set?:
                return interner.intern("kk_set_size")
            case .array?:
                return interner.intern("kk_array_size")
            case .list?, .collection?:
                return interner.intern("kk_list_size")
            default:
                break
            }
        case "isEmpty":
            switch knownNames.collectionKind(of: symbol) {
            case .map?:
                return interner.intern("kk_map_is_empty")
            case .set?:
                return interner.intern("kk_set_is_empty")
            case .array?:
                return interner.intern("kk_array_is_empty")
            case .list?, .collection?:
                return interner.intern("kk_list_is_empty")
            default:
                break
            }
        case "isNotEmpty":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .collection?:
                return interner.intern("kk_list_is_not_empty")
            default:
                break
            }
        case "firstNotNullOf":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_iterable_firstNotNullOf")
            default:
                break
            }
        case "firstNotNullOfOrNull":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_iterable_firstNotNullOfOrNull")
            default:
                break
            }
        case "requireNoNulls":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_iterable_requireNoNulls")
            default:
                break
            }
        default:
            break
        }

        return nil
    }

    private func unresolvedMapMemberCallee(
        memberName: String,
        receiverType: TypeID,
        argumentCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              knownNames.isMapLikeSymbol(symbol)
        else {
            return nil
        }
        switch memberName {
        case "count":
            return interner.intern(argumentCount == 0 ? "kk_map_size" : "kk_map_count")
        case "any":
            return interner.intern("kk_map_any")
        case "all":
            return interner.intern("kk_map_all")
        case "none":
            return interner.intern("kk_map_none")
        case "getValue":
            return interner.intern("kk_map_getValue")
        case "getOrDefault":
            return interner.intern("kk_map_getOrDefault")
        case "getOrElse":
            return interner.intern("kk_map_getOrElse")
        case "maxByOrNull":
            return interner.intern("kk_map_maxByOrNull")
        case "minByOrNull":
            return interner.intern("kk_map_minByOrNull")
        case "plus":
            return interner.intern("kk_map_plus")
        case "minus":
            return interner.intern("kk_map_minus")
        case "filterNot":
            return interner.intern("kk_map_filterNot")
        case "filterKeys":
            return interner.intern("kk_map_filterKeys")
        case "filterValues":
            return interner.intern("kk_map_filterValues")
        case "mapNotNull":
            return interner.intern("kk_map_mapNotNull")
        case "mapKeysTo":
            return interner.intern("kk_map_mapKeysTo")
        case "mapValuesTo":
            return interner.intern("kk_map_mapValuesTo")
        case "getOrPut":
            guard knownNames.isMutableMapSymbol(symbol) else {
                return nil
            }
            return interner.intern("kk_mutable_map_getOrPut")
        case "putAll":
            guard knownNames.isMutableMapSymbol(symbol) else {
                return nil
            }
            return interner.intern("kk_mutable_map_putAll")
        default:
            return nil
        }
    }

    private func collectionIsNullOrEmptyRuntimeCallee(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        switch knownNames.collectionKind(of: symbol) {
        case .map?:
            return interner.intern("kk_map_is_empty")
        case .set?:
            return interner.intern("kk_set_is_empty")
        case .array?:
            return interner.intern("kk_array_is_empty")
        case .list?, .collection?:
            return interner.intern("kk_list_is_empty")
        case .sequence?, nil:
            return nil
        }
    }

    // MARK: - Member Assignment

    func lowerMemberAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Synthetic properties whose getter external link ends in `_load`
        // (e.g. AtomicBoolean.value → kk_atomic_bool_load) must route their
        // setter to the matching `_store` runtime function rather than a
        // direct field-offset write, which would corrupt the underlying
        // runtime-managed box.
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let info = sema.symbols.symbol(propertySymbol),
           info.flags.contains(.synthetic),
           let getterLink = sema.symbols.externalLinkName(for: propertySymbol),
           getterLink.hasSuffix("_load")
        {
            let storeLinkName = String(getterLink.dropLast("_load".count)) + "_store"
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(storeLinkName),
                arguments: [receiverID, valueID],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface
           || ownerInfo.kind == .object,
           let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
               sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
           ]
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [receiverID, offsetExpr, valueID],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // Use the call binding from sema if available (property setter).
        let callBinding = sema.bindings.callBindings[exprID]
        let chosenCallee = callBinding?.chosenCallee
        let setterName = loweredMemberCalleeName(
            chosenCallee: chosenCallee,
            fallback: calleeName,
            receiverExpr: receiverExpr,
            argumentCount: 2, // receiver + value
            sema: sema,
            interner: interner
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.unitType)
        instructions.append(.call(
            symbol: chosenCallee,
            callee: setterName,
            arguments: [receiverID, valueID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// Lowers `T::class.simpleName` / `T::class.qualifiedName` to a call to
    /// the runtime function `kk_type_token_simple_name` (or `_qualified_name`).
    ///
    /// Two arguments are passed to the runtime:
    /// 1. The type token (Int64) — for reified type parameters this is the
    ///    synthetic token symbol injected by `InlineLoweringPass`; for concrete
    ///    types it is computed at compile-time.
    /// 2. A name-hint string pointer — the compiler emits the simple name as a
    ///    string literal so the runtime can use it directly for nominal types
    ///    whose hash-based token is lossy.
    private func lowerClassRefPropertyAccess(
        _: ExprID,
        classRefExprID _: ExprID,
        classRefReceiver _: ExprID?,
        classRefTargetType: TypeID,
        propertyName: String,
        ast _: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let nullableStringType = sema.types.makeNullable(stringType)

        // 1. Emit the type token.
        let tokenExpr: KIRExprID
        if case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
            // Reified type parameter — look up the synthetic token symbol.
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
            tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
        } else {
            // Concrete type — encode the type token at compile time.
            let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
            tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        }

        // 2. Emit the name-hint string.
        let nameHintExpr: KIRExprID
        if let name = RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
            let internedName = interner.intern(name)
            nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: stringType)
            instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
        } else {
            // No name available — pass 0 (null sentinel) so the runtime falls
            // back to token-based decoding.
            nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
        }

        // 3. Emit the runtime call.
        let runtimeFuncName = propertyName == "qualifiedName"
            ? "kk_type_token_qualified_name"
            : "kk_type_token_simple_name"
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: nullableStringType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeFuncName),
            arguments: [tokenExpr, nameHintExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    // MARK: - REFL-005: KClass.isInstance / members / constructors Lowering

    private func lowerKClassReifiedTypeNameHint(
        exprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let typeArg = sema.bindings.callBindings[exprID]?.substitutedTypeArguments.first
        let name = typeArg.flatMap { RuntimeTypeCheckToken.qualifiedName(of: $0, sema: sema, interner: interner) }
            ?? typeArg.flatMap { RuntimeTypeCheckToken.simpleName(of: $0, sema: sema, interner: interner) }
            ?? typeArg.map { sema.types.renderType($0) }
            ?? ""
        let internedName = interner.intern(name)
        let result = arena.appendExpr(.stringLiteral(internedName), type: sema.types.stringType)
        instructions.append(.constValue(result: result, value: .stringLiteral(internedName)))
        return result
    }

    /// Lowers `T::class.isInstance(value)`, `T::class.members`, `T::class.constructors`
    /// to runtime calls `kk_kclass_isInstance`, `kk_kclass_members`, `kk_kclass_constructors`.
    ///
    /// These functions operate on the KClass box, so we first create the KClass
    /// via `kk_kclass_create` and then call the appropriate runtime function.
    private func lowerKClassReflectMemberCall(
        _ exprID: ExprID,
        classRefTargetType: TypeID,
        memberName: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let stringType = sema.types.stringType

        // 1. Create the KClass box via kk_kclass_create.
        let tokenExpr: KIRExprID
        if case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
            tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
        } else {
            let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
            tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        }

        let nameHintExpr: KIRExprID
        if let name = RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
            let internedName = interner.intern(name)
            nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: stringType)
            instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
        } else {
            nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
        }

        let kClassFallback = sema.types.makeKClassType(argument: classRefTargetType)
        let kclassExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: kClassFallback)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kclass_create"),
            arguments: [tokenExpr, nameHintExpr],
            result: kclassExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // STDLIB-REFLECT-065: For annotation-related calls, ensure metadata and
        // annotations are registered even if the class was never instantiated.
        if memberName == "annotations" || memberName == "findAnnotation" || memberName == "findAssociatedObject" {
            if case let .classType(classType) = sema.types.kind(of: classRefTargetType) {
                let classSymbol = classType.classSymbol
                if let symbol = sema.symbols.symbol(classSymbol) {
                    // Emit metadata registration.
                    let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                    let fqNameInterned = interner.intern(fqName)
                    let fqNameExpr = arena.appendExpr(.stringLiteral(fqNameInterned), type: intType)
                    instructions.append(.constValue(result: fqNameExpr, value: .stringLiteral(fqNameInterned)))

                    let simpleNameStr = interner.resolve(symbol.name)
                    let simpleInterned = interner.intern(simpleNameStr)
                    let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleInterned), type: intType)
                    instructions.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleInterned)))

                    let supertypes = sema.symbols.directSupertypes(for: classSymbol)
                    let superClassSymbol = supertypes.first(where: { sema.symbols.symbol($0)?.kind == .class })
                    let supertypeNameExpr: KIRExprID
                    if let superClassSymbol, let superSym = sema.symbols.symbol(superClassSymbol) {
                        let superFq = superSym.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        let superIn = interner.intern(superFq)
                        supertypeNameExpr = arena.appendExpr(.stringLiteral(superIn), type: intType)
                        instructions.append(.constValue(result: supertypeNameExpr, value: .stringLiteral(superIn)))
                    } else {
                        supertypeNameExpr = arena.appendExpr(.intLiteral(0), type: intType)
                        instructions.append(.constValue(result: supertypeNameExpr, value: .intLiteral(0)))
                    }

                    var flags: Int64 = 0
                    if symbol.flags.contains(.dataType) { flags |= 1 << 0 }
                    if symbol.flags.contains(.sealedType) { flags |= 1 << 1 }
                    if symbol.flags.contains(.valueType) { flags |= 1 << 2 }
                    if symbol.kind == .interface { flags |= 1 << 3 }
                    if symbol.kind == .object { flags |= 1 << 4 }
                    if symbol.kind == .enumClass { flags |= 1 << 5 }
                    if symbol.kind == .annotationClass { flags |= 1 << 6 }
                    if symbol.flags.contains(.abstractType) { flags |= 1 << 7 }
                    let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
                    instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))

                    let fieldCount: Int64 = sema.symbols.nominalLayout(for: classSymbol).map { Int64($0.instanceFieldCount) } ?? -1
                    let fieldCountExpr = arena.appendExpr(.intLiteral(fieldCount), type: intType)
                    instructions.append(.constValue(result: fieldCountExpr, value: .intLiteral(fieldCount)))

                    let memberCount: Int64 = sema.symbols.nominalLayout(for: classSymbol).map { Int64($0.instanceFieldCount + $0.vtableSize) } ?? -1
                    let memberCountExpr = arena.appendExpr(.intLiteral(memberCount), type: intType)
                    instructions.append(.constValue(result: memberCountExpr, value: .intLiteral(memberCount)))

                    let constructorCount = Int64(sema.symbols.children(ofFQName: symbol.fqName).filter { sema.symbols.symbol($0)?.kind == .constructor }.count)
                    let constructorCountExpr = arena.appendExpr(.intLiteral(constructorCount), type: intType)
                    instructions.append(.constValue(result: constructorCountExpr, value: .intLiteral(constructorCount)))

                    let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_kclass_register_metadata"),
                        arguments: [tokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
                        result: registerResult,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
                        symbol: classSymbol,
                        sema: sema,
                        interner: interner
                    )
                    emitDataClassFieldRegistration(
                        objectSymbol: classSymbol,
                        classID: classID,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )

                    // Emit annotation registration.
                    let annotations = sema.symbols.annotations(for: classSymbol)
                    for annotation in annotations {
                        let annNameInterned = interner.intern(annotation.annotationFQName)
                        let annNameExpr = arena.appendExpr(.stringLiteral(annNameInterned), type: stringType)
                        instructions.append(.constValue(result: annNameExpr, value: .stringLiteral(annNameInterned)))

                        let argsEncoded = annotation.arguments.joined(separator: "|")
                        let argsInterned = interner.intern(argsEncoded)
                        let argsExpr = arena.appendExpr(.stringLiteral(argsInterned), type: stringType)
                        instructions.append(.constValue(result: argsExpr, value: .stringLiteral(argsInterned)))

                        let argCount = Int64(annotation.arguments.count)
                        let argCountExpr = arena.appendExpr(.intLiteral(argCount), type: intType)
                        instructions.append(.constValue(result: argCountExpr, value: .intLiteral(argCount)))

                        let annRegResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_kclass_register_single_annotation"),
                            arguments: [tokenExpr, annNameExpr, argsExpr, argCountExpr],
                            result: annRegResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                }
            }
        }

        // 2. Emit the specific member call.
        switch memberName {
        case "isInstance":
            // isInstance(value: Any?) -> Boolean
            let valueExpr: KIRExprID
            if let firstArg = args.first {
                valueExpr = driver.lowerExpr(
                    firstArg.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                valueExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: valueExpr, value: .intLiteral(0)))
            }
            let resultType = sema.bindings.exprTypes[exprID] ?? boolType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_isInstance"),
                arguments: [kclassExpr, valueExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "cast", "safeCast":
            let valueExpr: KIRExprID
            if let firstArg = args.first {
                valueExpr = driver.lowerExpr(
                    firstArg.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                valueExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: valueExpr, value: .intLiteral(0)))
            }
            let resultType = sema.bindings.exprTypes[exprID] ?? classRefTargetType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            let canThrow = memberName == "cast"
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(canThrow ? "kk_kclass_cast" : "kk_kclass_safeCast"),
                arguments: [kclassExpr, valueExpr],
                result: result,
                canThrow: canThrow,
                thrownResult: nil
            ))
            return result

        case "members":
            // members: Collection<KCallable<*>>
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_members"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "constructors":
            // constructors: Collection<KFunction<T>>
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_constructors"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-064: KClass.primaryConstructor
        case "primaryConstructor":
            // primaryConstructor: KFunction<T>?
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_primary_constructor"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-061: KClass member access — properties/functions variants
        case "properties":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_properties"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "memberProperties":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_member_properties"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "declaredMemberProperties":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_declared_member_properties"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "functions":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_functions"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "memberFunctions":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_member_functions"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "declaredMemberFunctions":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_declared_member_functions"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-060: KClass basic reflection features
        case "isFinal":
            let resultType = sema.bindings.exprTypes[exprID] ?? boolType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_is_final"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "isOpen":
            let resultType = sema.bindings.exprTypes[exprID] ?? boolType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_is_open"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "isAbstract":
            let resultType = sema.bindings.exprTypes[exprID] ?? boolType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_is_abstract"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "visibility":
            let resultType = sema.bindings.exprTypes[exprID] ?? stringType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_visibility"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "typeParameters":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_type_parameters"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "supertypes":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_supertypes"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-065: annotations
        case "annotations":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_get_annotations"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-065: findAnnotation<T>()
        case "findAnnotation":
            // findAnnotation<T>() -> T?  — the type argument name is passed as a string hint
            let searchNameExpr: KIRExprID
            if let firstArg = args.first {
                searchNameExpr = driver.lowerExpr(
                    firstArg.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                // No argument — use empty string to match nothing.
                let emptyStr = interner.intern("")
                searchNameExpr = arena.appendExpr(.stringLiteral(emptyStr), type: stringType)
                instructions.append(.constValue(result: searchNameExpr, value: .stringLiteral(emptyStr)))
            }
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_find_annotation"),
                arguments: [kclassExpr, searchNameExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-079: findAssociatedObject<T>()
        case "findAssociatedObject":
            let keyNameExpr = lowerKClassReifiedTypeNameHint(
                exprID: exprID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.makeNullable(sema.types.anyType)
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_find_associated_object"),
                arguments: [kclassExpr, keyNameExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        default:
            // Fallback — should not happen.
            let result = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: result, value: .intLiteral(0)))
            return result
        }
    }

    // MARK: - REFL-005: KClass variable receiver member calls

    /// Lowers `kclassVar.isInstance(value)`, `kclassVar.members`, `kclassVar.constructors`
    /// where the receiver is a local variable of type KClass<T>, not a direct `T::class` expression.
    /// The receiver variable already holds a KClass box, so we use it directly.
    private func lowerKClassVarReflectMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        memberName: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        // Lower the receiver expression to get the KClass box.
        let kclassExpr = driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        switch memberName {
        case "isInstance":
            let valueExpr: KIRExprID
            if let firstArg = args.first {
                valueExpr = driver.lowerExpr(
                    firstArg.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                valueExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: valueExpr, value: .intLiteral(0)))
            }
            let resultType = sema.bindings.exprTypes[exprID] ?? boolType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_isInstance"),
                arguments: [kclassExpr, valueExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "cast", "safeCast":
            let valueExpr: KIRExprID
            if let firstArg = args.first {
                valueExpr = driver.lowerExpr(
                    firstArg.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                valueExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: valueExpr, value: .intLiteral(0)))
            }
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            let canThrow = memberName == "cast"
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(canThrow ? "kk_kclass_cast" : "kk_kclass_safeCast"),
                arguments: [kclassExpr, valueExpr],
                result: result,
                canThrow: canThrow,
                thrownResult: nil
            ))
            return result

        case "members":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_members"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "constructors":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_constructors"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-064: KClass.primaryConstructor (variable receiver)
        case "primaryConstructor":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_primary_constructor"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-061: KClass member access — properties/functions variants
        case "properties":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_properties"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "memberProperties":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_member_properties"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "declaredMemberProperties":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_declared_member_properties"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "functions":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_functions"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "memberFunctions":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_member_functions"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "declaredMemberFunctions":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_declared_member_functions"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-060: KClass basic reflection features (variable receiver)
        case "isFinal":
            let resultType = sema.bindings.exprTypes[exprID] ?? boolType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_is_final"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "isOpen":
            let resultType = sema.bindings.exprTypes[exprID] ?? boolType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_is_open"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "isAbstract":
            let resultType = sema.bindings.exprTypes[exprID] ?? boolType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_is_abstract"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "visibility":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_visibility"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "typeParameters":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_type_parameters"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case "supertypes":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_supertypes"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-065: annotations
        case "annotations":
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_get_annotations"),
                arguments: [kclassExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-065: findAnnotation<T>()
        case "findAnnotation":
            let searchNameExpr: KIRExprID
            if let firstArg = args.first {
                searchNameExpr = driver.lowerExpr(
                    firstArg.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                let emptyStr = interner.intern("")
                searchNameExpr = arena.appendExpr(.stringLiteral(emptyStr), type: sema.types.stringType)
                instructions.append(.constValue(result: searchNameExpr, value: .stringLiteral(emptyStr)))
            }
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_find_annotation"),
                arguments: [kclassExpr, searchNameExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        // STDLIB-REFLECT-079: findAssociatedObject<T>()
        case "findAssociatedObject":
            let keyNameExpr = lowerKClassReifiedTypeNameHint(
                exprID: exprID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.makeNullable(sema.types.anyType)
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_kclass_find_associated_object"),
                arguments: [kclassExpr, keyNameExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        default:
            let result = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: result, value: .intLiteral(0)))
            return result
        }
    }

    // MARK: - takeIf / takeUnless Lowering (STDLIB-160)

    /// Attempts to lower a takeIf / takeUnless extension call.
    /// Returns nil if the expression is not a takeIf/takeUnless call.
    func tryTakeIfTakeUnlessLowering(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction],
        precomputedReceiver: KIRExprID? = nil
    ) -> KIRExprID? {
        guard let takeKind = sema.bindings.takeIfTakeUnlessKind(for: exprID),
              args.count == 1
        else { return nil }

        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        let loweredReceiverID = precomputedReceiver ?? driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // Lower lambda: predicate(receiver) -> Boolean (like scopeLet: lambda takes `it`)
        let loweredLambdaID = driver.lowerExpr(
            args[0].expr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        guard let info = driver.ctx.callableValueInfo(for: loweredLambdaID) else {
            return nil
        }

        let predicateResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: boolType
        )
        let callArgs: [KIRExprID]
        if info.hasClosureParam {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            callArgs = info.captureArguments + [zeroExpr, loweredReceiverID]
        } else {
            callArgs = info.captureArguments + [loweredReceiverID]
        }
        instructions.append(.call(
            symbol: info.symbol,
            callee: info.callee,
            arguments: callArgs,
            result: predicateResult,
            canThrow: false,
            thrownResult: nil
        ))

        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: boundType
        )
        let useReceiverLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()

        let testValue: Bool = takeKind == .takeIf
        let testExpr = arena.appendExpr(.boolLiteral(testValue), type: boolType)
        instructions.append(.constValue(result: testExpr, value: .boolLiteral(testValue)))

        // takeIf: jump to useReceiver when predicate == true
        // takeUnless: jump to useReceiver when predicate == false
        instructions.append(.jumpIfEqual(lhs: predicateResult, rhs: testExpr, target: useReceiverLabel))

        // Predicate failed: write null to result
        let nullVal = arena.appendExpr(.unit, type: boundType)
        instructions.append(.constValue(result: nullVal, value: .null))
        instructions.append(.copy(from: nullVal, to: result))
        instructions.append(.jump(endLabel))

        // Predicate passed: forward the lowered receiver as-is.
        // The surrounding lowering/codegen path will box later if needed.
        instructions.append(.label(useReceiverLabel))
        instructions.append(.copy(from: loweredReceiverID, to: result))
        instructions.append(.label(endLabel))

        return result
    }

    // MARK: - Scope Function Lowering (STDLIB-004)

    /// Attempts to lower a scope function call (let/run/apply/also).
    /// Returns nil if the expression is not a scope function call.
    func tryScopeFunctionLowering(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction],
        precomputedReceiver: KIRExprID? = nil
    ) -> KIRExprID? {
        guard let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
              args.count == 1
        else { return nil }

        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType

        // Lower the receiver expression (or use precomputed one for safe calls).
        let loweredReceiverID = precomputedReceiver ?? driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        switch scopeKind {
        case .scopeLet, .scopeAlso:
            // let/also: lambda takes `it` as explicit parameter.
            // Lower lambda normally, then call it with receiver as argument.
            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
            )
            if let info = driver.ctx.callableValueInfo(for: loweredLambdaID) {
                let callArgs: [KIRExprID]
                if info.hasClosureParam {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    callArgs = info.captureArguments + [zeroExpr, loweredReceiverID]
                } else {
                    callArgs = info.captureArguments + [loweredReceiverID]
                }
                instructions.append(.call(
                    symbol: info.symbol,
                    callee: info.callee,
                    arguments: callArgs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // Non-lambda-literal argument (e.g. function reference);
                // fall back to normal member call lowering.
                return nil
            }
            if scopeKind == .scopeAlso {
                // also: result is the receiver, not the lambda return value.
                instructions.append(.copy(from: loweredReceiverID, to: result))
            }
            return result

        case .scopeRun, .scopeApply:
            // run/apply: lambda has `this` as implicit receiver.
            // Set the implicit receiver to the lowered receiver before lowering
            // the lambda so that the lambda captures it.
            let receiverSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let receiverSymExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            instructions.append(.copy(from: loweredReceiverID, to: receiverSymExpr))

            let savedReceiverExprID = driver.ctx.activeImplicitReceiverExprID()
            let savedReceiverSymbol = driver.ctx.activeImplicitReceiverSymbol()
            driver.ctx.setLocalValue(receiverSymExpr, for: receiverSymbol)
            driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverSymExpr)

            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

            driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)

            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
            )
            if let info = driver.ctx.callableValueInfo(for: loweredLambdaID) {
                instructions.append(.call(
                    symbol: info.symbol,
                    callee: info.callee,
                    arguments: info.captureArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // Non-lambda-literal argument (e.g. function reference);
                // restore state and fall back to normal member call lowering.
                driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)
                return nil
            }
            if scopeKind == .scopeApply {
                // apply: result is the receiver, not the lambda return value.
                instructions.append(.copy(from: loweredReceiverID, to: result))
            }
            return result

        case .scopeUse:
            // use: like `let`, lambda takes `it` as explicit parameter,
            // but receiver.close() is called in a finally block (try-finally semantics).
            // If the block throws, close() is still called before the exception propagates.
            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
            )
            guard let info = driver.ctx.callableValueInfo(for: loweredLambdaID) else {
                return nil
            }

            let intType = sema.types.make(.primitive(.int, .nonNull))

            // Exception tracking slots for try-finally.
            let exceptionSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.nullableAnyType)
            let exceptionTypeSlot = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            let nullExceptionValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nullExceptionValue, value: .null))
            instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

            let finallyLabel = driver.ctx.makeLoopLabel()
            let rethrowLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()

            // try: invoke the block lambda.
            var blockInstructions: [KIRInstruction] = []
            let callArgs: [KIRExprID]
            if info.hasClosureParam {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                blockInstructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                callArgs = info.captureArguments + [zeroExpr, loweredReceiverID]
            } else {
                callArgs = info.captureArguments + [loweredReceiverID]
            }
            blockInstructions.append(.call(
                symbol: info.symbol,
                callee: info.callee,
                arguments: callArgs,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))

            // Wrap block call with throw-aware instructions so exceptions are
            // captured into exceptionSlot and control jumps to finallyLabel.
            driver.controlFlowLowerer.appendThrowAwareInstructions(
                blockInstructions,
                exceptionSlot: exceptionSlot,
                exceptionTypeSlot: exceptionTypeSlot,
                thrownTarget: finallyLabel,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
            instructions.append(.jump(finallyLabel))

            // finally: call close() on the receiver via virtual dispatch.
            // close() is an interface method on Closeable and requires dynamic dispatch
            // through the itable so that concrete implementations are invoked correctly.
            instructions.append(.label(finallyLabel))
            let receiverTypeForDispatch = sema.bindings.exprTypes[receiverExpr]
            let shouldGuardNullableClose = receiverTypeForDispatch.map {
                sema.types.nullability(of: $0) != .nonNull
            } ?? false
            let closeEndLabel: Int32? = shouldGuardNullableClose ? driver.ctx.makeLoopLabel() : nil
            if shouldGuardNullableClose, let closeEndLabel {
                let closeCallLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: closeCallLabel))
                instructions.append(.jump(closeEndLabel))
                instructions.append(.label(closeCallLabel))
            }
            let closeName = interner.intern("close")
            let closeResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.unitType
            )
            // Resolve the close() symbol from the Closeable interface and use
            // virtualCall with interface dispatch instead of a static .call.
            let closeableFQName: [InternedString] = [
                interner.intern("kotlin"), interner.intern("io"), interner.intern("Closeable")
            ]
            let closeFQName = closeableFQName + [closeName]
            let closeSymbol = sema.symbols.lookup(fqName: closeFQName)
            let closeDispatch: KIRDispatchKind? = closeSymbol.flatMap { sym in
                resolveVirtualDispatch(callee: sym, receiverTypeID: receiverTypeForDispatch, sema: sema)
            }
            if let closeDispatch, let closeSymbol {
                instructions.append(.virtualCall(
                    symbol: closeSymbol,
                    callee: closeName,
                    receiver: loweredReceiverID,
                    arguments: [],
                    result: closeResult,
                    canThrow: true,
                    thrownResult: nil,
                    dispatch: closeDispatch
                ))
            } else {
                // Fallback: if virtual dispatch is not needed (e.g. final class with
                // no subtypes), resolve the concrete close() method on the receiver type
                // so that the static call targets the correct mangled name.
                var concreteCloseSymbol: SymbolID? = nil
                var concreteCloseName = closeName
                if let recvTypeID = receiverTypeForDispatch,
                   case let .classType(recvClass) = sema.types.kind(of: recvTypeID)
                {
                    let recvSymbol = recvClass.classSymbol
                    if let recvInfo = sema.symbols.symbol(recvSymbol) {
                        let closeCandidateFQ = recvInfo.fqName + [closeName]
                        if let concreteSym = sema.symbols.lookup(fqName: closeCandidateFQ) {
                            concreteCloseSymbol = concreteSym
                            // Prefer the externalLinkName (e.g. kk_buffered_writer_close) over
                            // the Kotlin symbol name (which would just be "close") so that the
                            // generated .call instruction targets the correct runtime C function.
                            if let extLink = sema.symbols.externalLinkName(for: concreteSym),
                               !extLink.isEmpty
                            {
                                concreteCloseName = interner.intern(extLink)
                            } else {
                                concreteCloseName = sema.symbols.symbol(concreteSym)?.name ?? closeName
                            }
                        }
                    }
                }
                let callSymbol = concreteCloseSymbol ?? closeSymbol
                instructions.append(.call(
                    symbol: callSymbol,
                    callee: concreteCloseName,
                    arguments: [loweredReceiverID],
                    result: closeResult,
                    canThrow: true,
                    thrownResult: nil
                ))
            }
            if let closeEndLabel {
                instructions.append(.label(closeEndLabel))
            }

            // After finally: rethrow if an exception was caught, otherwise continue.
            instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
            instructions.append(.jump(endLabel))

            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: exceptionSlot))

            instructions.append(.label(endLabel))
            return result

        case .scopeWith:
            return nil // with is handled in lowerCallExpr

        case .scopeContext:
            return nil // context is handled in lowerCallExpr

        case .scopeTopLevelRun:
            return nil // top-level run is handled in lowerCallExpr
        }
    }
}
