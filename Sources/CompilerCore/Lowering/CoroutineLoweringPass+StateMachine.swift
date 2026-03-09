import Foundation

struct StateMachineTypeContext {
    let continuationType: TypeID
    let intType: TypeID?
    let unitType: TypeID?
}

extension CoroutineLoweringPass {
    func lowerSuspendBodyToStateMachineSkeleton(
        originalBody: [KIRInstruction],
        continuationParameterSymbol: SymbolID,
        loweredSymbol: SymbolID,
        module: KIRModule,
        interner: StringInterner,
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>,
        runtimeSuspendCallNames: Set<InternedString>,
        runtimeDelayCallee: InternedString,
        suspendPlan: SuspendLoweringPlan,
        spillSlotByExpr: [KIRExprID: Int64],
        smTypes: StateMachineTypeContext
    ) -> [KIRInstruction] {
        let continuationType = smTypes.continuationType
        let intType = smTypes.intType
        let unitType = smTypes.unitType
        let enterCallee = interner.intern("kk_coroutine_state_enter")
        let setLabelCallee = interner.intern("kk_coroutine_state_set_label")
        let exitCallee = interner.intern("kk_coroutine_state_exit")
        let setSpillCallee = interner.intern("kk_coroutine_state_set_spill")
        let getSpillCallee = interner.intern("kk_coroutine_state_get_spill")
        let setCompletionCallee = interner.intern("kk_coroutine_state_set_completion")
        let getCompletionCallee = interner.intern("kk_coroutine_state_get_completion")
        let suspendedProvider = interner.intern("kk_coroutine_suspended")
        let checkCancellationCallee = interner.intern("kk_coroutine_check_cancellation")
        let sourceDelayCallee = interner.intern("delay")
        let stateBlocks = suspendPlan.stateBlocks
        let transitionsByResumeLabel = suspendPlan.transitionsByResumeLabel
        let spillPlan = suspendPlan.spillPlan

        var lowered: [KIRInstruction] = []
        lowered.reserveCapacity(originalBody.count * 6 + 24)

        func slotForSpillExpr(_ exprID: KIRExprID) -> Int64? {
            if let overridden = spillSlotByExpr[exprID] {
                return overridden
            }
            return spillPlan.slotByExpr[exprID]
        }

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
                canThrow: false,
                thrownResult: nil
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
                    guard let slot = slotForSpillExpr(exprID) else {
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
                            canThrow: false,
                            thrownResult: nil
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
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                }

                // CORO-002: Check cancellation after resuming from suspension point.
                // If cancelled, kk_coroutine_check_cancellation writes a
                // CancellationException into the original call's thrown slot so
                // surrounding try/catch blocks can observe it.
                let cancelCheckResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: intType
                )
                lowered.append(
                    .call(
                        symbol: nil,
                        callee: checkCancellationCallee,
                        arguments: [continuationExpr],
                        result: cancelCheckResult,
                        canThrow: true,
                        thrownResult: transition.suspendingInstructionCallInfo?.thrownResult
                    )
                )
            }
            let nextResumeLabel = stateBlocks.indices.contains(index + 1)
                ? stateBlocks[index + 1].resumeLabel
                : nil

            for stateInstruction in block.instructions {
                let instruction = stateInstruction.instruction
                let suspendCallInfo = extractCallInfo(instruction)
                if let suspendCallInfo,
                   isSuspendCall(
                       symbol: suspendCallInfo.symbol,
                       callee: suspendCallInfo.callee,
                       suspendFunctionSymbols: suspendFunctionSymbols,
                       suspendFunctionNames: suspendFunctionNames,
                       runtimeSuspendCallNames: runtimeSuspendCallNames
                   ),
                   let nextResumeLabel
                {
                    let spilledExprs = spillPlan.exprsByTransitionSource[stateInstruction.sourceIndex] ?? []
                    for exprID in spilledExprs {
                        guard let slot = slotForSpillExpr(exprID) else {
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
                                canThrow: false,
                                thrownResult: nil
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
                            canThrow: false,
                            thrownResult: nil
                        )
                    )

                    let suspensionResult = suspendCallInfo.result ?? module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: continuationType
                    )
                    let loweredSuspendCallee = suspendCallInfo.callee == sourceDelayCallee ? runtimeDelayCallee : suspendCallInfo.callee
                    var loweredSuspendArguments = suspendCallInfo.arguments
                    if suspendCallInfo.callee == sourceDelayCallee {
                        loweredSuspendArguments.append(continuationExpr)
                    }
                    if suspendCallInfo.isVirtual,
                       case let .virtualCall(_, _, receiver, _, _, _, _, dispatch) = suspendCallInfo.originalInstruction
                    {
                        lowered.append(
                            .virtualCall(
                                symbol: suspendCallInfo.symbol,
                                callee: loweredSuspendCallee,
                                receiver: receiver,
                                arguments: loweredSuspendArguments,
                                result: suspensionResult,
                                canThrow: suspendCallInfo.canThrow,
                                thrownResult: suspendCallInfo.thrownResult,
                                dispatch: dispatch
                            )
                        )
                    } else {
                        lowered.append(
                            .call(
                                symbol: suspendCallInfo.symbol,
                                callee: loweredSuspendCallee,
                                arguments: loweredSuspendArguments,
                                result: suspensionResult,
                                canThrow: suspendCallInfo.canThrow,
                                thrownResult: suspendCallInfo.thrownResult,
                                isSuperCall: suspendCallInfo.isSuperCall
                            )
                        )
                    }

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
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                    lowered.append(.returnIfEqual(lhs: suspensionResult, rhs: suspendedExpr))
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: setCompletionCallee,
                            arguments: [continuationExpr, suspensionResult],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                    continue
                }

                switch instruction {
                case let .returnValue(value):
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
                            canThrow: false,
                            thrownResult: nil
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
                            canThrow: false,
                            thrownResult: nil
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

    func stateDispatchLabel(for resumeLabel: Int64) -> Int32 {
        Int32(1000 + resumeLabel)
    }

    struct IndexedInstruction {
        let sourceIndex: Int
        let instruction: KIRInstruction
    }

    struct SuspendStateBlock {
        let resumeLabel: Int64
        let instructions: [IndexedInstruction]
    }

    struct SuspendTransition {
        let sourceInstructionIndex: Int
        let callResultExpr: KIRExprID?
        let suspendingInstructionCallInfo: CallInfo?
    }

    struct SpillPlan {
        let slotByExpr: [KIRExprID: Int64]
        let exprsByTransitionSource: [Int: [KIRExprID]]
    }

    struct SuspendLoweringPlan {
        let stateBlocks: [SuspendStateBlock]
        let transitionsByResumeLabel: [Int64: SuspendTransition]
        let spillPlan: SpillPlan
    }

    struct CFGBlock {
        let id: Int
        let instructions: [IndexedInstruction]
        let successors: [Int]
    }
}
