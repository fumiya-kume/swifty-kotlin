
struct StateMachineTypeContext {
    let continuationType: TypeID
    let anyType: TypeID
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
        runtimeYieldCallee: InternedString,
        sourceYieldCallee: InternedString,
        suspendPlan: SuspendLoweringPlan,
        spillSlotByExpr: [KIRExprID: Int64],
        smTypes: StateMachineTypeContext
    ) -> [KIRInstruction] {
        let continuationType = smTypes.continuationType
        let anyType = smTypes.anyType
        let intType = smTypes.intType
        let unitType = smTypes.unitType
        let enterCallee = interner.intern("kk_coroutine_state_enter")
        let setLabelCallee = interner.intern("kk_coroutine_state_set_label")
        let exitCallee = interner.intern("kk_coroutine_state_exit")
        let setSpillCallee = interner.intern("kk_coroutine_state_set_spill")
        let getSpillCallee = interner.intern("kk_coroutine_state_get_spill")
        let setCompletionCallee = interner.intern("kk_coroutine_state_set_completion")
        let getCompletionCallee = interner.intern("kk_coroutine_state_get_completion")
        let getThrownExceptionCallee = interner.intern("kk_coroutine_state_get_thrown_exception")
        let suspendedProvider = interner.intern("kk_coroutine_suspended")
        let checkCancellationCallee = interner.intern("kk_coroutine_check_cancellation")
        let sourceDelayCallee = interner.intern("delay")
        let suspendCoroutineRuntimeCallee = interner.intern("kk_suspend_coroutine")
        let suspendCoroutineUninterceptedOrReturnCallee = interner.intern("suspendCoroutineUninterceptedOrReturn")
        // CORO-004: runtime suspend callees that take the caller continuation as a
        // trailing argument so they can resume the awaiting coroutine without blocking.
        let continuationConsumingRuntimeCallees: Set<InternedString> = [
            interner.intern("kk_kxmini_async_await"),
            interner.intern("kk_job_join"),
            interner.intern("kk_job_await_completion"),
        ]
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

        let continuationExpr = module.arena.appendTemporary(type: continuationType
        )
        lowered.append(.constValue(result: continuationExpr, value: .symbolRef(continuationParameterSymbol)))

        let functionIDExpr = module.arena.appendTemporary(type: intType
        )
        lowered.append(.constValue(result: functionIDExpr, value: .intLiteral(Int64(loweredSymbol.rawValue))))

        let resumeLabelExpr = module.arena.appendTemporary(type: intType
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

        // Only the entry block and actual suspension continuations can be
        // entered from the dispatcher. Ordinary CFG blocks depend on values
        // defined by their predecessors and have no spill reload prologue.
        for block in stateBlocks where block.resumeLabel == stateBlocks.first?.resumeLabel
            || transitionsByResumeLabel[block.resumeLabel] != nil
        {
            let expectedResumeExpr = module.arena.appendTemporary(type: intType
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
                    let completionTokenExpr = module.arena.appendTemporary(type: anyType
                    )
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: getCompletionCallee,
                            arguments: [continuationExpr],
                            result: completionTokenExpr,
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                    lowered.append(.copy(from: completionTokenExpr, to: callResultExpr))
                }

                let thrownExceptionExpr = module.arena.appendTemporary(type: intType
                )
                lowered.append(
                    .call(
                        symbol: nil,
                        callee: getThrownExceptionCallee,
                        arguments: [continuationExpr],
                        result: thrownExceptionExpr,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
                let throwLabel = Int32(4000 + block.resumeLabel * 2)
                let continueLabel = Int32(4000 + block.resumeLabel * 2 + 1)
                lowered.append(
                    .jumpIfNotNull(
                        value: thrownExceptionExpr,
                        target: throwLabel
                    )
                )

                // CORO-002: Check cancellation after resuming from suspension point.
                // If cancelled, kk_coroutine_check_cancellation writes a
                // CancellationException into the original call's thrown slot so
                // surrounding try/catch blocks can observe it.
                let cancelCheckResult = module.arena.appendTemporary(type: intType
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
                lowered.append(.jump(continueLabel))
                lowered.append(.label(throwLabel))
                if let thrownResultSlot = transition.suspendingInstructionCallInfo?.thrownResult {
                    // STDLIB-CORO-BUG-03: this suspend call sits inside a
                    // try/catch (or similar) region, which tracks in-flight
                    // exceptions via a value in thrownResultSlot rather than a
                    // native throw -- see the jumpIfNotNull checks generated
                    // for the surrounding try elsewhere in this function.
                    // Route the resumed exception through that same slot
                    // instead of hard-rethrowing past it, otherwise the
                    // surrounding catch never observes it. The function has
                    // not finished (the exception may be caught locally), so
                    // its continuation must stay alive -- kk_coroutine_state_exit
                    // only runs once, at the function's real exit point.
                    lowered.append(.copy(from: thrownExceptionExpr, to: thrownResultSlot))
                } else {
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: exitCallee,
                            arguments: [continuationExpr, thrownExceptionExpr],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                    lowered.append(.rethrow(value: thrownExceptionExpr))
                }
                lowered.append(.label(continueLabel))
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

                    let resumeLabelExpr = module.arena.appendTemporary(type: intType
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

                    let userResultExpr = suspendCallInfo.result
                    let suspendTokenResult = module.arena.appendTemporary(type: anyType
                    )
                    let loweredSuspendCallee: InternedString
                    var loweredSuspendArguments: [KIRExprID]
                    if suspendCallInfo.callee == suspendCoroutineUninterceptedOrReturnCallee {
                        guard let blockExpr = suspendCallInfo.arguments.first else {
                            lowered.append(instruction)
                            continue
                        }
                        loweredSuspendCallee = interner.intern("kk_function_invoke")
                        loweredSuspendArguments = [blockExpr, continuationExpr]
                    } else if suspendCallInfo.callee == sourceYieldCallee {
                        loweredSuspendCallee = runtimeYieldCallee
                        loweredSuspendArguments = suspendCallInfo.arguments
                        loweredSuspendArguments.append(continuationExpr)
                    } else {
                        loweredSuspendCallee = suspendCallInfo.callee == sourceDelayCallee ? runtimeDelayCallee : suspendCallInfo.callee
                        loweredSuspendArguments = suspendCallInfo.arguments
                        if suspendCallInfo.callee == sourceDelayCallee {
                            loweredSuspendArguments.append(continuationExpr)
                        } else if continuationConsumingRuntimeCallees.contains(suspendCallInfo.callee) {
                            // CORO-004: append the caller continuation so await / join can
                            // resume the coroutine via the runtime instead of blocking.
                            loweredSuspendArguments.append(continuationExpr)
                        }
                    }
                    if suspendCallInfo.callee == suspendCoroutineRuntimeCallee {
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
                                result: suspendTokenResult,
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
                                result: suspendTokenResult,
                                canThrow: suspendCallInfo.canThrow,
                                thrownResult: suspendCallInfo.thrownResult,
                                isSuperCall: suspendCallInfo.isSuperCall
                            )
                        )
                    }

                    let suspendedExpr = module.arena.appendTemporary(type: anyType
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
                    lowered.append(.returnIfEqual(lhs: suspendTokenResult, rhs: suspendedExpr))
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: setCompletionCallee,
                            arguments: [continuationExpr, suspendTokenResult],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                    if let userResultExpr {
                        lowered.append(.copy(from: suspendTokenResult, to: userResultExpr))
                    }
                    continue
                }

                switch instruction {
                case let .returnValue(value):
                    let exitValueExpr = module.arena.appendTemporary(type: continuationType
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
                    let exitValueExpr = module.arena.appendTemporary(type: continuationType
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
        let instructions: [IndexedInstruction]
        let successors: [Int]
    }
}
