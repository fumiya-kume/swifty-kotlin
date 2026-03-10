import Foundation

enum RuntimeFlowTag: Int64 {
    case emit = 0
    case map = 1
    case filter = 2
    case take = 3
}

struct FlowLoweringNames {
    let flow: InternedString
    let emit: InternedString
    let collect: InternedString
    let map: InternedString
    let filter: InternedString
    let take: InternedString
    let kkFlowCreate: InternedString
    let kkFlowEmit: InternedString
    let kkFlowCollect: InternedString
    let kkFlowRetain: InternedString
    let kkFlowRelease: InternedString
}

extension CoroutineLoweringPass {
    /// Lower `flow { }`, `emit`, `map`, `filter`, `take`, `collect` calls to their
    /// runtime ABI equivalents. Mirrors the `sequenceExprIDs` pattern in
    /// `CollectionLiteralLoweringPass`.
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
        let kkFlowRetainName = ctx.interner.intern("kk_flow_retain")
        let kkFlowReleaseName = ctx.interner.intern("kk_flow_release")

        module.arena.transformFunctions { function in
            var updated = function

            var flowExprIDs: Set<Int32> = []
            var flowGlobalSymbols: Set<SymbolID> = []

            func markFlowExpr(_ result: KIRExprID?) -> Bool {
                guard let result else { return false }
                return flowExprIDs.insert(result.rawValue).inserted
            }

            var symbolByExprRaw: [Int32: SymbolID] = [:]
            var propagatedSymbols = true
            while propagatedSymbols {
                propagatedSymbols = false
                for instruction in function.body {
                    switch instruction {
                    case let .constValue(result, .symbolRef(symbol)):
                        if symbolByExprRaw[result.rawValue] != symbol {
                            symbolByExprRaw[result.rawValue] = symbol
                            propagatedSymbols = true
                        }
                    case let .copy(from, to):
                        if let symbol = symbolByExprRaw[from.rawValue],
                           symbolByExprRaw[to.rawValue] != symbol
                        {
                            symbolByExprRaw[to.rawValue] = symbol
                            propagatedSymbols = true
                        }
                    default:
                        continue
                    }
                }
            }

            func isSymbolBackedFlowExpr(_ exprID: KIRExprID) -> Bool {
                if let expr = module.arena.expr(exprID), case .symbolRef = expr {
                    return true
                }
                return symbolByExprRaw[exprID.rawValue] != nil
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
                           (arguments.count == 2 || ((callee == mapName || callee == filterName) && arguments.count == 3)),
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == collectName || callee == kkFlowCollectName,
                           arguments.count == 2 || arguments.count == 3,
                           let flowHandleArg = arguments.first
                        {
                            if flowExprIDs.insert(flowHandleArg.rawValue).inserted {
                                changed = true
                            }
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

            var remainingConsumes: [Int32: Int] = [:]
            func markConsume(_ source: KIRExprID) {
                guard flowExprIDs.contains(source.rawValue) else {
                    return
                }
                remainingConsumes[source.rawValue, default: 0] += 1
            }
            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, arguments, _, _, _, _):
                    if callee == mapName || callee == filterName || callee == takeName,
                       (arguments.count == 2 || ((callee == mapName || callee == filterName) && arguments.count == 3))
                    {
                        markConsume(arguments[0])
                        continue
                    }
                    if callee == collectName || callee == kkFlowCollectName,
                       arguments.count == 2 || arguments.count == 3
                    {
                        markConsume(arguments[0])
                        continue
                    }
                    if isFlowTransformEmitCall(callee, arguments), arguments.count == 3 {
                        markConsume(arguments[0])
                    }
                case let .virtualCall(_, callee, receiver, arguments, _, _, _, _):
                    if callee == mapName || callee == filterName || callee == takeName || callee == collectName,
                       arguments.count == 1
                    {
                        markConsume(receiver)
                    }
                default:
                    continue
                }
            }

            // Phase 2: rewrite flow instructions.
            let names = FlowLoweringNames(
                flow: flowName,
                emit: emitName,
                collect: collectName,
                map: mapName,
                filter: filterName,
                take: takeName,
                kkFlowCreate: kkFlowCreateName,
                kkFlowEmit: kkFlowEmitName,
                kkFlowCollect: kkFlowCollectName,
                kkFlowRetain: kkFlowRetainName,
                kkFlowRelease: kkFlowReleaseName
            )
            let loweredBody = rewriteFlowInstructions(
                originalBody: function.body,
                module: module,
                ctx: ctx,
                flowExprIDs: &flowExprIDs,
                remainingConsumes: &remainingConsumes,
                symbolByExprRaw: symbolByExprRaw,
                names: names
            )

            updated.body = loweredBody
            return updated
        }
    }
}
