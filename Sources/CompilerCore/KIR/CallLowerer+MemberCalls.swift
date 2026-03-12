// swiftlint:disable file_length
import Foundation

struct MemberCallReceiver {
    let expr: ExprID
    let loweredID: KIRExprID
}

extension CallLowerer {
    private static let unresolvedCoroutineHandleMemberNames: Set<String> = ["await", "join", "cancel"]
    private static let unresolvedChannelMemberNames: Set<String> = ["send", "receive", "close"]

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
        "size", "get", "contains", "containsKey",
        "isEmpty", "first", "last", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast",
        "count", "iterator",
        "map", "filter", "mapNotNull", "filterNotNull", "forEach", "flatMap",
        "any", "none", "all",
        "fold", "reduce", "groupBy", "sortedBy", "find", "associateBy", "associateWith", "associate", "zip", "unzip",
        "withIndex", "forEachIndexed", "mapIndexed", "mapValues", "mapKeys",
        "getOrDefault", "getOrElse",
        "asSequence", "toList", "toMutableList", "toTypedArray",
        "take", "drop", "reversed", "sorted", "distinct", "flatten", "chunked", "windowed", "collect",
        "sortedDescending", "sortedByDescending", "sortedWith", "partition",
        "copyOf", "copyOfRange", "fill",
        "to", // FUNC-002
    ]

    func lowerMemberCallExpr(
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
                    instructions: &instructions
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
            instructions: &instructions
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
            instructions: &instructions
        ) {
            return scopeResult
        }

        let effectiveCalleeName = if sema.bindings.isInvokeOperatorCall(exprID) {
            interner.intern("invoke")
        } else {
            calleeName
        }
        if let objProp = tryLowerObjectMemberPropertyRead(
            exprID, args: args, sema: sema, arena: arena, interner: interner,
            instructions: &instructions
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
            instructions: &instructions
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
            requireNonNullableReceiverForConstFold: true,
            prependReceiverForUnresolvedCollectionCall: false,
            instructions: &instructions
        )
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

    private func isSequenceLikeType(
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

    private func isConcreteListLikeType(
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
            return addCollectionHOFClosureArguments(
                loweredArgIDs: loweredArgIDs,
                argExprIDs: args.map(\.expr),
                sema: sema,
                arena: arena,
                instructions: &instructions
            )
        }()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)

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

        // Primitive infix member functions: Int/Long/UInt/ULong.and|or|xor|shl|shr|ushr (EXPR-003, TYPE-005)
        if args.count == 1,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let rhsType = sema.types.makeNonNullable(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType)
            let isIntegerRhs = rhsType == intType || rhsType == longType || rhsType == uintType || rhsType == ulongType
            let primitiveCallee: InternedString? = switch interner.resolve(calleeName) {
            case "and":
                isIntegerRhs ? interner.intern("kk_bitwise_and") : nil
            case "or":
                isIntegerRhs ? interner.intern("kk_bitwise_or") : nil
            case "xor":
                isIntegerRhs ? interner.intern("kk_bitwise_xor") : nil
            case "shl":
                rhsType == intType ? interner.intern("kk_op_shl") : nil
            case "shr":
                rhsType == intType ? interner.intern("kk_op_shr") : nil
            case "ushr":
                rhsType == intType ? interner.intern("kk_op_ushr") : nil
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

        // Int.coerceIn(min, max) (STDLIB-150)
        if interner.resolve(calleeName) == "coerceIn", args.count == 2 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_int_coerceIn"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Int.coerceAtLeast(min) / Int.coerceAtMost(max) (STDLIB-150)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "coerceAtLeast" || calleeStr == "coerceAtMost" {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                let longType = sema.types.make(.primitive(.long, .nonNull))
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if nonNullReceiverType == intType || nonNullReceiverType == longType {
                    let runtimeName = calleeStr == "coerceAtLeast" ? "kk_int_coerceAtLeast" : "kk_int_coerceAtMost"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeName),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Primitive member function: Int/Long.toString(radix: Int) → kk_int_toString_radix (EXPR-003)
        if calleeName == interner.intern("toString"),
           args.count == 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_int_toString_radix"),
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong(),
        // toFloat(), toByte(), toShort() (TYPE-005)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
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
            case ("toInt", doubleType, intType): interner.intern("kk_double_to_int")
            case ("toInt", floatType, intType): interner.intern("kk_float_to_int")
            case ("toInt", longType, intType): interner.intern("kk_long_to_int")
            case ("toInt", intType, intType): nil // identity
            case ("toUInt", intType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", longType, uintType): interner.intern("kk_long_to_uint")
            case ("toUInt", uintType, uintType), ("toUInt", ulongType, uintType): nil // identity
            case ("toLong", intType, longType): interner.intern("kk_int_to_long")
            case ("toLong", uintType, longType): interner.intern("kk_uint_to_long")
            case ("toLong", doubleType, longType): interner.intern("kk_double_to_long")
            case ("toLong", floatType, longType): interner.intern("kk_float_to_long")
            case ("toLong", longType, longType), ("toLong", ulongType, longType): nil // identity
            case ("toULong", intType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", longType, ulongType): interner.intern("kk_long_to_ulong")
            case ("toULong", uintType, ulongType): interner.intern("kk_uint_to_ulong")
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
            if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble"].contains(calleeStr),
               nonNullReceiverType == nonNullResultType || isRepresentationPreservingConversion,
               nonNullReceiverType == intType || nonNullReceiverType == longType
               || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
               || nonNullReceiverType == floatType || nonNullReceiverType == doubleType
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

        // String stdlib: nullable-receiver 0-arg methods (NULL-002)
        // isNullOrEmpty/isNullOrBlank pass the raw (potentially null) receiver pointer to C runtime.
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if sema.bindings.callBindings[exprID] == nil,
               calleeStr == "isNullOrEmpty" || calleeStr == "isNullOrBlank"
            {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
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
                if calleeStr == "lines" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_lines"),
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
                if calleeStr == "firstOrNull" || calleeStr == "lastOrNull" {
                    let kkName = calleeStr == "firstOrNull" ? "kk_string_firstOrNull" : "kk_string_lastOrNull"
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
            }
        }

        // String stdlib: 1-arg methods (STDLIB-006)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let calleeStr = interner.resolve(calleeName)
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
                    ("kk_string_indexOf", [loweredReceiverID, loweredArgIDs[0]])
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
                case "take":
                    ("kk_string_take", [loweredReceiverID, loweredArgIDs[0]])
                case "drop":
                    ("kk_string_drop", [loweredReceiverID, loweredArgIDs[0]])
                case "takeLast":
                    ("kk_string_takeLast", [loweredReceiverID, loweredArgIDs[0]])
                case "dropLast":
                    ("kk_string_dropLast", [loweredReceiverID, loweredArgIDs[0]])
                default:
                    nil
                }
                if let runtimeCall {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCall.callee),
                        arguments: runtimeCall.arguments,
                        result: result,
                        canThrow: calleeStr == "repeat",
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: 2-arg substring overload (STDLIB-009)
        if args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
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

        // String stdlib: replaceFirst(oldValue, newValue) (STDLIB-188)
        if args.count == 2, interner.resolve(calleeName) == "replaceFirst" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
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

        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
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
                case "fill":
                    "kk_array_fill"
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
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let calleeStr = interner.resolve(calleeName)
                let runtimeCallee: String? = switch calleeStr {
                case "map":
                    "kk_sequence_map"
                case "filter":
                    "kk_sequence_filter"
                case "take":
                    "kk_sequence_take"
                case "forEach":
                    "kk_sequence_forEach"
                case "flatMap":
                    "kk_sequence_flatMap"
                case "drop":
                    "kk_sequence_drop"
                case "zip":
                    "kk_sequence_zip"
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
            if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                let runtimeCallee: String? = switch calleeStr {
                case "indexOf":
                    "kk_list_indexOf"
                case "lastIndexOf":
                    "kk_list_lastIndexOf"
                case "partition":
                    "kk_list_partition"
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
        }

        if args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "copyOfRange"
            {
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

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee: String? = switch interner.resolve(calleeName) {
                case "toList":
                    "kk_array_toList"
                case "toMutableList":
                    "kk_array_toMutableList"
                case "copyOf":
                    "kk_array_copyOf"
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
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let runtimeCallee: String? = switch interner.resolve(calleeName) {
                case "toList":
                    "kk_sequence_to_list"
                case "distinct":
                    "kk_sequence_distinct"
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
        }

        // String stdlib: format(vararg args) (STDLIB-006)
        if interner.resolve(calleeName) == "format",
           let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_format"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let boxedArgIDs = loweredArgIDs.map { argID in
                    let boxedArg = arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                    instructions.append(.copy(from: argID, to: boxedArg))
                    return boxedArg
                }
                let intType = sema.types.make(.primitive(.int, .nonNull))
                let packedArgs = driver.callSupportLowerer.packVarargArguments(
                    argIndices: Array(boxedArgIDs.indices),
                    providedArguments: boxedArgIDs,
                    spreadFlags: args.map(\.isSpread),
                    arena: arena,
                    interner: interner,
                    intType: intType,
                    anyType: sema.types.nullableAnyType,
                    instructions: &instructions
                )
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

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            argumentExprs: args.map(\.expr),
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
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
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: finalArguments
        )
        return result
    }

    private func isCollectionHOFCallee(
        _ calleeName: InternedString,
        interner: StringInterner
    ) -> Bool {
        [
            "map", "filter", "mapNotNull", "forEach", "flatMap",
            "any", "none", "all", "fold", "reduce", "groupBy",
            "sortedBy", "count", "first", "last", "find",
            "associateBy", "associateWith", "associate",
            "forEachIndexed", "mapIndexed", "sumOf", "mapValues", "mapKeys",
            "getOrElse",
            "indexOfFirst", "indexOfLast",
            "sortedByDescending", "sortedWith", "partition",
        ].contains(interner.resolve(calleeName))
    }

    private func addCollectionHOFClosureArguments(
        loweredArgIDs: [KIRExprID],
        argExprIDs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard loweredArgIDs.count == argExprIDs.count else {
            return loweredArgIDs
        }
        var finalArgs: [KIRExprID] = []
        finalArgs.reserveCapacity(loweredArgIDs.count + 1)

        for (loweredArgID, argExprID) in zip(loweredArgIDs, argExprIDs) {
            finalArgs.append(loweredArgID)
            guard sema.bindings.isCollectionHOFLambdaExpr(argExprID),
                  let callableInfo = driver.ctx.callableValueInfo(for: loweredArgID)
            else {
                continue
            }
            if let closureRaw = callableInfo.captureArguments.first {
                finalArgs.append(closureRaw)
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArgs.append(zeroExpr)
            }
        }

        return finalArgs
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
              let constant = propertyConstantInitializers[chosen],
              let symInfo = sema.symbols.symbol(chosen),
              symInfo.flags.contains(.constValue)
        else {
            return nil
        }
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
        var receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        if nullableReceiverAllowed {
            receiverType = sema.types.makeNonNullable(receiverType)
        }
        return receiverType == intType || receiverType == longType || receiverType == uintType || receiverType == ulongType
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
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let calleeText = interner.resolve(calleeName)
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
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: [KIRExprID]
    ) {
        var finalArguments = arguments
        if normalized.defaultMask != 0,
           let chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_joinToString"
        {
            materializeJoinToStringDefaultArguments(
                normalized.defaultMask,
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
                isSuperCall: isSuperCall
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

        let loweredCallee = loweredMemberCalleeName(
            chosenCallee: chosenCallee,
            fallback: calleeName,
            receiverExpr: receiver.expr,
            sema: sema,
            interner: interner
        )
        if loweredCallee == interner.intern("kk_channel_send")
            || loweredCallee == interner.intern("kk_channel_receive")
        {
            let continuationExpr = arena.appendExpr(
                .intLiteral(0),
                type: sema.types.intType
            )
            instructions.append(.constValue(result: continuationExpr, value: .intLiteral(0)))
            finalArguments.append(continuationExpr)
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
        if loweredCallee == interner.intern("kk_system_currentTimeMillis") {
            callArguments = []
        }
        let canThrow = loweredCallee == interner.intern("kk_list_random")
        instructions.append(.call(
            symbol: chosenCallee,
            callee: loweredCallee,
            arguments: callArguments,
            result: result,
            canThrow: canThrow,
            thrownResult: nil,
            isSuperCall: isSuperCall
        ))
    }

    private func materializeJoinToStringDefaultArguments(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        let defaults = [", ", "", ""]
        let stringType = sema.types.stringType
        for (paramIndex, defaultValue) in defaults.enumerated() {
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
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        let fallbackName = interner.resolve(fallback)
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType

        if let chosenCallee {
            if let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
               !externalLinkName.isEmpty
            {
                return interner.intern(externalLinkName)
            }
            if let unresolvedSynthetic = unresolvedSyntheticMemberCallee(
                memberName: fallbackName,
                receiverExpr: receiverExpr,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            ) {
                return unresolvedSynthetic
            }
            return fallback
        }

        if isCoroutineHandleReceiverType(receiverType, sema: sema, interner: interner) {
            switch fallbackName {
            case "await":
                return interner.intern("kk_kxmini_async_await")
            case "join":
                return interner.intern("kk_job_join")
            case "cancel":
                return interner.intern("kk_job_cancel")
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
            default:
                break
            }
        }
        if let collectionProperty = unresolvedCollectionPropertyCallee(
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
            sema: sema,
            interner: interner
        ) {
            return mapMember
        }
        if let unresolvedSynthetic = unresolvedSyntheticMemberCallee(
            memberName: fallbackName,
            receiverExpr: receiverExpr,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) {
            return unresolvedSynthetic
        }
        return fallback
    }

    // swiftlint:disable cyclomatic_complexity
    private func unresolvedSyntheticMemberCallee(
        memberName: String,
        receiverExpr: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
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
            case "toRegex":
                return interner.intern("kk_string_toRegex")
            default:
                break
            }
        }

        if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "indexOf":
                return interner.intern("kk_list_indexOf")
            case "lastIndexOf":
                return interner.intern("kk_list_lastIndexOf")
            case "partition":
                return interner.intern("kk_list_partition")
            default:
                break
            }
        }

        if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "map":
                return interner.intern("kk_array_map")
            case "filter":
                return interner.intern("kk_array_filter")
            case "toList":
                return interner.intern("kk_array_toList")
            case "toMutableList":
                return interner.intern("kk_array_toMutableList")
            case "forEach":
                return interner.intern("kk_array_forEach")
            case "any":
                return interner.intern("kk_array_any")
            case "none":
                return interner.intern("kk_array_none")
            case "copyOf":
                return interner.intern("kk_array_copyOf")
            case "fill":
                return interner.intern("kk_array_fill")
            default:
                break
            }
        }

        switch memberName {
        case "partition":
            return interner.intern("kk_list_partition")
        case "indexOf":
            return interner.intern("kk_list_indexOf")
        case "lastIndexOf":
            return interner.intern("kk_list_lastIndexOf")
        default:
            break
        }

        if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
            || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
        {
            switch memberName {
            case "map":
                return interner.intern("kk_sequence_map")
            case "filter":
                return interner.intern("kk_sequence_filter")
            case "take":
                return interner.intern("kk_sequence_take")
            case "toList":
                return interner.intern("kk_sequence_to_list")
            case "forEach":
                return interner.intern("kk_sequence_forEach")
            case "flatMap":
                return interner.intern("kk_sequence_flatMap")
            case "drop":
                return interner.intern("kk_sequence_drop")
            case "distinct":
                return interner.intern("kk_sequence_distinct")
            case "zip":
                return interner.intern("kk_sequence_zip")
            default:
                break
            }
        }

        return nil
    }

    // swiftlint:enable cyclomatic_complexity

    private func unresolvedCollectionPropertyCallee(
        memberName: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard memberName == "size" || memberName == "isEmpty",
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
            case .list?, .collection?:
                return interner.intern("kk_list_is_empty")
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
            return interner.intern("kk_map_count")
        case "any":
            return interner.intern("kk_map_any")
        case "all":
            return interner.intern("kk_map_all")
        case "none":
            return interner.intern("kk_map_none")
        case "getOrDefault":
            return interner.intern("kk_map_getOrDefault")
        case "getOrElse":
            return interner.intern("kk_map_getOrElse")
        default:
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

    func lowerMemberAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        valueExpr: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerMemberAssignExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            valueExpr: valueExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
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

        case .scopeWith:
            return nil // with is handled in lowerCallExpr
        }
    }
}
