import Foundation

extension CoroutineLoweringPass {
    func analyzeSuspendLoweringPlan(
        originalBody: [KIRInstruction],
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>,
        runtimeSuspendCallNames: Set<InternedString>
    ) -> SuspendLoweringPlan {
        let stateBlocks = buildSuspendStateBlocks(
            originalBody: originalBody,
            suspendFunctionSymbols: suspendFunctionSymbols,
            suspendFunctionNames: suspendFunctionNames,
            runtimeSuspendCallNames: runtimeSuspendCallNames
        )
        let liveOutByInstruction = computeLiveOutByInstruction(originalBody)

        var transitionsByResumeLabel: [Int64: SuspendTransition] = [:]
        var transitionSourceIndexes: Set<Int> = []
        for (index, block) in stateBlocks.enumerated() {
            guard stateBlocks.indices.contains(index + 1) else {
                continue
            }
            let nextResumeLabel = stateBlocks[index + 1].resumeLabel
            guard let tailInstruction = block.instructions.last else {
                continue
            }
            let callInfo = extractCallInfo(tailInstruction.instruction)
            guard let callInfo,
                  isSuspendCall(
                      symbol: callInfo.symbol,
                      callee: callInfo.callee,
                      suspendFunctionSymbols: suspendFunctionSymbols,
                      suspendFunctionNames: suspendFunctionNames,
                      runtimeSuspendCallNames: runtimeSuspendCallNames
                  )
            else {
                continue
            }
            let transition = SuspendTransition(
                sourceInstructionIndex: tailInstruction.sourceIndex,
                callResultExpr: callInfo.result
            )
            transitionsByResumeLabel[nextResumeLabel] = transition
            transitionSourceIndexes.insert(tailInstruction.sourceIndex)
        }
        let spillPlan = buildSpillPlan(
            transitionSourceIndexes: transitionSourceIndexes,
            liveOutByInstruction: liveOutByInstruction,
            transitionsByResumeLabel: transitionsByResumeLabel
        )
        return SuspendLoweringPlan(
            stateBlocks: stateBlocks,
            transitionsByResumeLabel: transitionsByResumeLabel,
            spillPlan: spillPlan
        )
    }

    func buildSuspendStateBlocks(
        originalBody: [KIRInstruction],
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>,
        runtimeSuspendCallNames: Set<InternedString>
    ) -> [SuspendStateBlock] {
        let cfgBlocks = buildControlFlowBlocks(originalBody)
        guard !cfgBlocks.isEmpty else {
            return [SuspendStateBlock(resumeLabel: 0, instructions: [])]
        }

        let reachableOrder = reachableBlockOrder(cfgBlocks: cfgBlocks)

        var blocks: [SuspendStateBlock] = []
        var currentResumeLabel: Int64 = 0
        var nextResumeLabel: Int64 = 1

        for blockID in reachableOrder {
            let cfgBlock = cfgBlocks[blockID]
            var chunk: [IndexedInstruction] = []
            chunk.reserveCapacity(cfgBlock.instructions.count)

            for indexed in cfgBlock.instructions {
                chunk.append(indexed)

                let callInfo = extractCallInfo(indexed.instruction)
                guard let callInfo else {
                    continue
                }
                guard isSuspendCall(
                    symbol: callInfo.symbol,
                    callee: callInfo.callee,
                    suspendFunctionSymbols: suspendFunctionSymbols,
                    suspendFunctionNames: suspendFunctionNames,
                    runtimeSuspendCallNames: runtimeSuspendCallNames
                ) else {
                    continue
                }

                blocks.append(
                    SuspendStateBlock(
                        resumeLabel: currentResumeLabel,
                        instructions: chunk
                    )
                )
                chunk = []
                currentResumeLabel = nextResumeLabel
                nextResumeLabel += 1
            }

            if !chunk.isEmpty {
                blocks.append(
                    SuspendStateBlock(
                        resumeLabel: currentResumeLabel,
                        instructions: chunk
                    )
                )
                currentResumeLabel = nextResumeLabel
                nextResumeLabel += 1
            }
        }

        if blocks.isEmpty {
            return [SuspendStateBlock(resumeLabel: 0, instructions: [])]
        }
        return blocks
    }

    func buildControlFlowBlocks(_ instructions: [KIRInstruction]) -> [CFGBlock] {
        guard !instructions.isEmpty else {
            return []
        }

        var labelToInstructionIndex: [Int32: Int] = [:]
        for (index, instruction) in instructions.enumerated() {
            if case let .label(labelID) = instruction {
                labelToInstructionIndex[labelID] = index
            }
        }

        var leaders: Set = [0]
        for (index, instruction) in instructions.enumerated() {
            switch instruction {
            case .label:
                leaders.insert(index)
            case let .jump(target):
                if let targetIndex = labelToInstructionIndex[target] {
                    leaders.insert(targetIndex)
                }
                if index + 1 < instructions.count {
                    leaders.insert(index + 1)
                }
            case let .jumpIfEqual(_, _, target):
                if let targetIndex = labelToInstructionIndex[target] {
                    leaders.insert(targetIndex)
                }
                if index + 1 < instructions.count {
                    leaders.insert(index + 1)
                }
            case let .jumpIfNotNull(_, target):
                if let targetIndex = labelToInstructionIndex[target] {
                    leaders.insert(targetIndex)
                }
                if index + 1 < instructions.count {
                    leaders.insert(index + 1)
                }
            case .returnUnit, .returnValue, .returnIfEqual, .rethrow:
                if index + 1 < instructions.count {
                    leaders.insert(index + 1)
                }
            default:
                continue
            }
        }

        let sortedLeaders = leaders.sorted()
        var ranges: [(start: Int, end: Int)] = []
        ranges.reserveCapacity(sortedLeaders.count)
        for (index, start) in sortedLeaders.enumerated() {
            let end = index + 1 < sortedLeaders.count ? sortedLeaders[index + 1] : instructions.count
            if start < end {
                ranges.append((start: start, end: end))
            }
        }
        guard !ranges.isEmpty else {
            return []
        }

        var instructionToBlock: [Int: Int] = [:]
        for (blockID, range) in ranges.enumerated() {
            for instructionIndex in range.start ..< range.end {
                instructionToBlock[instructionIndex] = blockID
            }
        }

        var blocks: [CFGBlock] = []
        blocks.reserveCapacity(ranges.count)

        for (blockID, range) in ranges.enumerated() {
            let blockInstructions = (range.start ..< range.end).map { index in
                IndexedInstruction(sourceIndex: index, instruction: instructions[index])
            }
            let terminator = blockInstructions.last?.instruction

            var successors: [Int] = []
            switch terminator {
            case let .some(.jump(target)):
                if let targetInstruction = labelToInstructionIndex[target],
                   let targetBlock = instructionToBlock[targetInstruction]
                {
                    successors.append(targetBlock)
                }

            case let .some(.jumpIfEqual(_, _, target)):
                if let targetInstruction = labelToInstructionIndex[target],
                   let targetBlock = instructionToBlock[targetInstruction]
                {
                    successors.append(targetBlock)
                }
                if blockID + 1 < ranges.count {
                    successors.append(blockID + 1)
                }

            case let .some(.jumpIfNotNull(_, target)):
                if let targetInstruction = labelToInstructionIndex[target],
                   let targetBlock = instructionToBlock[targetInstruction]
                {
                    successors.append(targetBlock)
                }
                if blockID + 1 < ranges.count {
                    successors.append(blockID + 1)
                }

            case .some(.returnUnit), .some(.returnValue), .some(.returnIfEqual), .some(.rethrow):
                break

            default:
                if blockID + 1 < ranges.count {
                    successors.append(blockID + 1)
                }
            }

            var dedupedSuccessors: [Int] = []
            dedupedSuccessors.reserveCapacity(successors.count)
            for successor in successors where !dedupedSuccessors.contains(successor) {
                dedupedSuccessors.append(successor)
            }
            blocks.append(
                CFGBlock(
                    id: blockID,
                    instructions: blockInstructions,
                    successors: dedupedSuccessors
                )
            )
        }

        return blocks
    }

    func buildSpillPlan(
        transitionSourceIndexes: Set<Int>,
        liveOutByInstruction: [Int: Set<KIRExprID>],
        transitionsByResumeLabel: [Int64: SuspendTransition]
    ) -> SpillPlan {
        var transitionSourceToExprs: [Int: Set<KIRExprID>] = [:]
        var allSpilledExprs: Set<KIRExprID> = []
        let resultExprs = Set(transitionsByResumeLabel.values.compactMap(\.callResultExpr))

        for sourceIndex in transitionSourceIndexes {
            var spillExprs = liveOutByInstruction[sourceIndex] ?? []
            spillExprs.subtract(resultExprs)
            transitionSourceToExprs[sourceIndex] = spillExprs
            allSpilledExprs.formUnion(spillExprs)
        }

        let sortedSpilledExprs = allSpilledExprs.sorted { lhs, rhs in
            lhs.rawValue < rhs.rawValue
        }
        var slotByExpr: [KIRExprID: Int64] = [:]
        slotByExpr.reserveCapacity(sortedSpilledExprs.count)
        for (slot, expr) in sortedSpilledExprs.enumerated() {
            slotByExpr[expr] = Int64(slot)
        }

        var exprsByTransitionSource: [Int: [KIRExprID]] = [:]
        exprsByTransitionSource.reserveCapacity(transitionSourceToExprs.count)
        for (sourceIndex, exprs) in transitionSourceToExprs {
            exprsByTransitionSource[sourceIndex] = exprs.sorted { lhs, rhs in
                lhs.rawValue < rhs.rawValue
            }
        }

        return SpillPlan(
            slotByExpr: slotByExpr,
            exprsByTransitionSource: exprsByTransitionSource
        )
    }

    func computeLiveOutByInstruction(_ instructions: [KIRInstruction]) -> [Int: Set<KIRExprID>] {
        guard !instructions.isEmpty else {
            return [:]
        }

        var labelToInstructionIndex: [Int32: Int] = [:]
        for (index, instruction) in instructions.enumerated() {
            if case let .label(labelID) = instruction {
                labelToInstructionIndex[labelID] = index
            }
        }

        var successorsByInstruction: [Int: [Int]] = [:]
        var useByInstruction: [Int: Set<KIRExprID>] = [:]
        var defByInstruction: [Int: Set<KIRExprID>] = [:]

        for (index, instruction) in instructions.enumerated() {
            let successors = instructionSuccessors(
                at: index,
                instruction: instruction,
                totalInstructions: instructions.count,
                labelToInstructionIndex: labelToInstructionIndex
            )
            successorsByInstruction[index] = successors
            useByInstruction[index] = usedExprIDs(in: instruction)
            defByInstruction[index] = definedExprIDs(in: instruction)
        }

        var liveIn: [Int: Set<KIRExprID>] = [:]
        var liveOut: [Int: Set<KIRExprID>] = [:]
        for index in instructions.indices {
            liveIn[index] = []
            liveOut[index] = []
        }

        var changed = true
        while changed {
            changed = false
            for index in instructions.indices.reversed() {
                let oldLiveIn = liveIn[index] ?? []
                let oldLiveOut = liveOut[index] ?? []
                let successors = successorsByInstruction[index] ?? []

                var newLiveOut: Set<KIRExprID> = []
                for successor in successors {
                    newLiveOut.formUnion(liveIn[successor] ?? [])
                }

                let uses = useByInstruction[index] ?? []
                let defs = defByInstruction[index] ?? []
                let newLiveIn = uses.union(newLiveOut.subtracting(defs))

                if newLiveIn != oldLiveIn || newLiveOut != oldLiveOut {
                    liveIn[index] = newLiveIn
                    liveOut[index] = newLiveOut
                    changed = true
                }
            }
        }

        return liveOut
    }

    func instructionSuccessors(
        at index: Int,
        instruction: KIRInstruction,
        totalInstructions: Int,
        labelToInstructionIndex: [Int32: Int]
    ) -> [Int] {
        let fallthroughSuccessors = index + 1 < totalInstructions ? [index + 1] : []
        switch instruction {
        case let .jump(target):
            guard let targetIndex = labelToInstructionIndex[target] else {
                return []
            }
            return [targetIndex]

        case let .jumpIfEqual(_, _, target):
            var successors = fallthroughSuccessors
            if let targetIndex = labelToInstructionIndex[target],
               !successors.contains(targetIndex)
            {
                successors.append(targetIndex)
            }
            return successors

        case let .jumpIfNotNull(_, target):
            var successors = fallthroughSuccessors
            if let targetIndex = labelToInstructionIndex[target],
               !successors.contains(targetIndex)
            {
                successors.append(targetIndex)
            }
            return successors

        case .returnUnit, .returnValue, .rethrow:
            return []

        case .returnIfEqual:
            return fallthroughSuccessors

        default:
            return fallthroughSuccessors
        }
    }

    func usedExprIDs(in instruction: KIRInstruction) -> Set<KIRExprID> {
        switch instruction {
        case let .jumpIfEqual(lhs, rhs, _):
            Set([lhs, rhs])
        case let .binary(_, lhs, rhs, _):
            Set([lhs, rhs])
        case let .call(_, _, arguments, _, _, _, _):
            Set(arguments)
        case let .virtualCall(_, _, receiver, arguments, _, _, _, _):
            Set([receiver] + arguments)
        case let .returnIfEqual(lhs, rhs):
            Set([lhs, rhs])
        case let .returnValue(value):
            Set([value])
        case let .jumpIfNotNull(value, _):
            Set([value])
        case let .copy(from, _):
            Set([from])
        case let .rethrow(value):
            Set([value])
        default:
            []
        }
    }

    func definedExprIDs(in instruction: KIRInstruction) -> Set<KIRExprID> {
        switch instruction {
        case let .constValue(result, _):
            return Set([result])
        case let .binary(_, _, _, result):
            return Set([result])
        case let .call(_, _, _, result, _, thrownResult, _):
            var ids = Set<KIRExprID>()
            if let result { ids.insert(result) }
            if let thrownResult { ids.insert(thrownResult) }
            return ids
        case let .virtualCall(_, _, _, _, result, _, thrownResult, _):
            var ids = Set<KIRExprID>()
            if let result { ids.insert(result) }
            if let thrownResult { ids.insert(thrownResult) }
            return ids
        case let .copy(_, to):
            return Set([to])
        default:
            return []
        }
    }

    func appendIntLiteralExpr(
        _ value: Int64,
        intType: TypeID?,
        module: KIRModule,
        lowered: inout [KIRInstruction]
    ) -> KIRExprID {
        let expr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: intType
        )
        lowered.append(.constValue(result: expr, value: .intLiteral(value)))
        return expr
    }

    func reachableBlockOrder(cfgBlocks: [CFGBlock]) -> [Int] {
        guard !cfgBlocks.isEmpty else {
            return []
        }
        var order: [Int] = []
        var stack = [0]
        var visited: Set<Int> = []

        while let blockID = stack.popLast() {
            guard visited.insert(blockID).inserted else {
                continue
            }
            order.append(blockID)
            let successors = cfgBlocks[blockID].successors
            for successor in successors.reversed() {
                stack.append(successor)
            }
        }
        return order
    }

    struct CallInfo {
        let symbol: SymbolID?
        let callee: InternedString
        let arguments: [KIRExprID]
        let result: KIRExprID?
        let canThrow: Bool
        let isVirtual: Bool
        let isSuperCall: Bool
        let originalInstruction: KIRInstruction
    }

    func extractCallInfo(_ instruction: KIRInstruction) -> CallInfo? {
        switch instruction {
        case let .call(symbol, callee, arguments, result, canThrow, _, isSuperCall):
            CallInfo(
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                isVirtual: false,
                isSuperCall: isSuperCall,
                originalInstruction: instruction
            )
        case let .virtualCall(symbol, callee, _, arguments, result, canThrow, _, _):
            CallInfo(
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                isVirtual: true,
                isSuperCall: false,
                originalInstruction: instruction
            )
        default:
            nil
        }
    }

    func isSuspendCall(
        symbol: SymbolID?,
        callee: InternedString,
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>,
        runtimeSuspendCallNames: Set<InternedString>
    ) -> Bool {
        if let symbol, suspendFunctionSymbols.contains(symbol) {
            return true
        }
        if suspendFunctionNames.contains(callee) {
            return true
        }
        return runtimeSuspendCallNames.contains(callee)
    }
}
