import Foundation

final class CoroutineLoweringPass: LoweringPass {
    // Internal visibility is required for cross-file extension decomposition
    static let name = "CoroutineLowering"

    private struct SuspendCallLookupKey: Hashable {
        let name: InternedString
        let arity: Int
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        let anyType = ctx.sema?.types.nullableAnyType ?? ctx.sema?.types.anyType
        let intType = ctx.sema?.types.make(.primitive(.int, .nonNull))
        let unitType = ctx.sema?.types.unitType
        let kxMiniRunBlockingCallee = ctx.interner.intern("runBlocking")
        let kxMiniLaunchCallee = ctx.interner.intern("launch")
        let kxMiniAsyncCallee = ctx.interner.intern("async")
        let kxMiniDelayCallee = ctx.interner.intern("delay")
        let runtimeRunBlockingCallee = ctx.interner.intern("kk_kxmini_run_blocking")
        let runtimeLaunchCallee = ctx.interner.intern("kk_kxmini_launch")
        let runtimeAsyncCallee = ctx.interner.intern("kk_kxmini_async")
        let runtimeDelayCallee = ctx.interner.intern("kk_kxmini_delay")
        let runtimeSuspendCallNames: Set<InternedString> = [kxMiniDelayCallee, runtimeDelayCallee]
        let kxMiniLauncherRuntimeCallees: [InternedString: InternedString] = [
            kxMiniRunBlockingCallee: runtimeRunBlockingCallee,
            kxMiniLaunchCallee: runtimeLaunchCallee,
            kxMiniAsyncCallee: runtimeAsyncCallee
        ]

        let suspendFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl, function.isSuspend else {
                return nil
            }
            return function
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
        var continuationTypeByLoweredSymbol: [SymbolID: TypeID] = [:]
        var suspendFunctionArityBySymbol: [SymbolID: Int] = [:]
        var loweredByNameBuckets: [InternedString: [(name: InternedString, symbol: SymbolID)]] = [:]
        var loweredByNameArityBuckets: [SuspendCallLookupKey: [(name: InternedString, symbol: SymbolID)]] = [:]
        var existingSymbolFQNames: Set<[InternedString]> = Set(ctx.sema?.symbols.allSymbols().map(\.fqName) ?? [])

        for suspendFunction in suspendFunctions {
            suspendFunctionArityBySymbol[suspendFunction.symbol] = suspendFunction.params.count
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
            let suspendLoweringPlan = analyzeSuspendLoweringPlan(
                originalBody: suspendFunction.body,
                suspendFunctionSymbols: suspendFunctionSymbols,
                suspendFunctionNames: suspendFunctionNames,
                runtimeSuspendCallNames: runtimeSuspendCallNames
            )
            let continuationNominal = synthesizeContinuationNominalIfPossible(
                original: suspendFunction,
                loweredName: loweredName,
                plan: suspendLoweringPlan,
                sema: ctx.sema,
                interner: ctx.interner,
                existingSymbolFQNames: &existingSymbolFQNames
            )
            let continuationType = continuationNominal?.continuationType
                ?? (ctx.sema?.types.nullableAnyType ?? suspendFunction.returnType)
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
                runtimeSuspendCallNames: runtimeSuspendCallNames,
                runtimeDelayCallee: runtimeDelayCallee,
                suspendPlan: suspendLoweringPlan,
                spillSlotByExpr: continuationNominal?.spillSlotByExpr ?? [:],
                continuationType: continuationType,
                intType: intType,
                unitType: unitType
            )
            if let continuationNominal {
                _ = module.arena.appendDecl(.nominalType(KIRNominalType(symbol: continuationNominal.typeSymbol)))
            }
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
            continuationTypeByLoweredSymbol[loweredSymbol] = continuationType
            suspendFunctionArityBySymbol[loweredSymbol] = suspendFunction.params.count
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

        var launcherThunkByOriginalSymbol: [SymbolID: (name: InternedString, symbol: SymbolID)] = [:]

        let launcherArgGetCallee = ctx.interner.intern("kk_coroutine_launcher_arg_get")
        for suspendFunction in suspendFunctions where suspendFunction.params.count > 0 {
            guard let loweredTarget = loweredBySymbol[suspendFunction.symbol] else {
                continue
            }
            let rawThunkName = ctx.interner.intern(
                "kk_launcher_thunk_" + ctx.interner.resolve(suspendFunction.name)
            )
            let thunkName = uniqueFunctionName(
                preferred: rawThunkName,
                existingFunctionNames: &existingFunctionNames,
                interner: ctx.interner
            )
            let thunkSymbol = allocateSyntheticSymbol(&nextSyntheticSymbol)
            let thunkContParamSymbol = allocateSyntheticSymbol(&nextSyntheticSymbol)
            let contType = continuationTypeByLoweredSymbol[loweredTarget.symbol]
                ?? anyType ?? suspendFunction.returnType

            var thunkBody: [KIRInstruction] = []

            let contRef = module.arena.appendExpr(
                .symbolRef(thunkContParamSymbol),
                type: contType
            )

            var callArgExprs: [KIRExprID] = []
            for paramIndex in 0..<suspendFunction.params.count {
                let slotExpr = module.arena.appendExpr(
                    .intLiteral(Int64(paramIndex)),
                    type: intType
                )
                let argResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: suspendFunction.params[paramIndex].type
                )
                thunkBody.append(
                    .call(
                        symbol: nil,
                        callee: launcherArgGetCallee,
                        arguments: [contRef, slotExpr],
                        result: argResult,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
                callArgExprs.append(argResult)
            }

            callArgExprs.append(contRef)

            let callResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: contType
            )
            thunkBody.append(
                .call(
                    symbol: loweredTarget.symbol,
                    callee: loweredTarget.name,
                    arguments: callArgExprs,
                    result: callResult,
                    canThrow: true,
                    thrownResult: nil
                )
            )
            thunkBody.append(.returnValue(callResult))

            let thunkFunction = KIRFunction(
                symbol: thunkSymbol,
                name: thunkName,
                params: [KIRParameter(symbol: thunkContParamSymbol, type: contType)],
                returnType: contType,
                body: thunkBody,
                isSuspend: false,
                isInline: false
            )
            _ = module.arena.appendDecl(.function(thunkFunction))
            launcherThunkByOriginalSymbol[suspendFunction.symbol] = (name: thunkName, symbol: thunkSymbol)
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
        let launcherArgSetCallee = ctx.interner.intern("kk_coroutine_launcher_arg_set")
        let kxMiniLauncherWithContCallees: [InternedString: InternedString] = [
            kxMiniRunBlockingCallee: ctx.interner.intern("kk_kxmini_run_blocking_with_cont"),
            kxMiniLaunchCallee: ctx.interner.intern("kk_kxmini_launch_with_cont"),
            kxMiniAsyncCallee: ctx.interner.intern("kk_kxmini_async_with_cont")
        ]

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)
            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let canThrow, _, _) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }

                if symbol == nil,
                   let runtimeLauncherCallee = kxMiniLauncherRuntimeCallees[callee] {
                    guard arguments.count >= 1 else {
                        ctx.diagnostics.error(
                            "KSWIFTK-CORO-0001",
                            "Coroutine launcher '\(ctx.interner.resolve(callee))' expects at least one suspend function reference argument.",
                            range: nil
                        )
                        loweredBody.append(instruction)
                        continue
                    }

                    guard let argumentExpr = module.arena.expr(arguments[0]),
                          case .symbolRef(let referencedSymbol) = argumentExpr,
                          let loweredTarget = loweredBySymbol[referencedSymbol] else {
                        ctx.diagnostics.error(
                            "KSWIFTK-CORO-0002",
                            "Coroutine launcher '\(ctx.interner.resolve(callee))' requires a suspend function reference argument.",
                            range: nil
                        )
                        loweredBody.append(instruction)
                        continue
                    }

                    let targetArity = suspendFunctionArityBySymbol[referencedSymbol] ?? 0
                    let extraArgs = Array(arguments.dropFirst())

                    guard extraArgs.count == targetArity else {
                        ctx.diagnostics.error(
                            "KSWIFTK-CORO-0003",
                            "Coroutine launcher '\(ctx.interner.resolve(callee))' passed \(extraArgs.count) argument(s) but referenced suspend function expects \(targetArity).",
                            range: nil
                        )
                        loweredBody.append(instruction)
                        continue
                    }

                    if targetArity == 0 {
                        let entryPointExpr = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)),
                            type: intType
                        )
                        loweredBody.append(
                            .constValue(
                                result: entryPointExpr,
                                value: .symbolRef(loweredTarget.symbol)
                            )
                        )

                        let entryFunctionID = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)),
                            type: intType
                        )
                        loweredBody.append(
                            .constValue(
                                result: entryFunctionID,
                                value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
                            )
                        )

                        loweredBody.append(
                            .call(
                                symbol: nil,
                                callee: runtimeLauncherCallee,
                                arguments: [entryPointExpr, entryFunctionID],
                                result: result,
                                canThrow: canThrow,
                                thrownResult: nil
                            )
                        )
                    } else {
                        guard let thunk = launcherThunkByOriginalSymbol[referencedSymbol] else {
                            preconditionFailure("Internal error: launcher thunk not found for suspend function '\(ctx.interner.resolve(loweredTarget.name))'")
                        }

                        let loweredFunctionIDExpr = module.arena.appendExpr(
                            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
                            type: intType
                        )
                        let contExpr = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)),
                            type: intType
                        )
                        loweredBody.append(
                            .call(
                                symbol: nil,
                                callee: continuationFactory,
                                arguments: [loweredFunctionIDExpr],
                                result: contExpr,
                                canThrow: false,
                                thrownResult: nil
                            )
                        )

                        for (index, argExpr) in extraArgs.enumerated() {
                            let slotExpr = module.arena.appendExpr(
                                .intLiteral(Int64(index)),
                                type: intType
                            )
                            loweredBody.append(
                                .call(
                                    symbol: nil,
                                    callee: launcherArgSetCallee,
                                    arguments: [contExpr, slotExpr, argExpr],
                                    result: nil,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                        }

                        let thunkRefExpr = module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)),
                            type: intType
                        )
                        loweredBody.append(
                            .constValue(
                                result: thunkRefExpr,
                                value: .symbolRef(thunk.symbol)
                            )
                        )

                        guard let runtimeWithContCallee = kxMiniLauncherWithContCallees[callee] else {
                            assertionFailure("Internal compiler error: missing runtime _with_cont callee mapping for launcher callee")
                            loweredBody.append(instruction)
                            continue
                        }

                        loweredBody.append(
                            .call(
                                symbol: nil,
                                callee: runtimeWithContCallee,
                                arguments: [thunkRefExpr, contExpr],
                                result: result,
                                canThrow: canThrow,
                                thrownResult: nil
                            )
                        )
                    }
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
                    type: continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? anyType
                )
                loweredBody.append(
                    .call(
                        symbol: nil,
                        callee: continuationFactory,
                        arguments: [continuationFunctionID],
                        result: continuationTemp,
                        canThrow: false,
                        thrownResult: nil
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
                        canThrow: canThrow,
                        thrownResult: nil
                    )
                )
            }
            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }

    func nextAvailableSyntheticSymbol(module: KIRModule, sema: SemaModule?) -> Int32 {
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

    func allocateSyntheticSymbol(_ nextSyntheticSymbol: inout Int32) -> SymbolID {
        let id = SymbolID(rawValue: nextSyntheticSymbol)
        nextSyntheticSymbol += 1
        return id
    }

    func uniqueFunctionName(
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
}
