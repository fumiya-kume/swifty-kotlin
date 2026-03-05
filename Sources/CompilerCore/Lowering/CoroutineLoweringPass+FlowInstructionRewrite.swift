import Foundation

extension CoroutineLoweringPass {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func rewriteFlowInstructions(
        originalBody: [KIRInstruction],
        module: KIRModule,
        ctx: KIRContext,
        flowExprIDs: inout Set<Int32>,
        remainingConsumes: inout [Int32: Int],
        symbolByExprRaw: [Int32: SymbolID],
        names: FlowLoweringNames
    ) -> [KIRInstruction] {
        var loweredBody: [KIRInstruction] = []
        loweredBody.reserveCapacity(originalBody.count)

        func appendIntConstantInBody(_ value: Int64) -> KIRExprID {
            let expr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: ctx.sema?.types.intType ?? TypeID.invalid
            )
            loweredBody.append(.constValue(result: expr, value: .intLiteral(value)))
            return expr
        }

        func appendFlowReleaseCall(_ handleExpr: KIRExprID) {
            loweredBody.append(.call(
                symbol: nil,
                callee: names.kkFlowRelease,
                arguments: [handleExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        func isFlowTransformEmitCall(_ callee: InternedString, _ arguments: [KIRExprID]) -> Bool {
            guard callee == names.kkFlowEmit, arguments.count == 3 else {
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

        func isSymbolBackedFlowExpr(_ exprID: KIRExprID) -> Bool {
            if let expr = module.arena.expr(exprID), case .symbolRef = expr {
                return true
            }
            return symbolByExprRaw[exprID.rawValue] != nil
        }

        func prepareFlowHandleForConsume(
            _ sourceHandle: KIRExprID
        ) -> (callArg: KIRExprID, releaseAfterCall: KIRExprID?) {
            if isSymbolBackedFlowExpr(sourceHandle) {
                let retained = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: ctx.sema?.types.anyType ?? TypeID.invalid
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: names.kkFlowRetain,
                    arguments: [sourceHandle],
                    result: retained,
                    canThrow: false,
                    thrownResult: nil
                ))
                return (retained, retained)
            }

            if let count = remainingConsumes[sourceHandle.rawValue], count > 0 {
                let nextCount = count - 1
                remainingConsumes[sourceHandle.rawValue] = nextCount
                return (sourceHandle, nextCount == 0 ? sourceHandle : nil)
            }
            return (sourceHandle, nil)
        }

        for instruction in originalBody {
            switch instruction {
            case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall):
                if callee == names.flow, arguments.count == 1, symbol == nil {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowCreate,
                        arguments: [arguments[0], appendIntConstantInBody(0)],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        isSuperCall: isSuperCall
                    ))
                    continue
                }

                if callee == names.emit, arguments.count == 1, symbol == nil {
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowEmit,
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

                if callee == names.map, arguments.count == 2, symbol == nil,
                   flowExprIDs.contains(arguments[0].rawValue)
                {
                    let consume = prepareFlowHandleForConsume(arguments[0])
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowEmit,
                        arguments: [consume.callArg, arguments[1], appendIntConstantInBody(RuntimeFlowTag.map.rawValue)],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        isSuperCall: isSuperCall
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    if let result {
                        flowExprIDs.insert(result.rawValue)
                    }
                    continue
                }

                if callee == names.filter, arguments.count == 2, symbol == nil,
                   flowExprIDs.contains(arguments[0].rawValue)
                {
                    let consume = prepareFlowHandleForConsume(arguments[0])
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowEmit,
                        arguments: [consume.callArg, arguments[1], appendIntConstantInBody(RuntimeFlowTag.filter.rawValue)],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        isSuperCall: isSuperCall
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    if let result {
                        flowExprIDs.insert(result.rawValue)
                    }
                    continue
                }

                if callee == names.take, arguments.count == 2, symbol == nil,
                   flowExprIDs.contains(arguments[0].rawValue)
                {
                    let consume = prepareFlowHandleForConsume(arguments[0])
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowEmit,
                        arguments: [consume.callArg, arguments[1], appendIntConstantInBody(RuntimeFlowTag.take.rawValue)],
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        isSuperCall: isSuperCall
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    if let result {
                        flowExprIDs.insert(result.rawValue)
                    }
                    continue
                }

                if callee == names.collect, arguments.count == 2, symbol == nil,
                   flowExprIDs.contains(arguments[0].rawValue)
                {
                    let consume = prepareFlowHandleForConsume(arguments[0])
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowCollect,
                        arguments: [consume.callArg, arguments[1], appendIntConstantInBody(0)],
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    continue
                }

                if callee == names.collect, arguments.count == 3, symbol == nil,
                   flowExprIDs.contains(arguments[0].rawValue)
                {
                    let consume = prepareFlowHandleForConsume(arguments[0])
                    var rewrittenArguments = arguments
                    rewrittenArguments[0] = consume.callArg
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowCollect,
                        arguments: rewrittenArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    continue
                }

                if callee == names.kkFlowCollect,
                   arguments.count == 2,
                   flowExprIDs.contains(arguments[0].rawValue)
                {
                    let consume = prepareFlowHandleForConsume(arguments[0])
                    loweredBody.append(.call(
                        symbol: symbol,
                        callee: callee,
                        arguments: [consume.callArg, arguments[1], appendIntConstantInBody(0)],
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    continue
                }

                if callee == names.kkFlowCollect,
                   arguments.count == 3,
                   flowExprIDs.contains(arguments[0].rawValue)
                {
                    let consume = prepareFlowHandleForConsume(arguments[0])
                    var rewrittenArguments = arguments
                    rewrittenArguments[0] = consume.callArg
                    loweredBody.append(.call(
                        symbol: symbol,
                        callee: callee,
                        arguments: rewrittenArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    continue
                }

                loweredBody.append(instruction)

            case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
                if callee == names.map, arguments.count == 1,
                   flowExprIDs.contains(receiver.rawValue)
                {
                    let consume = prepareFlowHandleForConsume(receiver)
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowEmit,
                        arguments: [consume.callArg, arguments[0], appendIntConstantInBody(RuntimeFlowTag.map.rawValue)],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    if let result {
                        flowExprIDs.insert(result.rawValue)
                    }
                    continue
                }

                if callee == names.filter, arguments.count == 1,
                   flowExprIDs.contains(receiver.rawValue)
                {
                    let consume = prepareFlowHandleForConsume(receiver)
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowEmit,
                        arguments: [consume.callArg, arguments[0], appendIntConstantInBody(RuntimeFlowTag.filter.rawValue)],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    if let result {
                        flowExprIDs.insert(result.rawValue)
                    }
                    continue
                }

                if callee == names.take, arguments.count == 1,
                   flowExprIDs.contains(receiver.rawValue)
                {
                    let consume = prepareFlowHandleForConsume(receiver)
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowEmit,
                        arguments: [consume.callArg, arguments[0], appendIntConstantInBody(RuntimeFlowTag.take.rawValue)],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
                    if let result {
                        flowExprIDs.insert(result.rawValue)
                    }
                    continue
                }

                if callee == names.collect, arguments.count == 1,
                   flowExprIDs.contains(receiver.rawValue)
                {
                    let consume = prepareFlowHandleForConsume(receiver)
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: names.kkFlowCollect,
                        arguments: [consume.callArg, arguments[0], appendIntConstantInBody(0)],
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    if let releaseHandle = consume.releaseAfterCall { appendFlowReleaseCall(releaseHandle) }
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

        return loweredBody
    }
}
