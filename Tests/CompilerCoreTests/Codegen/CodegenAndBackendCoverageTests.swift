import Foundation
import XCTest
@testable import CompilerCore

final class CodegenAndBackendCoverageTests: XCTestCase {
    func testCodegenEmitsKirDumpArtifact() throws {
        let source = """
        inline fun helper(x: Int) = x + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory

            let kirBase = tempDir.appendingPathComponent(UUID().uuidString).path
            _ = try runCodegenPipeline(inputPath: path, moduleName: "KirMod", emit: .kirDump, outputPath: kirBase)
            XCTAssertTrue(FileManager.default.fileExists(atPath: kirBase + ".kir"))
        }
    }

    func testCodegenEmitsLlvmIRArtifact() throws {
        let source = """
        inline fun helper(x: Int) = x + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory
            let llvmBase = tempDir.appendingPathComponent(UUID().uuidString).path
            let llvmCtx = try runCodegenPipeline(inputPath: path, moduleName: "LLMod", emit: .llvmIR, outputPath: llvmBase)
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            XCTAssertTrue(llvmPath.hasSuffix(".ll"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: llvmPath))
        }
    }

    func testCodegenEmitsLibraryArtifacts() throws {
        let source = """
        inline fun helper(x: Int) = x + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory
            let libBase = tempDir.appendingPathComponent(UUID().uuidString).path
            _ = try runCodegenPipeline(inputPath: path, moduleName: "LibMod", emit: .library, outputPath: libBase)

            let libDir = libBase + ".kklib"
            let manifestPath = libDir + "/manifest.json"
            let metadataPath = libDir + "/metadata.bin"
            let objectPath = libDir + "/objects/LibMod_0.o"
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifestPath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: metadataPath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))

            let manifest = try String(contentsOfFile: manifestPath, encoding: .utf8)
            XCTAssertTrue(manifest.contains("\"moduleName\": \"LibMod\""))

            let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
            XCTAssertTrue(metadata.contains("symbols="))

            let inlineDir = libDir + "/inline-kir"
            let inlineFiles = try FileManager.default.contentsOfDirectory(atPath: inlineDir)
            XCTAssertFalse(inlineFiles.isEmpty)
            XCTAssertTrue(inlineFiles.allSatisfy { $0.hasSuffix(".kirbin") })
        }
    }

    func testCodegenProducesDeterministicKirOutput() throws {
        let source = """
        fun helper(x: Int, y: Int) = x + y
        fun main() = helper(40, 2)
        """
        try assertDeterministicCodegenOutput(source: source, emit: .kirDump)
    }

    func testCodegenProducesDeterministicLlvmIROutput() throws {
        let source = """
        fun helper(x: Int, y: Int) = x + y
        fun main() = helper(40, 2)
        """
        try assertDeterministicCodegenOutput(source: source, emit: .llvmIR)
    }

    func testCodegenProducesDeterministicObjectOutput() throws {
        let source = """
        fun helper(x: Int, y: Int) = x + y
        fun main() = helper(40, 2)
        """
        try assertDeterministicCodegenOutput(source: source, emit: .object)
    }

    func testCodegenBackendSelectionSupportsLlvmCApiFlag() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "LLVMCAPIFlag",
                inputs: [path],
                outputPath: outputBase,
                emit: .object,
                target: defaultTargetTriple(),
                irFlags: ["backend=llvm-c-api"]
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            if llvmCapiBindingsAvailable() {
                try CodegenPhase().run(ctx)

                let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
                XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
                XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
            } else {
                XCTAssertThrowsError(try CodegenPhase().run(ctx))
                XCTAssertTrue(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-1007" })
            }
        }
    }

    func testCodegenBackendSelectionWarnsOnUnknownBackendAndFallsBack() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "UnknownBackendFlag",
                inputs: [path],
                outputPath: outputBase,
                emit: .object,
                target: defaultTargetTriple(),
                irFlags: ["backend=unknown-backend"]
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

            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
            XCTAssertTrue(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-1002" })
        }
    }

    func testCodegenBackendSelectionLlvmCApiStrictModeFails() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "LLVMCAPIStrict",
                inputs: [path],
                outputPath: outputBase,
                emit: .object,
                target: defaultTargetTriple(),
                irFlags: ["backend=llvm-c-api", "backend-strict=true"]
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            do {
                try CodegenPhase().run(ctx)
                let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
                XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
                XCTAssertFalse(ctx.diagnostics.diagnostics.contains {
                    $0.code == "KSWIFTK-BACKEND-1003" || $0.code == "KSWIFTK-BACKEND-1004"
                })
            } catch {
                XCTAssertTrue(ctx.diagnostics.diagnostics.contains {
                    $0.code == "KSWIFTK-BACKEND-1003" || $0.code == "KSWIFTK-BACKEND-1004"
                })
            }
        }
    }

    func testLlvmCapiBackendNativeFailureReportsErrorWithoutFallback() throws {
        guard let bindings = LLVMCAPIBindings.load(),
              bindings.smokeTestContextLifecycle() else {
            throw XCTSkip("LLVM C API bindings are unavailable in this environment.")
        }

        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 2500),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])],
            arena: arena
        )

        let backend = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: diagnostics,
            isStrictMode: false
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let missingObjectPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing")
            .appendingPathComponent("out.o")
            .path

        XCTAssertThrowsError(
            try backend.emitObject(
                module: module,
                runtime: runtime,
                outputObjectPath: missingObjectPath,
                interner: interner
            )
        )
        XCTAssertTrue(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-1006" })
        XCTAssertFalse(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-1005" })
    }

    func testCodegenBackendSelectionLlvmCApiAndSyntheticBackendObjectCompatibilitySmoke() throws {
        guard llvmCapiBindingsAvailable() else {
            throw XCTSkip("LLVM C API bindings are unavailable in this environment.")
        }

        let source = """
        fun helper(v: Int) = v + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory

            let syntheticBase = tempDir.appendingPathComponent(UUID().uuidString).path
            let syntheticOptions = CompilerOptions(
                moduleName: "CompatSynthetic",
                inputs: [path],
                outputPath: syntheticBase,
                emit: .object,
                target: defaultTargetTriple(),
                irFlags: ["backend=synthetic-c"]
            )
            let syntheticCtx = CompilationContext(
                options: syntheticOptions,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(syntheticCtx)
            try LoweringPhase().run(syntheticCtx)
            try CodegenPhase().run(syntheticCtx)
            let syntheticObject = try XCTUnwrap(syntheticCtx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: syntheticObject))

            let llvmCapiBase = tempDir.appendingPathComponent(UUID().uuidString).path
            let llvmCapiOptions = CompilerOptions(
                moduleName: "CompatLlvmCApi",
                inputs: [path],
                outputPath: llvmCapiBase,
                emit: .object,
                target: defaultTargetTriple(),
                irFlags: ["backend=llvm-c-api"]
            )
            let llvmCapiCtx = CompilationContext(
                options: llvmCapiOptions,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(llvmCapiCtx)
            try LoweringPhase().run(llvmCapiCtx)
            try CodegenPhase().run(llvmCapiCtx)
            let llvmCapiObject = try XCTUnwrap(llvmCapiCtx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: llvmCapiObject))

            let syntheticSize = (try? FileManager.default.attributesOfItem(atPath: syntheticObject)[.size] as? NSNumber)?.intValue ?? 0
            let llvmCapiSize = (try? FileManager.default.attributesOfItem(atPath: llvmCapiObject)[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(syntheticSize, 0)
            XCTAssertGreaterThan(llvmCapiSize, 0)
        }
    }

    func testLlvmCapiBackendCanLinkAndRunExecutable() throws {
        guard llvmCapiBindingsAvailable() else {
            throw XCTSkip("LLVM C API bindings are unavailable in this environment.")
        }

        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let options = CompilerOptions(
                moduleName: "LLVMCAPIExe",
                inputs: [path],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                irFlags: ["backend=llvm-c-api"]
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

    func testLlvmCapiBackendEmitsRuntimeStringAndCoroutineHelpersInLLVMIR() throws {
        guard let bindings = LLVMCAPIBindings.load(),
              bindings.smokeTestContextLifecycle() else {
            throw XCTSkip("LLVM C API bindings are unavailable in this environment.")
        }

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
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let backend = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine(),
            isStrictMode: true
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

    func testLlvmCapiBindingsCandidatePathsHonorEnvironmentOverride() {
        let overridePath = "/tmp/custom-libLLVM.dylib"
        let paths = LLVMCAPIBindings.candidateLibraryPaths(environment: ["KSWIFTK_LLVM_DYLIB": overridePath])
        XCTAssertEqual(paths.first, overridePath)
        XCTAssertTrue(paths.contains("libLLVM.dylib"))
    }

    func testLLVMBackendEmitsOutputsAndReportsCommandFailure() throws {
        let interner = StringInterner()
        let module = makeComplexKIRModule(interner: interner)
        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O2,
            debugInfo: true,
            diagnostics: DiagnosticEngine()
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let tempDir = FileManager.default.temporaryDirectory
        let irPath = tempDir.appendingPathComponent(UUID().uuidString + ".ll").path
        let objPath = tempDir.appendingPathComponent(UUID().uuidString + ".o").path

        try backend.emitLLVMIR(module: module, runtime: runtime, outputIRPath: irPath, interner: interner)
        try backend.emitObject(module: module, runtime: runtime, outputObjectPath: objPath, interner: interner)
        XCTAssertTrue(FileManager.default.fileExists(atPath: irPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: objPath))
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        XCTAssertTrue(ir.contains("!llvm.dbg.cu"))
        XCTAssertTrue(ir.contains("kk_register_frame_map"))
        XCTAssertTrue(ir.contains("kk_push_frame"))
        XCTAssertTrue(ir.contains("kk_pop_frame"))
        XCTAssertTrue(ir.contains("kk_frame_map_offsets_"))
        XCTAssertTrue(ir.contains("kk_register_module_globals"))
        XCTAssertTrue(ir.contains("kk_unregister_module_globals"))
        XCTAssertTrue(ir.contains("kk_register_global_root"))
        XCTAssertTrue(ir.contains("kk_unregister_global_root"))

        let fnName = LLVMBackend.cFunctionSymbol(
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

        let failingDiagnostics = DiagnosticEngine()
        let failingBackend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: failingDiagnostics
        )
        let missingDir = tempDir.appendingPathComponent(UUID().uuidString).path + "/sub/out.o"
        XCTAssertThrowsError(
            try failingBackend.emitObject(module: module, runtime: runtime, outputObjectPath: missingDir, interner: interner)
        )
        XCTAssertTrue(failingDiagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-0001" })
    }

    func testLLVMBackendEmitsCoroutineRootLifecycleHooks() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSymbol = SymbolID(rawValue: 990)
        let functionIDValue = arena.appendExpr(.intLiteral(7))
        let returnSeed = arena.appendExpr(.intLiteral(0))
        let continuation = arena.appendExpr(.temporary(1))
        let exited = arena.appendExpr(.temporary(2))

        let main = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.anyType,
            body: [
                .constValue(result: functionIDValue, value: .intLiteral(7)),
                .constValue(result: returnSeed, value: .intLiteral(0)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_continuation_new"),
                    arguments: [functionIDValue],
                    result: continuation,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_exit"),
                    arguments: [continuation, returnSeed],
                    result: exited,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(exited)
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)

        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, runtime: runtime, outputIRPath: irPath, interner: interner)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        XCTAssertTrue(ir.contains("call void @kk_register_coroutine_root"))
        XCTAssertTrue(ir.contains("call void @kk_unregister_coroutine_root"))
    }

    func testLLVMBackendSupportsExternalThrowChannelCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSymbol = SymbolID(rawValue: 910)
        let callResult = arena.appendExpr(.temporary(0))

        let main = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.anyType,
            body: [
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: callResult, canThrow: true, thrownResult: nil),
                .returnValue(callResult)
            ],
            isSuspend: false,
            isInline: false
        )
        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)

        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let objectPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o").path
        try backend.emitObject(module: module, runtime: runtime, outputObjectPath: objectPath, interner: interner)
        XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
    }

    // MARK: - Private Helpers

    private func runCodegenPipeline(inputPath: String, moduleName: String, emit: EmitMode, outputPath: String) throws -> CompilationContext {
        let ctx = makeCompilationContext(
            inputs: [inputPath],
            moduleName: moduleName,
            emit: emit,
            outputPath: outputPath
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    private func assertDeterministicCodegenOutput(source: String, emit: EmitMode) throws {
        try withTemporaryFile(contents: source) { path in
            let fm = FileManager.default
            let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: workDir) }

            let artifactBase1 = workDir.appendingPathComponent("deterministic_1").path
            let artifactBase2 = workDir.appendingPathComponent("deterministic_2").path
            var first = try readCodegenArtifact(inputPath: path, emit: emit, outputPath: artifactBase1)
            var second = try readCodegenArtifact(inputPath: path, emit: emit, outputPath: artifactBase2)
            if emit == .llvmIR {
                first = stripPathDependentLines(first)
                second = stripPathDependentLines(second)
            }
            if emit == .object {
                first = stripPathDependentBytes(first, outputPath: artifactBase1)
                second = stripPathDependentBytes(second, outputPath: artifactBase2)
            }
            XCTAssertEqual(first, second)
        }
    }

    private func stripPathDependentBytes(_ data: Data, outputPath: String) -> Data {
        // The synthetic C backend writes the generated C source to a temp path derived from
        // the output path.  clang then embeds that source filename inside the object file
        // (e.g. in the ELF .strtab or Mach-O STABS).  When we compile twice with different
        // output paths the embedded filenames differ, making the raw bytes non-equal even
        // though the code is identical.  Replacing every occurrence of the path-dependent
        // prefix with a fixed placeholder normalises the two objects so they can be compared.
        let prefix = "kswiftk_codegen_"
        guard let prefixData = prefix.data(using: .utf8) else { return data }
        var result = data
        // Find all occurrences of the prefix and zero-out the hex hash that follows until '.c'
        var searchStart = result.startIndex
        while let range = result.range(of: prefixData, in: searchStart..<result.endIndex) {
            let hashStart = range.upperBound
            // Find the end of the hash (look for '.c' or null byte)
            var hashEnd = hashStart
            while hashEnd < result.endIndex {
                let byte = result[hashEnd]
                if byte == 0x2E || byte == 0x00 { // '.' or null
                    break
                }
                hashEnd = result.index(after: hashEnd)
            }
            // Replace hash bytes with zeros
            for i in hashStart..<hashEnd {
                result[i] = 0x30 // '0'
            }
            searchStart = hashEnd
        }
        return result
    }

    private func stripPathDependentLines(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let filtered = text.components(separatedBy: "\n").filter { line in
            !line.hasPrefix("source_filename = ") && !line.hasPrefix("; ModuleID = ")
        }
        return Data(filtered.joined(separator: "\n").utf8)
    }

    private func readCodegenArtifact(inputPath: String, emit: EmitMode, outputPath: String) throws -> Data {
        let ctx = try runCodegenPipeline(
            inputPath: inputPath,
            moduleName: "Determinism",
            emit: emit,
            outputPath: outputPath
        )

        let artifactPath: String
        switch emit {
        case .kirDump:
            artifactPath = outputPath + ".kir"
        case .llvmIR:
            artifactPath = try XCTUnwrap(ctx.generatedLLVMIRPath)
        case .object:
            artifactPath = try XCTUnwrap(ctx.generatedObjectPath)
        default:
            XCTFail("unsupported emit for determinism test: \(emit)")
            artifactPath = outputPath
        }
        return try Data(contentsOf: URL(fileURLWithPath: artifactPath))
    }

    private func makeComplexKIRModule(interner: StringInterner) -> KIRModule {
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 1)
        let calleeSym = SymbolID(rawValue: 2)

        let e0 = arena.appendExpr(.intLiteral(10))
        let e1 = arena.appendExpr(.intLiteral(3))
        let e2 = arena.appendExpr(.boolLiteral(true))
        let e3 = arena.appendExpr(.stringLiteral(interner.intern("hello\\n\"world\"")))
        let e4 = arena.appendExpr(.symbolRef(calleeSym))
        let e5 = arena.appendExpr(.temporary(5))
        let e6 = arena.appendExpr(.temporary(6))
        let e7 = arena.appendExpr(.temporary(7))
        let e8 = arena.appendExpr(.temporary(8))
        let e9 = arena.appendExpr(.unit)
        let eFalse = arena.appendExpr(.boolLiteral(false))

        let callee = KIRFunction(
            symbol: calleeSym,
            name: interner.intern("callee"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let main = KIRFunction(
            symbol: mainSym,
            name: interner.intern("1-main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .nop,
                .beginBlock,
                .constValue(result: e0, value: .intLiteral(10)),
                .constValue(result: e1, value: .intLiteral(3)),
                .constValue(result: e2, value: .boolLiteral(true)),
                .constValue(result: e3, value: .stringLiteral(interner.intern("hello\\n\"world\""))),
                .constValue(result: e4, value: .symbolRef(calleeSym)),
                .constValue(result: e5, value: .temporary(99)),
                .constValue(result: e9, value: .unit),
                .binary(op: .add, lhs: e0, rhs: e1, result: e5),
                .binary(op: .subtract, lhs: e0, rhs: e1, result: e6),
                .binary(op: .multiply, lhs: e0, rhs: e1, result: e7),
                .binary(op: .divide, lhs: e0, rhs: e1, result: e8),
                .binary(op: .equal, lhs: e0, rhs: e1, result: e5),
                .call(symbol: nil, callee: interner.intern("println"), arguments: [e3], result: e5, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_println_any"), arguments: [e3], result: nil, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [e0, e1], result: e5, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_sub"), arguments: [e0, e1], result: e6, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_mul"), arguments: [e0, e1], result: e7, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_div"), arguments: [e0, e1], result: e8, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_eq"), arguments: [e0, e1], result: e5, canThrow: false, thrownResult: nil),
                .constValue(result: eFalse, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: e2, rhs: eFalse, target: 800),
                .copy(from: e0, to: e5),
                .jump(801),
                .label(800),
                .copy(from: e1, to: e5),
                .label(801),
                .call(symbol: calleeSym, callee: interner.intern("ignored"), arguments: [], result: e5, canThrow: false, thrownResult: nil),
                .returnValue(e5),
                .endBlock
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        _ = arena.appendDecl(.global(KIRGlobal(symbol: mainSym, type: TypeSystem().anyType)))
        _ = arena.appendDecl(.nominalType(KIRNominalType(symbol: mainSym)))
        _ = arena.appendDecl(.function(callee))

        return KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)
    }

    func testSyntheticCBackendObjectContainsDebugSectionWhenDebugInfoEnabled() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "DebugObj",
                inputs: [path],
                outputPath: outputBase,
                emit: .object,
                target: defaultTargetTriple(),
                debugInfo: true
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

            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            let objectData = try Data(contentsOf: URL(fileURLWithPath: objectPath))
            XCTAssertGreaterThan(objectData.count, 0)

            let noDebugBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let noDebugOptions = CompilerOptions(
                moduleName: "NoDebugObj",
                inputs: [path],
                outputPath: noDebugBase,
                emit: .object,
                target: defaultTargetTriple(),
                debugInfo: false
            )
            let noDebugCtx = CompilationContext(
                options: noDebugOptions,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(noDebugCtx)
            try LoweringPhase().run(noDebugCtx)
            try CodegenPhase().run(noDebugCtx)

            let noDebugObjectPath = try XCTUnwrap(noDebugCtx.generatedObjectPath)
            let noDebugData = try Data(contentsOf: URL(fileURLWithPath: noDebugObjectPath))
            XCTAssertGreaterThan(noDebugData.count, 0)
            XCTAssertGreaterThan(objectData.count, noDebugData.count)
        }
    }

    func testSyntheticCBackendLLVMIRContainsDebugFlagWhenDebugInfoEnabled() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "DebugIR",
                inputs: [path],
                outputPath: outputBase,
                emit: .llvmIR,
                target: defaultTargetTriple(),
                debugInfo: true
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

            let irPath = try XCTUnwrap(ctx.generatedLLVMIRPath)
            let irContent = try String(contentsOfFile: irPath, encoding: .utf8)
            XCTAssertTrue(
                irContent.contains("!llvm.dbg") || irContent.contains("debug") || irContent.contains("DW_TAG"),
                "LLVM IR should contain debug metadata when -g is enabled"
            )
        }
    }

    func testLlvmCapiBackendPassesDebugInfoToNativeEmitter() throws {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 3000),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])],
            arena: arena
        )

        let backendWithDebug = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: true,
            diagnostics: diagnostics,
            isStrictMode: false
        )
        let backendNoDebug = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: diagnostics,
            isStrictMode: false
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])

        if llvmCapiBindingsAvailable() {
            let debugIRPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_debug.ll").path
            let noDebugIRPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_nodebug.ll").path
            defer {
                try? FileManager.default.removeItem(atPath: debugIRPath)
                try? FileManager.default.removeItem(atPath: noDebugIRPath)
            }

            try backendWithDebug.emitLLVMIR(
                module: module,
                runtime: runtime,
                outputIRPath: debugIRPath,
                interner: interner
            )
            try backendNoDebug.emitLLVMIR(
                module: module,
                runtime: runtime,
                outputIRPath: noDebugIRPath,
                interner: interner
            )

            let debugIR = try String(contentsOfFile: debugIRPath, encoding: .utf8)
            let noDebugIR = try String(contentsOfFile: noDebugIRPath, encoding: .utf8)

            if LLVMCAPIBindings.load()?.debugInfoAvailable == true {
                XCTAssertTrue(debugIR.contains("!llvm.dbg") || debugIR.count > noDebugIR.count)
            }
            XCTAssertFalse(noDebugIR.contains("!llvm.dbg"))
        }
    }

    func testLlvmCapiBindingsReportsDebugInfoAvailability() {
        guard let bindings = LLVMCAPIBindings.load() else {
            return
        }
        _ = bindings.debugInfoAvailable
    }

    func testLlvmCapiBindingsReportsDebugLocationAvailability() {
        guard let bindings = LLVMCAPIBindings.load() else {
            return
        }
        _ = bindings.debugLocationAvailable
    }

    func testLlvmCapiBackendDebugIRContainsDebugLocationMetadata() throws {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 4000)
        let e0 = arena.appendExpr(.intLiteral(42))
        let function = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: e0, value: .intLiteral(42)),
                .returnValue(e0)
            ],
            isSuspend: false,
            isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])],
            arena: arena
        )

        let backend = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: true,
            diagnostics: diagnostics,
            isStrictMode: false
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])

        guard llvmCapiBindingsAvailable() else { return }
        guard LLVMCAPIBindings.load()?.debugInfoAvailable == true else { return }
        guard LLVMCAPIBindings.load()?.debugLocationAvailable == true else { return }

        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_dbgloc.ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }

        try backend.emitLLVMIR(
            module: module,
            runtime: runtime,
            outputIRPath: irPath,
            interner: interner
        )

        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        // When debug locations are set, instructions carry !dbg metadata
        // references and DISubprogram / DILocation entries appear in the IR.
        XCTAssertTrue(ir.contains("!dbg"), "Expected !dbg metadata references in IR when debugInfo is enabled")
        XCTAssertTrue(ir.contains("DISubprogram"), "Expected DISubprogram metadata in IR")
    }

}
