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
                  sema.symbols.symbol(chosen)?.kind == .constructor {
            // Constructor calls need an allocated object as the implicit receiver (p0).
            // Allocate via kk_array_new(1) and prepend it to the argument list.
            let allocType = boundType ?? sema.types.anyType
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let slotCountExpr = arena.appendExpr(.intLiteral(1), type: intType)
            instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(1)))
            let allocatedObj = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: allocType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_new"),
                arguments: [slotCountExpr],
                result: allocatedObj,
                canThrow: false,
                thrownResult: nil
            ))
            finalArgIDs.insert(allocatedObj, at: 0)
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
            instructions.append(.call(
                symbol: chosen,
                callee: loweredMemberCalleeName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
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
            instructions.append(.call(
                symbol: chosen,
                callee: loweredMemberCalleeName,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
        return result
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
