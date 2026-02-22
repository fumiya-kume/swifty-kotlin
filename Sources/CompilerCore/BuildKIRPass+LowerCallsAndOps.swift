import Foundation

extension BuildKIRPhase {
    func lowerCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let loweredCalleeExprID = lowerExpr(
            calleeExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let loweredCallable = callableValueInfoByExprID[loweredCalleeExprID]
        let sourceCalleeName: InternedString
        if let callee = ast.arena.expr(calleeExpr), case .nameRef(let name, _) = callee {
            sourceCalleeName = name
        } else if let loweredCallable {
            sourceCalleeName = loweredCallable.callee
        } else {
            sourceCalleeName = interner.intern("<unknown>")
        }
        let loweredArgIDs = args.map { argument in
            lowerExpr(
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
        let callBinding = sema.bindings.callBindings[exprID]
        let callableValueCallBinding = sema.bindings.callableValueCalls[exprID]
        let chosen = callBinding?.chosenCallee
        let callNormalized: NormalizedCallResult
        if callBinding != nil {
            callNormalized = normalizedCallArguments(
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
        } else {
            callNormalized = NormalizedCallResult(
                arguments: normalizedCallableValueArguments(
                    providedArguments: loweredArgIDs,
                    callableValueCallBinding: callableValueCallBinding,
                    sema: sema
                ),
                defaultMask: 0,
                calleeHasDefaults: false
            )
        }
        var finalArgIDs = callNormalized.arguments
        if let loweredCallable {
            finalArgIDs.insert(contentsOf: loweredCallable.captureArguments, at: 0)
        } else if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen),
           signature.receiverType != nil,
           let implicitReceiver = currentImplicitReceiverExprID {
            finalArgIDs.insert(implicitReceiver, at: 0)
        }
        if callNormalized.defaultMask != 0, let chosen {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            if let callBinding,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArgIDs.append(tokenExpr)
                }
            }
            let maskExpr = arena.appendExpr(.intLiteral(Int64(callNormalized.defaultMask)), type: intType)
            instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(callNormalized.defaultMask))))
            finalArgIDs.append(maskExpr)
            let stubName = interner.intern(interner.resolve(sourceCalleeName) + "$default")
            let stubSym = defaultStubSymbol(for: chosen)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            if let callBinding, let chosen,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArgIDs.append(tokenExpr)
                }
            }
            let loweredCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty {
                loweredCalleeName = interner.intern(externalLinkName)
            } else if let loweredCallable {
                loweredCalleeName = loweredCallable.callee
            } else if chosen == nil {
                loweredCalleeName = loweredRuntimeBuiltinCallee(
                    for: sourceCalleeName,
                    argumentCount: finalArgIDs.count,
                    interner: interner
                ) ?? sourceCalleeName
            } else {
                loweredCalleeName = sourceCalleeName
            }
            instructions.append(.call(
                symbol: chosen ?? loweredCallable?.symbol,
                callee: loweredCalleeName,
                arguments: finalArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
        return result
    }

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
        let boundType = sema.bindings.exprTypes[exprID]
        let loweredReceiverID = lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let loweredArgIDs = args.map { argument in
            lowerExpr(
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
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        let memberNormalized = normalizedCallArguments(
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
        var finalArguments = memberNormalized.arguments
        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen),
           signature.receiverType != nil {
            finalArguments.insert(loweredReceiverID, at: 0)
        }
        if memberNormalized.defaultMask != 0, let chosen {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            if let callBinding,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            let maskExpr = arena.appendExpr(.intLiteral(Int64(memberNormalized.defaultMask)), type: intType)
            instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(memberNormalized.defaultMask))))
            finalArguments.append(maskExpr)
            let stubName = interner.intern(interner.resolve(calleeName) + "$default")
            let stubSym = defaultStubSymbol(for: chosen)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            if let callBinding, let chosen,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            let loweredMemberCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty {
                loweredMemberCalleeName = interner.intern(externalLinkName)
            } else {
                loweredMemberCalleeName = calleeName
            }
            let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
            if !isSuperCall,
               let chosen,
               let dispatchKind = resolveVirtualDispatch(callee: chosen, sema: sema) {
                instructions.append(.virtualCall(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    receiver: loweredReceiverID,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: dispatchKind
                ))
            } else {
                instructions.append(.call(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
        }
        return result
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
        let boundType = sema.bindings.exprTypes[exprID]
        let loweredReceiverID = lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let loweredArgIDs = args.map { argument in
            lowerExpr(
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
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        let safeNormalized = normalizedCallArguments(
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
        var finalArguments = safeNormalized.arguments
        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen),
           signature.receiverType != nil {
            finalArguments.insert(loweredReceiverID, at: 0)
        }
        if safeNormalized.defaultMask != 0, let chosen {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            if let callBinding,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            let maskExpr = arena.appendExpr(.intLiteral(Int64(safeNormalized.defaultMask)), type: intType)
            instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(safeNormalized.defaultMask))))
            finalArguments.append(maskExpr)
            let stubName = interner.intern(interner.resolve(calleeName) + "$default")
            let stubSym = defaultStubSymbol(for: chosen)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            if let callBinding, let chosen,
               let sig = sema.symbols.functionSignature(for: chosen),
               !sig.reifiedTypeParameterIndices.isEmpty {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for index in sig.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            let loweredMemberCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty {
                loweredMemberCalleeName = interner.intern(externalLinkName)
            } else {
                loweredMemberCalleeName = calleeName
            }
            let isSafeSuper = sema.bindings.isSuperCallExpr(exprID)
            if !isSafeSuper,
               let chosen,
               let dispatchKind = resolveVirtualDispatch(callee: chosen, sema: sema) {
                instructions.append(.virtualCall(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    receiver: loweredReceiverID,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: dispatchKind
                ))
            } else {
                instructions.append(.call(
                    symbol: chosen,
                    callee: loweredMemberCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
        }
        return result
    }

    /// Determine if a callee method requires virtual dispatch.
    /// Returns `.vtable(slot:)` for class methods or `.itable(slot:)` for interface methods,
    /// or `nil` if the call should use direct (static) dispatch.
    private func resolveVirtualDispatch(callee: SymbolID, sema: SemaModule) -> KIRDispatchKind? {
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

    private func normalizedCallableValueArguments(
        providedArguments: [KIRExprID],
        callableValueCallBinding: CallableValueCallBinding?,
        sema: SemaModule
    ) -> [KIRExprID] {
        guard let callableValueCallBinding,
              case .functionType(let functionType) = sema.types.kind(of: callableValueCallBinding.functionType) else {
            return providedArguments
        }

        let parameterCount = functionType.params.count
        guard parameterCount == providedArguments.count,
              !callableValueCallBinding.parameterMapping.isEmpty else {
            return providedArguments
        }

        var reordered = Array(repeating: KIRExprID.invalid, count: parameterCount)
        for (argIndex, paramIndex) in callableValueCallBinding.parameterMapping {
            guard argIndex >= 0,
                  argIndex < providedArguments.count,
                  paramIndex >= 0,
                  paramIndex < parameterCount,
                  reordered[paramIndex] == .invalid else {
                return providedArguments
            }
            reordered[paramIndex] = providedArguments[argIndex]
        }

        guard !reordered.contains(.invalid) else {
            return providedArguments
        }
        return reordered
    }
}
