import Foundation

final class CoroutineLoweringPass: LoweringPass {
    /// Internal visibility is required for cross-file extension decomposition
    static let name = "CoroutineLowering"

    typealias LoweredSuspendFunction = (name: InternedString, symbol: SymbolID)

    struct SuspendCallLookupKey: Hashable {
        let name: InternedString
        let arity: Int
    }

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        let callCallees: Set<InternedString> = [
            ctx.interner.intern("runBlocking"),
            ctx.interner.intern("launch"),
            ctx.interner.intern("async"),
            ctx.interner.intern("coroutineScope"),
            ctx.interner.intern("flow"),
            ctx.interner.intern("emit"),
            ctx.interner.intern("collect"),
            ctx.interner.intern("map"),
            ctx.interner.intern("filter"),
            ctx.interner.intern("take"),
            ctx.interner.intern("kk_flow_create"),
            ctx.interner.intern("kk_flow_emit"),
            ctx.interner.intern("kk_flow_collect"),
        ]
        let virtualCallees: Set<InternedString> = [
            ctx.interner.intern("collect"),
            ctx.interner.intern("map"),
            ctx.interner.intern("filter"),
            ctx.interner.intern("take"),
        ]
        for decl in module.arena.declarations {
            if case let .function(function) = decl {
                if function.isSuspend { return true }
                for instruction in function.body {
                    switch instruction {
                    case let .call(_, callee, _, _, _, _, _):
                        if callCallees.contains(callee) {
                            return true
                        }
                    case let .virtualCall(_, callee, _, _, _, _, _, _):
                        if virtualCallees.contains(callee) {
                            return true
                        }
                    default:
                        break
                    }
                }
            }
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        // Lower flow { }, emit, map, filter, take, collect before suspend-function lowering.
        lowerFlowExpressions(module: module, ctx: ctx)

        let anyType = ctx.sema?.types.nullableAnyType ?? ctx.sema?.types.anyType
        let intType = ctx.sema?.types.make(.primitive(.int, .nonNull))
        let unitType = ctx.sema?.types.unitType
        let kxMiniRunBlockingCallee = ctx.interner.intern("runBlocking")
        let kxMiniLaunchCallee = ctx.interner.intern("launch")
        let kxMiniAsyncCallee = ctx.interner.intern("async")
        let kxMiniCoroutineScopeCallee = ctx.interner.intern("coroutineScope")
        let kxMiniDelayCallee = ctx.interner.intern("delay")
        let runtimeRunBlockingCallee = ctx.interner.intern("kk_kxmini_run_blocking")
        let runtimeLaunchCallee = ctx.interner.intern("kk_kxmini_launch")
        let runtimeAsyncCallee = ctx.interner.intern("kk_kxmini_async")
        let runtimeCoroutineScopeRunCallee = ctx.interner.intern("kk_coroutine_scope_run")
        let runtimeDelayCallee = ctx.interner.intern("kk_kxmini_delay")
        let flowCollectCallee = ctx.interner.intern("kk_flow_collect")
        let runtimeSuspendCallNames: Set<InternedString> = [kxMiniDelayCallee, runtimeDelayCallee]
        let kxMiniLauncherRuntimeCallees: [InternedString: InternedString] = [
            kxMiniRunBlockingCallee: runtimeRunBlockingCallee,
            kxMiniLaunchCallee: runtimeLaunchCallee,
            kxMiniAsyncCallee: runtimeAsyncCallee,
            kxMiniCoroutineScopeCallee: runtimeCoroutineScopeRunCallee,
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
                sema: ctx.sema
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
        let runtimeRunBlockingWithContCallee = ctx.interner.intern("kk_kxmini_run_blocking_with_cont")
        let kxMiniLauncherWithContCallees: [InternedString: InternedString] = [
            kxMiniRunBlockingCallee: ctx.interner.intern("kk_kxmini_run_blocking_with_cont"),
            kxMiniLaunchCallee: ctx.interner.intern("kk_kxmini_launch_with_cont"),
            kxMiniAsyncCallee: ctx.interner.intern("kk_kxmini_async_with_cont"),
            kxMiniCoroutineScopeCallee: ctx.interner.intern("kk_coroutine_scope_run_with_cont"),
        ]

        let rewriteContext = SuspendRewriteContext(
            module: module,
            ctx: ctx,
            anyType: anyType,
            intType: intType,
            flowCollectCallee: flowCollectCallee,
            continuationFactory: continuationFactory,
            launcherArgSetCallee: launcherArgSetCallee,
            runtimeRunBlockingWithContCallee: runtimeRunBlockingWithContCallee,
            kxMiniLauncherRuntimeCallees: kxMiniLauncherRuntimeCallees,
            kxMiniLauncherWithContCallees: kxMiniLauncherWithContCallees,
            loweredBySymbol: loweredBySymbol,
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
