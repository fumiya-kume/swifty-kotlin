import Foundation

final class CoroutineLoweringPass: LoweringPass {
    static let name = "CoroutineLowering"

    private struct SuspendCallLookupKey: Hashable {
        let name: InternedString
        let arity: Int
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
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
                suspendFunctionNames: suspendFunctionNames
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
        let continuationProvider = ctx.interner.intern("kk_coroutine_suspended")

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

                let continuationTemp = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                loweredBody.append(
                    .call(
                        symbol: nil,
                        callee: continuationProvider,
                        arguments: [],
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
        suspendFunctionNames: Set<InternedString>
    ) -> [KIRInstruction] {
        let enterCallee = interner.intern("kk_coroutine_state_enter")
        let setLabelCallee = interner.intern("kk_coroutine_state_set_label")
        let exitCallee = interner.intern("kk_coroutine_state_exit")
        let suspendedProvider = interner.intern("kk_coroutine_suspended")

        let stateBlocks = buildSuspendStateBlocks(
            originalBody: originalBody,
            suspendFunctionSymbols: suspendFunctionSymbols,
            suspendFunctionNames: suspendFunctionNames
        )

        var lowered: [KIRInstruction] = []
        lowered.reserveCapacity(originalBody.count * 3 + 16)

        let continuationExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        lowered.append(.constValue(result: continuationExpr, value: .symbolRef(continuationParameterSymbol)))

        let functionIDExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        lowered.append(.constValue(result: functionIDExpr, value: .intLiteral(Int64(loweredSymbol.rawValue))))

        let resumeLabelExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
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
            let expectedResumeExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
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
            let nextResumeLabel = stateBlocks.indices.contains(index + 1)
                ? stateBlocks[index + 1].resumeLabel
                : nil

            for instruction in block.instructions {
                if case .call(let symbol, let callee, let arguments, let result, let canThrow) = instruction,
                   isSuspendCall(
                    symbol: symbol,
                    callee: callee,
                    suspendFunctionSymbols: suspendFunctionSymbols,
                    suspendFunctionNames: suspendFunctionNames
                   ),
                   let nextResumeLabel {
                    let resumeLabelExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
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

                    let suspensionResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                    lowered.append(
                        .call(
                            symbol: symbol,
                            callee: callee,
                            arguments: arguments,
                            result: suspensionResult,
                            canThrow: canThrow
                        )
                    )

                    let suspendedExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
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
                    continue
                }

                switch instruction {
                case .returnValue(let value):
                    let exitValueExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
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
                    let unitExpr = module.arena.appendExpr(.unit)
                    let exitValueExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
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

    private struct SuspendStateBlock {
        let resumeLabel: Int64
        let instructions: [KIRInstruction]
    }

    private struct CFGBlock {
        let id: Int
        let instructions: [KIRInstruction]
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
            var chunk: [KIRInstruction] = []
            chunk.reserveCapacity(cfgBlock.instructions.count)

            for instruction in cfgBlock.instructions {
                chunk.append(instruction)

                guard case .call(let symbol, let callee, _, _, _) = instruction else {
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
            let blockInstructions = Array(instructions[range.start..<range.end])
            let terminator = blockInstructions.last

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

