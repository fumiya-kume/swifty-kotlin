@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {
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
            guard case let .function(fn) = decl else { return nil }
            return interner.resolve(fn.name).hasPrefix("kk_launcher_thunk_") ? fn : nil
        }
        XCTAssertEqual(thunkFunctions.count, 1)
        let thunk = try XCTUnwrap(thunkFunctions.first)
        XCTAssertEqual(thunk.params.count, 1)

        let thunkCallees = thunk.body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(thunkCallees.contains("kk_coroutine_launcher_arg_get"))
        XCTAssertTrue(thunkCallees.contains(where: { $0.hasPrefix("kk_suspend_") }))

        guard case let .function(loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
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

        guard case let .function(loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
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
            guard case let .function(fn) = decl else { return nil }
            return interner.resolve(fn.name).hasPrefix("kk_launcher_thunk_") ? fn : nil
        }
        XCTAssertEqual(thunkFunctions.count, 1)
        let thunk = try XCTUnwrap(thunkFunctions.first)
        XCTAssertEqual(thunk.params.count, 1)

        let thunkCallees = thunk.body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(thunkCallees.contains("kk_coroutine_launcher_arg_get"))
        XCTAssertTrue(thunkCallees.contains(where: { $0.hasPrefix("kk_suspend_") }))

        // Main should use the _with_cont path and store capture via arg_set
        guard case let .function(loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
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

        guard case let .function(loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
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
            guard case let .function(fn) = decl else { return nil }
            return interner.resolve(fn.name).hasPrefix("kk_launcher_thunk_") ? fn : nil
        }
        XCTAssertEqual(thunkFunctions.count, 1)

        guard case let .function(loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }
        let mainCallees = loweredMain.body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(mainCallees.contains("kk_kxmini_launch_with_cont"))
        XCTAssertTrue(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        XCTAssertFalse(mainCallees.contains("launch"))

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    // MARK: - ABI Boxing/Unboxing Tests
}
