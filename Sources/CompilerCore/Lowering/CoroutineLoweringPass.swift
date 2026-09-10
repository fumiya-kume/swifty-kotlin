
final class CoroutineLoweringPass: LoweringPass {
    /// Internal visibility is required for cross-file extension decomposition
    static let name = "CoroutineLowering"

    typealias LoweredSuspendFunction = (name: InternedString, symbol: SymbolID)

    struct SuspendCallLookupKey: Hashable, CustomStringConvertible {
        let name: InternedString
        let arity: Int

        var description: String {
            return "\(name):\(arity)"
        }
    }

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        module.ensureFeaturesScanned()
        if module.features.contains(.hasSuspendFunction) { return true }
        let coroutineCallees: Set<InternedString> = [
            ctx.interner.intern("runBlocking"),
            ctx.interner.intern("launch"),
            ctx.interner.intern("async"),
            ctx.interner.intern("produce"),
            ctx.interner.intern("startCoroutine"),
            ctx.interner.intern("createCoroutineUnintercepted"),
            ctx.interner.intern("withContext"),
            ctx.interner.intern("withTimeout"),
            ctx.interner.intern("withTimeoutOrNull"),
            ctx.interner.intern("suspendCoroutineUninterceptedOrReturn"),
            ctx.interner.intern("flow"),
            ctx.interner.intern("channelFlow"),
            ctx.interner.intern("callbackFlow"),
            ctx.interner.intern("emit"),
            ctx.interner.intern("collect"),
            ctx.interner.intern("collectLatest"),
            ctx.interner.intern("map"),
            ctx.interner.intern("filter"),
            ctx.interner.intern("take"),
            ctx.interner.intern("transform"),
            ctx.interner.intern("single"),
            ctx.interner.intern("takeWhile"),
            ctx.interner.intern("dropWhile"),
            ctx.interner.intern("flatMapConcat"),
            ctx.interner.intern("flatMapMerge"),
            ctx.interner.intern("flatMapLatest"),
            ctx.interner.intern("combine"),
            ctx.interner.intern("zip"),
            ctx.interner.intern("merge"),
            ctx.interner.intern("buffer"),
            ctx.interner.intern("conflate"),
            ctx.interner.intern("flowOn"),
            ctx.interner.intern("debounce"),
            ctx.interner.intern("sample"),
            ctx.interner.intern("delayEach"),
            ctx.interner.intern("kk_suspend_function_invoke_0"),
            ctx.interner.intern("kk_suspend_function_invoke"),
            ctx.interner.intern("kk_suspend_function_invoke_2"),
            ctx.interner.intern("kk_flow_create"),
            ctx.interner.intern("kk_channel_flow_create"),
            ctx.interner.intern("kk_callback_flow_create"),
            ctx.interner.intern("kk_flow_emit"),
            ctx.interner.intern("kk_flow_collect"),
        ]
        return !coroutineCallees.isDisjoint(with: module.usedCallees)
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        // Lower Flow builder/operators before suspend-function lowering.
        lowerFlowExpressions(module: module, ctx: ctx)

        let anyType = ctx.sema?.types.nullableAnyType ?? ctx.sema?.types.anyType
        let intType = ctx.sema?.types.make(.primitive(.int, .nonNull))
        let unitType = ctx.sema?.types.unitType
        let sequenceClassSymbol = ctx.sema?.symbols.lookup(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("sequences"),
            ctx.interner.intern("Sequence"),
        ])
        let kxMiniRunBlockingCallee = ctx.interner.intern("runBlocking")
        let kxMiniLaunchCallee = ctx.interner.intern("launch")
        let kxMiniAsyncCallee = ctx.interner.intern("async")
        let kxMiniProduceCallee = ctx.interner.intern("produce")
        let kxMiniWithContextCallee = ctx.interner.intern("withContext")
        let kxMiniWithTimeoutCallee = ctx.interner.intern("withTimeout")
        let kxMiniWithTimeoutOrNullCallee = ctx.interner.intern("withTimeoutOrNull")
        let suspendCoroutineUninterceptedOrReturnCallee = ctx.interner.intern("suspendCoroutineUninterceptedOrReturn")
        let kxMiniDelayCallee = ctx.interner.intern("delay")
        let kxMiniYieldCallee = ctx.interner.intern("yield")
        let startCoroutineCallee = ctx.interner.intern("startCoroutine")
        let createCoroutineCallee = ctx.interner.intern("createCoroutine")
        let createCoroutineUninterceptedCallee = ctx.interner.intern("createCoroutineUnintercepted")
        let startCoroutineUninterceptedOrReturnCallee = ctx.interner.intern("startCoroutineUninterceptedOrReturn")
        let runtimeRunBlockingCallee = ctx.interner.intern("kk_kxmini_run_blocking")
        let runtimeLaunchCallee = ctx.interner.intern("kk_kxmini_launch")
        let runtimeAsyncCallee = ctx.interner.intern("kk_kxmini_async")
        let runtimeProduceCallee = ctx.interner.intern("kk_produce")
        let runtimeDelayCallee = ctx.interner.intern("kk_kxmini_delay")
        let runtimeYieldCallee = ctx.interner.intern("kk_coroutine_yield")
        let runtimeSequenceBuilderYieldCallee = ctx.interner.intern("__kk_sequence_builder_yield")
        let runtimeIteratorBuilderYieldCallee = ctx.interner.intern("__kk_iterator_builder_yield")
        let runtimeWithTimeoutCallee = ctx.interner.intern("kk_with_timeout")
        let runtimeWithTimeoutOrNullCallee = ctx.interner.intern("kk_with_timeout_or_null")
        let flowCollectCallee = ctx.interner.intern("kk_flow_collect")
        let flowCollectLatestCallee = ctx.interner.intern("__kk_flow_collectLatest")
        let runtimeSuspendCallNames: Set<InternedString> = [
            kxMiniDelayCallee,
            runtimeDelayCallee,
            kxMiniYieldCallee,
            runtimeYieldCallee,
            runtimeSequenceBuilderYieldCallee,
            runtimeIteratorBuilderYieldCallee,
            suspendCoroutineUninterceptedOrReturnCallee,
            ctx.interner.intern("kk_suspend_function_invoke_0"),
            ctx.interner.intern("kk_suspend_function_invoke"),
            ctx.interner.intern("kk_suspend_function_invoke_2"),
            ctx.interner.intern("kk_suspend_coroutine"),
            // CORO-004: await / join are real suspend points that consume the
            // caller continuation so the runtime can resume them without blocking.
            ctx.interner.intern("kk_kxmini_async_await"),
            ctx.interner.intern("kk_job_join"),
            ctx.interner.intern("kk_job_await_completion"),
            // CORO-004: withContext suspends the caller while the dispatched block
            // runs on another dispatcher; the runtime resumes via callerState.resume.
            kxMiniWithContextCallee,
        ]
        let kxMiniLauncherRuntimeCallees: [InternedString: InternedString] = [
            kxMiniRunBlockingCallee: runtimeRunBlockingCallee,
            kxMiniLaunchCallee: runtimeLaunchCallee,
            kxMiniAsyncCallee: runtimeAsyncCallee,
            kxMiniProduceCallee: runtimeProduceCallee,
            runtimeProduceCallee: runtimeProduceCallee,
        ]

        let suspendFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl, function.isSuspend else {
                return nil
            }
            return function
        }
        let suspendFunctionSymbols = Set(suspendFunctions.map(\.symbol))
        let suspendFunctionNames = Set(suspendFunctions.map(\.name))

        var existingFunctionNames: Set<InternedString> = Set(module.arena.declarations.compactMap { decl in
            guard case let .function(function) = decl else {
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
        var existingSymbolFQNames: Set<[InternedString]> = Set(ctx.sema?.symbols.allSymbols().lazy.map(\.fqName) ?? [])

        for suspendFunction in suspendFunctions {
            suspendFunctionArityBySymbol[suspendFunction.symbol] = suspendFunction.params.count
            let rawLowered = ctx.interner.intern("kk_suspend_" + ctx.interner.resolve(suspendFunction.name))
            let loweredName = uniqueFunctionName(
                preferred: rawLowered,
                existingFunctionNames: &existingFunctionNames,
                interner: ctx.interner
            )
            let loweredFunctionSymbol = defineSyntheticCoroutineFunctionSymbol(
                original: suspendFunction,
                loweredName: loweredName,
                nextSyntheticSymbol: &nextSyntheticSymbol,
                sema: ctx.sema,
                interner: ctx.interner
            )
            let loweredSymbol = loweredFunctionSymbol.kirSymbol
            let loweredSemaSymbol = loweredFunctionSymbol.semaSymbol
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
                owner: loweredSemaSymbol ?? loweredSymbol,
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
                runtimeYieldCallee: runtimeYieldCallee,
                sourceYieldCallee: kxMiniYieldCallee,
                suspendPlan: suspendLoweringPlan,
                spillSlotByExpr: continuationNominal?.spillSlotByExpr ?? [:],
                smTypes: StateMachineTypeContext(
                    continuationType: continuationType,
                    anyType: anyType ?? continuationType,
                    intType: intType,
                    unitType: unitType
                )
            )
            if let continuationNominal {
                _ = module.arena.appendDecl(.nominalType(KIRNominalType(symbol: continuationNominal.typeSymbol)))
            }
            let loweredFunction = KIRFunction(
                symbol: loweredSymbol,
                name: loweredName,
                params: suspendFunction.params + [
                    KIRParameter(symbol: continuationParameterSymbol, type: continuationType),
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
            if let loweredSemaSymbol {
                updateLoweredFunctionSignatureIfPossible(
                    loweredSymbol: loweredSemaSymbol,
                    continuationParameterSymbol: continuationParameterSymbol,
                    originalSymbol: suspendFunction.symbol,
                    continuationType: continuationType,
                    sema: ctx.sema
                )
            }
        }

        let launcherArgGetCallee = ctx.interner.intern("kk_coroutine_launcher_arg_get")
        let launcherThunkContext = LauncherThunkSynthesisContext(
            module: module,
            interner: ctx.interner,
            sema: ctx.sema,
            anyType: anyType,
            intType: intType,
            launcherArgGetCallee: launcherArgGetCallee,
            loweredBySymbol: loweredBySymbol,
            continuationTypeByLoweredSymbol: continuationTypeByLoweredSymbol
        )
        let launcherThunkByOriginalSymbol = synthesizeLauncherThunks(
            suspendFunctions: suspendFunctions,
            nextSyntheticSymbol: &nextSyntheticSymbol,
            existingFunctionNames: &existingFunctionNames,
            using: launcherThunkContext
        )
        let sequenceBuilderThunkByOriginalSymbol = synthesizeSequenceBuilderReceiverThunks(
            suspendFunctions: suspendFunctions,
            nextSyntheticSymbol: &nextSyntheticSymbol,
            existingFunctionNames: &existingFunctionNames,
            using: launcherThunkContext
        )

        let loweredByUniqueName = loweredByNameBuckets.reduce(into: [InternedString: (name: InternedString, symbol: SymbolID)]()) { partial, entry in
            guard entry.value.count == 1, let value = entry.value.first else {
                return
            }
            partial[entry.key] = value
        }
        var originalByLoweredName: [InternedString: (original: SymbolID, lowered: LoweredSuspendFunction)] = [:]
        for (original, lowered) in loweredBySymbol {
            originalByLoweredName[lowered.name] = (original: original, lowered: lowered)
        }
        let loweredByUniqueNameArity = loweredByNameArityBuckets.reduce(into: [SuspendCallLookupKey: (name: InternedString, symbol: SymbolID)]()) { partial, entry in
            guard entry.value.count == 1, let value = entry.value.first else {
                return
            }
            partial[entry.key] = value
        }
        let continuationFactory = ctx.interner.intern("kk_coroutine_continuation_new")
        let runtimeCreateCoroutineUninterceptedCallee = ctx.interner.intern("kk_create_coroutine_unintercepted")
        let runtimeStartCoroutineUninterceptedOrReturnCallee = ctx.interner.intern("kk_start_coroutine_unintercepted_or_return")
        let runtimeContinuationResumeCallee = ctx.interner.intern("kk_coroutine_continuation_resume")
        let launcherArgSetCallee = ctx.interner.intern("kk_coroutine_launcher_arg_set")
        let coroutineScopeLaunchCallee = ctx.interner.intern("kk_coroutine_scope_launch")
        let runtimeRunBlockingWithContCallee = ctx.interner.intern("kk_kxmini_run_blocking_with_cont")
        let kxMiniLauncherWithContCallees: [InternedString: InternedString] = [
            kxMiniRunBlockingCallee: ctx.interner.intern("kk_kxmini_run_blocking_with_cont"),
            kxMiniLaunchCallee: ctx.interner.intern("kk_kxmini_launch_with_cont"),
            kxMiniAsyncCallee: ctx.interner.intern("kk_kxmini_async_with_cont"),
            kxMiniProduceCallee: ctx.interner.intern("kk_kxmini_produce_with_cont"),
            runtimeProduceCallee: ctx.interner.intern("kk_kxmini_produce_with_cont"),
        ]

        let rewriteContext = SuspendRewriteContext(
            module: module,
            ctx: ctx,
            anyType: anyType,
            intType: intType,
            unitType: unitType,
            flowCollectCallee: flowCollectCallee,
            flowCollectLatestCallee: flowCollectLatestCallee,
            withContextCallee: kxMiniWithContextCallee,
            runtimeWithContextCallee: ctx.interner.intern("kk_with_context"),
            withTimeoutCallee: kxMiniWithTimeoutCallee,
            runtimeWithTimeoutCallee: runtimeWithTimeoutCallee,
            withTimeoutOrNullCallee: kxMiniWithTimeoutOrNullCallee,
            runtimeWithTimeoutOrNullCallee: runtimeWithTimeoutOrNullCallee,
            yieldCallee: kxMiniYieldCallee,
            runtimeYieldCallee: runtimeYieldCallee,
            startCoroutineCallee: startCoroutineCallee,
            createCoroutineCallee: createCoroutineCallee,
            createCoroutineUninterceptedCallee: createCoroutineUninterceptedCallee,
            startCoroutineUninterceptedOrReturnCallee: startCoroutineUninterceptedOrReturnCallee,
            runtimeCreateCoroutineUninterceptedCallee: runtimeCreateCoroutineUninterceptedCallee,
            runtimeStartCoroutineUninterceptedOrReturnCallee: runtimeStartCoroutineUninterceptedOrReturnCallee,
            runtimeContinuationResumeCallee: runtimeContinuationResumeCallee,
            continuationFactory: continuationFactory,
            directSuspendCallCallee: ctx.interner.intern("kk_coroutine_call_direct_suspend"),
            launcherArgSetCallee: launcherArgSetCallee,
            runtimeRunBlockingWithContCallee: runtimeRunBlockingWithContCallee,
            kxMiniLauncherRuntimeCallees: kxMiniLauncherRuntimeCallees,
            kxMiniLauncherWithContCallees: kxMiniLauncherWithContCallees,
            coroutineScopeLaunchCallee: coroutineScopeLaunchCallee,
            sequenceBuilderBuildCallee: ctx.interner.intern("__kk_sequence_builder_build"),
            sequenceBuilderBuildCoroCallee: ctx.interner.intern("__kk_sequence_builder_build_coro"),
            sequenceBuilderYieldAllCallee: ctx.interner.intern("__kk_sequence_builder_yieldAll"),
            sequenceBuilderYieldCallee: ctx.interner.intern("__kk_sequence_builder_yield"),
            sequenceClassSymbol: sequenceClassSymbol,
            iteratorBuilderBuildCallee: ctx.interner.intern("__kk_iterator_builder_build"),
            iteratorBuilderBuildCoroCallee: ctx.interner.intern("__kk_iterator_builder_build_coro"),
            sequenceBuilderThunkByOriginalSymbol: sequenceBuilderThunkByOriginalSymbol,
            loweredBySymbol: loweredBySymbol,
            originalByLoweredName: originalByLoweredName,
            continuationTypeByLoweredSymbol: continuationTypeByLoweredSymbol,
            suspendFunctionArityBySymbol: suspendFunctionArityBySymbol,
            loweredByUniqueNameArity: loweredByUniqueNameArity,
            loweredByUniqueName: loweredByUniqueName,
            launcherThunkByOriginalSymbol: launcherThunkByOriginalSymbol
        )
        rewriteSuspendFunctionsAndCallSites(using: rewriteContext)
        module.recordLowering(Self.name)
    }

    func nextAvailableSyntheticSymbol(module: KIRModule, sema: SemaModule?) -> Int32 {
        var maxRaw: Int32 = 0
        for decl in module.arena.declarations {
            switch decl {
            case let .function(function):
                maxRaw = max(maxRaw, function.symbol.rawValue + 1)
            case let .global(global):
                maxRaw = max(maxRaw, global.symbol.rawValue + 1)
            case let .nominalType(nominal):
                maxRaw = max(maxRaw, nominal.symbol.rawValue + 1)
            }
        }
        if let sema {
            maxRaw = max(maxRaw, Int32(sema.symbols.count))
        }
        return maxRaw
    }

    func allocateSyntheticSymbol(
        _ nextSyntheticSymbol: inout Int32,
        sema: SemaModule?,
        interner: StringInterner
    ) -> SymbolID {
        // Continuation-parameter and lowered-function sema symbols are drawn from
        // the dense sema id space (sema.symbols.define). A separate integer
        // counter would overlap that space -- and because codegen resolves a
        // `.symbolRef` to a same-id parameter before a same-id function (see
        // NativeEmitter+EmissionConstants), a lowered function symbol that
        // collides with a continuation-parameter symbol makes a suspend entry
        // point resolve to a data pointer, crashing at run time. Reserve every
        // synthetic KIR symbol from the same sema id space so ids stay unique.
        if let sema {
            let uniqueName = interner.intern("$kk_coro_synthetic_\(sema.symbols.count)")
            return sema.symbols.define(
                kind: .function,
                name: uniqueName,
                fqName: [uniqueName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
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
