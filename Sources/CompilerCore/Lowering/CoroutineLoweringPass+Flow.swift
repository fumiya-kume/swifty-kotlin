import Foundation

// MARK: - Flow Lowering (CORO-003)

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
        let kkFlowMapName = ctx.interner.intern("kk_flow_map")
        let kkFlowFilterName = ctx.interner.intern("kk_flow_filter")
        let kkFlowTakeName = ctx.interner.intern("kk_flow_take")

        module.arena.transformFunctions { function in
            var updated = function

            // Phase 1: identify which expression IDs hold Flow values.
            var flowExprIDs: Set<Int32> = []

            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, arguments, result, _, _, _):
                    if callee == flowName, arguments.count == 1 {
                        if let result { flowExprIDs.insert(result.rawValue) }
                    } else if callee == mapName || callee == filterName || callee == takeName {
                        if arguments.count == 2, flowExprIDs.contains(arguments[0].rawValue) {
                            if let result { flowExprIDs.insert(result.rawValue) }
                        }
                    }
                case let .virtualCall(_, callee, receiver, _, result, _, _, _):
                    if callee == mapName || callee == filterName || callee == takeName {
                        if flowExprIDs.contains(receiver.rawValue) {
                            if let result { flowExprIDs.insert(result.rawValue) }
                        }
                    }
                case let .copy(from, to):
                    if flowExprIDs.contains(from.rawValue) {
                        flowExprIDs.insert(to.rawValue)
                    }
                default:
                    break
                }
            }

            guard !flowExprIDs.isEmpty || function.body.contains(where: {
                if case let .call(_, callee, _, _, _, _, _) = $0 { return callee == flowName || callee == emitName }
                return false
            }) else {
                return updated
            }

            // Phase 2: rewrite flow instructions.
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, arguments, result, canThrow, thrownResult, _):
                    // flow(lambda) → kk_flow_create(lambda)
                    if callee == flowName, arguments.count == 1 {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCreateName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }
                    // emit(value) → kk_flow_emit(value)  [uses _flowEmitContext thread-local]
                    if callee == emitName, arguments.count == 1 {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowEmitName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }
                    // map(flowHandle, lambda) → kk_flow_map(flowHandle, lambda)
                    if callee == mapName, arguments.count == 2,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowMapName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }
                    // filter(flowHandle, predicate) → kk_flow_filter(flowHandle, predicate)
                    if callee == filterName, arguments.count == 2,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowFilterName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }
                    // take(flowHandle, n) → kk_flow_take(flowHandle, n)
                    if callee == takeName, arguments.count == 2,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowTakeName,
                            arguments: arguments,
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        continue
                    }
                    // collect(flowHandle, lambda) → kk_flow_collect(flowHandle, lambda)
                    if callee == collectName, arguments.count == 2,
                       flowExprIDs.contains(arguments[0].rawValue)
                    {
                        loweredBody.append(.call(
                            symbol: nil,
                            callee: kkFlowCollectName,
                            arguments: arguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult
                        ))
                        continue
                    }
                    loweredBody.append(instruction)

                // Handle .virtualCall for method-call form: flow.map { }, flow.collect { }, etc.
                case let .virtualCall(_, callee, receiver, arguments, result, _, _, _):
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
                            canThrow: false,
                            thrownResult: nil
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
