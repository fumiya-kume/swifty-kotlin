import Foundation

/// Rewrites Flow builtins (`flow/emit/map/filter/take/collect`) into
/// runtime ABI calls (`kk_flow_create/kk_flow_emit/kk_flow_collect`).
final class FlowLoweringPass: LoweringPass {
    static let name = "FlowLowering"

    /// Runtime ABI tag contract shared by C/Swift flow runtime (see `RuntimeFlowOp`).
    private enum RuntimeFlowTag: Int64 {
        case emit = 0
        case map = 1
        case filter = 2
        case take = 3
    }

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        let calleeNames: Set<InternedString> = [
            ctx.interner.intern("flow"),
            ctx.interner.intern("emit"),
            ctx.interner.intern("map"),
            ctx.interner.intern("filter"),
            ctx.interner.intern("take"),
            ctx.interner.intern("collect"),
        ]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, _, _, _, _, _):
                    if calleeNames.contains(callee) {
                        return true
                    }
                case let .virtualCall(_, callee, _, _, _, _, _, _):
                    if calleeNames.contains(callee) {
                        return true
                    }
                default:
                    continue
                }
            }
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        let interner = ctx.interner
        let flowName = interner.intern("flow")
        let emitName = interner.intern("emit")
        let mapName = interner.intern("map")
        let filterName = interner.intern("filter")
        let takeName = interner.intern("take")
        let collectName = interner.intern("collect")

        let kkFlowCreateName = interner.intern("kk_flow_create")
        let kkFlowEmitName = interner.intern("kk_flow_emit")
        let kkFlowCollectName = interner.intern("kk_flow_collect")

        let intType = ctx.sema?.types.intType

        var functionNameBySymbol: [SymbolID: InternedString] = [:]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            functionNameBySymbol[function.symbol] = function.name
        }

        var flowBuilderFunctionNames: Set<InternedString> = []
        var flowBuilderFunctionSymbols: Set<SymbolID> = []
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            var symbolByExprRaw: [Int32: SymbolID] = [:]
            for instruction in function.body {
                if case let .constValue(result, .symbolRef(symbol)) = instruction {
                    symbolByExprRaw[result.rawValue] = symbol
                }
            }
            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, arguments, _, _, _, _):
                    guard callee == flowName, arguments.count == 1 else {
                        continue
                    }
                    let lambdaArg = arguments[0]
                    if let symbol = symbolByExprRaw[lambdaArg.rawValue] {
                        flowBuilderFunctionSymbols.insert(symbol)
                        if let lambdaName = functionNameBySymbol[symbol] {
                            flowBuilderFunctionNames.insert(lambdaName)
                        }
                    }
                    // Keep convention-based fallback for synthetic lambda names.
                    let fallbackLambdaName = interner.intern("kk_lambda_\(lambdaArg.rawValue)")
                    flowBuilderFunctionNames.insert(fallbackLambdaName)
                case let .virtualCall(_, callee, _, arguments, _, _, _, _):
                    guard callee == flowName, arguments.count == 1 else {
                        continue
                    }
                    let lambdaArg = arguments[0]
                    if let symbol = symbolByExprRaw[lambdaArg.rawValue] {
                        flowBuilderFunctionSymbols.insert(symbol)
                        if let lambdaName = functionNameBySymbol[symbol] {
                            flowBuilderFunctionNames.insert(lambdaName)
                        }
                    }
                    // Keep convention-based fallback for synthetic lambda names.
                    let fallbackLambdaName = interner.intern("kk_lambda_\(lambdaArg.rawValue)")
                    flowBuilderFunctionNames.insert(fallbackLambdaName)
                default:
                    continue
                }
            }
        }

        module.arena.transformFunctions { function in
            var updated = function
            let isFlowBuilderFunction =
                flowBuilderFunctionSymbols.contains(function.symbol)
                || flowBuilderFunctionNames.contains(function.name)

            var flowExprIDs: Set<Int32> = []
            var activeFlowExpr: KIRExprID? = nil
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count + 16)

            func appendIntConstant(_ value: Int64) -> KIRExprID {
                let expr = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: intType
                )
                loweredBody.append(.constValue(result: expr, value: .intLiteral(value)))
                return expr
            }

            for instruction in function.body {
                switch instruction {
                case let .copy(from, to):
                    if flowExprIDs.contains(from.rawValue) {
                        flowExprIDs.insert(to.rawValue)
                        activeFlowExpr = to
                    }
                    loweredBody.append(instruction)

                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall):
                    if callee == collectName,
                       arguments.count == 1,
                       let flowExpr = activeFlowExpr,
                       flowExprIDs.contains(flowExpr.rawValue)
                    {
                        // Placeholder: CoroutineLoweringPass rewrites collectorFunctionID
                        // to the actual suspend-lowered function ID for non-suspend
                        // collector references.
                        let collectorFunctionID = appendIntConstant(0)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCollectName,
                            arguments: [flowExpr, arguments[0], collectorFunctionID],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }

                    if callee == flowName, arguments.count == 1 {
                        let continuation = appendIntConstant(0)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCreateName,
                            arguments: [arguments[0], continuation],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result {
                            flowExprIDs.insert(result.rawValue)
                            activeFlowExpr = result
                        }
                    continue
                }

                    if callee == emitName, isFlowBuilderFunction {
                        let flowHandleExpr: KIRExprID
                        let valueExpr: KIRExprID
                        if arguments.count >= 2 {
                            flowHandleExpr = arguments[0]
                            valueExpr = arguments[1]
                        } else if arguments.count == 1 {
                            // Flow builder `emit(x)` has no explicit receiver.
                            // Runtime resolves handle from active collection context.
                            flowHandleExpr = appendIntConstant(0)
                            valueExpr = arguments[0]
                        } else {
                            loweredBody.append(instruction)
                            continue
                        }
                        let tag = appendIntConstant(RuntimeFlowTag.emit.rawValue)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [flowHandleExpr, valueExpr, tag],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result {
                            activeFlowExpr = result
                        }
                        continue
                    }

                    if (callee == mapName || callee == filterName || callee == takeName),
                       arguments.count == 2,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        let tagValue: Int64 = switch callee {
                        case mapName:
                            RuntimeFlowTag.map.rawValue
                        case filterName:
                            RuntimeFlowTag.filter.rawValue
                        default:
                            RuntimeFlowTag.take.rawValue
                        }
                        let tag = appendIntConstant(tagValue)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [arguments[0], arguments[1], tag],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result {
                            flowExprIDs.insert(result.rawValue)
                            activeFlowExpr = result
                        }
                        continue
                    }

                    if callee == collectName,
                       arguments.count == 2,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        // Placeholder: CoroutineLoweringPass rewrites collectorFunctionID
                        // to the actual suspend-lowered function ID for non-suspend
                        // collector references.
                        let collectorFunctionID = appendIntConstant(0)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCollectName,
                            arguments: [arguments[0], arguments[1], collectorFunctionID],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result {
                            activeFlowExpr = result
                        }
                        continue
                    }

                    if callee == kkFlowCreateName,
                       let result
                    {
                        flowExprIDs.insert(result.rawValue)
                        activeFlowExpr = result
                    } else if callee == kkFlowEmitName,
                              arguments.count == 3,
                              let result,
                              let tagExpr = module.arena.expr(arguments[2]),
                              case let .intLiteral(tag) = tagExpr
                    {
                        if tag == RuntimeFlowTag.map.rawValue
                            || tag == RuntimeFlowTag.filter.rawValue
                            || tag == RuntimeFlowTag.take.rawValue
                        {
                            flowExprIDs.insert(result.rawValue)
                            activeFlowExpr = result
                        }
                    }

                    loweredBody.append(.call(
                        symbol: symbol,
                        callee: callee,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))

                case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
                    if callee == emitName, isFlowBuilderFunction {
                        let flowHandleExpr: KIRExprID
                        let valueExpr: KIRExprID
                        if arguments.count == 1 {
                            // Flow builder `emit(x)` has no explicit receiver.
                            // Runtime resolves handle from active collection context.
                            flowHandleExpr = appendIntConstant(0)
                            valueExpr = arguments[0]
                        } else {
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
                            continue
                        }
                        let tag = appendIntConstant(RuntimeFlowTag.emit.rawValue)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [flowHandleExpr, valueExpr, tag],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result {
                            activeFlowExpr = result
                        }
                        continue
                    }

                    if (callee == mapName || callee == filterName || callee == takeName),
                       arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        let tagValue: Int64 = switch callee {
                        case mapName:
                            RuntimeFlowTag.map.rawValue
                        case filterName:
                            RuntimeFlowTag.filter.rawValue
                        default:
                            RuntimeFlowTag.take.rawValue
                        }
                        let tag = appendIntConstant(tagValue)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: [receiver, arguments[0], tag],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result {
                            flowExprIDs.insert(result.rawValue)
                            activeFlowExpr = result
                        }
                        continue
                    }

                    if callee == collectName,
                       arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        // Placeholder: CoroutineLoweringPass rewrites collectorFunctionID
                        // to the actual suspend-lowered function ID for non-suspend
                        // collector references.
                        let collectorFunctionID = appendIntConstant(0)
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCollectName,
                            arguments: [receiver, arguments[0], collectorFunctionID],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        activeFlowExpr = receiver
                        continue
                    }

                    if callee == kkFlowCreateName,
                       let result
                    {
                        flowExprIDs.insert(result.rawValue)
                        activeFlowExpr = result
                    } else if callee == kkFlowEmitName,
                              arguments.count == 3,
                              let result,
                              let tagExpr = module.arena.expr(arguments[2]),
                              case let .intLiteral(tag) = tagExpr
                    {
                        if tag == RuntimeFlowTag.map.rawValue
                            || tag == RuntimeFlowTag.filter.rawValue
                            || tag == RuntimeFlowTag.take.rawValue
                        {
                            flowExprIDs.insert(result.rawValue)
                            activeFlowExpr = result
                        }
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

        module.recordLowering(Self.name)
    }
}
