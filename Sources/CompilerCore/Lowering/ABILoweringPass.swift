// swiftlint:disable file_length
import Foundation

// swiftlint:disable:next type_body_length
final class ABILoweringPass: LoweringPass {
    static let name = "ABILowering"

    // swiftlint:disable:next function_body_length
    func run(module: KIRModule, ctx: KIRContext) throws {
        let nonThrowingCallees = nonThrowingCallees(interner: ctx.interner)

        let boxIntCallee = ctx.interner.intern("kk_box_int")
        let boxBoolCallee = ctx.interner.intern("kk_box_bool")
        let boxLongCallee = ctx.interner.intern("kk_box_long")
        let boxFloatCallee = ctx.interner.intern("kk_box_float")
        let boxDoubleCallee = ctx.interner.intern("kk_box_double")
        let boxCharCallee = ctx.interner.intern("kk_box_char")
        let unboxIntCallee = ctx.interner.intern("kk_unbox_int")
        let unboxBoolCallee = ctx.interner.intern("kk_unbox_bool")
        let unboxLongCallee = ctx.interner.intern("kk_unbox_long")
        let unboxFloatCallee = ctx.interner.intern("kk_unbox_float")
        let unboxDoubleCallee = ctx.interner.intern("kk_unbox_double")
        let unboxCharCallee = ctx.interner.intern("kk_unbox_char")

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
                            boxIntCallee: boxIntCallee,
                            boxBoolCallee: boxBoolCallee,
                            boxLongCallee: boxLongCallee,
                            boxFloatCallee: boxFloatCallee,
                            boxDoubleCallee: boxDoubleCallee,
                            boxCharCallee: boxCharCallee,
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
                        unboxIntCallee: unboxIntCallee,
                        unboxBoolCallee: unboxBoolCallee,
                        unboxLongCallee: unboxLongCallee,
                        unboxFloatCallee: unboxFloatCallee,
                        unboxDoubleCallee: unboxDoubleCallee,
                        unboxCharCallee: unboxCharCallee
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
                if case let .returnValue(value) = instruction, let types {
                    if let functionReturnKind, isAnyOrNullableAny(functionReturnKind) || isNonValueClassReference(functionReturnKind, symbols: symbols) {
                        let valueType = intrinsicArgType(value, arena: module.arena, types: types)
                        if let valueType {
                            let resolvedValueKind = resolveValueClassKind(
                                types.kind(of: valueType), types: types, symbols: symbols
                            )
                            if let boxCallee = boxCalleeForPrimitive(
                                resolvedValueKind,
                                boxIntCallee: boxIntCallee,
                                boxBoolCallee: boxBoolCallee,
                                boxLongCallee: boxLongCallee,
                                boxFloatCallee: boxFloatCallee,
                                boxDoubleCallee: boxDoubleCallee,
                                boxCharCallee: boxCharCallee
                            ) {
                                let boxedResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)),
                                    type: function.returnType
                                )
                                newBody.append(.call(
                                    symbol: nil,
                                    callee: boxCallee,
                                    arguments: [value],
                                    result: boxedResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                newBody.append(.returnValue(boxedResult))
                                idx += 1
                                continue
                            }
                        }
                    }
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                // Handle copy: insert boxing/unboxing at type boundaries
                if case let .copy(from, to) = instruction, let types {
                    let fromType = intrinsicArgType(from, arena: module.arena, types: types)
                    let toType = module.arena.exprType(to)
                    if let fromType, let toType {
                        let rawFromKind = types.kind(of: fromType)
                        let fromKind = resolveValueClassKind(rawFromKind, types: types, symbols: symbols)
                        let rawToKind = types.kind(of: toType)
                        let toKind = resolveValueClassKind(rawToKind, types: types, symbols: symbols)
                        // Box: primitive → Any/Any?, nonNull primitive → nullable primitive, or primitive → non-value-class reference
                        if isAnyOrNullableAny(toKind) || needsBoxingForCopy(sourceKind: fromKind, targetKind: toKind) || isNonValueClassReference(rawToKind, symbols: symbols) {
                            if let boxCallee = boxCalleeForPrimitive(
                                fromKind,
                                boxIntCallee: boxIntCallee,
                                boxBoolCallee: boxBoolCallee,
                                boxLongCallee: boxLongCallee,
                                boxFloatCallee: boxFloatCallee,
                                boxDoubleCallee: boxDoubleCallee,
                                boxCharCallee: boxCharCallee
                            ) {
                                newBody.append(.call(
                                    symbol: nil,
                                    callee: boxCallee,
                                    arguments: [from],
                                    result: to,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                idx += 1
                                continue
                            }
                        }
                        // Unbox: Any/Any?, non-value-class reference, or nullable primitive → nonNull primitive
                        if needsUnboxing(sourceKind: fromKind, targetKind: toKind, symbols: symbols) {
                            if let unboxCallee = unboxingCallee(
                                sourceKind: fromKind,
                                targetKind: toKind,
                                unboxIntCallee: unboxIntCallee,
                                unboxBoolCallee: unboxBoolCallee,
                                unboxLongCallee: unboxLongCallee,
                                unboxFloatCallee: unboxFloatCallee,
                                unboxDoubleCallee: unboxDoubleCallee,
                                unboxCharCallee: unboxCharCallee,
                                types: types,
                                symbols: symbols
                            ) {
                                newBody.append(.call(
                                    symbol: nil,
                                    callee: unboxCallee,
                                    arguments: [from],
                                    result: to,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                idx += 1
                                continue
                            }
                        }
                    }
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
                        boxIntCallee: boxIntCallee,
                        boxBoolCallee: boxBoolCallee,
                        boxLongCallee: boxLongCallee,
                        boxFloatCallee: boxFloatCallee,
                        boxDoubleCallee: boxDoubleCallee,
                        boxCharCallee: boxCharCallee,
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
                    unboxIntCallee: unboxIntCallee,
                    unboxBoolCallee: unboxBoolCallee,
                    unboxLongCallee: unboxLongCallee,
                    unboxFloatCallee: unboxFloatCallee,
                    unboxDoubleCallee: unboxDoubleCallee,
                    unboxCharCallee: unboxCharCallee
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

            updated.body = newBody
            return updated
        }
        module.recordLowering(Self.name)
    }
}
