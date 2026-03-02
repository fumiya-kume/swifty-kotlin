import Foundation

extension CallLowerer {
    private static let unresolvedCollectionMemberNames: Set<String> = [
        "size", "get", "contains", "containsKey",
        "isEmpty", "first", "last", "indexOf",
        "count", "iterator"
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
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold) {
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
           signature.receiverType != nil {
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
           let chosenCallee {
            appendReifiedTypeTokens(
                chosenCallee: chosenCallee,
                callBinding: callBinding,
                sema: sema,
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
           let dispatchKind = resolveVirtualDispatch(callee: chosenCallee, receiverTypeID: receiverTypeForDispatch, sema: sema) {
            // For virtualCall, the receiver is a separate field, so remove it
            // from finalArguments (it was inserted at index 0 above).
            var vcArguments = finalArguments
            if let signature = sema.symbols.functionSignature(for: chosenCallee),
               signature.receiverType != nil,
               !vcArguments.isEmpty {
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
    // swiftlint:disable:next file_length
}
