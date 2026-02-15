import Foundation

final class CoroutineLoweringPass: LoweringPass {
    static let name = "CoroutineLowering"

    private struct SuspendCallLookupKey: Hashable {
        let name: InternedString
        let arity: Int
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        let anyType = ctx.sema?.types.nullableAnyType ?? ctx.sema?.types.anyType
        let intType = ctx.sema?.types.make(.primitive(.int, .nonNull))
        let unitType = ctx.sema?.types.unitType
        let suspendFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl, function.isSuspend else {
                return nil
            }
            return function
        }
        guard !suspendFunctions.isEmpty else {
            module.recordLowering(Self.name)
            return
        }
        let suspendFunctionSymbols = Set(suspendFunctions.map(\.symbol))
        let suspendFunctionNames = Set(suspendFunctions.map(\.name))

        var existingFunctionNames: Set<InternedString> = Set(module.arena.declarations.compactMap { decl in
            guard case .function(let function) = decl else {
                return nil
            }
            return function.name
        })

        var nextSyntheticSymbol = nextAvailableSyntheticSymbol(module: module, sema: ctx.sema)
        var loweredBySymbol: [SymbolID: (name: InternedString, symbol: SymbolID)] = [:]
        var loweredByNameBuckets: [InternedString: [(name: InternedString, symbol: SymbolID)]] = [:]
        var loweredByNameArityBuckets: [SuspendCallLookupKey: [(name: InternedString, symbol: SymbolID)]] = [:]

        for suspendFunction in suspendFunctions {
            let rawLowered = ctx.interner.intern("kk_suspend_" + ctx.interner.resolve(suspendFunction.name))
            let loweredName = uniqueFunctionName(
                preferred: rawLowered,
                existingFunctionNames: &existingFunctionNames,
                interner: ctx.interner
            )
            let loweredSymbol = defineSyntheticCoroutineFunctionSymbol(
                original: suspendFunction,
                loweredName: loweredName,
                nextSyntheticSymbol: &nextSyntheticSymbol,
                sema: ctx.sema
            )
            let continuationType = ctx.sema?.types.nullableAnyType ?? suspendFunction.returnType
            let continuationParameterSymbol = defineSyntheticContinuationParameterSymbol(
                owner: loweredSymbol,
                loweredName: loweredName,
                nextSyntheticSymbol: &nextSyntheticSymbol,
                sema: ctx.sema,
                interner: ctx.interner
            )
            let loweredBody = lowerSuspendBodyToStateMachineSkeleton(
                originalBody: suspendFunction.body,
                continuationParameterSymbol: continuationParameterSymbol,
                loweredSymbol: loweredSymbol,
                module: module,
                interner: ctx.interner,
                suspendFunctionSymbols: suspendFunctionSymbols,
                suspendFunctionNames: suspendFunctionNames,
                continuationType: continuationType,
                intType: intType,
                unitType: unitType
            )
            let loweredFunction = KIRFunction(
                symbol: loweredSymbol,
                name: loweredName,
                params: suspendFunction.params + [
                    KIRParameter(symbol: continuationParameterSymbol, type: continuationType)
                ],
                returnType: continuationType,
                body: loweredBody,
                isSuspend: false,
                isInline: false
            )
            _ = module.arena.appendDecl(.function(loweredFunction))

            let lowered = (name: loweredName, symbol: loweredSymbol)
            loweredBySymbol[suspendFunction.symbol] = lowered
            loweredByNameBuckets[suspendFunction.name, default: []].append(lowered)
            let byNameArityKey = SuspendCallLookupKey(name: suspendFunction.name, arity: suspendFunction.params.count)
            loweredByNameArityBuckets[byNameArityKey, default: []].append(lowered)
            updateLoweredFunctionSignatureIfPossible(
                loweredSymbol: loweredSymbol,
                continuationParameterSymbol: continuationParameterSymbol,
                originalSymbol: suspendFunction.symbol,
                continuationType: continuationType,
                sema: ctx.sema
            )
        }

        let loweredByUniqueName = loweredByNameBuckets.reduce(into: [InternedString: (name: InternedString, symbol: SymbolID)]()) { partial, entry in
            guard entry.value.count == 1, let value = entry.value.first else {
                return
            }
            partial[entry.key] = value
        }
        let loweredByUniqueNameArity = loweredByNameArityBuckets.reduce(into: [SuspendCallLookupKey: (name: InternedString, symbol: SymbolID)]()) { partial, entry in
            guard entry.value.count == 1, let value = entry.value.first else {
                return
            }
            partial[entry.key] = value
        }
        let continuationFactory = ctx.interner.intern("kk_coroutine_continuation_new")

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)
            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let canThrow) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }

                let loweredTarget: (name: InternedString, symbol: SymbolID)?
                if let symbol, let bySymbol = loweredBySymbol[symbol] {
                    loweredTarget = bySymbol
                } else if let byNameArity = loweredByUniqueNameArity[
                    SuspendCallLookupKey(name: callee, arity: arguments.count)
                ] {
                    loweredTarget = byNameArity
                } else if let byName = loweredByUniqueName[callee] {
                    loweredTarget = byName
                } else {
                    loweredTarget = nil
                }

                guard let loweredTarget else {
                    loweredBody.append(instruction)
                    continue
                }

                let continuationFunctionID = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: intType
                )
                loweredBody.append(
                    .constValue(
                        result: continuationFunctionID,
                        value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
                    )
                )

                let continuationTemp = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: anyType
                )
                loweredBody.append(
                    .call(
                        symbol: nil,
                        callee: continuationFactory,
                        arguments: [continuationFunctionID],
                        result: continuationTemp,
                        canThrow: false
                    )
                )
                var loweredArguments = arguments
                loweredArguments.append(continuationTemp)
                loweredBody.append(
                    .call(
                        symbol: loweredTarget.symbol,
                        callee: loweredTarget.name,
                        arguments: loweredArguments,
                        result: result,
                        canThrow: canThrow
                    )
                )
            }
            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func nextAvailableSyntheticSymbol(module: KIRModule, sema: SemaModule?) -> Int32 {
        var maxRaw: Int32 = 0
        for decl in module.arena.declarations {
            switch decl {
            case .function(let function):
                maxRaw = max(maxRaw, function.symbol.rawValue + 1)
            case .global(let global):
                maxRaw = max(maxRaw, global.symbol.rawValue + 1)
            case .nominalType(let nominal):
                maxRaw = max(maxRaw, nominal.symbol.rawValue + 1)
            }
        }
        if let sema {
            maxRaw = max(maxRaw, Int32(sema.symbols.count))
        }
        return maxRaw
    }

    private func allocateSyntheticSymbol(_ nextSyntheticSymbol: inout Int32) -> SymbolID {
        let id = SymbolID(rawValue: nextSyntheticSymbol)
        nextSyntheticSymbol += 1
        return id
    }

    private func uniqueFunctionName(
        preferred: InternedString,
        existingFunctionNames: inout Set<InternedString>,
        interner: StringInterner
    ) -> InternedString {
        if existingFunctionNames.insert(preferred).inserted {
            return preferred
        }
        let base = interner.resolve(preferred)
        var suffix = 1
        while true {
            let candidate = interner.intern("\(base)$\(suffix)")
            if existingFunctionNames.insert(candidate).inserted {
                return candidate
            }
            suffix += 1
        }
    }

    private func defineSyntheticCoroutineFunctionSymbol(
        original: KIRFunction,
        loweredName: InternedString,
        nextSyntheticSymbol: inout Int32,
        sema: SemaModule?
    ) -> SymbolID {
        guard let sema, let originalSymbol = sema.symbols.symbol(original.symbol) else {
            return allocateSyntheticSymbol(&nextSyntheticSymbol)
        }
        let loweredFQName = Array(originalSymbol.fqName.dropLast()) + [loweredName]
        return sema.symbols.define(
            kind: .function,
            name: loweredName,
            fqName: loweredFQName,
            declSite: originalSymbol.declSite,
            visibility: originalSymbol.visibility,
            flags: [.synthetic, .static]
        )
    }

    private func defineSyntheticContinuationParameterSymbol(
        owner: SymbolID,
        loweredName: InternedString,
        nextSyntheticSymbol: inout Int32,
        sema: SemaModule?,
        interner: StringInterner
    ) -> SymbolID {
        guard let sema, let loweredSymbol = sema.symbols.symbol(owner) else {
            return allocateSyntheticSymbol(&nextSyntheticSymbol)
        }
        let parameterName = interner.intern("$continuation")
        return sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: loweredSymbol.fqName + [parameterName],
            declSite: loweredSymbol.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
    }

    private func updateLoweredFunctionSignatureIfPossible(
        loweredSymbol: SymbolID,
        continuationParameterSymbol: SymbolID,
        originalSymbol: SymbolID,
        continuationType: TypeID,
        sema: SemaModule?
    ) {
        guard let sema else {
            return
        }
        let originalSignature = sema.symbols.functionSignature(for: originalSymbol)
        let loweredParameterTypes = (originalSignature?.parameterTypes ?? []) + [continuationType]
        let loweredValueSymbols = (originalSignature?.valueParameterSymbols ?? []) + [continuationParameterSymbol]
        let loweredDefaults = (originalSignature?.valueParameterHasDefaultValues ?? []) + [false]
        let loweredVararg = (originalSignature?.valueParameterIsVararg ?? []) + [false]
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: originalSignature?.receiverType,
                parameterTypes: loweredParameterTypes,
                returnType: continuationType,
                isSuspend: false,
                valueParameterSymbols: loweredValueSymbols,
                valueParameterHasDefaultValues: loweredDefaults,
                valueParameterIsVararg: loweredVararg,
                typeParameterSymbols: originalSignature?.typeParameterSymbols ?? []
            ),
            for: loweredSymbol
        )
    }

    private func lowerSuspendBodyToStateMachineSkeleton(
        originalBody: [KIRInstruction],
        continuationParameterSymbol: SymbolID,
        loweredSymbol: SymbolID,
        module: KIRModule,
        interner: StringInterner,
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>,
        continuationType: TypeID,
        intType: TypeID?,
        unitType: TypeID?
    ) -> [KIRInstruction] {
        let enterCallee = interner.intern("kk_coroutine_state_enter")
        let setLabelCallee = interner.intern("kk_coroutine_state_set_label")
        let exitCallee = interner.intern("kk_coroutine_state_exit")
        let setSpillCallee = interner.intern("kk_coroutine_state_set_spill")
        let getSpillCallee = interner.intern("kk_coroutine_state_get_spill")
        let setCompletionCallee = interner.intern("kk_coroutine_state_set_completion")
        let getCompletionCallee = interner.intern("kk_coroutine_state_get_completion")
        let suspendedProvider = interner.intern("kk_coroutine_suspended")

        let stateBlocks = buildSuspendStateBlocks(
            originalBody: originalBody,
            suspendFunctionSymbols: suspendFunctionSymbols,
            suspendFunctionNames: suspendFunctionNames
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
            guard case .call(let symbol, let callee, _, let result, _) = tailInstruction.instruction,
                  isSuspendCall(
                    symbol: symbol,
                    callee: callee,
                    suspendFunctionSymbols: suspendFunctionSymbols,
                    suspendFunctionNames: suspendFunctionNames
                  ) else {
                continue
            }
            let transition = SuspendTransition(
                sourceInstructionIndex: tailInstruction.sourceIndex,
                callResultExpr: result
            )
            transitionsByResumeLabel[nextResumeLabel] = transition
            transitionSourceIndexes.insert(tailInstruction.sourceIndex)
        }
        let spillPlan = buildSpillPlan(
            transitionSourceIndexes: transitionSourceIndexes,
            liveOutByInstruction: liveOutByInstruction,
            transitionsByResumeLabel: transitionsByResumeLabel
        )

        var lowered: [KIRInstruction] = []
        lowered.reserveCapacity(originalBody.count * 6 + 24)

        let continuationExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: continuationType
        )
        lowered.append(.constValue(result: continuationExpr, value: .symbolRef(continuationParameterSymbol)))

        let functionIDExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: intType
        )
        lowered.append(.constValue(result: functionIDExpr, value: .intLiteral(Int64(loweredSymbol.rawValue))))

        let resumeLabelExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: intType
        )
        lowered.append(
            .call(
                symbol: nil,
                callee: enterCallee,
                arguments: [continuationExpr, functionIDExpr],
                result: resumeLabelExpr,
                canThrow: false
            )
        )

        for block in stateBlocks {
            let expectedResumeExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: intType
            )
            lowered.append(.constValue(result: expectedResumeExpr, value: .intLiteral(block.resumeLabel)))
            lowered.append(
                .jumpIfEqual(
                    lhs: resumeLabelExpr,
                    rhs: expectedResumeExpr,
                    target: stateDispatchLabel(for: block.resumeLabel)
                )
            )
        }
        lowered.append(.jump(stateDispatchLabel(for: stateBlocks.first?.resumeLabel ?? 0)))

        for (index, block) in stateBlocks.enumerated() {
            lowered.append(.label(stateDispatchLabel(for: block.resumeLabel)))
            if let transition = transitionsByResumeLabel[block.resumeLabel] {
                let reloadExprs = spillPlan.exprsByTransitionSource[transition.sourceInstructionIndex] ?? []
                for exprID in reloadExprs {
                    guard let slot = spillPlan.slotByExpr[exprID] else {
                        continue
                    }
                    let slotExpr = appendIntLiteralExpr(
                        slot,
                        intType: intType,
                        module: module,
                        lowered: &lowered
                    )
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: getSpillCallee,
                            arguments: [continuationExpr, slotExpr],
                            result: exprID,
                            canThrow: false
                        )
                    )
                }
                if let callResultExpr = transition.callResultExpr {
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: getCompletionCallee,
                            arguments: [continuationExpr],
                            result: callResultExpr,
                            canThrow: false
                        )
                    )
                }
            }
            let nextResumeLabel = stateBlocks.indices.contains(index + 1)
                ? stateBlocks[index + 1].resumeLabel
                : nil

            for stateInstruction in block.instructions {
                let instruction = stateInstruction.instruction
                if case .call(let symbol, let callee, let arguments, let result, let canThrow) = instruction,
                   isSuspendCall(
                    symbol: symbol,
                    callee: callee,
                    suspendFunctionSymbols: suspendFunctionSymbols,
                   suspendFunctionNames: suspendFunctionNames
                   ),
                   let nextResumeLabel {
                    let spilledExprs = spillPlan.exprsByTransitionSource[stateInstruction.sourceIndex] ?? []
                    for exprID in spilledExprs {
                        guard let slot = spillPlan.slotByExpr[exprID] else {
                            continue
                        }
                        let slotExpr = appendIntLiteralExpr(
                            slot,
                            intType: intType,
                            module: module,
                            lowered: &lowered
                        )
                        lowered.append(
                            .call(
                                symbol: nil,
                                callee: setSpillCallee,
                                arguments: [continuationExpr, slotExpr, exprID],
                                result: nil,
                                canThrow: false
                            )
                        )
                    }

                    let resumeLabelExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: intType
                    )
                    lowered.append(.constValue(result: resumeLabelExpr, value: .intLiteral(nextResumeLabel)))

                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: setLabelCallee,
                            arguments: [continuationExpr, resumeLabelExpr],
                            result: nil,
                            canThrow: false
                        )
                    )

                    let suspensionResult = result ?? module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: continuationType
                    )
                    lowered.append(
                        .call(
                            symbol: symbol,
                            callee: callee,
                            arguments: arguments,
                            result: suspensionResult,
                            canThrow: canThrow
                        )
                    )

                    let suspendedExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: continuationType
                    )
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: suspendedProvider,
                            arguments: [],
                            result: suspendedExpr,
                            canThrow: false
                        )
                    )
                    lowered.append(.returnIfEqual(lhs: suspensionResult, rhs: suspendedExpr))
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: setCompletionCallee,
                            arguments: [continuationExpr, suspensionResult],
                            result: nil,
                            canThrow: false
                        )
                    )
                    continue
                }

                switch instruction {
                case .returnValue(let value):
                    let exitValueExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: continuationType
                    )
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: exitCallee,
                            arguments: [continuationExpr, value],
                            result: exitValueExpr,
                            canThrow: false
                        )
                    )
                    lowered.append(.returnValue(exitValueExpr))

                case .returnUnit:
                    let unitExpr = module.arena.appendExpr(.unit, type: unitType)
                    let exitValueExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: continuationType
                    )
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: exitCallee,
                            arguments: [continuationExpr, unitExpr],
                            result: exitValueExpr,
                            canThrow: false
                        )
                    )
                    lowered.append(.returnValue(exitValueExpr))

                default:
                    lowered.append(instruction)
                }
            }
        }

        return lowered
    }

    private func stateDispatchLabel(for resumeLabel: Int64) -> Int32 {
        Int32(1000 + resumeLabel)
    }

    private struct IndexedInstruction {
        let sourceIndex: Int
        let instruction: KIRInstruction
    }

    private struct SuspendStateBlock {
        let resumeLabel: Int64
        let instructions: [IndexedInstruction]
    }

    private struct SuspendTransition {
        let sourceInstructionIndex: Int
        let callResultExpr: KIRExprID?
    }

    private struct SpillPlan {
        let slotByExpr: [KIRExprID: Int64]
        let exprsByTransitionSource: [Int: [KIRExprID]]
    }

    private struct CFGBlock {
        let id: Int
        let instructions: [IndexedInstruction]
        let successors: [Int]
    }

    private func buildSuspendStateBlocks(
        originalBody: [KIRInstruction],
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>
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

                guard case .call(let symbol, let callee, _, _, _) = indexed.instruction else {
                    continue
                }
                guard isSuspendCall(
                    symbol: symbol,
                    callee: callee,
                    suspendFunctionSymbols: suspendFunctionSymbols,
                    suspendFunctionNames: suspendFunctionNames
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

    private func buildControlFlowBlocks(_ instructions: [KIRInstruction]) -> [CFGBlock] {
        guard !instructions.isEmpty else {
            return []
        }

        var labelToInstructionIndex: [Int32: Int] = [:]
        for (index, instruction) in instructions.enumerated() {
            if case .label(let labelID) = instruction {
                labelToInstructionIndex[labelID] = index
            }
        }

        var leaders: Set<Int> = [0]
        for (index, instruction) in instructions.enumerated() {
            switch instruction {
            case .label:
                leaders.insert(index)
            case .jump(let target):
                if let targetIndex = labelToInstructionIndex[target] {
                    leaders.insert(targetIndex)
                }
                if index + 1 < instructions.count {
                    leaders.insert(index + 1)
                }
            case .jumpIfEqual(_, _, let target):
                if let targetIndex = labelToInstructionIndex[target] {
                    leaders.insert(targetIndex)
                }
                if index + 1 < instructions.count {
                    leaders.insert(index + 1)
                }
            case .returnUnit, .returnValue, .returnIfEqual:
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
            for instructionIndex in range.start..<range.end {
                instructionToBlock[instructionIndex] = blockID
            }
        }

        var blocks: [CFGBlock] = []
        blocks.reserveCapacity(ranges.count)

        for (blockID, range) in ranges.enumerated() {
            let blockInstructions = (range.start..<range.end).map { index in
                IndexedInstruction(sourceIndex: index, instruction: instructions[index])
            }
            let terminator = blockInstructions.last?.instruction

            var successors: [Int] = []
            switch terminator {
            case .some(.jump(let target)):
                if let targetInstruction = labelToInstructionIndex[target],
                   let targetBlock = instructionToBlock[targetInstruction] {
                    successors.append(targetBlock)
                }

            case .some(.jumpIfEqual(_, _, let target)):
                if let targetInstruction = labelToInstructionIndex[target],
                   let targetBlock = instructionToBlock[targetInstruction] {
                    successors.append(targetBlock)
                }
                if blockID + 1 < ranges.count {
                    successors.append(blockID + 1)
                }

            case .some(.returnUnit), .some(.returnValue), .some(.returnIfEqual):
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

    private func buildSpillPlan(
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

    private func computeLiveOutByInstruction(_ instructions: [KIRInstruction]) -> [Int: Set<KIRExprID>] {
        guard !instructions.isEmpty else {
            return [:]
        }

        var labelToInstructionIndex: [Int32: Int] = [:]
        for (index, instruction) in instructions.enumerated() {
            if case .label(let labelID) = instruction {
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

    private func instructionSuccessors(
        at index: Int,
        instruction: KIRInstruction,
        totalInstructions: Int,
        labelToInstructionIndex: [Int32: Int]
    ) -> [Int] {
        let fallthroughSuccessors = index + 1 < totalInstructions ? [index + 1] : []
        switch instruction {
        case .jump(let target):
            guard let targetIndex = labelToInstructionIndex[target] else {
                return []
            }
            return [targetIndex]

        case .jumpIfEqual(_, _, let target):
            var successors = fallthroughSuccessors
            if let targetIndex = labelToInstructionIndex[target],
               !successors.contains(targetIndex) {
                successors.append(targetIndex)
            }
            return successors

        case .returnUnit, .returnValue:
            return []

        case .returnIfEqual:
            return fallthroughSuccessors

        default:
            return fallthroughSuccessors
        }
    }

    private func usedExprIDs(in instruction: KIRInstruction) -> Set<KIRExprID> {
        switch instruction {
        case .jumpIfEqual(let lhs, let rhs, _):
            return Set([lhs, rhs])
        case .binary(_, let lhs, let rhs, _):
            return Set([lhs, rhs])
        case .select(let condition, let thenValue, let elseValue, _):
            return Set([condition, thenValue, elseValue])
        case .call(_, _, let arguments, _, _):
            return Set(arguments)
        case .returnIfEqual(let lhs, let rhs):
            return Set([lhs, rhs])
        case .returnValue(let value):
            return Set([value])
        default:
            return []
        }
    }

    private func definedExprIDs(in instruction: KIRInstruction) -> Set<KIRExprID> {
        switch instruction {
        case .constValue(let result, _):
            return Set([result])
        case .binary(_, _, _, let result):
            return Set([result])
        case .select(_, _, _, let result):
            return Set([result])
        case .call(_, _, _, let result, _):
            if let result {
                return Set([result])
            }
            return []
        default:
            return []
        }
    }

    private func appendIntLiteralExpr(
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

    private func reachableBlockOrder(cfgBlocks: [CFGBlock]) -> [Int] {
        guard !cfgBlocks.isEmpty else {
            return []
        }
        var order: [Int] = []
        var stack: [Int] = [0]
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

    private func isSuspendCall(
        symbol: SymbolID?,
        callee: InternedString,
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>
    ) -> Bool {
        if let symbol, suspendFunctionSymbols.contains(symbol) {
            return true
        }
        return suspendFunctionNames.contains(callee)
    }
}
