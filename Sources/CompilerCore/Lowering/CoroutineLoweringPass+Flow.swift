import Foundation

// MARK: - Flow Lowering (CORO-003)

extension CoroutineLoweringPass {
    // Lower `flow { }`, `emit`, `map`, `filter`, `take`, `collect` calls to their
    // runtime ABI equivalents. Mirrors the `sequenceExprIDs` pattern in
    // `CollectionLiteralLoweringPass`.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func lowerFlowExpressions(module: KIRModule, ctx: KIRContext) {
        let flowName = ctx.interner.intern("flow")
        let emitName = ctx.interner.intern("emit")
        let collectName = ctx.interner.intern("collect")
        let mapName = ctx.interner.intern("map")
        let filterName = ctx.interner.intern("filter")
        let takeName = ctx.interner.intern("take")

        let kkFlowCreateName = ctx.interner.intern("kk_flow_create")
        let kkFlowEmitName = ctx.interner.intern("kk_flow_emit")
        let kkFlowCollectName = ctx.interner.intern("kk_flow_collect")

        module.arena.transformFunctions { function in
            var updated = function

            var flowExprIDs: Set<Int32> = []
            var flowGlobalSymbols: Set<SymbolID> = []

            enum RuntimeFlowTag: Int64 {
                case emit = 0
                case map = 1
                case filter = 2
                case take = 3
            }

            func markFlowExpr(_ result: KIRExprID?) -> Bool {
                guard let result else { return false }
                return flowExprIDs.insert(result.rawValue).inserted
            }

            func isFlowTransformEmitCall(_ callee: InternedString, _ arguments: [KIRExprID]) -> Bool {
                guard callee == kkFlowEmitName, arguments.count == 3 else {
                    return false
                }
                guard let tagExpr = module.arena.expr(arguments[2]),
                      case let .intLiteral(tagValue) = tagExpr,
                      tagValue == RuntimeFlowTag.map.rawValue ||
                      tagValue == RuntimeFlowTag.filter.rawValue ||
                      tagValue == RuntimeFlowTag.take.rawValue
                else {
                    return false
                }
                return true
            }

            var changed = true
            while changed {
                changed = false

                for instruction in function.body {
                    switch instruction {
                    case let .call(symbol, callee, arguments, result, _, _, _):
                        if callee == flowName, arguments.count == 1, symbol == nil {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == kkFlowCreateName, arguments.count == 2 {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowTransformEmitCall(callee, arguments) {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == mapName || callee == filterName || callee == takeName,
                           arguments.count == 2,
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == collectName || callee == kkFlowCollectName,
                           arguments.count == 2 || arguments.count == 3,
                           let flowHandleArg = arguments.first,
                           flowExprIDs.insert(flowHandleArg.rawValue).inserted
                        {
                            continue
                        }
                        if callee == emitName,
                           arguments.count == 1,
                           symbol == nil
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }

                    case let .virtualCall(_, callee, receiver, arguments, result, _, _, _):
                        if callee == mapName || callee == filterName || callee == takeName,
                           arguments.count == 1,
                           flowExprIDs.contains(receiver.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == collectName,
                           arguments.count == 1,
                           flowExprIDs.contains(receiver.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }

                    case let .copy(from, to):
                        if flowExprIDs.contains(from.rawValue),
                           flowExprIDs.insert(to.rawValue).inserted
                        {
                            changed = true
                        }

                    case let .storeGlobal(value, symbol):
                        if flowExprIDs.contains(value.rawValue) {
                            if flowGlobalSymbols.insert(symbol).inserted {
                                changed = true
                            }
                        } else if flowGlobalSymbols.remove(symbol) != nil {
                            changed = true
                        }

                    case let .loadGlobal(result, symbol):
                        if flowGlobalSymbols.contains(symbol),
                           flowExprIDs.insert(result.rawValue).inserted
                        {
                            changed = true
                        }

                    default:
                        break
                    }
                }
            }

            let hasFlowLikeCalls = function.body.contains { instruction in
                switch instruction {
                case let .call(_, callee, _, _, _, _, _):
                    callee == flowName || callee == emitName || callee == collectName ||
                        callee == mapName || callee == filterName || callee == takeName ||
                        callee == kkFlowCreateName || callee == kkFlowEmitName || callee == kkFlowCollectName
                case let .virtualCall(_, callee, _, _, _, _, _, _):
                    callee == mapName || callee == filterName || callee == takeName || callee == collectName
                default:
                    false
                }
            }

            guard !flowExprIDs.isEmpty || hasFlowLikeCalls else {
                return updated
            }

            // Phase 2: rewrite flow instructions.
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            func appendIntConstantInBody(_ value: Int64) -> KIRExprID {
                let expr = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: ctx.sema?.types.intType ?? TypeID.invalid
                )
                loweredBody.append(.constValue(result: expr, value: .intLiteral(value)))
                return expr
            }

            for instruction in function.body {
                switch instruction {
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall):
                    if callee == flowName, arguments.count == 1, symbol == nil {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCreateName,
                            arguments: [arguments[0], appendIntConstantInBody(0)],
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        continue
                    }

                    if callee == emitName, arguments.count == 1, symbol == nil {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [
                                appendIntConstantInBody(0),
                                arguments[0],
                                appendIntConstantInBody(RuntimeFlowTag.emit.rawValue),
                            ],
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        continue
                    }

                    if callee == mapName, arguments.count == 2, symbol == nil,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [arguments[0], arguments[1], appendIntConstantInBody(RuntimeFlowTag.map.rawValue)],
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        if let result {
                            flowExprIDs.insert(result.rawValue)
                        }
                        continue
                    }

                    if callee == filterName, arguments.count == 2, symbol == nil,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [arguments[0], arguments[1], appendIntConstantInBody(RuntimeFlowTag.filter.rawValue)],
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        if let result {
                            flowExprIDs.insert(result.rawValue)
                        }
                        continue
                    }

                    if callee == takeName, arguments.count == 2, symbol == nil,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [arguments[0], arguments[1], appendIntConstantInBody(RuntimeFlowTag.take.rawValue)],
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        if let result {
                            flowExprIDs.insert(result.rawValue)
                        }
                        continue
                    }

                    if callee == collectName, arguments.count == 2, symbol == nil,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCollectName,
                            arguments: [arguments[0], arguments[1], appendIntConstantInBody(0)],
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall
                        ))
                        continue
                    }

                    if callee == collectName, arguments.count == 3, symbol == nil,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCollectName,
                            arguments: arguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall
                        ))
                        continue
                    }

                    if callee == kkFlowCollectName,
                       arguments.count == 2,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: symbol,
                            callee: callee,
                            arguments: [arguments[0], arguments[1], appendIntConstantInBody(0)],
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall
                        ))
                        continue
                    }

                    loweredBody.append(instruction)

                case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
                    if callee == mapName, arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [receiver, arguments[0], appendIntConstantInBody(RuntimeFlowTag.map.rawValue)],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result {
                            flowExprIDs.insert(result.rawValue)
                        }
                        continue
                    }

                    if callee == filterName, arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [receiver, arguments[0], appendIntConstantInBody(RuntimeFlowTag.filter.rawValue)],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result {
                            flowExprIDs.insert(result.rawValue)
                        }
                        continue
                    }

                    if callee == takeName, arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [receiver, arguments[0], appendIntConstantInBody(RuntimeFlowTag.take.rawValue)],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result {
                            flowExprIDs.insert(result.rawValue)
                        }
                        continue
                    }

                    if callee == collectName, arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCollectName,
                            arguments: [receiver, arguments[0], appendIntConstantInBody(0)],
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult
                        ))
                        continue
                    }

                    loweredBody.append(.virtualCall(
                        symbol: symbol,
                        callee: callee,
                        receiver: receiver,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        dispatch: dispatch
                    ))

                default:
                    loweredBody.append(instruction)
                }
            }

            updated.body = loweredBody
            return updated
        }
    }
}
