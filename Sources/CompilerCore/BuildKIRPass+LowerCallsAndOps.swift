import Foundation

extension BuildKIRPhase {
    func lowerBinaryExpr(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let lhsID = lowerExpr(
            lhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let rhsID = lowerExpr(
            rhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        if let callBinding = sema.bindings.callBindings[exprID],
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
           signature.receiverType != nil {
            let normalizedResult = normalizedCallArguments(
                providedArguments: [rhsID],
                callBinding: callBinding,
                chosenCallee: callBinding.chosenCallee,
                spreadFlags: [false],
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            var finalArguments = normalizedResult.arguments
            finalArguments.insert(lhsID, at: 0)
            if normalizedResult.defaultMask != 0 {
                if let sig = sema.symbols.functionSignature(for: callBinding.chosenCallee),
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
                let maskExpr = arena.appendExpr(.intLiteral(Int64(normalizedResult.defaultMask)), type: intType)
                instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(normalizedResult.defaultMask))))
                finalArguments.append(maskExpr)
                let stubName = interner.intern(
                    (sema.symbols.symbol(callBinding.chosenCallee).map { interner.resolve($0.name) } ?? "unknown") + "$default"
                )
                let stubSym = defaultStubSymbol(for: callBinding.chosenCallee)
                instructions.append(.call(
                    symbol: stubSym,
                    callee: stubName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                if let sig = sema.symbols.functionSignature(for: callBinding.chosenCallee),
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
                let loweredCalleeName: InternedString
                if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                   !externalLinkName.isEmpty {
                    loweredCalleeName = interner.intern(externalLinkName)
                } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                    loweredCalleeName = symbol.name
                } else {
                    loweredCalleeName = binaryOperatorFunctionName(for: op, interner: interner)
                }
                instructions.append(.call(
                    symbol: callBinding.chosenCallee,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return result
        }
        if case .add = op, sema.bindings.exprTypes[exprID] == stringType {
            instructions.append(
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_string_concat"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        if let runtimeCallee = builtinBinaryRuntimeCallee(for: op, interner: interner) {
            instructions.append(
                .call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        let kirOp: KIRBinaryOp
        switch op {
        case .add:
            kirOp = .add
        case .subtract:
            kirOp = .subtract
        case .multiply:
            kirOp = .multiply
        case .divide:
            kirOp = .divide
        case .modulo:
            kirOp = .modulo
        case .equal:
            kirOp = .equal
        case .notEqual:
            kirOp = .notEqual
        case .lessThan:
            kirOp = .lessThan
        case .lessOrEqual:
            kirOp = .lessOrEqual
        case .greaterThan:
            kirOp = .greaterThan
        case .greaterOrEqual:
            kirOp = .greaterOrEqual
        case .logicalAnd:
            kirOp = .logicalAnd
        case .logicalOr:
            kirOp = .logicalOr
        case .elvis:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_elvis"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeTo:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_rangeTo"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
        return result
    }

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
        let calleeName: InternedString
        if let callee = ast.arena.expr(calleeExpr), case .nameRef(let name, _) = callee {
            calleeName = name
        } else {
            calleeName = sema.symbols.allSymbols().first?.name ?? InternedString()
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
        let chosen = callBinding?.chosenCallee
        let callNormalized = normalizedCallArguments(
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
        var finalArgIDs = callNormalized.arguments
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
            let stubName = interner.intern(interner.resolve(calleeName) + "$default")
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
            } else if chosen == nil {
                loweredCalleeName = loweredRuntimeBuiltinCallee(
                    for: calleeName,
                    argumentCount: finalArgIDs.count,
                    interner: interner
                ) ?? calleeName
            } else {
                loweredCalleeName = calleeName
            }
            instructions.append(.call(
                symbol: chosen,
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

    func lowerArrayAccessExpr(
        _ exprID: ExprID,
        arrayExpr: ExprID,
        indexExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let arrayID = lowerExpr(
            arrayExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let indexID = lowerExpr(
            indexExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [arrayID, indexID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func lowerArrayAssignExpr(
        _ exprID: ExprID,
        arrayExpr: ExprID,
        indexExpr: ExprID,
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let arrayID = lowerExpr(
            arrayExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let indexID = lowerExpr(
            indexExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [arrayID, indexID, valueID],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
