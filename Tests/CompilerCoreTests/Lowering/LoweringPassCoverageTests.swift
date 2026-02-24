import Foundation
import XCTest
@testable import CompilerCore

final class LoweringPassCoverageTests: XCTestCase {
    func testLoweringRewritesMainCallSites() throws {
        let fixture = try makeLoweringRewriteFixture()

        guard case .function(let loweredMain)? = fixture.module.arena.decl(fixture.mainID) else {
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
        XCTAssertEqual(throwFlags["kk_coroutine_continuation_new"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_suspend_suspendTarget"]?.allSatisfy({ $0 == true }), true)
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
            if case .label(let id) = instruction {
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
        XCTAssertEqual(throwFlags["kk_suspend_suspendTarget"]?.allSatisfy({ $0 == true }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_suspended"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_set_label"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_set_completion"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_get_completion"]?.allSatisfy({ $0 == false }), true)
    }

    func testLoweringNormalizesEmptyFunctionBody() throws {
        let fixture = try makeLoweringRewriteFixture()

        guard case .function(let loweredEmpty)? = fixture.module.arena.decl(fixture.emptyID) else {
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
            XCTAssertEqual(throwFlags["kk_kxmini_delay"]?.allSatisfy({ $0 == false }), true)
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
            } catch CommandRunnerError.nonZeroExit(let failed) {
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
                .returnUnit
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

        guard case .function(let loweredCaller)? = module.arena.decl(callerID) else {
            XCTFail("expected lowered caller function")
            return
        }

        let rawSuspendCalls = loweredCaller.body.contains { instruction in
            guard case .call(_, let callee, _, _, _, _, _) = instruction else {
                return false
            }
            return interner.resolve(callee) == "susp"
        }
        XCTAssertFalse(rawSuspendCalls)

        let rewrittenSuspendCalls = loweredCaller.body.compactMap { instruction -> (name: String, arity: Int, canThrow: Bool)? in
            guard case .call(_, let callee, let arguments, _, let canThrow, _, _) = instruction else {
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
                .returnValue(rhs)
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
            if case .label(let id) = instruction {
                return id
            }
            return nil
        }
        // Coroutine dispatch labels + original user label 20
        XCTAssertTrue(labels.contains(coroutineDispatchLabelBase))
        XCTAssertTrue(labels.contains(coroutineDispatchLabelBase + 1))
        XCTAssertTrue(labels.contains(20))

        let hasOriginalBranch = loweredSuspend.body.contains { instruction in
            if case .jumpIfEqual(_, _, let target) = instruction {
                return target == 20
            }
            return false
        }
        XCTAssertTrue(hasOriginalBranch)
    }

    func testCoroutineLoweringSpillsAndReloadsLiveValuesAcrossSuspension() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let suspendSym = SymbolID(rawValue: 1900)
        let liveValue = arena.appendExpr(.temporary(0))
        let callResult = arena.appendExpr(.temporary(1))
        let summedResult = arena.appendExpr(.temporary(2))

        let suspendFn = KIRFunction(
            symbol: suspendSym,
            name: interner.intern("suspendTarget"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: liveValue, value: .intLiteral(41)),
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: callResult, canThrow: false, thrownResult: nil),
                .binary(op: .add, lhs: liveValue, rhs: callResult, result: summedResult),
                .returnValue(summedResult)
            ],
            isSuspend: true,
            isInline: false
        )

        let suspendID = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [suspendID])], arena: arena)
        let options = CompilerOptions(
            moduleName: "CoroutineSpill",
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

        let loweredCalls = extractCallees(from: loweredSuspend.body, interner: interner)
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_set_spill"))
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_get_spill"))
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_set_completion"))
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_get_completion"))

        let setSpillCount = loweredCalls.filter { $0 == "kk_coroutine_state_set_spill" }.count
        let getSpillCount = loweredCalls.filter { $0 == "kk_coroutine_state_get_spill" }.count
        XCTAssertEqual(setSpillCount, 1)
        XCTAssertEqual(getSpillCount, 1)

        let throwFlags = extractThrowFlags(from: loweredSuspend.body, interner: interner)
        XCTAssertEqual(throwFlags["kk_suspend_suspendTarget"]?.allSatisfy({ $0 == true }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_set_spill"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_get_spill"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_set_completion"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_get_completion"]?.allSatisfy({ $0 == false }), true)
    }

    func testCoroutineLoweringSynthesizesContinuationNominalTypeLayoutAndSignature() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()

        let packageName = interner.intern("pkg")
        let suspendName = interner.intern("suspendTarget")
        let parameterName = interner.intern("value")
        let range = makeRange()
        let intType = types.make(.primitive(.int, .nonNull))

        let suspendSymbol = symbols.define(
            kind: .function,
            name: suspendName,
            fqName: [packageName, suspendName],
            declSite: range,
            visibility: .public,
            flags: [.suspendFunction]
        )
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: [packageName, suspendName, parameterName],
            declSite: range,
            visibility: .private
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                isSuspend: true,
                valueParameterSymbols: [parameterSymbol]
            ),
            for: suspendSymbol
        )

        let liveValue = arena.appendExpr(.temporary(0), type: intType)
        let callResult = arena.appendExpr(.temporary(1), type: intType)
        let sumResult = arena.appendExpr(.temporary(2), type: intType)

        let suspendFunction = KIRFunction(
            symbol: suspendSymbol,
            name: suspendName,
            params: [KIRParameter(symbol: parameterSymbol, type: intType)],
            returnType: intType,
            body: [
                .constValue(result: liveValue, value: .symbolRef(parameterSymbol)),
                .call(
                    symbol: suspendSymbol,
                    callee: suspendName,
                    arguments: [liveValue],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .binary(op: .add, lhs: liveValue, rhs: callResult, result: sumResult),
                .returnValue(sumResult)
            ],
            isSuspend: true,
            isInline: false
        )

        let suspendID = arena.appendDecl(.function(suspendFunction))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [suspendID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "CoroutineContinuationType",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.kir = module
        ctx.sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )

        try LoweringPhase().run(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let continuationTypeSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class &&
                symbol.flags.contains(.synthetic) &&
                interner.resolve(symbol.name).contains("kk_suspend_suspendTarget$Cont")
        }))

        let continuationFields = sema.symbols.allSymbols().filter { symbol in
            symbol.kind == .field &&
                symbol.fqName.count == continuationTypeSymbol.fqName.count + 1 &&
                zip(continuationTypeSymbol.fqName, symbol.fqName).allSatisfy { $0 == $1 }
        }
        let fieldNames = Set(continuationFields.map { interner.resolve($0.name) })
        XCTAssertTrue(fieldNames.contains("$label"))
        XCTAssertTrue(fieldNames.contains("$completion"))
        XCTAssertTrue(fieldNames.contains("$spill0"))

        let layout = try XCTUnwrap(sema.symbols.nominalLayout(for: continuationTypeSymbol.id))
        XCTAssertGreaterThanOrEqual(layout.instanceFieldCount, 3)
        let labelField = try XCTUnwrap(continuationFields.first(where: { interner.resolve($0.name) == "$label" }))
        let completionField = try XCTUnwrap(continuationFields.first(where: { interner.resolve($0.name) == "$completion" }))
        let spillField = try XCTUnwrap(continuationFields.first(where: { interner.resolve($0.name) == "$spill0" }))
        let labelOffset = try XCTUnwrap(layout.fieldOffsets[labelField.id])
        let completionOffset = try XCTUnwrap(layout.fieldOffsets[completionField.id])
        let spillOffset = try XCTUnwrap(layout.fieldOffsets[spillField.id])
        XCTAssertLessThan(labelOffset, completionOffset)
        XCTAssertLessThan(completionOffset, spillOffset)

        let loweredSuspendSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && interner.resolve(symbol.name).hasPrefix("kk_suspend_suspendTarget")
        }))
        let loweredSignature = try XCTUnwrap(sema.symbols.functionSignature(for: loweredSuspendSymbol.id))
        let continuationParameterType = try XCTUnwrap(loweredSignature.parameterTypes.last)
        guard case .classType(let classType) = types.kind(of: continuationParameterType) else {
            XCTFail("Expected lowered continuation parameter type to be class type.")
            return
        }
        XCTAssertEqual(classType.classSymbol, continuationTypeSymbol.id)

        let nominalSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case .nominalType(let nominal) = decl else {
                return nil
            }
            return nominal.symbol
        }
        XCTAssertTrue(nominalSymbols.contains(continuationTypeSymbol.id))
    }

    func testSuspendExceptionPropagationKeepsThrowingChannelAcrossSuspendChain() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 2100)
        let topSymbol = SymbolID(rawValue: 2101)
        let leafSymbol = SymbolID(rawValue: 2102)

        let mainResult = arena.appendExpr(.temporary(0))
        let topResult = arena.appendExpr(.temporary(1))
        let leafResult = arena.appendExpr(.temporary(2))

        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: topSymbol, callee: interner.intern("top"), arguments: [], result: mainResult, canThrow: false, thrownResult: nil),
                .returnValue(mainResult)
            ],
            isSuspend: false,
            isInline: false
        )
        let topFunction = KIRFunction(
            symbol: topSymbol,
            name: interner.intern("top"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: leafSymbol, callee: interner.intern("leaf"), arguments: [], result: topResult, canThrow: false, thrownResult: nil),
                .returnValue(topResult)
            ],
            isSuspend: true,
            isInline: false
        )
        let leafFunction = KIRFunction(
            symbol: leafSymbol,
            name: interner.intern("leaf"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: leafResult, canThrow: false, thrownResult: nil),
                .returnValue(leafResult)
            ],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFunction))
        _ = arena.appendDecl(.function(topFunction))
        _ = arena.appendDecl(.function(leafFunction))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "CoroutineThrowFlags",
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

        let loweredMain = try findKIRFunction(named: "main", in: module, interner: interner)
        let loweredTop = try findKIRFunction(named: "kk_suspend_top", in: module, interner: interner)
        let loweredLeaf = try findKIRFunction(named: "kk_suspend_leaf", in: module, interner: interner)

        let mainThrowFlags = extractThrowFlags(from: loweredMain.body, interner: interner)
        XCTAssertEqual(mainThrowFlags["kk_suspend_top"]?.allSatisfy({ $0 == true }), true)

        let topThrowFlags = extractThrowFlags(from: loweredTop.body, interner: interner)
        XCTAssertEqual(topThrowFlags["kk_suspend_leaf"]?.allSatisfy({ $0 == true }), true)
        XCTAssertEqual(topThrowFlags["kk_coroutine_state_set_label"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(topThrowFlags["kk_coroutine_state_set_completion"]?.allSatisfy({ $0 == false }), true)

        let leafThrowFlags = extractThrowFlags(from: loweredLeaf.body, interner: interner)
        XCTAssertEqual(leafThrowFlags["external_throwing"]?.allSatisfy({ $0 == true }), true)
    }

    func testInlineLoweringExpandsInlineBodyAndRewritesResultUse() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 300)
        let inlineSym = SymbolID(rawValue: 301)
        let inlineParamSym = SymbolID(rawValue: 302)

        let inlineArg = arena.appendExpr(.temporary(0))
        let inlineOne = arena.appendExpr(.temporary(1))
        let inlineSum = arena.appendExpr(.temporary(2))
        let callerArg = arena.appendExpr(.temporary(3))
        let callerResult = arena.appendExpr(.temporary(4))

        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("plusOne"),
            params: [KIRParameter(symbol: inlineParamSym, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: inlineArg, value: .symbolRef(inlineParamSym)),
                .constValue(result: inlineOne, value: .intLiteral(1)),
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [inlineArg, inlineOne], result: inlineSum, canThrow: false, thrownResult: nil),
                .returnValue(inlineSum)
            ],
            isSuspend: false,
            isInline: true
        )
        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: callerArg, value: .intLiteral(41)),
                .call(symbol: inlineSym, callee: interner.intern("plusOne"), arguments: [callerArg], result: callerResult, canThrow: false, thrownResult: nil),
                .returnValue(callerResult)
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(inlineFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineLowering",
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

        guard case .function(let loweredCaller)? = module.arena.decl(callerID) else {
            XCTFail("expected lowered caller function")
            return
        }

        let calleeNames = extractCallees(from: loweredCaller.body, interner: interner)
        XCTAssertFalse(calleeNames.contains("plusOne"))
        XCTAssertTrue(calleeNames.contains("kk_op_add"))

        let returnValues = loweredCaller.body.compactMap { instruction -> KIRExprID? in
            guard case .returnValue(let expr) = instruction else { return nil }
            return expr
        }
        XCTAssertEqual(returnValues.count, 1)
        XCTAssertNotEqual(returnValues.first, callerResult)
    }

    func testDataEnumSealedSynthesisAddsSyntheticHelpers() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        let colorName = interner.intern("Color")
        let colorSymbol = symbols.define(
            kind: .enumClass,
            name: colorName,
            fqName: packagePath + [colorName],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("RED"),
            fqName: packagePath + [colorName, interner.intern("RED")],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("BLUE"),
            fqName: packagePath + [colorName, interner.intern("BLUE")],
            declSite: nil,
            visibility: .public
        )

        let baseName = interner.intern("Base")
        let baseSymbol = symbols.define(
            kind: .class,
            name: baseName,
            fqName: packagePath + [baseName],
            declSite: nil,
            visibility: .public,
            flags: [.sealedType]
        )
        let childName = interner.intern("Child")
        let childSymbol = symbols.define(
            kind: .class,
            name: childName,
            fqName: packagePath + [childName],
            declSite: nil,
            visibility: .public
        )
        symbols.setDirectSupertypes([baseSymbol], for: childSymbol)

        let pointName = interner.intern("Point")
        let pointSymbol = symbols.define(
            kind: .class,
            name: pointName,
            fqName: packagePath + [pointName],
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )

        let arena = KIRArena()
        let colorDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: colorSymbol)))
        let baseDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: baseSymbol)))
        let pointDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: pointSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [colorDecl, baseDecl, pointDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "Synthesis",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)

        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name)
        }
        XCTAssertTrue(functionNames.contains("Color$enumValuesCount"))
        XCTAssertTrue(functionNames.contains("Base$sealedSubtypeCount"))
        XCTAssertTrue(functionNames.contains("Point$copy"))

        let copyFunction = try findKIRFunction(named: "Point$copy", in: module, interner: interner)
        XCTAssertEqual(copyFunction.params.count, 1)
    }

    func testDataEnumSealedSynthesisAddsOrdinalNameValuesValueOf() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        let colorName = interner.intern("Color")
        let colorSymbol = symbols.define(
            kind: .enumClass,
            name: colorName,
            fqName: packagePath + [colorName],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("RED"),
            fqName: packagePath + [colorName, interner.intern("RED")],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("GREEN"),
            fqName: packagePath + [colorName, interner.intern("GREEN")],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("BLUE"),
            fqName: packagePath + [colorName, interner.intern("BLUE")],
            declSite: nil,
            visibility: .public
        )

        let arena = KIRArena()
        let colorDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: colorSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [colorDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "EnumSynthesis",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)

        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name)
        }

        // Verify count helper still exists
        XCTAssertTrue(functionNames.contains("Color$enumValuesCount"), "Missing Color$enumValuesCount, got: \(functionNames)")

        // Verify per-entry ordinal helpers
        XCTAssertTrue(functionNames.contains("RED$enumOrdinal"), "Missing RED$enumOrdinal, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("GREEN$enumOrdinal"), "Missing GREEN$enumOrdinal, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("BLUE$enumOrdinal"), "Missing BLUE$enumOrdinal, got: \(functionNames)")

        // Verify per-entry name helpers
        XCTAssertTrue(functionNames.contains("RED$enumName"), "Missing RED$enumName, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("GREEN$enumName"), "Missing GREEN$enumName, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("BLUE$enumName"), "Missing BLUE$enumName, got: \(functionNames)")

        // Verify values() and valueOf() companion functions
        XCTAssertTrue(functionNames.contains("values"), "Missing values, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("valueOf"), "Missing valueOf, got: \(functionNames)")

        // Verify ordinal values are correct (0-based)
        let redOrdinal = try findKIRFunction(named: "RED$enumOrdinal", in: module, interner: interner)
        let greenOrdinal = try findKIRFunction(named: "GREEN$enumOrdinal", in: module, interner: interner)
        let blueOrdinal = try findKIRFunction(named: "BLUE$enumOrdinal", in: module, interner: interner)

        // Each ordinal function should have a constValue instruction with the correct ordinal
        let redConst = redOrdinal.body.compactMap { inst -> Int64? in
            guard case .constValue(_, let value) = inst, case .intLiteral(let v) = value else { return nil }
            return v
        }
        XCTAssertTrue(redConst.contains(0), "RED ordinal should be 0, got consts: \(redConst)")

        let greenConst = greenOrdinal.body.compactMap { inst -> Int64? in
            guard case .constValue(_, let value) = inst, case .intLiteral(let v) = value else { return nil }
            return v
        }
        XCTAssertTrue(greenConst.contains(1), "GREEN ordinal should be 1, got consts: \(greenConst)")

        let blueConst = blueOrdinal.body.compactMap { inst -> Int64? in
            guard case .constValue(_, let value) = inst, case .intLiteral(let v) = value else { return nil }
            return v
        }
        XCTAssertTrue(blueConst.contains(2), "BLUE ordinal should be 2, got consts: \(blueConst)")

        // Verify name functions return correct string literals
        let redName = try findKIRFunction(named: "RED$enumName", in: module, interner: interner)
        let redNameConsts = redName.body.compactMap { inst -> InternedString? in
            guard case .constValue(_, let value) = inst, case .stringLiteral(let s) = value else { return nil }
            return s
        }
        XCTAssertTrue(redNameConsts.contains(interner.intern("RED")), "RED name function should return \"RED\"")

        // Verify valueOf has parameter
        let valueOfFn = try findKIRFunction(named: "valueOf", in: module, interner: interner)
        XCTAssertEqual(valueOfFn.params.count, 1, "valueOf should have 1 parameter")

        // Verify valueOf body contains string comparison calls
        let valueOfCallees = extractCallees(from: valueOfFn.body, interner: interner)
        XCTAssertTrue(valueOfCallees.contains("kk_string_equals"), "valueOf should call kk_string_equals")
        XCTAssertTrue(valueOfCallees.contains("kk_enum_valueOf_throw"), "valueOf should call kk_enum_valueOf_throw for no-match case")
    }

    func testInlineLoweringMapsReifiedTypeTokenSymbolRefToHiddenArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()

        let packageName = interner.intern("demo")
        let mainName = interner.intern("main")
        let inlineName = interner.intern("inlineToken")
        let typeParameterName = interner.intern("T")
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSymbol = symbols.define(
            kind: .function,
            name: mainName,
            fqName: [packageName, mainName],
            declSite: nil,
            visibility: .public
        )
        let inlineSymbol = symbols.define(
            kind: .function,
            name: inlineName,
            fqName: [packageName, inlineName],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction]
        )
        let typeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParameterName,
            fqName: [packageName, interner.intern("$inlineToken"), typeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.reifiedTypeParameter]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: intType,
                typeParameterSymbols: [typeParameterSymbol],
                reifiedTypeParameterIndices: Set([0])
            ),
            for: inlineSymbol
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: intType
            ),
            for: mainSymbol
        )

        // Type token symbols use a negative offset to avoid collision with real symbol IDs
        let hiddenTokenSymbol = SymbolID(rawValue: Int32(typeTokenSymbolOffset) - typeParameterSymbol.rawValue)
        let inlineTokenExpr = arena.appendExpr(.temporary(0), type: intType)
        let callerTokenExpr = arena.appendExpr(.intLiteral(321), type: intType)
        let callerResultExpr = arena.appendExpr(.temporary(1), type: intType)

        let inlineFunction = KIRFunction(
            symbol: inlineSymbol,
            name: inlineName,
            params: [KIRParameter(symbol: hiddenTokenSymbol, type: intType)],
            returnType: intType,
            body: [
                .constValue(result: inlineTokenExpr, value: .symbolRef(typeParameterSymbol)),
                .returnValue(inlineTokenExpr)
            ],
            isSuspend: false,
            isInline: true
        )
        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: mainName,
            params: [],
            returnType: intType,
            body: [
                .constValue(result: callerTokenExpr, value: .intLiteral(321)),
                .call(
                    symbol: inlineSymbol,
                    callee: inlineName,
                    arguments: [callerTokenExpr],
                    result: callerResultExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callerResultExpr)
            ],
            isSuspend: false,
            isInline: false
        )

        let mainDeclID = arena.appendDecl(.function(mainFunction))
        _ = arena.appendDecl(.function(inlineFunction))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDeclID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineReifiedToken",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.kir = module
        ctx.sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )

        try LoweringPhase().run(ctx)

        guard case .function(let loweredMain)? = module.arena.decl(mainDeclID) else {
            XCTFail("Expected lowered main function.")
            return
        }

        let loweredCallees = loweredMain.body.compactMap { instruction -> InternedString? in
            guard case .call(_, let callee, _, _, _, _, _) = instruction else {
                return nil
            }
            return callee
        }
        XCTAssertFalse(loweredCallees.contains(inlineName))

        let symbolRefConstants = loweredMain.body.compactMap { instruction -> SymbolID? in
            guard case .constValue(_, let value) = instruction,
                  case .symbolRef(let symbol) = value else {
                return nil
            }
            return symbol
        }
        XCTAssertFalse(symbolRefConstants.contains(typeParameterSymbol))

        let returnExpr = try XCTUnwrap(loweredMain.body.compactMap { instruction -> KIRExprID? in
            guard case .returnValue(let value) = instruction else {
                return nil
            }
            return value
        }.first)
        guard case .intLiteral(let returnedLiteral)? = module.arena.expr(returnExpr) else {
            XCTFail("Expected inline result to resolve to hidden token argument value.")
            return
        }
        XCTAssertEqual(returnedLiteral, 321)
    }

    // MARK: - Coroutine Launcher Arg Tests

    func testCoroutineLauncherWithArgBearingSuspendFunctionGeneratesThunk() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 800)
        let suspendSymbol = SymbolID(rawValue: 801)
        let suspendParamSymbol = SymbolID(rawValue: 802)

        let funcRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let argExpr = arena.appendExpr(.intLiteral(42))
        let launcherResult = arena.appendExpr(.temporary(2))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: argExpr, value: .intLiteral(42)),
                .call(
                    symbol: nil,
                    callee: interner.intern("runBlocking"),
                    arguments: [funcRefExpr, argExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(launcherResult)
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("compute"),
            params: [KIRParameter(symbol: suspendParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [.returnValue(arena.appendExpr(.symbolRef(suspendParamSymbol)))],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "LauncherArgTest",
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

        let thunkFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let fn) = decl else { return nil }
            return interner.resolve(fn.name).hasPrefix("kk_launcher_thunk_") ? fn : nil
        }
        XCTAssertEqual(thunkFunctions.count, 1)
        let thunk = try XCTUnwrap(thunkFunctions.first)
        XCTAssertEqual(thunk.params.count, 1)

        let thunkCallees = thunk.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(thunkCallees.contains("kk_coroutine_launcher_arg_get"))
        XCTAssertTrue(thunkCallees.contains(where: { $0.hasPrefix("kk_suspend_") }))

        guard case .function(let loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(mainCallees.contains("kk_coroutine_continuation_new"))
        XCTAssertTrue(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        XCTAssertTrue(mainCallees.contains("kk_kxmini_run_blocking_with_cont"))
        XCTAssertFalse(mainCallees.contains("runBlocking"))

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    func testCoroutineLauncherZeroArgSuspendStillUsesOriginalPath() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 810)
        let suspendSymbol = SymbolID(rawValue: 811)

        let funcRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let launcherResult = arena.appendExpr(.temporary(1))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("runBlocking"),
                    arguments: [funcRefExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(launcherResult)
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("simple"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "LauncherZeroArgTest",
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

        guard case .function(let loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(mainCallees.contains("kk_kxmini_run_blocking"))
        XCTAssertFalse(mainCallees.contains("kk_kxmini_run_blocking_with_cont"))
        XCTAssertFalse(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    func testCoroutineLauncherWithSuspendLambdaCapturesGeneratesThunk() throws {
        // Simulates: val x = 42; runBlocking { x }
        // The lambda captures `x`, so it has 1 capture param and 0 value params.
        // The launcher call should include the capture value as an extra arg,
        // and the CoroutineLoweringPass should generate a thunk that forwards it.
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 820)
        let lambdaSymbol = SymbolID(rawValue: 821)
        let captureParamSymbol = SymbolID(rawValue: 822)

        let captureValueExpr = arena.appendExpr(.intLiteral(42))
        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol))
        let launcherResult = arena.appendExpr(.temporary(2))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: captureValueExpr, value: .intLiteral(42)),
                .constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: nil,
                    callee: interner.intern("runBlocking"),
                    arguments: [lambdaRefExpr, captureValueExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(launcherResult)
            ],
            isSuspend: false,
            isInline: false
        )

        // Lambda function with 1 capture param, isSuspend: true
        let lambdaFn = KIRFunction(
            symbol: lambdaSymbol,
            name: interner.intern("kk_lambda_99"),
            params: [KIRParameter(symbol: captureParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [.returnValue(arena.appendExpr(.symbolRef(captureParamSymbol)))],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "LauncherLambdaCaptureTest",
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

        // Should generate a thunk for the lambda (1 capture param)
        let thunkFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let fn) = decl else { return nil }
            return interner.resolve(fn.name).hasPrefix("kk_launcher_thunk_") ? fn : nil
        }
        XCTAssertEqual(thunkFunctions.count, 1)
        let thunk = try XCTUnwrap(thunkFunctions.first)
        XCTAssertEqual(thunk.params.count, 1)

        let thunkCallees = thunk.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(thunkCallees.contains("kk_coroutine_launcher_arg_get"))
        XCTAssertTrue(thunkCallees.contains(where: { $0.hasPrefix("kk_suspend_") }))

        // Main should use the _with_cont path and store capture via arg_set
        guard case .function(let loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(mainCallees.contains("kk_coroutine_continuation_new"))
        XCTAssertTrue(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        XCTAssertTrue(mainCallees.contains("kk_kxmini_run_blocking_with_cont"))
        XCTAssertFalse(mainCallees.contains("runBlocking"))

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    func testCoroutineLauncherWithZeroCapturesSuspendLambdaUsesOriginalPath() throws {
        // Simulates: runBlocking { 42 }
        // The lambda has no captures and no value params → uses zero-arg path.
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 830)
        let lambdaSymbol = SymbolID(rawValue: 831)

        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol))
        let launcherResult = arena.appendExpr(.temporary(1))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: nil,
                    callee: interner.intern("runBlocking"),
                    arguments: [lambdaRefExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(launcherResult)
            ],
            isSuspend: false,
            isInline: false
        )

        // Lambda with no params (no captures, no value params)
        let lambdaFn = KIRFunction(
            symbol: lambdaSymbol,
            name: interner.intern("kk_lambda_100"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [.returnValue(arena.appendExpr(.intLiteral(42)))],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "LauncherLambdaZeroCaptureTest",
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

        guard case .function(let loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        // Zero-arg path: should use kk_kxmini_run_blocking, NOT _with_cont
        XCTAssertTrue(mainCallees.contains("kk_kxmini_run_blocking"))
        XCTAssertFalse(mainCallees.contains("kk_kxmini_run_blocking_with_cont"))
        XCTAssertFalse(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    func testCoroutineLauncherLaunchWithSuspendLambdaCapturesGeneratesThunk() throws {
        // Verify that launch correctly handles lambdas with captures
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 840)
        let lambdaSymbol = SymbolID(rawValue: 841)
        let captureParamSymbol = SymbolID(rawValue: 842)

        let captureValueExpr = arena.appendExpr(.intLiteral(10))
        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol))
        let launcherResult = arena.appendExpr(.temporary(2))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: captureValueExpr, value: .intLiteral(10)),
                .constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: nil,
                    callee: interner.intern("launch"),
                    arguments: [lambdaRefExpr, captureValueExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(launcherResult)
            ],
            isSuspend: false,
            isInline: false
        )

        let lambdaFn = KIRFunction(
            symbol: lambdaSymbol,
            name: interner.intern("kk_lambda_101"),
            params: [KIRParameter(symbol: captureParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "LauncherLaunchLambdaTest",
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

        let thunkFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let fn) = decl else { return nil }
            return interner.resolve(fn.name).hasPrefix("kk_launcher_thunk_") ? fn : nil
        }
        XCTAssertEqual(thunkFunctions.count, 1)

        guard case .function(let loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(mainCallees.contains("kk_kxmini_launch_with_cont"))
        XCTAssertTrue(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        XCTAssertFalse(mainCallees.contains("launch"))

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    // MARK: - ABI Boxing/Unboxing Tests

    func testABILoweringBoxesIntArgumentForAnyParameter() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 3000)
        let targetSym = SymbolID(rawValue: 3001)
        let targetParamSym = SymbolID(rawValue: 3002)

        let targetName = interner.intern("acceptAny")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyNullableType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.intLiteral(42), type: intType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: anyNullableType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIBoxInt", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int call for Int -> Any? boxing, got: \(callees)")
    }

    func testABILoweringBoxesBoolArgumentForAnyParameter() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 3100)
        let targetSym = SymbolID(rawValue: 3101)
        let targetParamSym = SymbolID(rawValue: 3102)

        let targetName = interner.intern("acceptAny")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyNullableType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.boolLiteral(true), type: boolType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: anyNullableType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIBoxBool", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_bool"), "Expected kk_box_bool call for Bool -> Any? boxing, got: \(callees)")
    }

    func testABILoweringBoxesIntToNullableIntParameter() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))

        let callerSym = SymbolID(rawValue: 3200)
        let targetSym = SymbolID(rawValue: 3201)
        let targetParamSym = SymbolID(rawValue: 3202)

        let targetName = interner.intern("acceptNullableInt")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [nullableIntType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.intLiteral(7), type: intType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: nullableIntType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIBoxNullableInt", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int call for Int -> Int? boxing, got: \(callees)")
    }

    func testABILoweringUnboxesAnyReturnToIntResult() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 3300)
        let targetSym = SymbolID(rawValue: 3301)

        let targetName = interner.intern("getAny")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: anyNullableType),
            for: targetSym
        )

        let resultExpr = arena.appendExpr(.temporary(0), type: intType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [],
            returnType: anyNullableType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIUnboxAny", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_unbox_int"), "Expected kk_unbox_int call for Any? -> Int unboxing, got: \(callees)")
    }

    func testABILoweringUnboxesNullableIntReturnToNonNullInt() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))

        let callerSym = SymbolID(rawValue: 3400)
        let targetSym = SymbolID(rawValue: 3401)

        let targetName = interner.intern("getNullableInt")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: nullableIntType),
            for: targetSym
        )

        let resultExpr = arena.appendExpr(.temporary(0), type: intType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [],
            returnType: nullableIntType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIUnboxNullableInt", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_unbox_int"), "Expected kk_unbox_int call for Int? -> Int unboxing, got: \(callees)")
    }

    func testABILoweringBoxesReturnValueWhenFunctionReturnsAny() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let fnSym = SymbolID(rawValue: 3500)
        let valueExpr = arena.appendExpr(.intLiteral(42), type: intType)

        let fn = KIRFunction(
            symbol: fnSym,
            name: interner.intern("returnBoxed"),
            params: [],
            returnType: anyNullableType,
            body: [
                .returnValue(valueExpr)
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIBoxReturn", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "returnBoxed", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int before returnValue for Any? return type, got: \(callees)")
    }

    func testABILoweringBoxesCopyFromIntToAnySlot() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let fnSym = SymbolID(rawValue: 3600)
        let fromExpr = arena.appendExpr(.intLiteral(10), type: intType)
        let toExpr = arena.appendExpr(.temporary(1), type: anyNullableType)

        let fn = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyBoxed"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABICopyBox", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "copyBoxed", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int for copy Int -> Any?, got: \(callees)")
        // Verify that the copy instruction was replaced (no copy should remain)
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        XCTAssertFalse(hasCopy, "Expected copy to be replaced with boxing call")
    }

    func testABILoweringUnboxesCopyFromAnyToIntSlot() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let fnSym = SymbolID(rawValue: 3700)
        let fromExpr = arena.appendExpr(.temporary(0), type: anyNullableType)
        let toExpr = arena.appendExpr(.temporary(1), type: intType)

        let fn = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyUnboxed"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABICopyUnbox", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "copyUnboxed", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_unbox_int"), "Expected kk_unbox_int for copy Any? -> Int, got: \(callees)")
        // Verify that the copy instruction was replaced
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        XCTAssertFalse(hasCopy, "Expected copy to be replaced with unboxing call")
    }

    func testABILoweringBoxesAllPrimitiveTypesForAnyParameter() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let anyNullableType = types.make(.any(.nullable))

        // Define primitives and their expected boxing callees
        let primitives: [(TypeKind, KIRExprKind, String)] = [
            (.primitive(.int, .nonNull), .intLiteral(1), "kk_box_int"),
            (.primitive(.boolean, .nonNull), .boolLiteral(true), "kk_box_bool"),
            (.primitive(.long, .nonNull), .longLiteral(1), "kk_box_long"),
            (.primitive(.float, .nonNull), .floatLiteral(1), "kk_box_float"),
            (.primitive(.double, .nonNull), .doubleLiteral(1), "kk_box_double"),
            (.primitive(.char, .nonNull), .charLiteral(65), "kk_box_char"),
        ]

        for (index, (kind, exprKind, expectedCallee)) in primitives.enumerated() {
            let testArena = KIRArena()
            let primType = types.make(kind)

            let callerSym = SymbolID(rawValue: Int32(4000 + index * 10))
            let targetSym = SymbolID(rawValue: Int32(4001 + index * 10))
            let targetParamSym = SymbolID(rawValue: Int32(4002 + index * 10))
            let targetName = interner.intern("accept_\(expectedCallee)")

            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [anyNullableType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
                for: targetSym
            )

            let argExpr = testArena.appendExpr(exprKind, type: primType)
            let resultExpr = testArena.appendExpr(.temporary(1), type: types.unitType)

            let callerFn = KIRFunction(
                symbol: callerSym,
                name: interner.intern("main"),
                params: [],
                returnType: types.unitType,
                body: [
                    .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                    .returnUnit
                ],
                isSuspend: false,
                isInline: false
            )
            let targetFn = KIRFunction(
                symbol: targetSym,
                name: targetName,
                params: [KIRParameter(symbol: targetParamSym, type: anyNullableType)],
                returnType: types.unitType,
                body: [.returnUnit],
                isSuspend: false,
                isInline: false
            )

            let callerID = testArena.appendDecl(.function(callerFn))
            _ = testArena.appendDecl(.function(targetFn))
            let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: testArena)

            let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
            let ctx = CompilationContext(
                options: CompilerOptions(moduleName: "ABIBoxAll_\(index)", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: interner
            )
            ctx.kir = module
            ctx.sema = sema

            try LoweringPhase().run(ctx)

            let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
            let callees = extractCallees(from: lowered.body, interner: interner)
            XCTAssertTrue(callees.contains(expectedCallee), "Expected \(expectedCallee) for \(kind) -> Any? boxing, got: \(callees)")
        }
    }

    func testABILoweringBoxesCopyFromNonNullIntToNullableIntSlot() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))

        let fnSym = SymbolID(rawValue: 3800)
        let fromExpr = arena.appendExpr(.intLiteral(5), type: intType)
        let toExpr = arena.appendExpr(.temporary(1), type: nullableIntType)

        let fn = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyNullableBox"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABICopyNullableBox", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "copyNullableBox", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int for copy Int -> Int?, got: \(callees)")
    }

    // MARK: - Property Lowering Tests

    /// Verify that a get call with a property symbol is rewritten to a direct
    /// accessor call using the synthetic getter symbol (-12_000 - propertySymbol).
    func testPropertyLoweringRewritesGetterCallToDirectAccessorSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let propertySym = SymbolID(rawValue: 50)
        let callerSym = SymbolID(rawValue: 51)

        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let result = arena.appendExpr(.temporary(1), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: propertySym,
                    callee: interner.intern("get"),
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "PropGetter", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        try LoweringPhase().run(ctx)

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The getter call should use the synthetic accessor symbol.
        let expectedGetterSymbol = SymbolID(rawValue: -12_000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case .call(let sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedGetterSymbol),
                       "Expected synthetic getter symbol \(expectedGetterSymbol), got: \(callSymbols)")

        // kk_property_access must NOT appear.
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    /// Verify that a set call with a property symbol is rewritten to a direct
    /// accessor call using the synthetic setter symbol (-13_000 - propertySymbol).
    func testPropertyLoweringRewritesSetterCallToDirectAccessorSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let propertySym = SymbolID(rawValue: 60)
        let callerSym = SymbolID(rawValue: 61)

        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let value = arena.appendExpr(.temporary(1), type: types.anyType)
        let result = arena.appendExpr(.temporary(2), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("setter_caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: propertySym,
                    callee: interner.intern("set"),
                    arguments: [receiver, value],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "PropSetter", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        try LoweringPhase().run(ctx)

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        let expectedSetterSymbol = SymbolID(rawValue: -13_000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case .call(let sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedSetterSymbol),
                       "Expected synthetic setter symbol \(expectedSetterSymbol), got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    /// Verify that get/set calls without a property symbol are left unchanged.
    func testPropertyLoweringPreservesGetSetCallsWithoutSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 70)
        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let result = arena.appendExpr(.temporary(1), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("no_sym_caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("get"),
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "PropNoSym", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        try LoweringPhase().run(ctx)

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The call should remain unchanged (no symbol to derive accessor from).
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("get"))
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    /// Verify that backing field copy is rewritten to a direct setter call.
    func testPropertyLoweringRewritesBackingFieldCopyToDirectSetterCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        // Create a property symbol and its backing field symbol.
        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("myProp"),
            fqName: [interner.intern("Foo"), interner.intern("myProp")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let backingFieldSym = symbols.define(
            kind: .backingField,
            name: interner.intern("$backing_myProp"),
            fqName: [interner.intern("Foo"), interner.intern("$backing_myProp")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setBackingFieldSymbol(backingFieldSym, for: propertySym)

        let callerSym = SymbolID(rawValue: 100)
        let fromExpr = arena.appendExpr(.intLiteral(42), type: types.anyType)
        let toExpr = arena.appendExpr(.symbolRef(backingFieldSym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("bf_setter"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "BFSetter", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema
        try LoweringPhase().run(ctx)

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The copy should be rewritten to a set call with the synthetic setter
        // symbol derived from the property (not the backing field).
        let expectedSetterSymbol = SymbolID(rawValue: -13_000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case .call(let sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedSetterSymbol),
                       "Expected setter symbol \(expectedSetterSymbol) for backing field copy, got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("set"))
        XCTAssertFalse(callees.contains("kk_property_access"))

        // Verify no copy instruction remains for the backing field.
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        XCTAssertFalse(hasCopy, "Backing field copy should have been rewritten to a setter call")
    }

    // MARK: - Private Helpers

    private struct LoweringRewriteFixture {
        let interner: StringInterner
        let module: KIRModule
        let mainID: KIRDeclID
        let emptyID: KIRDeclID
    }

    private func makeLoweringRewriteFixture() throws -> LoweringRewriteFixture {
        let interner = StringInterner()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 10)
        let inlineSym = SymbolID(rawValue: 11)
        let suspendSym = SymbolID(rawValue: 12)
        let emptySym = SymbolID(rawValue: 13)

        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let v2 = arena.appendExpr(.temporary(2))
        let v3 = arena.appendExpr(.temporary(3))
        let vFalse = arena.appendExpr(.boolLiteral(false))

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("kk_range_iterator"), arguments: [v0], result: v3, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_for_lowered"), arguments: [v3], result: v1, canThrow: false, thrownResult: nil),
                .constValue(result: vFalse, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: v0, rhs: vFalse, target: 800),
                .jump(801),
                .label(800),
                .copy(from: v2, to: v1),
                .label(801),
                .call(symbol: nil, callee: interner.intern("get"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("set"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("<lambda>"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("inlineTarget"), arguments: [], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("suspendTarget"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )
        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("inlineTarget"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: true
        )
        let suspendFn = KIRFunction(
            symbol: suspendSym,
            name: interner.intern("suspendTarget"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: v2, canThrow: false, thrownResult: nil),
                .returnValue(v2)
            ],
            isSuspend: true,
            isInline: false
        )
        let emptyFn = KIRFunction(
            symbol: emptySym,
            name: interner.intern("empty"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(inlineFn))
        _ = arena.appendDecl(.function(suspendFn))
        let emptyID = arena.appendDecl(.function(emptyFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID, emptyID])], arena: arena)

        let options = CompilerOptions(
            moduleName: "Lowering",
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

        return LoweringRewriteFixture(interner: interner, module: module, mainID: mainID, emptyID: emptyID)
    }
}
