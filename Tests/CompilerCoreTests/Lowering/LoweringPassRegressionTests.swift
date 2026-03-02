@testable import CompilerCore
import Foundation
import XCTest

final class LoweringPassRegressionTests: XCTestCase {
    func testLoweringRewritesMainCallSites() throws {
        let fixture = try makeLoweringRewriteFixture()

        guard case let .function(loweredMain)? = fixture.module.arena.decl(fixture.mainID) else {
            XCTFail("expected lowered main function")
            return
        }

        let callees = extractCallees(from: loweredMain.body, interner: fixture.interner)
        XCTAssertTrue(callees.contains("kk_range_iterator"))
        XCTAssertTrue(callees.contains("kk_range_hasNext"))
        XCTAssertTrue(callees.contains("kk_range_next"))
        XCTAssertFalse(callees.contains("kk_for_lowered"))
        // kk_when_select removed; select is now control flow (jumpIfEqual + copy + jump + label)
        XCTAssertFalse(callees.contains("kk_when_select"))
        // kk_property_access removed — PropertyLowering now emits direct accessor calls.
        // The test fixture uses symbol-less get/set calls, so they remain unchanged.
        XCTAssertFalse(callees.contains("kk_property_access"))
        XCTAssertTrue(callees.contains("get"))
        XCTAssertTrue(callees.contains("set"))
        XCTAssertTrue(callees.contains("kk_lambda_invoke"))
        XCTAssertFalse(callees.contains("inlineTarget"))
        XCTAssertTrue(callees.contains("kk_coroutine_continuation_new"))
        XCTAssertTrue(callees.contains("kk_suspend_suspendTarget"))

        let throwFlags = extractThrowFlags(from: loweredMain.body, interner: fixture.interner)
        XCTAssertEqual(throwFlags["kk_coroutine_continuation_new"]?.allSatisfy { $0 == false }, true)
        XCTAssertEqual(throwFlags["kk_suspend_suspendTarget"]?.allSatisfy { $0 == true }, true)
    }

    func testLoweringBuildsSuspendStateMachineAndThrowFlags() throws {
        let fixture = try makeLoweringRewriteFixture()
        let loweredSuspend = try findKIRFunction(named: "kk_suspend_suspendTarget", in: fixture.module, interner: fixture.interner)

        XCTAssertEqual(loweredSuspend.params.count, 1)
        XCTAssertEqual(loweredSuspend.isSuspend, false)

        let loweredSuspendCallees = extractCallees(from: loweredSuspend.body, interner: fixture.interner)
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_enter"))
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_set_label"))
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_set_completion"))
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_get_completion"))
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_exit"))

        let dispatchJumpCount = loweredSuspend.body.filter { instruction in
            if case .jumpIfEqual = instruction {
                return true
            }
            return false
        }.count
        // A suspend function with one suspension point needs at least 2 dispatch jumps:
        // one for label 1000 (entry) and one for label 1001 (resume point)
        XCTAssertGreaterThanOrEqual(dispatchJumpCount, 2)

        let dispatchLabels = loweredSuspend.body.compactMap { instruction -> Int32? in
            if case let .label(id) = instruction {
                return id
            }
            return nil
        }
        // Coroutine state machine dispatch labels start at coroutineDispatchLabelBase
        XCTAssertTrue(dispatchLabels.contains(coroutineDispatchLabelBase))
        XCTAssertTrue(dispatchLabels.contains(coroutineDispatchLabelBase + 1))

        let hasSuspendGuard = loweredSuspend.body.contains { instruction in
            if case .returnIfEqual = instruction {
                return true
            }
            return false
        }
        XCTAssertTrue(hasSuspendGuard)

        let throwFlags = extractThrowFlags(from: loweredSuspend.body, interner: fixture.interner)
        XCTAssertEqual(throwFlags["kk_suspend_suspendTarget"]?.allSatisfy { $0 == true }, true)
        XCTAssertEqual(throwFlags["kk_coroutine_suspended"]?.allSatisfy { $0 == false }, true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_set_label"]?.allSatisfy { $0 == false }, true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_set_completion"]?.allSatisfy { $0 == false }, true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_get_completion"]?.allSatisfy { $0 == false }, true)
    }

    func testLoweringNormalizesEmptyFunctionBody() throws {
        let fixture = try makeLoweringRewriteFixture()

        guard case let .function(loweredEmpty)? = fixture.module.arena.decl(fixture.emptyID) else {
            XCTFail("expected lowered empty function")
            return
        }
        XCTAssertEqual(loweredEmpty.body.last, .returnUnit)
        XCTAssertFalse(loweredEmpty.body.isEmpty)
    }

    func testCoroutineLoweringRewritesKxMiniLauncherAndDelayBuiltins() throws {
        let source = """
        suspend fun delayedValue(): Int {
            delay(1)
            return 42
        }
        fun main(): Any? = runBlocking(delayedValue)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "KxMiniLowering", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let suspendBody = try findKIRFunctionBody(named: "kk_suspend_delayedValue", in: module, interner: ctx.interner)

            let mainCalls = extractCallees(from: mainBody, interner: ctx.interner)
            XCTAssertTrue(mainCalls.contains("kk_kxmini_run_blocking"))
            XCTAssertFalse(mainCalls.contains("runBlocking"))

            let delayCalls = extractCallees(from: suspendBody, interner: ctx.interner)
            XCTAssertTrue(delayCalls.contains("kk_kxmini_delay"))

            let throwFlags = extractThrowFlags(from: suspendBody, interner: ctx.interner)
            XCTAssertEqual(throwFlags["kk_kxmini_delay"]?.allSatisfy { $0 == false }, true)
        }
    }

    func testCoroutineLoweringRewritesCoroutineScopeToScopeRun() throws {
        let source = """
        suspend fun delayedValue(): Int {
            delay(1)
            return 42
        }
        fun main(): Any? = coroutineScope(delayedValue)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "CoroutineScopeLowering", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let mainCalls = extractCallees(from: mainBody, interner: ctx.interner)
            XCTAssertTrue(mainCalls.contains("kk_coroutine_scope_run"), "Expected coroutineScope to be rewritten to kk_coroutine_scope_run")
            XCTAssertFalse(mainCalls.contains("coroutineScope"), "coroutineScope should have been rewritten")
        }
    }

    func testKxMiniRunBlockingDelayExecutableReturnsExpectedExitCode() throws {
        let source = """
        suspend fun delayedValue(): Int {
            delay(1)
            return 42
        }
        fun main(): Any? = runBlocking(delayedValue)
        """

        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "KxMiniExecutable",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

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

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "CoroutineOverloadRewrite",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module

        try LoweringPhase().run(ctx)

        guard case let .function(loweredCaller)? = module.arena.decl(callerID) else {
            XCTFail("expected lowered caller function")
            return
        }

        let rawSuspendCalls = loweredCaller.body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _) = instruction else {
                return false
            }
            return interner.resolve(callee) == "susp"
        }
        XCTAssertFalse(rawSuspendCalls)

        let rewrittenSuspendCalls = loweredCaller.body.compactMap { instruction -> (name: String, arity: Int, canThrow: Bool)? in
            guard case let .call(_, callee, arguments, _, canThrow, _, _) = instruction else {
                return nil
            }
            let name = interner.resolve(callee)
            guard name.hasPrefix("kk_suspend_susp") else {
                return nil
            }
            return (name: name, arity: arguments.count, canThrow: canThrow)
        }
        XCTAssertEqual(rewrittenSuspendCalls.count, 2)
        XCTAssertEqual(Set(rewrittenSuspendCalls.map(\.arity)), Set([1, 2]))
        XCTAssertTrue(rewrittenSuspendCalls.allSatisfy(\.canThrow))
    }

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
        let options = CompilerOptions(
            moduleName: "CoroutineCFG",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
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
        XCTAssertTrue(labels.contains(coroutineDispatchLabelBase))
        XCTAssertTrue(labels.contains(coroutineDispatchLabelBase + 1))
        XCTAssertTrue(labels.contains(20))

        let hasOriginalBranch = loweredSuspend.body.contains { instruction in
            if case let .jumpIfEqual(_, _, target) = instruction {
                return target == 20
            }
            return false
        }
        XCTAssertTrue(hasOriginalBranch)
    }

    // MARK: - Private Helpers

    private func makeContext(
        interner: StringInterner,
        moduleName: String,
        emit: EmitMode = .kirDump,
        diagnostics: DiagnosticEngine = DiagnosticEngine()
    ) -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: emit,
            target: defaultTargetTriple()
        )
        return CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
    }

    @discardableResult
    private func runLowering(
        module: KIRModule,
        interner: StringInterner,
        moduleName: String,
        emit: EmitMode = .kirDump,
        sema: SemaModule? = nil,
        diagnostics: DiagnosticEngine = DiagnosticEngine()
    ) throws -> CompilationContext {
        let ctx = makeContext(interner: interner, moduleName: moduleName, emit: emit, diagnostics: diagnostics)
        ctx.kir = module
        ctx.sema = sema
        try LoweringPhase().run(ctx)
        return ctx
    }
}
