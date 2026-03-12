import Foundation

struct BoxingCalleeNames {
    let int: InternedString
    let bool: InternedString
    let long: InternedString
    let float: InternedString
    let double: InternedString
    let char: InternedString
}

struct UnboxingCalleeNames {
    let int: InternedString
    let bool: InternedString
    let long: InternedString
    let float: InternedString
    let double: InternedString
    let char: InternedString
}

final class ABILoweringPass: LoweringPass {
    static let name = "ABILowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let nonThrowingCallees = nonThrowingCallees(interner: ctx.interner)

        let boxCallees = BoxingCalleeNames(
            int: ctx.interner.intern("kk_box_int"),
            bool: ctx.interner.intern("kk_box_bool"),
            long: ctx.interner.intern("kk_box_long"),
            float: ctx.interner.intern("kk_box_float"),
            double: ctx.interner.intern("kk_box_double"),
            char: ctx.interner.intern("kk_box_char")
        )
        let unboxCallees = UnboxingCalleeNames(
            int: ctx.interner.intern("kk_unbox_int"),
            bool: ctx.interner.intern("kk_unbox_bool"),
            long: ctx.interner.intern("kk_unbox_long"),
            float: ctx.interner.intern("kk_unbox_float"),
            double: ctx.interner.intern("kk_unbox_double"),
            char: ctx.interner.intern("kk_unbox_char")
        )

        let types = ctx.sema?.types
        let symbols = ctx.sema?.symbols

        var signatureByName: [InternedString: FunctionSignature] = [:]
        if let symbols {
            for decl in module.arena.declarations {
                guard case let .function(fn) = decl else { continue }
                if let sig = symbols.functionSignature(for: fn.symbol) {
                    signatureByName[fn.name] = sig
                }
            }
        }

        module.arena.transformFunctions { function in
            var updated = function
            var newBody: [KIRInstruction] = []
            newBody.reserveCapacity(function.body.count)

            let functionReturnKind: TypeKind? = types.map { $0.kind(of: function.returnType) }

            var idx = 0
            while idx < function.body.count {
                let instruction = function.body[idx]
                if case let .virtualCall(vcSymbol, vcCallee, vcReceiver, vcArguments, vcResult, _, vcThrownResult, vcDispatch) = instruction {
                    let vcCanThrow = !nonThrowingCallees.contains(vcCallee)
                    var vcSignature: FunctionSignature?
                    if let symbols, let vcSymbol {
                        vcSignature = symbols.functionSignature(for: vcSymbol)
                    }
                    if vcSignature == nil {
                        vcSignature = signatureByName[vcCallee]
                    }
                    let vcBoxedArguments: [KIRExprID] = if let vcSignature, let types {
                        applyArgumentBoxing(
                            arguments: vcArguments,
                            signature: vcSignature,
                            receiverOffset: 0,
                            module: module,
                            types: types,
                            symbols: symbols,
                            boxCallees: boxCallees,
                            newBody: &newBody
                        )
                    } else {
                        vcArguments
                    }
                    let vcUnbox = resolveUnboxForCall(
                        callSymbol: vcSymbol,
                        callee: vcCallee,
                        result: vcResult,
                        signatureByName: signatureByName,
                        module: module,
                        types: types,
                        symbols: symbols,
                        unboxCallees: unboxCallees
                    )
                    if let (vcUnboxCallee, vcReturnType) = vcUnbox, let vcResult {
                        let tempResult = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)),
                            type: vcReturnType
                        )
                        newBody.append(.virtualCall(
                            symbol: vcSymbol,
                            callee: vcCallee,
                            receiver: vcReceiver,
                            arguments: vcBoxedArguments,
                            result: tempResult,
                            canThrow: vcCanThrow,
                            thrownResult: vcThrownResult,
                            dispatch: vcDispatch
                        ))
                        if vcThrownResult != nil {
                            let nextIdx = idx + 1
                            if nextIdx < function.body.count,
                               case .jumpIfNotNull = function.body[nextIdx]
                            {
                                newBody.append(function.body[nextIdx])
                                idx += 1
                            }
                        }
                        newBody.append(.call(
                            symbol: nil,
                            callee: vcUnboxCallee,
                            arguments: [tempResult],
                            result: vcResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    } else {
                        newBody.append(.virtualCall(
                            symbol: vcSymbol,
                            callee: vcCallee,
                            receiver: vcReceiver,
                            arguments: vcBoxedArguments,
                            result: vcResult,
                            canThrow: vcCanThrow,
                            thrownResult: vcThrownResult,
                            dispatch: vcDispatch
                        ))
                    }
                    idx += 1
                    continue
                }

                // Handle returnValue: box primitive if function returns Any/Any?
                if case let .returnValue(value) = instruction, let types,
                   let rewritten = rewriteReturnValueBoxing(
                       value: value,
                       functionReturnKind: functionReturnKind,
                       returnType: function.returnType,
                       module: module, types: types, symbols: symbols,
                       boxCallees: boxCallees
                   )
                {
                    newBody.append(contentsOf: rewritten)
                    idx += 1
                    continue
                }
                if case .returnValue = instruction {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                // Handle copy: insert boxing/unboxing at type boundaries
                if case let .copy(from, to) = instruction, let types,
                   let rewritten = rewriteCopyBoxingOrUnboxing(
                       from: from, to: to,
                       module: module, types: types, symbols: symbols,
                       boxCallees: boxCallees,
                       unboxCallees: unboxCallees
                   )
                {
                    newBody.append(rewritten)
                    idx += 1
                    continue
                }
                if case .copy = instruction {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                guard case let .call(callSymbol, callee, arguments, result, _, thrownResult, isSuperCall) = instruction else {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                // Synthetic property accessor symbols are always non-throwing.
                // Preserve historical classification via SyntheticSymbolScheme.
                let isSyntheticAccessor: Bool = {
                    guard let s = callSymbol else { return false }
                    return SyntheticSymbolScheme.isLikelySyntheticPropertyAccessor(s)
                }()
                let canThrow = !isSyntheticAccessor && !nonThrowingCallees.contains(callee)

                var signature: FunctionSignature?
                if let symbols, let callSymbol {
                    signature = symbols.functionSignature(for: callSymbol)
                }
                if signature == nil {
                    signature = signatureByName[callee]
                }
                let boxedArguments: [KIRExprID]
                if let signature, let types {
                    let receiverOffset = signature.receiverType != nil ? 1 : 0
                    boxedArguments = applyArgumentBoxing(
                        arguments: arguments,
                        signature: signature,
                        receiverOffset: receiverOffset,
                        module: module,
                        types: types,
                        symbols: symbols,
                        boxCallees: boxCallees,
                        newBody: &newBody
                    )
                } else {
                    boxedArguments = arguments
                }

                let resolvedUnbox = resolveUnboxForCall(
                    callSymbol: callSymbol,
                    callee: callee,
                    result: result,
                    signatureByName: signatureByName,
                    module: module,
                    types: types,
                    symbols: symbols,
                    unboxCallees: unboxCallees
                )

                if let (resolvedUnboxCallee, resolvedReturnType) = resolvedUnbox, let result {
                    let tempResult = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: resolvedReturnType
                    )
                    newBody.append(.call(
                        symbol: callSymbol,
                        callee: callee,
                        arguments: boxedArguments,
                        result: tempResult,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                    if thrownResult != nil {
                        let nextIdx = idx + 1
                        if nextIdx < function.body.count,
                           case .jumpIfNotNull = function.body[nextIdx]
                        {
                            newBody.append(function.body[nextIdx])
                            idx += 1
                        }
                    }
                    newBody.append(.call(
                        symbol: nil,
                        callee: resolvedUnboxCallee,
                        arguments: [tempResult],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    newBody.append(.call(
                        symbol: callSymbol,
                        callee: callee,
                        arguments: boxedArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                }
                idx += 1
            }

            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func rewriteReturnValueBoxing(
        value: KIRExprID,
        functionReturnKind: TypeKind?,
        returnType: TypeID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        boxCallees: BoxingCalleeNames
    ) -> [KIRInstruction]? {
        guard let functionReturnKind,
              isAnyOrNullableAny(functionReturnKind) || isNonValueClassReference(functionReturnKind, symbols: symbols),
              let valueType = intrinsicArgType(value, arena: module.arena, types: types)
        else {
            return nil
        }
        let resolvedValueKind = resolveValueClassKind(
            types.kind(of: valueType), types: types, symbols: symbols
        )
        guard let boxCallee = boxCalleeForPrimitive(
            resolvedValueKind,
            boxCallees: boxCallees
        ) else {
            return nil
        }
        let boxedResult = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: returnType
        )
        return [
            .call(symbol: nil, callee: boxCallee, arguments: [value],
                  result: boxedResult, canThrow: false, thrownResult: nil),
            .returnValue(boxedResult),
        ]
    }

    private func rewriteCopyBoxingOrUnboxing(
        from: KIRExprID, to: KIRExprID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        boxCallees: BoxingCalleeNames,
        unboxCallees: UnboxingCalleeNames
    ) -> KIRInstruction? {
        guard let fromType = intrinsicArgType(from, arena: module.arena, types: types),
              let toType = module.arena.exprType(to)
        else {
            return nil
        }
        let rawFromKind = types.kind(of: fromType)
        let fromKind = resolveValueClassKind(rawFromKind, types: types, symbols: symbols)
        let rawToKind = types.kind(of: toType)
        let toKind = resolveValueClassKind(rawToKind, types: types, symbols: symbols)
        if isAnyOrNullableAny(toKind) || needsBoxingForCopy(sourceKind: fromKind, targetKind: toKind)
            || isNonValueClassReference(rawToKind, symbols: symbols),
            let boxCallee = boxCalleeForPrimitive(
                fromKind,
                boxCallees: boxCallees
            )
        {
            return .call(symbol: nil, callee: boxCallee, arguments: [from],
                         result: to, canThrow: false, thrownResult: nil)
        }
        if needsUnboxing(sourceKind: fromKind, targetKind: toKind, symbols: symbols),
           let unboxCallee = unboxingCallee(
               sourceKind: fromKind, targetKind: toKind,
               unboxCallees: unboxCallees,
               types: types, symbols: symbols
           )
        {
            return .call(symbol: nil, callee: unboxCallee, arguments: [from],
                         result: to, canThrow: false, thrownResult: nil)
        }
        return nil
    }
}
