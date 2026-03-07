@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testLLVMBackendCanLinkAndRunExecutable() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let options = CompilerOptions(
                moduleName: "LLVMExe",
                inputs: [path],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            XCTAssertEqual(result.exitCode, 0)
        }
    }

    func testLLVMBackendEmitsRuntimeStringAndCoroutineHelpersInLLVMIR() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let left = interner.intern("left")
        let right = interner.intern("right")

        let leftExpr = arena.appendExpr(.stringLiteral(left))
        let rightExpr = arena.appendExpr(.stringLiteral(right))
        let concatResult = arena.appendExpr(.temporary(0))
        let suspendedResult = arena.appendExpr(.temporary(1))
        let labelValue = arena.appendExpr(.intLiteral(7))
        let labelResult = arena.appendExpr(.temporary(2))
        let spillSlotValue = arena.appendExpr(.intLiteral(0))
        let spillStored = arena.appendExpr(.temporary(3))
        let spillLoaded = arena.appendExpr(.temporary(4))
        let completionStored = arena.appendExpr(.temporary(5))
        let completionLoaded = arena.appendExpr(.temporary(6))
        let throwingResult = arena.appendExpr(.temporary(7))
        let whenCondition = arena.appendExpr(.boolLiteral(true))
        let whenResult = arena.appendExpr(.temporary(8))
        let falseConst = arena.appendExpr(.boolLiteral(false))
        let continuationResult = arena.appendExpr(.temporary(10))
        let stateExitResult = arena.appendExpr(.temporary(11))

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1200),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: leftExpr, value: .stringLiteral(left)),
                .constValue(result: rightExpr, value: .stringLiteral(right)),
                .call(symbol: nil, callee: interner.intern("kk_string_concat"), arguments: [leftExpr, rightExpr], result: concatResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_coroutine_suspended"), arguments: [], result: suspendedResult, canThrow: false, thrownResult: nil),
                .constValue(result: labelValue, value: .intLiteral(7)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_set_label"),
                    arguments: [suspendedResult, labelValue],
                    result: labelResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .constValue(result: spillSlotValue, value: .intLiteral(0)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_set_spill"),
                    arguments: [suspendedResult, spillSlotValue, concatResult],
                    result: spillStored,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_get_spill"),
                    arguments: [suspendedResult, spillSlotValue],
                    result: spillLoaded,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_set_completion"),
                    arguments: [suspendedResult, spillLoaded],
                    result: completionStored,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_get_completion"),
                    arguments: [suspendedResult],
                    result: completionLoaded,
                    canThrow: false,
                    thrownResult: nil
                ),
                // Control flow for if/when: branch on condition == false
                .constValue(result: falseConst, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: whenCondition, rhs: falseConst, target: 900),
                .copy(from: concatResult, to: whenResult),
                .jump(901),
                .label(900),
                .copy(from: completionLoaded, to: whenResult),
                .label(901),
                .call(symbol: nil, callee: interner.intern("println"), arguments: [whenResult], result: nil, canThrow: false, thrownResult: nil),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_continuation_new"),
                    arguments: [labelValue],
                    result: continuationResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_exit"),
                    arguments: [continuationResult, completionLoaded],
                    result: stateExitResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: throwingResult, canThrow: true, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, runtime: runtime, outputIRPath: irPath, interner: interner)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        XCTAssertTrue(ir.contains("@kk_string_from_utf8"))
        XCTAssertTrue(ir.contains("@kk_string_concat"))
        XCTAssertTrue(ir.contains("@kk_coroutine_suspended"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_set_label"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_set_spill"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_get_spill"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_set_completion"))
        XCTAssertTrue(ir.contains("@kk_coroutine_state_get_completion"))
        XCTAssertTrue(ir.contains("@kk_println_any"))
        XCTAssertTrue(ir.contains("@kk_register_frame_map"))
        XCTAssertTrue(ir.contains("@kk_push_frame"))
        XCTAssertTrue(ir.contains("@kk_pop_frame"))
        XCTAssertTrue(ir.contains("@kk_register_coroutine_root"))
        XCTAssertTrue(ir.contains("@kk_unregister_coroutine_root"))
        XCTAssertTrue(ir.contains("coroutine_root_register"))
        XCTAssertTrue(ir.contains("coroutine_root_unregister"))
        // select i1 no longer emitted; control flow uses conditional branches instead
        let hasConditionalBranch = ir.contains("br i1") || ir.contains("icmp eq")
        XCTAssertTrue(hasConditionalBranch)
        XCTAssertTrue(ir.contains("thrown_slot_"))
        XCTAssertTrue(ir.contains("@external_throwing"))
    }

    func testLlvmBindingsCandidatePathsHonorEnvironmentOverride() {
        // Create a temp file so the existence check passes.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".dylib")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let overridePath = tempURL.path
        let resolvedPath = URL(fileURLWithPath: overridePath).standardized.path
        let paths = LLVMCAPIBindings.candidateLibraryPaths(environment: ["KSWIFTK_LLVM_DYLIB": overridePath])
        XCTAssertEqual(paths.first, resolvedPath)
        XCTAssertTrue(paths.contains("libLLVM.dylib"))

        // Non-existent paths are rejected and not added to candidates.
        let missing = "/tmp/does-not-exist-kswiftk-\(UUID().uuidString).dylib"
        let pathsWithMissing = LLVMCAPIBindings.candidateLibraryPaths(environment: ["KSWIFTK_LLVM_DYLIB": missing])
        XCTAssertFalse(pathsWithMissing.contains(missing))
    }

    func testLlvmBindingsCandidatePathsIncludeVersionedLibrariesFromLibraryPath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let versionedLibrary = tempDirectory.appendingPathComponent("libLLVM-18.so")
        FileManager.default.createFile(atPath: versionedLibrary.path, contents: Data())

        let paths = LLVMCAPIBindings.candidateLibraryPaths(environment: [
            "LIBRARY_PATH": tempDirectory.path,
        ])

        XCTAssertTrue(paths.contains(versionedLibrary.standardized.path))
    }

    func testCodegenFunctionSymbolSanitizesNames() {
        let interner = StringInterner()
        let fnName = CodegenSymbolSupport.cFunctionSymbol(
            for: KIRFunction(
                symbol: SymbolID(rawValue: 9),
                name: interner.intern("1 bad-name"),
                params: [],
                returnType: TypeSystem().unitType,
                body: [.returnUnit],
                isSuspend: false,
                isInline: false
            ),
            interner: interner
        )
        XCTAssertTrue(fnName.hasPrefix("kk_fn__1_bad_name_9"))
    }
}
