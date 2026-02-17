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
        XCTAssertTrue(callees.contains("iterator"))
        XCTAssertTrue(callees.contains("hasNext"))
        XCTAssertTrue(callees.contains("next"))
        XCTAssertFalse(callees.contains("kk_for_lowered"))
        XCTAssertTrue(callees.contains("kk_when_select"))
        XCTAssertTrue(callees.contains("kk_property_access"))
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
            guard case .call(_, let callee, _, _, _, _) = instruction else {
                return false
            }
            return interner.resolve(callee) == "susp"
        }
        XCTAssertFalse(rawSuspendCalls)

        let rewrittenSuspendCalls = loweredCaller.body.compactMap { instruction -> (name: String, arity: Int, canThrow: Bool)? in
            guard case .call(_, let callee, let arguments, _, let canThrow, _) = instruction else {
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
            guard case .call(_, let callee, _, _, _, _) = instruction else {
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

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("iterator"), arguments: [v0], result: v3, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_for_lowered"), arguments: [v3], result: v1, canThrow: false, thrownResult: nil),
                .select(condition: v0, thenValue: v1, elseValue: v2, result: v1),
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
