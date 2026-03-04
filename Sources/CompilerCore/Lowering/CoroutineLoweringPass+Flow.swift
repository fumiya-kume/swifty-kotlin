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
        let kkFlowMapName = ctx.interner.intern("kk_flow_map")
        let kkFlowFilterName = ctx.interner.intern("kk_flow_filter")
        let kkFlowTakeName = ctx.interner.intern("kk_flow_take")

        module.arena.transformFunctions { function in
            var updated = function

            // Phase 1: identify which expression IDs hold Flow values.
            var flowExprIDs: Set<Int32> = []
            var flowGlobalSymbols: Set<SymbolID> = []

            func markFlowExpr(_ result: KIRExprID?) -> Bool {
                guard let result else { return false }
                return flowExprIDs.insert(result.rawValue).inserted
            }

            func isFlowTransformCall(_ callee: InternedString, argumentCount: Int) -> Bool {
                (callee == mapName || callee == filterName || callee == takeName) && argumentCount == 2 ||
                    (callee == kkFlowMapName || callee == kkFlowFilterName || callee == kkFlowTakeName) && argumentCount == 2
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
                        if callee == kkFlowCreateName, arguments.count == 1 {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }

                        // map/filter/take produce a new flow handle when the
                        // first argument is already known as a flow handle.
                        if isFlowTransformCall(callee, argumentCount: arguments.count),
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }

                        // collect call form (collect(flow, lambda)) seeds the
                        // first argument as a flow handle.
                        if (callee == collectName && arguments.count == 2 && symbol == nil) ||
                            (callee == kkFlowCollectName && arguments.count == 2)
                        {
                            if let flowHandleArg = arguments.first,
                               flowExprIDs.insert(flowHandleArg.rawValue).inserted
                            {
                                changed = true
                            }
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
                        callee == kkFlowCreateName || callee == kkFlowEmitName || callee == kkFlowCollectName ||
                        callee == kkFlowMapName || callee == kkFlowFilterName || callee == kkFlowTakeName
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

            for instruction in function.body {
                switch instruction {
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall):
                    // flow(lambda) → kk_flow_create(lambda)
                    if callee == flowName, arguments.count == 1, symbol == nil {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCreateName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        continue
                    }
                    // emit(value) → kk_flow_emit(value) [uses flowEmitContext]
                    if callee == emitName, arguments.count == 1, symbol == nil {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        continue
                    }
                    // map(flowHandle, lambda) → kk_flow_map(flowHandle, lambda)
                    if callee == mapName, arguments.count == 2, symbol == nil,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowMapName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        if let result { flowExprIDs.insert(result.rawValue) }
                        continue
                    }
                    // filter(flowHandle, predicate) → kk_flow_filter(flowHandle, predicate)
                    if callee == filterName, arguments.count == 2, symbol == nil,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowFilterName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        if let result { flowExprIDs.insert(result.rawValue) }
                        continue
                    }
                    // take(flowHandle, n) → kk_flow_take(flowHandle, n)
                    if callee == takeName, arguments.count == 2, symbol == nil,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowTakeName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: isSuperCall
                        ))
                        if let result { flowExprIDs.insert(result.rawValue) }
                        continue
                    }
                    // collect(flowHandle, lambda) → kk_flow_collect(flowHandle, lambda)
                    if callee == collectName, arguments.count == 2, symbol == nil,
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
                    loweredBody.append(instruction)

                // Method-call form: flow.map { }, flow.collect { }, etc.
                case let .virtualCall(_, callee, receiver, arguments, result, canThrow, thrownResult, _):
                    if callee == mapName, arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowMapName,
                            arguments: [receiver] + arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result { flowExprIDs.insert(result.rawValue) }
                        continue
                    }
                    if callee == filterName, arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowFilterName,
                            arguments: [receiver] + arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result { flowExprIDs.insert(result.rawValue) }
                        continue
                    }
                    if callee == takeName, arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowTakeName,
                            arguments: [receiver] + arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        if let result { flowExprIDs.insert(result.rawValue) }
                        continue
                    }
                    if callee == collectName, arguments.count == 1,
                       flowExprIDs.contains(receiver.rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCollectName,
                            arguments: [receiver] + arguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult
                        ))
                        continue
                    }
                    loweredBody.append(instruction)

                default:
                    loweredBody.append(instruction)
                }
            }

            updated.body = loweredBody
            return updated
        }
    }
}
