import Foundation

final class ABILoweringPass: LoweringPass {
    static let name = "ABILowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let nonThrowingCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_add"),
            ctx.interner.intern("kk_op_sub"),
            ctx.interner.intern("kk_op_mul"),
            ctx.interner.intern("kk_op_div"),
            ctx.interner.intern("kk_op_eq"),
            ctx.interner.intern("kk_string_concat"),
            ctx.interner.intern("kk_when_select"),
            ctx.interner.intern("kk_for_lowered"),
            ctx.interner.intern("iterator"),
            ctx.interner.intern("hasNext"),
            ctx.interner.intern("next"),
            ctx.interner.intern("kk_property_access"),
            ctx.interner.intern("kk_lambda_invoke"),
            ctx.interner.intern("kk_println_any"),
            ctx.interner.intern("kk_coroutine_suspended"),
            ctx.interner.intern("kk_coroutine_continuation_new"),
            ctx.interner.intern("kk_coroutine_state_enter"),
            ctx.interner.intern("kk_coroutine_state_set_label"),
            ctx.interner.intern("kk_coroutine_state_exit"),
            ctx.interner.intern("kk_coroutine_state_set_spill"),
            ctx.interner.intern("kk_coroutine_state_get_spill"),
            ctx.interner.intern("kk_coroutine_state_set_completion"),
            ctx.interner.intern("kk_coroutine_state_get_completion"),
            ctx.interner.intern("kk_kxmini_run_blocking"),
            ctx.interner.intern("kk_kxmini_launch"),
            ctx.interner.intern("kk_kxmini_async"),
            ctx.interner.intern("kk_kxmini_async_await"),
            ctx.interner.intern("kk_kxmini_delay"),
            ctx.interner.intern("kk_array_new"),
            ctx.interner.intern("kk_box_int"),
            ctx.interner.intern("kk_box_bool"),
            ctx.interner.intern("kk_box_long"),
            ctx.interner.intern("kk_box_float"),
            ctx.interner.intern("kk_box_double"),
            ctx.interner.intern("kk_box_char"),
            ctx.interner.intern("kk_unbox_int"),
            ctx.interner.intern("kk_unbox_bool"),
            ctx.interner.intern("kk_unbox_long"),
            ctx.interner.intern("kk_unbox_float"),
            ctx.interner.intern("kk_unbox_double"),
            ctx.interner.intern("kk_unbox_char"),
            ctx.interner.intern("kk_println_float"),
            ctx.interner.intern("kk_println_double"),
            ctx.interner.intern("kk_println_char")
        ]

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
                guard case .function(let fn) = decl else { continue }
                if let sig = symbols.functionSignature(for: fn.symbol) {
                    signatureByName[fn.name] = sig
                }
            }
        }

        module.arena.transformFunctions { function in
            var updated = function
            var newBody: [KIRInstruction] = []
            newBody.reserveCapacity(function.body.count)

            var idx = 0
            while idx < function.body.count {
                let instruction = function.body[idx]
                guard case .call(let callSymbol, let callee, let arguments, let result, _, let thrownResult) = instruction else {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                let canThrow = !nonThrowingCallees.contains(callee)

                var boxedArguments = arguments
                if let types {
                    var signature: FunctionSignature?
                    if let symbols, let callSymbol {
                        signature = symbols.functionSignature(for: callSymbol)
                    }
                    if signature == nil {
                        signature = signatureByName[callee]
                    }
                    if let signature {
                        let parameterTypes = signature.parameterTypes
                        let receiverOffset = signature.receiverType != nil ? 1 : 0
                        for argIndex in arguments.indices {
                            let paramIndex = argIndex - receiverOffset
                            guard paramIndex >= 0 && paramIndex < parameterTypes.count else {
                                continue
                            }
                            let paramType = parameterTypes[paramIndex]
                            let argType = intrinsicArgType(arguments[argIndex], arena: module.arena, types: types)
                            guard let argType else {
                                continue
                            }
                            if let boxCallee = boxingCallee(
                                argType: argType,
                                paramType: paramType,
                                types: types,
                                boxIntCallee: boxIntCallee,
                                boxBoolCallee: boxBoolCallee,
                                boxLongCallee: boxLongCallee,
                                boxFloatCallee: boxFloatCallee,
                                boxDoubleCallee: boxDoubleCallee,
                                boxCharCallee: boxCharCallee
                            ) {
                                let boxedResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)),
                                    type: paramType
                                )
                                newBody.append(.call(
                                    symbol: nil,
                                    callee: boxCallee,
                                    arguments: [arguments[argIndex]],
                                    result: boxedResult,
                                    canThrow: false,
                                    thrownResult: nil
                                ))
                                boxedArguments[argIndex] = boxedResult
                            }
                        }
                    }
                }

                var resolvedUnboxCallee: InternedString?
                var resolvedReturnType: TypeID?
                if let types, let result {
                    var returnType: TypeID?
                    if let callSymbol {
                        returnType = returnTypeForCall(
                            callSymbol: callSymbol,
                            symbols: symbols
                        )
                    }
                    if returnType == nil {
                        returnType = signatureByName[callee]?.returnType
                    }
                    if let returnType {
                        let returnKind = types.kind(of: returnType)
                        if isAnyOrNullableAny(returnKind) {
                            let resultType = module.arena.exprType(result)
                            if let resultType {
                                let resultKind = types.kind(of: resultType)
                                resolvedUnboxCallee = unboxingCallee(
                                    sourceKind: returnKind,
                                    targetKind: resultKind,
                                    unboxIntCallee: unboxIntCallee,
                                    unboxBoolCallee: unboxBoolCallee,
                                    unboxLongCallee: unboxLongCallee,
                                    unboxFloatCallee: unboxFloatCallee,
                                    unboxDoubleCallee: unboxDoubleCallee,
                                    unboxCharCallee: unboxCharCallee
                                )
                                resolvedReturnType = returnType
                            }
                        }
                    }
                }

                if let resolvedUnboxCallee, let resolvedReturnType, let result {
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
                        thrownResult: thrownResult
                    ))
                    if thrownResult != nil {
                        let nextIdx = idx + 1
                        if nextIdx < function.body.count,
                           case .jumpIfNotNull = function.body[nextIdx] {
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
                        thrownResult: thrownResult
                    ))
                }
                idx += 1
            }

            updated.body = newBody
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func boxingCallee(
        argType: TypeID,
        paramType: TypeID,
        types: TypeSystem,
        boxIntCallee: InternedString,
        boxBoolCallee: InternedString,
        boxLongCallee: InternedString,
        boxFloatCallee: InternedString,
        boxDoubleCallee: InternedString,
        boxCharCallee: InternedString
    ) -> InternedString? {
        let argKind = types.kind(of: argType)
        let paramKind = types.kind(of: paramType)

        guard isAnyOrNullableAny(paramKind) else {
            if case .primitive(let paramPrimitive, .nullable) = paramKind,
               case .primitive(let argPrimitive, .nonNull) = argKind,
               paramPrimitive == argPrimitive {
                switch argPrimitive {
                case .int:
                    return boxIntCallee
                case .long:
                    return boxLongCallee
                case .boolean:
                    return boxBoolCallee
                case .float:
                    return boxFloatCallee
                case .double:
                    return boxDoubleCallee
                case .char:
                    return boxCharCallee
                default:
                    return nil
                }
            }
            return nil
        }

        switch argKind {
        case .primitive(.int, _):
            return boxIntCallee
        case .primitive(.long, _):
            return boxLongCallee
        case .primitive(.boolean, _):
            return boxBoolCallee
        case .primitive(.float, _):
            return boxFloatCallee
        case .primitive(.double, _):
            return boxDoubleCallee
        case .primitive(.char, _):
            return boxCharCallee
        default:
            return nil
        }
    }

    private func unboxingCallee(
        sourceKind: TypeKind,
        targetKind: TypeKind,
        unboxIntCallee: InternedString,
        unboxBoolCallee: InternedString,
        unboxLongCallee: InternedString,
        unboxFloatCallee: InternedString,
        unboxDoubleCallee: InternedString,
        unboxCharCallee: InternedString
    ) -> InternedString? {
        guard isAnyOrNullableAny(sourceKind) else {
            return nil
        }

        switch targetKind {
        case .primitive(.int, _):
            return unboxIntCallee
        case .primitive(.long, _):
            return unboxLongCallee
        case .primitive(.boolean, _):
            return unboxBoolCallee
        case .primitive(.float, _):
            return unboxFloatCallee
        case .primitive(.double, _):
            return unboxDoubleCallee
        case .primitive(.char, _):
            return unboxCharCallee
        default:
            return nil
        }
    }

    private func intrinsicArgType(
        _ argExprID: KIRExprID,
        arena: KIRArena,
        types: TypeSystem
    ) -> TypeID? {
        if let kind = arena.expr(argExprID) {
            switch kind {
            case .intLiteral:
                return types.make(.primitive(.int, .nonNull))
            case .longLiteral:
                return types.make(.primitive(.long, .nonNull))
            case .floatLiteral:
                return types.make(.primitive(.float, .nonNull))
            case .doubleLiteral:
                return types.make(.primitive(.double, .nonNull))
            case .charLiteral:
                return types.make(.primitive(.char, .nonNull))
            case .boolLiteral:
                return types.make(.primitive(.boolean, .nonNull))
            case .stringLiteral:
                return types.make(.primitive(.string, .nonNull))
            default:
                break
            }
        }
        return arena.exprType(argExprID)
    }

    private func isAnyOrNullableAny(_ kind: TypeKind) -> Bool {
        if case .any = kind {
            return true
        }
        return false
    }

    private func returnTypeForCall(
        callSymbol: SymbolID?,
        symbols: SymbolTable?
    ) -> TypeID? {
        guard let callSymbol, let symbols else {
            return nil
        }
        return symbols.functionSignature(for: callSymbol)?.returnType
    }
}
