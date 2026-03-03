import Foundation

extension CallLowerer {
    private static let unresolvedCollectionMemberNames: Set<String> = [
        "size", "get", "contains", "containsKey",
        "isEmpty", "first", "last", "indexOf",
        "count", "iterator",
        "map", "filter", "forEach", "flatMap",
        "any", "none", "all",
        "asSequence", "toList", "take", // swiftlint:disable:this trailing_comma
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
        // ── T::class.simpleName / T::class.qualifiedName ──────────────
        if case let .callableRef(classRefReceiver, refMember, _) = ast.arena.expr(receiverExpr),
           interner.resolve(refMember) == "class",
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

        let effectiveCalleeName = if sema.bindings.isInvokeOperatorCall(exprID) {
            interner.intern("invoke")
        } else {
            calleeName
        }
        if let objProp = tryLowerObjectMemberPropertyRead(
            exprID, args: args, sema: sema, arena: arena,
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
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)

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

        // Primitive infix member functions: Int/Long.and|or|xor|shl|shr|ushr (EXPR-003)
        if args.count == 1,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let rhsType = sema.types.makeNonNullable(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType)
            let primitiveCallee: InternedString? = switch interner.resolve(calleeName) {
            case "and":
                (rhsType == intType || rhsType == longType) ? interner.intern("kk_bitwise_and") : nil
            case "or":
                (rhsType == intType || rhsType == longType) ? interner.intern("kk_bitwise_or") : nil
            case "xor":
                (rhsType == intType || rhsType == longType) ? interner.intern("kk_bitwise_xor") : nil
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

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        let normalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: loweredArgIDs,
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
            receiverExpr: receiverExpr,
            loweredReceiverID: loweredReceiverID,
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

    private func tryLowerObjectMemberPropertyRead(
        _ exprID: ExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
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
        let propType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: valueSym)
            ?? sema.types.anyType
        let id = arena.appendExpr(.symbolRef(valueSym), type: propType)
        instructions.append(.loadGlobal(result: id, symbol: valueSym))
        return id
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
        var receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        if nullableReceiverAllowed {
            receiverType = sema.types.makeNonNullable(receiverType)
        }
        return receiverType == intType || receiverType == longType
    }

    private func appendReceiverToMemberArguments(
        _ loweredReceiverID: KIRExprID,
        receiverExpr _: ExprID,
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
        let calleeText = interner.resolve(calleeName)
        if Self.unresolvedCollectionMemberNames.contains(calleeText) {
            arguments.insert(loweredReceiverID, at: 0)
        }
    }

    private func emitMemberCallInstruction(
        normalized: NormalizedCallResult,
        callBinding: CallBinding?,
        chosenCallee: SymbolID?,
        calleeName: InternedString,
        receiverExpr: ExprID,
        loweredReceiverID: KIRExprID,
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
           let chosenCallee
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

        let loweredMemberCalleeName = loweredMemberCalleeName(
            chosenCallee: chosenCallee,
            fallback: calleeName,
            sema: sema,
            interner: interner
        )
        let receiverTypeForDispatch = sema.bindings.exprTypes[receiverExpr]
        if !isSuperCall,
           let chosenCallee,
           let dispatchKind = resolveVirtualDispatch(callee: chosenCallee, receiverTypeID: receiverTypeForDispatch, sema: sema)
        {
            // For virtualCall, the receiver is a separate field, so remove it
            // from finalArguments (it was inserted at index 0 above).
            var vcArguments = finalArguments
            if let signature = sema.symbols.functionSignature(for: chosenCallee),
               signature.receiverType != nil,
               !vcArguments.isEmpty
            {
                vcArguments.removeFirst()
            }
            instructions.append(.virtualCall(
                symbol: chosenCallee,
                callee: loweredMemberCalleeName,
                receiver: loweredReceiverID,
                arguments: vcArguments,
                result: result,
                canThrow: false,
                thrownResult: nil,
                dispatch: dispatchKind
            ))
            return
        }
        instructions.append(.call(
            symbol: chosenCallee,
            callee: loweredMemberCalleeName,
            arguments: finalArguments,
            result: result,
            canThrow: false,
            thrownResult: nil,
            isSuperCall: isSuperCall
        ))
    }

    private func loweredMemberCalleeName(
        chosenCallee: SymbolID?,
        fallback: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        guard let chosenCallee,
              let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
              !externalLinkName.isEmpty
        else {
            return fallback
        }
        return interner.intern(externalLinkName)
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
        // Use the call binding from sema if available (property setter).
        let callBinding = sema.bindings.callBindings[exprID]
        let chosenCallee = callBinding?.chosenCallee
        let setterName = loweredMemberCalleeName(chosenCallee: chosenCallee, fallback: calleeName, sema: sema, interner: interner)
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

    // swiftlint:disable:next file_length
}
