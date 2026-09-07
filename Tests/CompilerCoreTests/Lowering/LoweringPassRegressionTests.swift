#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LoweringPassRegressionTests {
    @Test
    func testLoweringRewritesMainCallSites() throws {
        let fixture = try makeLoweringRewriteFixture()

        guard case let .function(loweredMain)? = fixture.module.arena.decl(fixture.mainID) else {
            Issue.record("expected lowered main function")
            return
        }

        let callees = extractCallees(from: loweredMain.body, interner: fixture.interner)
        #expect(callees.contains("__kk_uint_range_iterator"), "Callees: \(callees)")
        #expect(!callees.contains("kk_range_iterator"), "Callees: \(callees)")
        #expect(callees.contains("kk_range_hasNext"), "Callees: \(callees)")
        #expect(callees.contains("kk_range_next"), "Callees: \(callees)")
        #expect(!callees.contains("kk_for_lowered"), "Callees: \(callees)")
        // kk_when_select removed; select is now control flow (jumpIfEqual + copy + jump + label)
        #expect(!callees.contains("kk_when_select"), "Callees: \(callees)")
        // kk_property_access removed — PropertyLowering now emits direct accessor calls.
        // The test fixture uses symbol-less get/set calls, so they remain unchanged.
        #expect(!callees.contains("kk_property_access"), "Callees: \(callees)")
        #expect(callees.contains("get"), "Callees: \(callees)")
        #expect(callees.contains("set"), "Callees: \(callees)")
        #expect(callees.contains("kk_lambda_invoke"), "Callees: \(callees)")
        #expect(!callees.contains("inlineTarget"), "Callees: \(callees)")
        #expect(callees.contains("kk_coroutine_continuation_new"), "Callees: \(callees)")
        #expect(callees.contains("kk_suspend_suspendTarget"), "Callees: \(callees)")

        let throwFlags = extractThrowFlags(from: loweredMain.body, interner: fixture.interner)
        #expect(throwFlags["kk_coroutine_continuation_new"]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags["kk_suspend_suspendTarget"]?.allSatisfy { $0 == true } == true)
    }

    @Test
    func testLoweringBuildsSuspendStateMachineAndThrowFlags() throws {
        let fixture = try makeLoweringRewriteFixture()
        let loweredSuspend = try findKIRFunction(named: "kk_suspend_suspendTarget", in: fixture.module, interner: fixture.interner)

        #expect(loweredSuspend.params.count == 1)
        #expect(loweredSuspend.isSuspend == false)

        let loweredSuspendCallees = extractCallees(from: loweredSuspend.body, interner: fixture.interner)
        #expect(loweredSuspendCallees.contains("kk_coroutine_state_enter"))
        #expect(loweredSuspendCallees.contains("kk_coroutine_state_set_label"))
        #expect(loweredSuspendCallees.contains("kk_coroutine_state_set_completion"))
        #expect(loweredSuspendCallees.contains("kk_coroutine_state_get_completion"))
        #expect(loweredSuspendCallees.contains("kk_coroutine_state_exit"))

        let dispatchJumpCount = loweredSuspend.body.filter { instruction in
            if case .jumpIfEqual = instruction {
                return true
            }
            return false
        }.count
        // A suspend function with one suspension point needs at least 2 dispatch jumps:
        // one for label 1000 (entry) and one for label 1001 (resume point)
        #expect(dispatchJumpCount >= 2)

        let dispatchLabels = loweredSuspend.body.compactMap { instruction -> Int32? in
            if case let .label(id) = instruction {
                return id
            }
            return nil
        }
        // Coroutine state machine dispatch labels start at coroutineDispatchLabelBase
        #expect(dispatchLabels.contains(coroutineDispatchLabelBase))
        #expect(dispatchLabels.contains(coroutineDispatchLabelBase + 1))

        let hasSuspendGuard = loweredSuspend.body.contains { instruction in
            if case .returnIfEqual = instruction {
                return true
            }
            return false
        }
        #expect(hasSuspendGuard)

        let throwFlags = extractThrowFlags(from: loweredSuspend.body, interner: fixture.interner)
        #expect(loweredSuspendCallees.contains("kk_coroutine_call_direct_suspend"))
        #expect(throwFlags["kk_coroutine_call_direct_suspend"]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags["kk_coroutine_suspended"]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags["kk_coroutine_state_set_label"]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags["kk_coroutine_state_set_completion"]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags["kk_coroutine_state_get_completion"]?.allSatisfy { $0 == false } == true)
    }

    @Test
    func testLoweringNormalizesEmptyFunctionBody() throws {
        let fixture = try makeLoweringRewriteFixture()

        guard case let .function(loweredEmpty)? = fixture.module.arena.decl(fixture.emptyID) else {
            Issue.record("expected lowered empty function")
            return
        }
        #expect(loweredEmpty.body.last == .returnUnit)
        #expect(!loweredEmpty.body.isEmpty)
    }

    @Test
    func testCoroutineLoweringRewritesOverloadedSuspendCallsByNameAndArity() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSymbol = SymbolID(rawValue: 950)
        let suspendNoArgSymbol = SymbolID(rawValue: 951)
        let suspendOneArgSymbol = SymbolID(rawValue: 952)
        let suspendOneArgParam = SymbolID(rawValue: 953)

        let argValue = arena.appendExpr(.temporary(0))
        let noArgResult = arena.appendExpr(.temporary(1))
        let oneArgResult = arena.appendExpr(.temporary(2))

        let caller = KIRFunction(
            symbol: callerSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: argValue, value: .intLiteral(42)),
                .call(symbol: nil, callee: interner.intern("susp"), arguments: [], result: noArgResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("susp"), arguments: [argValue], result: oneArgResult, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendNoArg = KIRFunction(
            symbol: suspendNoArgSymbol,
            name: interner.intern("susp"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )
        let suspendOneArg = KIRFunction(
            symbol: suspendOneArgSymbol,
            name: interner.intern("susp"),
            params: [KIRParameter(symbol: suspendOneArgParam, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(caller))
        _ = arena.appendDecl(.function(suspendNoArg))
        _ = arena.appendDecl(.function(suspendOneArg))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "CoroutineOverloadRewrite",
            emit: .kirDump,
            interner: interner
        )
        ctx.kir = module

        try LoweringPhase().run(ctx)

        guard case let .function(loweredCaller)? = module.arena.decl(callerID) else {
            Issue.record("expected lowered caller function")
            return
        }

        let rawSuspendCalls = loweredCaller.body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return interner.resolve(callee) == "susp"
        }
        #expect(!rawSuspendCalls)

        let rewrittenSuspendCalls = loweredCaller.body.compactMap { instruction -> (name: String, arity: Int, canThrow: Bool)? in
            guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction else {
                return nil
            }
            let name = interner.resolve(callee)
            guard name.hasPrefix("kk_suspend_susp") else {
                return nil
            }
            return (name: name, arity: arguments.count, canThrow: canThrow)
        }
        #expect(rewrittenSuspendCalls.count == 2)
        #expect(Set(rewrittenSuspendCalls.map(\.arity)) == Set([1, 2]))
        let allCanThrow = rewrittenSuspendCalls.allSatisfy(\.canThrow)
        #expect(allCanThrow)
    }

    @Test
    func testCoroutineLoweringPreservesControlFlowAroundSuspendCalls() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let suspendSym = SymbolID(rawValue: 900)
        let lhs = arena.appendExpr(.temporary(0))
        let rhs = arena.appendExpr(.temporary(1))
        let callResult = arena.appendExpr(.temporary(2))

        let suspendFn = KIRFunction(
            symbol: suspendSym,
            name: interner.intern("suspendTarget"),
            params: [],
            returnType: types.unitType,
            body: [
                .label(10),
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: callResult, canThrow: false, thrownResult: nil),
                .jumpIfEqual(lhs: lhs, rhs: rhs, target: 20),
                .returnValue(lhs),
                .label(20),
                .returnValue(rhs),
            ],
            isSuspend: true,
            isInline: false
        )

        let suspendID = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [suspendID])], arena: arena)
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "CoroutineCFG",
            emit: .kirDump,
            interner: interner
        )
        ctx.kir = module

        try LoweringPhase().run(ctx)

        let loweredSuspend = try findKIRFunction(named: "kk_suspend_suspendTarget", in: module, interner: interner)

        let labels = loweredSuspend.body.compactMap { instruction -> Int32? in
            if case let .label(id) = instruction {
                return id
            }
            return nil
        }
        // Coroutine dispatch labels + original user label 20
        #expect(labels.contains(coroutineDispatchLabelBase))
        #expect(labels.contains(coroutineDispatchLabelBase + 1))
        #expect(labels.contains(20))

        let hasOriginalBranch = loweredSuspend.body.contains { instruction in
            if case let .jumpIfEqual(_, _, target) = instruction {
                return target == 20
            }
            return false
        }
        #expect(hasOriginalBranch)
    }

    @Test
    func testConsolidatedLoweringSourceScenarios() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.random.Random

            fun main_sample0() {
                val random = Random(7)
                val charValue = ('a'..'z').random(random)
                val intValue = (10..20).random(random)
                val longValue = (100L..110L).random(random)
                val uintValue = (10u..20u).random(random)
                val ulongValue = (100uL..110uL).random(random)
                println(charValue)
                println(intValue)
                println(longValue)
                println(uintValue)
                println(ulongValue)
            }
            """,
            """
            package sample1
            suspend fun delayedValue_1(): Int {
                delay(1)
                return 42
            }
            fun main_sample1(): Any? = runBlocking(delayedValue_1)
            """,
            """
            package sample2
            import kotlinx.coroutines.*

            suspend fun awaitAndJoin(d: Deferred<Int>, j: Job): Int {
                val value = d.await()
                j.join()
                return value
            }
            """,
            """
            package sample3
            suspend fun delayedValue_3(): Int {
                delay(1)
                return 42
            }
            fun main_sample3(): Any? = runBlocking { coroutineScope { delayedValue_3() } }
            """,
            """
            package sample4
            import kotlinx.coroutines.*
            import kotlinx.coroutines.sync.*

            fun main_sample4() = runBlocking {
                val mutex = Mutex()
                println(mutex.withLock { 1 })
            }
            """,
            """
            package sample5
            suspend fun delayedValue_5(v: Int): Int = v

            suspend fun outerSuspendHost(value: Int): Int {
                suspend fun localSuspendBridge(value: Int): Int = delayedValue_5(value)
                return localSuspendBridge(value)
            }

            fun main_sample5(): Any? = runBlocking(outerSuspendHost)
            """,
            """
            package sample6
            import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

            suspend fun probe(): Any? {
                return suspendCoroutineUninterceptedOrReturn { cont ->
                    cont
                }
            }
            fun main_sample6(): Any? = runBlocking(probe)
            """,
            """
            package sample7
            fun myCompare(a: Int, b: Int): Int = a - b

            fun interface Stringify {
                fun render(value: Int): String
            }

            fun label(value: Int): String = "v=" + value

            fun main_sample7() {
                val comparator = Comparator<Int>(::myCompare)
                println(comparator.compare(3, 5))
                println(Stringify(::label).render(42))
            }
            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            let module = try #require(ctx.kir)

            // testRangeRandomCallsKeepRandomArgument
            do {
                let body = try findKIRFunctionBody(named: "main_sample0", in: module, interner: ctx.interner)
                let allCallees = extractCallees(from: body, interner: ctx.interner)

                let randomCalls = body.compactMap { instruction -> (String, Int, Bool)? in
                    guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction else {
                        return nil
                    }
                    let name = ctx.interner.resolve(callee)
                    guard name == "random"
                    else {
                        return nil
                    }
                    return (name, arguments.count, canThrow)
                }

                #expect(randomCalls.count == 5, "Expected five source-backed range.random calls, got: \(randomCalls); all callees: \(allCallees)")
                #expect(randomCalls.allSatisfy { _, argumentCount, canThrow in
                    argumentCount == 2 && canThrow
                }, "Expected source wrapper receiver + Random argument and canThrow=true, got: \(randomCalls); all callees: \(allCallees)")
                #expect(
                    allCallees.allSatisfy { name in
                        !name.contains("range_random") && !name.contains("randomOrNull")
                    },
                    "Legacy range random runtime links must not remain in user call lowering: \(allCallees)"
                )
            }
            // testCoroutineLoweringRewritesKxMiniLauncherAndDelayBuiltins
            do {
                let mainBody = try findKIRFunctionBody(named: "main_sample1", in: module, interner: ctx.interner)
                let suspendBody = try findKIRFunctionBody(named: "kk_suspend_delayedValue_1", in: module, interner: ctx.interner)

                let mainCalls = extractCallees(from: mainBody, interner: ctx.interner)
                #expect(mainCalls.contains("kk_kxmini_run_blocking"))
                #expect(!mainCalls.contains("runBlocking"))

                let delayCalls = extractCallees(from: suspendBody, interner: ctx.interner)
                #expect(delayCalls.contains("kk_kxmini_delay"))

                let throwFlags = extractThrowFlags(from: suspendBody, interner: ctx.interner)
                #expect(throwFlags["kk_kxmini_delay"]?.allSatisfy { $0 == false } == true)
            }
            // testCoroutineLoweringTreatsAwaitAndJoinAsSuspendPoints
            do {
                let suspendBody = try findKIRFunctionBody(named: "kk_suspend_awaitAndJoin", in: module, interner: ctx.interner)

                let callees = extractCallees(from: suspendBody, interner: ctx.interner)
                #expect(callees.contains("kk_kxmini_async_await"), "await should lower to kk_kxmini_async_await")
                #expect(callees.contains("kk_job_join"), "join should lower to kk_job_join")
                #expect(
                    callees.contains("kk_coroutine_state_set_label"),
                    "await/join must be treated as suspend points (resume label install)"
                )

                let throwFlags = extractThrowFlags(from: suspendBody, interner: ctx.interner)
                #expect(throwFlags["kk_kxmini_async_await"]?.allSatisfy { $0 == false } == true)
                #expect(throwFlags["kk_job_join"]?.allSatisfy { $0 == false } == true)
            }
            // testCoroutineScopeNoLongerLowersToScopeRun
            do {
                let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                    extractCallees(from: function.body, interner: ctx.interner)
                }
                #expect(!allCallees.contains("kk_coroutine_scope_run"), "coroutineScope must not lower to the removed kk_coroutine_scope_run")
                #expect(!allCallees.contains("kk_supervisor_scope_run"), "supervisorScope must not lower to the removed kk_supervisor_scope_run")
            }
            // testNonInlineCallIsNotRedirectedToSameNamedInlineOverload
            do {
                let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                    extractCallees(from: function.body, interner: ctx.interner)
                }
                #expect(
                    !allCallees.contains("__kk_lock_withLock"),
                    "Mutex.withLock must not be inlined into the Lock.withLock bridge"
                )
            }
            // testCoroutineLoweringRewritesSuspendLocalFunctionCalls
            do {
                let allFunctions = findAllKIRFunctions(in: module)

                let loweredOuter = try #require(allFunctions.first(where: { function in
                    ctx.interner.resolve(function.name) == "kk_suspend_outerSuspendHost"
                }))
                let loweredLocal = try #require(allFunctions.first(where: { function in
                    ctx.interner.resolve(function.name) == "kk_suspend_localSuspendBridge"
                }))

                let outerCallees = extractCallees(from: loweredOuter.body, interner: ctx.interner)
                #expect(outerCallees.contains("kk_coroutine_call_direct_suspend"))
                #expect(!outerCallees.contains("localSuspendBridge"))

                let localCallees = extractCallees(from: loweredLocal.body, interner: ctx.interner)
                #expect(localCallees.contains("kk_coroutine_call_direct_suspend"))
                #expect(localCallees.contains("kk_coroutine_state_enter"))
                #expect(localCallees.contains("kk_coroutine_state_exit"))
            }
            // testCoroutineLoweringRewritesSuspendCoroutineUninterceptedOrReturnFromImport
            do {
                let probeBody = try findKIRFunctionBody(named: "kk_suspend_probe", in: module, interner: ctx.interner)

                let callees = extractCallees(from: probeBody, interner: ctx.interner)
                #expect(callees.contains("kk_coroutine_suspended"), "callees: \(callees)")
                #expect(!callees.contains("suspendCoroutineUninterceptedOrReturn"), "callees: \(callees)")
            }
            // testSamConvertedCallableRefLowersToInterfaceWrapper
            do {
                let mainBody = try findKIRFunctionBody(named: "main_sample7", in: module, interner: ctx.interner)
                let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
                #expect(
                    mainCallees.filter { $0 == "kk_object_register_itable_method" }.count == 2,
                    "Callees: \(mainCallees)"
                )
                #expect(mainCallees.contains("kk_type_register_iface"), "Callees: \(mainCallees)")

                let functionNames = findAllKIRFunctions(in: module).map { ctx.interner.resolve($0.name) }
                #expect(
                    functionNames.filter { $0.hasPrefix("kk_sam_ref_thunk_") }.count == 2,
                    "Functions: \(functionNames.filter { $0.hasPrefix("kk_sam_") })"
                )
            }
        }
    }

    @Test
    func testConsolidatedKIRSourceScenarios() throws {
        let sources: [String] = [
            """
            package sample8
            import kotlinx.coroutines.*

            suspend fun invokeZero(block: suspend () -> Int): Int = block()

            suspend fun invokeOne(block: suspend (Int) -> Int): Int = block(41)

            fun main_sample8() = runBlocking {
                val zero = invokeZero { 7 }
                val one = invokeOne { value -> value + 1 }
                println(zero)
                println(one)
            }
            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            let module = try #require(ctx.kir)

            // testCoroutineLoweringRewritesSuspendFunctionTypeInvokeCalls
            do {
                let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                    extractCallees(from: function.body, interner: ctx.interner)
                }
                let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.severity): \($0.message)" }

                #expect(allCallees.contains("kk_suspend_function_invoke_0"), "Callees: \(allCallees)")
                #expect(allCallees.contains("kk_suspend_function_invoke"), "Callees: \(allCallees)")
                #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error }, "Diagnostics: \(diagnostics)")
            }
        }
    }

    @Test
    func testSafeCallInlineResultIsMaterializedBeforeMerge() throws {
        let source = """
        fun main() {
            val nullableInput: String? = null
            println(nullableInput?.let { it.uppercase() })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .object)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let printlnCallIndex = mainBody.firstIndex { instruction in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                    return false
                }
                let calleeName = ctx.interner.resolve(callee)
                return (calleeName == "println" || calleeName == "kk_println_any") && !arguments.isEmpty
            }
            let printlnCallInstruction = try #require(printlnCallIndex.map { mainBody[$0] }, "expected println call in main")
            guard case let .call(_, _, printlnArgs, _, _, _, _, _) = printlnCallInstruction else {
                return
            }
            let printlnArg = printlnArgs[0]

            let uppercaseResult = try #require(mainBody[..<printlnCallIndex!].lazy.compactMap { instruction -> KIRExprID? in
                guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                      let result,
                      ctx.interner.resolve(callee) == "kk_string_uppercase_flat"
                else {
                    return nil
                }
                return result
            }.last, "expected kk_string_uppercase_flat call before println")

            let hasCopyFromUppercase = mainBody[..<printlnCallIndex!].contains { instruction in
                if case let .copy(from, to) = instruction, to == printlnArg {
                    if from == uppercaseResult {
                        return true
                    }
                    // String results may be boxed through kk_string_from_flat before the copy.
                    return mainBody[..<printlnCallIndex!].contains { earlier in
                        guard case let .call(_, callee, args, result, _, _, _, _) = earlier,
                              let result,
                              result == from,
                              args.contains(uppercaseResult)
                        else {
                            return false
                        }
                        let name = ctx.interner.resolve(callee)
                        return name == "kk_string_from_flat" || name == "kk_string_to_flat"
                    }
                }
                if case let .call(_, callee, args, result, _, _, _, _) = instruction,
                   let result,
                   result == printlnArg,
                   args.contains(uppercaseResult) {
                    let name = ctx.interner.resolve(callee)
                    return name == "kk_string_from_flat" || name == "kk_string_to_flat"
                }
                return false
            }
            #expect(hasCopyFromUppercase, "safe-call inline result must be materialized before println")
        }
    }
}


#endif
