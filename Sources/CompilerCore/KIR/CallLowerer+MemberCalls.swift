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
        lowerMemberLikeCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
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
        lowerMemberLikeCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
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

        // P5-111: If the sema bound this member-call expression to a
        // property/field symbol (zero-arg property access like `Counter.n`),
        // emit a loadGlobal from the property's global slot instead of a call.
        // Only applies to object member properties (which have KIRGlobal declarations).
        // Class instance property reads fall through to the normal call path.
        if args.isEmpty,
           let propSymbol = sema.bindings.identifierSymbols[exprID],
           let propSym = sema.symbols.symbol(propSymbol),
           (propSym.kind == .property || propSym.kind == .field) {
            let parentSym = sema.symbols.parentSymbol(for: propSymbol)
            let parentKind = parentSym.flatMap({ sema.symbols.symbol($0) })?.kind
            if parentKind == .object {
                // Lower receiver first (triggers singleton <clinit> for objects).
                _ = driver.lowerExpr(
                    receiverExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let propType = boundType ?? sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
                let propRef = arena.appendExpr(.symbolRef(propSymbol), type: propType)
                let targetSym = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
                instructions.append(.loadGlobal(result: propRef, symbol: targetSym))
                return propRef
            }
        }

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
        if interner.resolve(calleeName) == "inv",
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
              symInfo.flags.contains(.constValue) else {
            return nil
        }
        if requireNonNullableReceiver {
            guard let receiverType = sema.bindings.exprTypes[receiverExpr],
                  receiverType == sema.types.makeNonNullable(receiverType) else {
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
           signature.receiverType != nil {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        guard chosenCallee == nil,
              prependReceiverForUnresolvedCollectionCall else {
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
            appendMemberReifiedTypeTokens(
                chosenCallee: chosenCallee,
                callBinding: callBinding,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArguments
            )
            appendMemberDefaultMask(
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

        appendMemberReifiedTypeTokens(
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

    private func appendMemberReifiedTypeTokens(
        chosenCallee: SymbolID?,
        callBinding: CallBinding?,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard let chosenCallee,
              let callBinding,
              let signature = sema.symbols.functionSignature(for: chosenCallee),
              !signature.reifiedTypeParameterIndices.isEmpty else {
            return
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        for index in signature.reifiedTypeParameterIndices.sorted() {
            let concreteType = index < callBinding.substitutedTypeArguments.count
                ? callBinding.substitutedTypeArguments[index]
                : sema.types.anyType
            let tokenExpr = arena.appendExpr(
                .intLiteral(Int64(concreteType.rawValue)),
                type: intType
            )
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
            arguments.append(tokenExpr)
        }
    }

    private func appendMemberDefaultMask(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let maskExpr = arena.appendExpr(.intLiteral(defaultMask), type: intType)
        instructions.append(.constValue(result: maskExpr, value: .intLiteral(defaultMask)))
        arguments.append(maskExpr)
    }

    private func loweredMemberCalleeName(
        chosenCallee: SymbolID?,
        fallback: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString {
        guard let chosenCallee,
              let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
              !externalLinkName.isEmpty else {
            return fallback
        }
        return interner.intern(externalLinkName)
    }

    /// Determine if a callee method requires virtual dispatch.
    /// Returns `.vtable(slot:)` for class methods or `.itable(slot:)` for interface methods,
    /// or `nil` if the call should use direct (static) dispatch.
    private func resolveVirtualDispatch(callee: SymbolID, receiverTypeID: TypeID?, sema: SemaModule) -> KIRDispatchKind? {
        guard let calleeSymbol = sema.symbols.symbol(callee),
              calleeSymbol.kind == .function else {
            return nil
        }
        guard let parentID = sema.symbols.parentSymbol(for: callee),
              let parentSymbol = sema.symbols.symbol(parentID) else {
            return nil
        }
        guard let layout = sema.symbols.nominalLayout(for: parentID) else {
            return nil
        }
        if parentSymbol.kind == .interface {
            // If the receiver is a concrete class with no subtypes, use direct
            // dispatch.  Kotlin classes are final by default, so this is safe and
            // avoids the itable path which requires runtime typeInfo support.
            if let receiverTypeID,
               case .classType(let classType) = sema.types.kind(of: receiverTypeID) {
                let receiverClassSymID = classType.classSymbol
                if let receiverClassSym = sema.symbols.symbol(receiverClassSymID),
                   receiverClassSym.kind == .class {
                    let subtypes = sema.symbols.directSubtypes(of: receiverClassSymID)
                    if subtypes.isEmpty {
                        return nil
                    }
                }
            }
            let interfaceSlot = layout.itableSlots[parentID] ?? 0
            if let methodSlot = layout.vtableSlots[callee] {
                return .itable(interfaceSlot: interfaceSlot, methodSlot: methodSlot)
            }
            return nil
        }
        if parentSymbol.kind == .class {
            // Only use virtual dispatch if the class actually has subtypes.
            // In Kotlin, classes are final by default; virtual dispatch is only
            // needed when the class is open/abstract (has known subtypes).
            let subtypes = sema.symbols.directSubtypes(of: parentID)
            guard !subtypes.isEmpty else {
                return nil
            }
            if let vtableSlot = layout.vtableSlots[callee] {
                return .vtable(slot: vtableSlot)
            }
            return nil
        }
        return nil
    }
}
