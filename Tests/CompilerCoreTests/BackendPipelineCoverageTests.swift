import Foundation
import XCTest
@testable import CompilerCore

final class BackendPipelineCoverageTests: XCTestCase {
    func testLoadSourcesPhaseReportsMissingInputsAndUnreadableFiles() {
        let emptyCtx = makeCompilationContext(inputs: [])
        XCTAssertThrowsError(try LoadSourcesPhase().run(emptyCtx))
        XCTAssertEqual(emptyCtx.diagnostics.diagnostics.last?.code, "KSWIFTK-SOURCE-0001")

        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kt")
            .path
        let missingCtx = makeCompilationContext(inputs: [missingPath])
        XCTAssertThrowsError(try LoadSourcesPhase().run(missingCtx))
        XCTAssertEqual(missingCtx.diagnostics.diagnostics.last?.code, "KSWIFTK-SOURCE-0002")
    }

    func testRunToKIRAndLoweringRecordsAllPasses() throws {
        let source = """
        inline fun add(a: Int, b: Int) = a + b
        suspend fun susp(v: Int) = v
        fun chooser(flag: Boolean, n: Int) = when (flag) { true -> n + 1, false -> n - 1, else -> n }
        fun main() {
            add(1, 2)
            susp(3)
            chooser(true, 4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            XCTAssertEqual(module.executedLowerings, [
                "NormalizeBlocks",
                "OperatorLowering",
                "ForLowering",
                "WhenLowering",
                "PropertyLowering",
                "DataEnumSealedSynthesis",
                "LambdaClosureConversion",
                "InlineLowering",
                "CoroutineLowering",
                "ABILowering"
            ])
            XCTAssertGreaterThan(module.functionCount, 0)
        }
    }

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

    func testBuildKIRLowersStringAdditionToRuntimeConcatCall() throws {
        let source = """
        fun main() = "a" + "b"
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else {
                    return nil
                }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callees = body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _) = instruction else {
                    return nil
                }
                return ctx.interner.resolve(callee)
            }

            XCTAssertTrue(callees.contains("kk_string_concat"))
            XCTAssertFalse(body.contains { instruction in
                guard case .binary(let op, _, _, _) = instruction else {
                    return false
                }
                return op == .add
            })
        }
    }

    func testBuildKIRLowersUnaryOperatorsToExpectedOperations() throws {
        let source = """
        fun main(): Int {
            val x = 2
            val a = -x
            val b = +x
            if (!false) return a + b
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else {
                    return nil
                }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)

            let binaryOps = body.compactMap { instruction -> KIRBinaryOp? in
                guard case .binary(let op, _, _, _) = instruction else {
                    return nil
                }
                return op
            }
            XCTAssertTrue(binaryOps.contains(.subtract))
            XCTAssertTrue(binaryOps.contains(.equal))
        }
    }

    func testBuildKIRLowersComparisonAndLogicalOperatorsToRuntimeCalls() throws {
        let source = """
        fun main(): Int {
            val x = 3
            val a = x != 2
            val b = x < 5
            val c = x <= 3
            val d = x > 1
            val e = x >= 3
            val f = true && false
            val g = false || true
            if (a && b && c && d && e && !f && g) return 1
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else {
                    return nil
                }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callees = Set(body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _) = instruction else {
                    return nil
                }
                return ctx.interner.resolve(callee)
            })

            XCTAssertTrue(callees.contains("kk_op_ne"))
            XCTAssertTrue(callees.contains("kk_op_lt"))
            XCTAssertTrue(callees.contains("kk_op_le"))
            XCTAssertTrue(callees.contains("kk_op_gt"))
            XCTAssertTrue(callees.contains("kk_op_ge"))
            XCTAssertTrue(callees.contains("kk_op_and"))
            XCTAssertTrue(callees.contains("kk_op_or"))
        }
    }

    func testBuildKIRUsesResolvedOperatorOverloadCallForBinaryExpression() throws {
        // Kotlin member functions take precedence over extensions with the same
        // signature.  Int.plus is a built-in member, so `operator fun Int.plus`
        // defined as an extension must NOT shadow the built-in `+`.
        let source = """
        operator fun Int.plus(other: Int): Int = this - other
        fun main(): Int = 7 + 3
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else {
                    return nil
                }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)

            // The built-in binary .add instruction should be used, not a call.
            XCTAssertTrue(body.contains { instruction in
                guard case .binary(let op, _, _, _) = instruction else {
                    return false
                }
                return op == .add
            })
            XCTAssertFalse(body.contains { instruction in
                guard case .call(_, let callee, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "plus"
            })
        }
    }

    func testArrayAccessAndAssignmentLowerToRuntimeCallsWithExpectedThrowFlags() throws {
        let source = """
        fun main(): Any? {
            val arr = IntArray(2)
            arr[0] = 7
            return arr[0]
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else {
                    return nil
                }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)

            let callNames = body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _) = instruction else {
                    return nil
                }
                return ctx.interner.resolve(callee)
            }
            XCTAssertTrue(callNames.contains("kk_array_new"))
            XCTAssertTrue(callNames.contains("kk_array_set"))
            XCTAssertTrue(callNames.contains("kk_array_get"))

            let throwFlags: [String: [Bool]] = body.reduce(into: [:]) { partial, instruction in
                guard case .call(_, let callee, _, _, let canThrow) = instruction else {
                    return
                }
                partial[ctx.interner.resolve(callee), default: []].append(canThrow)
            }
            XCTAssertEqual(throwFlags["kk_array_new"]?.allSatisfy({ $0 == false }), true)
            XCTAssertEqual(throwFlags["kk_array_set"]?.allSatisfy({ $0 == true }), true)
            XCTAssertEqual(throwFlags["kk_array_get"]?.allSatisfy({ $0 == true }), true)
        }
    }

    func testArrayOutOfBoundsThrownChannelReturnsEarlyBeforeSubsequentReturn() throws {
        let source = """
        fun readOutOfBounds(arr: Any?): Any? = arr[5]
        fun main(): Any? {
            val arr = IntArray(1)
            readOutOfBounds(arr)
            return 99
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ArrayThrownChannel",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            let result: CommandResult
            do {
                result = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected top-level thrown channel to fail process exit.")
                return
            } catch CommandRunnerError.nonZeroExit(let failed) {
                result = failed
            }
            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.stderr.contains("KSWIFTK-LINK-0003"))
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
        let selectResult = arena.appendExpr(.temporary(9))
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
                .call(symbol: nil, callee: interner.intern("kk_string_concat"), arguments: [leftExpr, rightExpr], result: concatResult, canThrow: false),
                .call(symbol: nil, callee: interner.intern("kk_coroutine_suspended"), arguments: [], result: suspendedResult, canThrow: false),
                .constValue(result: labelValue, value: .intLiteral(7)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_set_label"),
                    arguments: [suspendedResult, labelValue],
                    result: labelResult,
                    canThrow: false
                ),
                .constValue(result: spillSlotValue, value: .intLiteral(0)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_set_spill"),
                    arguments: [suspendedResult, spillSlotValue, concatResult],
                    result: spillStored,
                    canThrow: false
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_get_spill"),
                    arguments: [suspendedResult, spillSlotValue],
                    result: spillLoaded,
                    canThrow: false
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_set_completion"),
                    arguments: [suspendedResult, spillLoaded],
                    result: completionStored,
                    canThrow: false
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_get_completion"),
                    arguments: [suspendedResult],
                    result: completionLoaded,
                    canThrow: false
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_when_select"),
                    arguments: [whenCondition, concatResult, completionLoaded],
                    result: whenResult,
                    canThrow: false
                ),
                .select(condition: whenCondition, thenValue: whenResult, elseValue: concatResult, result: selectResult),
                .call(symbol: nil, callee: interner.intern("println"), arguments: [selectResult], result: nil, canThrow: false),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_continuation_new"),
                    arguments: [labelValue],
                    result: continuationResult,
                    canThrow: false
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_exit"),
                    arguments: [continuationResult, completionLoaded],
                    result: stateExitResult,
                    canThrow: false
                ),
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: throwingResult, canThrow: true),
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
        XCTAssertTrue(ir.contains("select i1"))
        XCTAssertTrue(ir.contains("thrown_slot_"))
        XCTAssertTrue(ir.contains("@external_throwing"))
    }

    func testLlvmCapiBindingsCandidatePathsHonorEnvironmentOverride() {
        let overridePath = "/tmp/custom-libLLVM.dylib"
        let paths = LLVMCAPIBindings.candidateLibraryPaths(environment: ["KSWIFTK_LLVM_DYLIB": overridePath])
        XCTAssertEqual(paths.first, overridePath)
        XCTAssertTrue(paths.contains("libLLVM.dylib"))
    }

    func testSemaLoadsSymbolsFromKklibSearchPath() throws {
        let librarySource = """
        package extdemo
        fun plus(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus
            fun main() = plus(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)

                let sema = try XCTUnwrap(appCtx.sema)
                let importedPlus = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus" &&
                    symbol.kind == .function &&
                    symbol.flags.contains(.synthetic)
                }
                XCTAssertNotNil(importedPlus)
                XCTAssertFalse(appCtx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
            }
        }
    }

    func testInlineLoweringExpandsImportedInlineFunctionFromKklib() throws {
        let librarySource = """
        package extdemo
        inline fun plus1(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus1
            fun main() = plus1(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)

                let sema = try XCTUnwrap(appCtx.sema)
                let importedInline = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus1" &&
                    symbol.kind == .function &&
                    symbol.flags.contains(.inlineFunction)
                }
                XCTAssertNotNil(importedInline)
                XCTAssertFalse(sema.importedInlineFunctions.isEmpty)

                let kir = try XCTUnwrap(appCtx.kir)
                guard let mainFunction = kir.arena.declarations.compactMap({ decl -> KIRFunction? in
                    guard case .function(let function) = decl else { return nil }
                    return appCtx.interner.resolve(function.name) == "main" ? function : nil
                }).first else {
                    XCTFail("Expected lowered main function")
                    return
                }

                let calls = mainFunction.body.compactMap { instruction -> String? in
                    guard case .call(_, let callee, _, _, _) = instruction else {
                        return nil
                    }
                    return appCtx.interner.resolve(callee)
                }
                XCTAssertFalse(calls.contains("plus1"))
                XCTAssertTrue(calls.contains("kk_op_add"))
            }
        }
    }

    func testLinkPhaseAutoLinksKotlinLibraryObjectForCrossModuleCall() throws {
        let librarySource = """
        package extdemo
        fun plus(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus
            fun main() = plus(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .path
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "CrossModuleApp",
                    emit: .executable,
                    outputPath: outputPath,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)
                try CodegenPhase().run(appCtx)
                try LinkPhase().run(appCtx)

                XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
                let process = Process()
                process.executableURL = URL(fileURLWithPath: outputPath)
                process.arguments = []
                try process.run()
                process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 42)
            }
        }
    }

    func testSemaSynthesizesNominalLayoutsAndLibraryMetadataContainsLayoutFields() throws {
        let source = """
        package layoutdemo
        class Base
        class Derived: Base
        """

        try withTemporaryFile(contents: source) { path in
            let semaCtx = makeCompilationContext(inputs: [path], moduleName: "LayoutSema", emit: .kirDump)
            try runToKIR(semaCtx)

            let sema = try XCTUnwrap(semaCtx.sema)
            let base = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                semaCtx.interner.resolve(symbol.name) == "Base" && symbol.kind == .class
            }))
            let derived = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                semaCtx.interner.resolve(symbol.name) == "Derived" && symbol.kind == .class
            }))

            let baseLayout = sema.symbols.nominalLayout(for: base.id)
            let derivedLayout = sema.symbols.nominalLayout(for: derived.id)
            XCTAssertNotNil(baseLayout)
            XCTAssertNotNil(derivedLayout)
            XCTAssertEqual(baseLayout?.objectHeaderWords, 2)
            XCTAssertGreaterThanOrEqual(baseLayout?.instanceSizeWords ?? 0, 2)
            XCTAssertEqual(derivedLayout?.superClass, base.id)

            let libBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libCtx = makeCompilationContext(
                inputs: [path],
                moduleName: "LayoutLib",
                emit: .library,
                outputPath: libBase
            )
            try runToKIR(libCtx)
            try LoweringPhase().run(libCtx)
            try CodegenPhase().run(libCtx)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
            XCTAssertTrue(metadata.contains("layoutWords="))
            XCTAssertTrue(metadata.contains("vtable="))
            XCTAssertTrue(metadata.contains("itable="))
            XCTAssertTrue(metadata.contains("superFq=layoutdemo.Base"))
        }
    }

    func testSemaAllocatesVtableSlotsFromImportedNominalMetadata() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtMeta",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        class _ fq=ext.C
        function _ fq=ext.C.m arity=0 suspend=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "VTableImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let classSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                ctx.interner.resolve(symbol.name) == "C" && symbol.kind == .class
            }))
            let layout = sema.symbols.nominalLayout(for: classSymbol.id)
            XCTAssertNotNil(layout)
            XCTAssertEqual(layout?.vtableSlots.count, 1)
            XCTAssertEqual(layout?.vtableSize, 1)
            XCTAssertEqual(layout?.itableSlots.count, 0)
            XCTAssertEqual(layout?.itableSize, 0)
        }
    }

    func testSemaReusesVtableSlotForImportedOverrideMethods() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtMetaOverride",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=4
        class _ fq=ext.Base fields=0 layoutWords=3 vtable=1 itable=0
        function _ fq=ext.Base.m arity=0 suspend=0
        class _ fq=ext.Derived superFq=ext.Base fields=0 layoutWords=3 vtable=1 itable=0
        function _ fq=ext.Derived.m arity=0 suspend=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "VTableOverrideImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let baseClass = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base")]).first)
            let derivedClass = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Derived")]).first)
            let baseMethod = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base"), ctx.interner.intern("m")]).first)
            let derivedMethod = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Derived"), ctx.interner.intern("m")]).first)

            let baseLayout = try XCTUnwrap(sema.symbols.nominalLayout(for: baseClass))
            let derivedLayout = try XCTUnwrap(sema.symbols.nominalLayout(for: derivedClass))
            XCTAssertEqual(derivedLayout.superClass, baseClass)
            XCTAssertEqual(baseLayout.vtableSize, 1)
            XCTAssertEqual(derivedLayout.vtableSize, 1)
            XCTAssertEqual(derivedLayout.vtableSlots[baseMethod], derivedLayout.vtableSlots[derivedMethod])
        }
    }

    func testSemaInheritsImportedFieldLayoutFromMetadataHints() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtLayoutHint",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        class _ fq=ext.Base fields=1 layoutWords=4 vtable=0 itable=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        class Derived: ext.Base
        fun main() = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LayoutHintImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let baseClass = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base")]).first)
            let derivedClass = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Derived")]).first)
            let baseLayout = try XCTUnwrap(sema.symbols.nominalLayout(for: baseClass))
            let derivedLayout = try XCTUnwrap(sema.symbols.nominalLayout(for: derivedClass))

            XCTAssertEqual(baseLayout.instanceFieldCount, 1)
            XCTAssertEqual(baseLayout.instanceSizeWords, 4)
            XCTAssertEqual(derivedLayout.superClass, baseClass)
            XCTAssertEqual(derivedLayout.instanceFieldCount, 1)
            XCTAssertEqual(derivedLayout.instanceSizeWords, 4)
        }
    }

    func testLibraryMetadataExportsTypeSignatures() throws {
        let source = """
        package metaexport
        fun id(v: Int): Int = v
        val answer: Int = 42
        """
        try withTemporaryFile(contents: source) { path in
            let libBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MetaExport",
                emit: .library,
                outputPath: libBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
            XCTAssertTrue(metadata.contains("function "))
            XCTAssertTrue(metadata.contains("property "))
            XCTAssertTrue(metadata.contains("sig=F1<I,I>"))
            XCTAssertTrue(metadata.contains("sig=I"))
        }
    }

    func testLibraryImportRestoresFunctionAndPropertyTypeSignatures() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtTyped",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        function _ fq=ext.id arity=1 suspend=0 sig=F1<I,I>
        property _ fq=ext.answer sig=I
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "TypedImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ext = ctx.interner.intern("ext")
            let idName = ctx.interner.intern("id")
            let answerName = ctx.interner.intern("answer")

            let functionSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, idName]).first)
            let propertySymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, answerName]).first)
            let functionSignature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
            let propertyType = try XCTUnwrap(sema.symbols.propertyType(for: propertySymbol))

            XCTAssertEqual(functionSignature.parameterTypes.count, 1)
            XCTAssertEqual(functionSignature.isSuspend, false)
            XCTAssertEqual(sema.types.kind(of: functionSignature.parameterTypes[0]), .primitive(.int, .nonNull))
            XCTAssertEqual(sema.types.kind(of: functionSignature.returnType), .primitive(.int, .nonNull))
            XCTAssertEqual(sema.types.kind(of: propertyType), .primitive(.int, .nonNull))
        }
    }

    func testLibraryImportRestoresExplicitNominalLayoutSlotsAndOffsets() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtLayout",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=4
        interface _ fq=ext.Face
        class _ fq=ext.Box fields=1 layoutWords=3 vtable=1 itable=1 fieldOffsets=ext.Box.value@2 vtableSlots=ext.Box.get#0#0@0 itableSlots=ext.Face@0
        function _ fq=ext.Box.get arity=0 suspend=0 sig=F0<I>
        property _ fq=ext.Box.value sig=I
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LayoutImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ext = ctx.interner.intern("ext")
            let box = ctx.interner.intern("Box")
            let face = ctx.interner.intern("Face")
            let get = ctx.interner.intern("get")
            let value = ctx.interner.intern("value")

            let boxSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, box]).first)
            let faceSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, face]).first)
            let getSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, box, get]).first)
            let valueSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ext, box, value]).first)
            let layout = try XCTUnwrap(sema.symbols.nominalLayout(for: boxSymbol))

            XCTAssertEqual(layout.fieldOffsets[valueSymbol], 2)
            XCTAssertEqual(layout.vtableSlots[getSymbol], 0)
            XCTAssertEqual(layout.itableSlots[faceSymbol], 0)
            XCTAssertEqual(layout.vtableSize, 1)
            XCTAssertEqual(layout.itableSize, 1)
        }
    }

    func testLibraryImportReportsMetadataInconsistencyDiagnostics() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtBroken",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        class _ fq=ext.Box vtable=1 vtableSlots=ext.Box.get#0#0@1,ext.Box.missing#0#0@0
        function _ fq=ext.Box.get arity=0 suspend=0 sig=broken
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BrokenImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let codes = Set(ctx.diagnostics.diagnostics.map(\.code))
            XCTAssertTrue(codes.contains("KSWIFTK-LIB-0003"))
            XCTAssertTrue(codes.contains("KSWIFTK-LIB-0004"))
            XCTAssertTrue(codes.contains("KSWIFTK-LIB-0005"))
        }
    }

    func testLinkPhaseReportsMissingMainAndCanLinkExecutable() throws {
        try withTemporaryFile(contents: "fun notMain() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NoMain", emit: .executable, outputPath: out)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            XCTAssertThrowsError(try LinkPhase().run(ctx))
            XCTAssertTrue(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0002" })
        }

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "HasMain",
                inputs: [path],
                outputPath: out,
                emit: .executable,
                target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
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

            XCTAssertTrue(FileManager.default.fileExists(atPath: out))
        }
    }

    func testLinkPhaseWrapperReportsTopLevelThrownException() throws {
        let source = """
        fun main(): Any? {
            val arr = IntArray(1)
            return arr[2]
        }
        """
        try withTemporaryFile(contents: source) { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(inputs: [path], moduleName: "TopLevelThrow", emit: .executable, outputPath: out)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: out))

            let result: CommandResult
            do {
                result = try CommandRunner.run(executable: out, arguments: [])
                XCTFail("Expected executable to fail on unhandled top-level exception.")
                return
            } catch CommandRunnerError.nonZeroExit(let failed) {
                result = failed
            }

            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.stderr.contains("KSWIFTK-LINK-0003"))
            XCTAssertTrue(result.stderr.contains("KSwiftK panic"))
        }
    }

    func testLinkPhaseAutoLinksKklibManifestObjectsAndDeduplicates() throws {
        let fm = FileManager.default
        let workspaceDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspaceDir) }

        let libraryDir = workspaceDir.appendingPathComponent("NativePlus.kklib")
        let objectsDir = libraryDir.appendingPathComponent("objects")
        try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)

        let cSource = """
        #include <stdint.h>
        intptr_t plus(intptr_t value, intptr_t* outThrown) {
            (void)outThrown;
            return value + 1;
        }
        """
        let cSourceURL = workspaceDir.appendingPathComponent("native_plus.c")
        try cSource.write(to: cSourceURL, atomically: true, encoding: .utf8)

        let objectURL = objectsDir.appendingPathComponent("native_plus.o")
        _ = try CommandRunner.run(
            executable: "/usr/bin/clang",
            arguments: ["-c", cSourceURL.path, "-o", objectURL.path]
        )

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NativePlus",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "arm64-apple-macosx",
          "objects": ["objects/native_plus.o", "objects/native_plus.o"],
          "metadata": "metadata.bin"
        }
        """
        try manifest.write(
            to: libraryDir.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try "symbols=0\n".write(
            to: libraryDir.appendingPathComponent("metadata.bin"),
            atomically: true,
            encoding: .utf8
        )

        let appSource = """
        fun main() = plus(41)
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = workspaceDir.appendingPathComponent("AppExecutable").path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "App",
                emit: .executable,
                outputPath: outputPath,
                searchPaths: [libraryDir.path, workspaceDir.path]
            )
            try runToKIR(appCtx)
            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            try LinkPhase().run(appCtx)

            XCTAssertTrue(fm.fileExists(atPath: outputPath))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: outputPath)
            process.arguments = []
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 42)
        }
    }

    func testLLVMBackendEmitsOutputsAndReportsCommandFailure() throws {
        let interner = StringInterner()
        let module = makeComplexKIRModule(interner: interner)
        let backend = LLVMBackend(
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0"),
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
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil),
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
                    canThrow: false
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_exit"),
                    arguments: [continuation, returnSeed],
                    result: exited,
                    canThrow: false
                ),
                .returnValue(exited)
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)

        let backend = LLVMBackend(
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0"),
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
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: callResult, canThrow: true),
                .returnValue(callResult)
            ],
            isSuspend: false,
            isInline: false
        )
        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)

        let backend = LLVMBackend(
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0"),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let objectPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o").path
        try backend.emitObject(module: module, runtime: runtime, outputObjectPath: objectPath, interner: interner)
        XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
    }

    func testLoweringRewritesMainCallSites() throws {
        let fixture = try makeLoweringRewriteFixture()

        guard case .function(let loweredMain)? = fixture.module.arena.decl(fixture.mainID) else {
            XCTFail("expected lowered main function")
            return
        }

        let callees = loweredMain.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _) = instruction else { return nil }
            return fixture.interner.resolve(callee)
        }
        XCTAssertTrue(callees.contains("iterator"))
        XCTAssertTrue(callees.contains("hasNext"))
        XCTAssertTrue(callees.contains("next"))
        XCTAssertFalse(callees.contains("kk_for_lowered"))
        XCTAssertTrue(callees.contains("kk_when_select"))
        XCTAssertTrue(callees.contains("kk_property_access"))
        XCTAssertTrue(callees.contains("kk_lambda_invoke"))
        XCTAssertFalse(callees.contains("inlineTarget"))
        XCTAssertFalse(callees.contains("inlined_inlineTarget"))
        XCTAssertTrue(callees.contains("kk_coroutine_continuation_new"))
        XCTAssertTrue(callees.contains("kk_suspend_suspendTarget"))

        let throwFlags: [String: [Bool]] = loweredMain.body.reduce(into: [:]) { partial, instruction in
            guard case .call(_, let callee, _, _, let canThrow) = instruction else {
                return
            }
            let name = fixture.interner.resolve(callee)
            partial[name, default: []].append(canThrow)
        }
        XCTAssertEqual(throwFlags["kk_coroutine_continuation_new"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_suspend_suspendTarget"]?.allSatisfy({ $0 == true }), true)
    }

    func testLoweringBuildsSuspendStateMachineAndThrowFlags() throws {
        let fixture = try makeLoweringRewriteFixture()
        let loweredSuspend = fixture.module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return fixture.interner.resolve(function.name) == "kk_suspend_suspendTarget" ? function : nil
        }.first

        XCTAssertEqual(loweredSuspend?.params.count, 1)
        XCTAssertEqual(loweredSuspend?.isSuspend, false)

        let loweredSuspendCallees = loweredSuspend?.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _) = instruction else {
                return nil
            }
            return fixture.interner.resolve(callee)
        } ?? []
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_enter"))
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_set_label"))
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_set_completion"))
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_get_completion"))
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_exit"))

        let dispatchJumpCount = loweredSuspend?.body.filter { instruction in
            if case .jumpIfEqual = instruction {
                return true
            }
            return false
        }.count ?? 0
        XCTAssertGreaterThanOrEqual(dispatchJumpCount, 2)

        let dispatchLabels = loweredSuspend?.body.compactMap { instruction -> Int32? in
            if case .label(let id) = instruction {
                return id
            }
            return nil
        } ?? []
        XCTAssertTrue(dispatchLabels.contains(1000))
        XCTAssertTrue(dispatchLabels.contains(1001))

        let hasSuspendGuard = loweredSuspend?.body.contains { instruction in
            if case .returnIfEqual = instruction {
                return true
            }
            return false
        } ?? false
        XCTAssertTrue(hasSuspendGuard)

        let throwFlags: [String: [Bool]] = loweredSuspend?.body.reduce(into: [:]) { partial, instruction in
            guard case .call(_, let callee, _, _, let canThrow) = instruction else {
                return
            }
            let name = fixture.interner.resolve(callee)
            partial[name, default: []].append(canThrow)
        } ?? [:]
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
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else {
                    return nil
                }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let loweredSuspend = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else {
                    return nil
                }
                return ctx.interner.resolve(function.name) == "kk_suspend_delayedValue" ? function : nil
            }.first

            let mainCalls = mainFunction?.body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _) = instruction else {
                    return nil
                }
                return ctx.interner.resolve(callee)
            } ?? []
            XCTAssertTrue(mainCalls.contains("kk_kxmini_run_blocking"))
            XCTAssertFalse(mainCalls.contains("runBlocking"))

            let delayCalls = loweredSuspend?.body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _) = instruction else {
                    return nil
                }
                return ctx.interner.resolve(callee)
            } ?? []
            XCTAssertTrue(delayCalls.contains("kk_kxmini_delay"))

            let throwFlags = loweredSuspend?.body.reduce(into: [String: [Bool]]()) { partial, instruction in
                guard case .call(_, let callee, _, _, let canThrow) = instruction else {
                    return
                }
                partial[ctx.interner.resolve(callee), default: []].append(canThrow)
            } ?? [:]
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
            let process = Process()
            process.executableURL = URL(fileURLWithPath: outputPath)
            process.arguments = []
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 42)
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
                .call(symbol: nil, callee: interner.intern("susp"), arguments: [], result: noArgResult, canThrow: false),
                .call(symbol: nil, callee: interner.intern("susp"), arguments: [argValue], result: oneArgResult, canThrow: false),
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
            guard case .call(_, let callee, _, _, _) = instruction else {
                return false
            }
            return interner.resolve(callee) == "susp"
        }
        XCTAssertFalse(rawSuspendCalls)

        let rewrittenSuspendCalls = loweredCaller.body.compactMap { instruction -> (name: String, arity: Int, canThrow: Bool)? in
            guard case .call(_, let callee, let arguments, _, let canThrow) = instruction else {
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
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: callResult, canThrow: false),
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

        let loweredSuspend = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name) == "kk_suspend_suspendTarget" ? function : nil
        }.first
        XCTAssertNotNil(loweredSuspend)

        let labels = loweredSuspend?.body.compactMap { instruction -> Int32? in
            if case .label(let id) = instruction {
                return id
            }
            return nil
        } ?? []
        XCTAssertTrue(labels.contains(1000))
        XCTAssertTrue(labels.contains(1001))
        XCTAssertTrue(labels.contains(20))

        let hasOriginalBranch = loweredSuspend?.body.contains { instruction in
            if case .jumpIfEqual(_, _, let target) = instruction {
                return target == 20
            }
            return false
        } ?? false
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
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: callResult, canThrow: false),
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

        let loweredSuspend = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name) == "kk_suspend_suspendTarget" ? function : nil
        }.first
        XCTAssertNotNil(loweredSuspend)

        let loweredCalls = loweredSuspend?.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _) = instruction else {
                return nil
            }
            return interner.resolve(callee)
        } ?? []
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_set_spill"))
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_get_spill"))
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_set_completion"))
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_get_completion"))

        let setSpillCount = loweredCalls.filter { $0 == "kk_coroutine_state_set_spill" }.count
        let getSpillCount = loweredCalls.filter { $0 == "kk_coroutine_state_get_spill" }.count
        XCTAssertEqual(setSpillCount, 1)
        XCTAssertEqual(getSpillCount, 1)

        let throwFlags: [String: [Bool]] = loweredSuspend?.body.reduce(into: [:]) { partial, instruction in
            guard case .call(_, let callee, _, _, let canThrow) = instruction else {
                return
            }
            partial[interner.resolve(callee), default: []].append(canThrow)
        } ?? [:]
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
                    canThrow: false
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
                .call(symbol: topSymbol, callee: interner.intern("top"), arguments: [], result: mainResult, canThrow: false),
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
                .call(symbol: leafSymbol, callee: interner.intern("leaf"), arguments: [], result: topResult, canThrow: false),
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
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: leafResult, canThrow: false),
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

        let loweredMain = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name) == "main" ? function : nil
        }.first
        let loweredTop = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name) == "kk_suspend_top" ? function : nil
        }.first
        let loweredLeaf = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name) == "kk_suspend_leaf" ? function : nil
        }.first

        XCTAssertNotNil(loweredMain)
        XCTAssertNotNil(loweredTop)
        XCTAssertNotNil(loweredLeaf)

        let mainThrowFlags: [String: [Bool]] = loweredMain?.body.reduce(into: [:]) { partial, instruction in
            guard case .call(_, let callee, _, _, let canThrow) = instruction else {
                return
            }
            partial[interner.resolve(callee), default: []].append(canThrow)
        } ?? [:]
        XCTAssertEqual(mainThrowFlags["kk_suspend_top"]?.allSatisfy({ $0 == true }), true)

        let topThrowFlags: [String: [Bool]] = loweredTop?.body.reduce(into: [:]) { partial, instruction in
            guard case .call(_, let callee, _, _, let canThrow) = instruction else {
                return
            }
            partial[interner.resolve(callee), default: []].append(canThrow)
        } ?? [:]
        XCTAssertEqual(topThrowFlags["kk_suspend_leaf"]?.allSatisfy({ $0 == true }), true)
        XCTAssertEqual(topThrowFlags["kk_coroutine_state_set_label"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(topThrowFlags["kk_coroutine_state_set_completion"]?.allSatisfy({ $0 == false }), true)

        let leafThrowFlags: [String: [Bool]] = loweredLeaf?.body.reduce(into: [:]) { partial, instruction in
            guard case .call(_, let callee, _, _, let canThrow) = instruction else {
                return
            }
            partial[interner.resolve(callee), default: []].append(canThrow)
        } ?? [:]
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
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [inlineArg, inlineOne], result: inlineSum, canThrow: false),
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
                .call(symbol: inlineSym, callee: interner.intern("plusOne"), arguments: [callerArg], result: callerResult, canThrow: false),
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

        let calleeNames = loweredCaller.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
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

        let copyFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name) == "Point$copy" ? function : nil
        }.first
        XCTAssertEqual(copyFunction?.params.count, 1)
    }

    func testLinkPhaseSkipsForObjectEmitMode() throws {
        let objectCtx = makeCompilationContext(inputs: [], moduleName: "SkipLink", emit: .object)
        XCTAssertNoThrow(try LinkPhase().run(objectCtx))
    }

    func testLinkPhaseFailsWhenObjectIsMissingForExecutable() throws {
        let missingObjectCtx = makeCompilationContext(inputs: [], moduleName: "MissingObj", emit: .executable)
        XCTAssertThrowsError(try LinkPhase().run(missingObjectCtx))
    }

    func testLinkPhaseFailsWhenKIRModuleIsMissing() throws {
        let tempObjectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        try Data().write(to: tempObjectURL)

        let noKirCtx = makeCompilationContext(inputs: [], moduleName: "NoKir", emit: .executable)
        noKirCtx.generatedObjectPath = tempObjectURL.path
        XCTAssertThrowsError(try LinkPhase().run(noKirCtx))
    }

    func testLinkPhaseReportsDiagnosticForUnsupportedTargetArchitecture() throws {
        let tempObjectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        try Data().write(to: tempObjectURL)

        let interner = StringInterner()
        let arena = KIRArena()
        let mainSym = SymbolID(rawValue: 99)
        let mainDecl = arena.appendDecl(.function(KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDecl])], arena: arena)

        let badTargetOptions = CompilerOptions(
            moduleName: "BadTarget",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .executable,
            target: TargetTriple(arch: "definitely-bad-arch", vendor: "apple", os: "macosx", osVersion: nil)
        )
        let badTargetCtx = CompilationContext(
            options: badTargetOptions,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        badTargetCtx.generatedObjectPath = tempObjectURL.path
        badTargetCtx.kir = module

        XCTAssertThrowsError(try LinkPhase().run(badTargetCtx))
        XCTAssertTrue(badTargetCtx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0001" })
    }

    func testFrontendAndSemaResolveTypedDeclarationsAndEmitExpectedDiagnostics() throws {
        let source = """
        package typed.demo
        import typed.demo.*

        public inline suspend fun transform<T>(
            vararg values: T,
            crossinline mapper: T,
            noinline fallback: T = mapper
        ): String? = "ok"
        fun String.decorate(): String = this

        fun typed(a: Int, b: String?, c: Any): Int = 1
        fun duplicate(x: Int, x: Int): Int = x

        val explicit: Int = 1
        var delegated by delegateProvider
        val unknown: CustomType = explicit
        val explicit: Int = 2

        class TypedBox<T>(value: T)
        object Obj
        typealias Alias = String
        enum class Kind { A, B }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "Typed", emit: .kirDump)
            try runToKIR(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let declarations = ast.arena.declarations()
            XCTAssertGreaterThanOrEqual(declarations.count, 8)

            var sawTypedParameter = false
            var sawFunctionReturnType = false
            var sawFunctionReceiverType = false
            var sawExplicitPropertyType = false
            var sawDelegatedPropertyWithoutType = false

            for decl in declarations {
                switch decl {
                case .funDecl(let fn):
                    if fn.returnType != nil {
                        sawFunctionReturnType = true
                    }
                    if fn.receiverType != nil {
                        sawFunctionReceiverType = true
                    }
                    if fn.valueParams.contains(where: { $0.type != nil }) {
                        sawTypedParameter = true
                    }
                case .propertyDecl(let property):
                    if let typeID = property.type, let typeRef = ast.arena.typeRef(typeID) {
                        sawExplicitPropertyType = true
                        if case .named(let path, _) = typeRef {
                            XCTAssertFalse(path.isEmpty)
                        }
                    } else if ctx.interner.resolve(property.name) == "delegated" {
                        sawDelegatedPropertyWithoutType = true
                    }
                default:
                    continue
                }
            }

            XCTAssertTrue(sawTypedParameter)
            XCTAssertTrue(sawFunctionReturnType)
            XCTAssertTrue(sawFunctionReceiverType)
            XCTAssertTrue(sawExplicitPropertyType)
            XCTAssertTrue(sawDelegatedPropertyWithoutType)

            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.symbols.allSymbols().isEmpty)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
            let decorateSymbol = sema.symbols.allSymbols().first(where: { symbol in
                ctx.interner.resolve(symbol.name) == "decorate"
            })
            XCTAssertNotNil(decorateSymbol)
            if let decorateSymbol {
                let signature = sema.symbols.functionSignature(for: decorateSymbol.id)
                XCTAssertNotNil(signature?.receiverType)
            }

            let codes = Set(ctx.diagnostics.diagnostics.map(\.code))
            XCTAssertTrue(codes.contains("KSWIFTK-TYPE-0002"))
            XCTAssertTrue(codes.contains("KSWIFTK-SEMA-0001"))
        }
    }

    func testTypeCheckAndBuildKIRCoverExpressionVariants() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()

        let range = makeRange(file: FileID(rawValue: 0), start: 0, end: 1)
        let astArena = ASTArena()

        let intTypeRef = astArena.appendTypeRef(.named(path: [interner.intern("Int")], nullable: false))
        let boolTypeRef = astArena.appendTypeRef(.named(path: [interner.intern("Boolean")], nullable: false))
        let stringTypeRef = astArena.appendTypeRef(.named(path: [interner.intern("String")], nullable: false))

        let helperName = interner.intern("helper")
        let calcName = interner.intern("calc")
        let argName = interner.intern("arg")
        let unknownName = interner.intern("unknown")

        let eInt1 = astArena.appendExpr(.intLiteral(1, range))
        let eInt2 = astArena.appendExpr(.intLiteral(2, range))
        let eBoolTrue = astArena.appendExpr(.boolLiteral(true, range))
        let eBoolFalse = astArena.appendExpr(.boolLiteral(false, range))
        let eString = astArena.appendExpr(.stringLiteral(interner.intern("s"), range))
        let eNameLocal = astArena.appendExpr(.nameRef(argName, range))
        let eNameKnown = astArena.appendExpr(.nameRef(helperName, range))
        let eNameUnknown = astArena.appendExpr(.nameRef(unknownName, range))

        let eAdd = astArena.appendExpr(.binary(op: .add, lhs: eInt1, rhs: eInt2, range: range))
        let eSub = astArena.appendExpr(.binary(op: .subtract, lhs: eInt2, rhs: eInt1, range: range))
        let eMul = astArena.appendExpr(.binary(op: .multiply, lhs: eInt1, rhs: eInt2, range: range))
        let eDiv = astArena.appendExpr(.binary(op: .divide, lhs: eInt2, rhs: eInt1, range: range))
        let eEq = astArena.appendExpr(.binary(op: .equal, lhs: eInt1, rhs: eInt2, range: range))
        let eNe = astArena.appendExpr(.binary(op: .notEqual, lhs: eInt1, rhs: eInt2, range: range))
        let eLt = astArena.appendExpr(.binary(op: .lessThan, lhs: eInt1, rhs: eInt2, range: range))
        let eLe = astArena.appendExpr(.binary(op: .lessOrEqual, lhs: eInt1, rhs: eInt2, range: range))
        let eGt = astArena.appendExpr(.binary(op: .greaterThan, lhs: eInt2, rhs: eInt1, range: range))
        let eGe = astArena.appendExpr(.binary(op: .greaterOrEqual, lhs: eInt2, rhs: eInt1, range: range))
        let eAnd = astArena.appendExpr(.binary(op: .logicalAnd, lhs: eBoolTrue, rhs: eBoolFalse, range: range))
        let eOr = astArena.appendExpr(.binary(op: .logicalOr, lhs: eBoolFalse, rhs: eBoolTrue, range: range))
        let eUnaryPlus = astArena.appendExpr(.unary(op: .plus, operand: eInt1, range: range))
        let eUnaryMinus = astArena.appendExpr(.unary(op: .minus, operand: eInt2, range: range))
        let eUnaryNot = astArena.appendExpr(.unary(op: .not, operand: eBoolFalse, range: range))

        let eCallKnown = astArena.appendExpr(.call(callee: eNameKnown, args: [CallArgument(expr: eInt1)], range: range))
        let eCallUnknown = astArena.appendExpr(.call(callee: eNameUnknown, args: [CallArgument(expr: eInt1)], range: range))
        let eCallNonName = astArena.appendExpr(.call(callee: eInt1, args: [], range: range))
        let eBreak = astArena.appendExpr(.breakExpr(range: range))
        let eContinue = astArena.appendExpr(.continueExpr(range: range))
        let eWhile = astArena.appendExpr(.whileExpr(condition: eBoolTrue, body: eBreak, range: range))
        let eDoWhile = astArena.appendExpr(.doWhileExpr(body: eContinue, condition: eBoolTrue, range: range))
        let eFor = astArena.appendExpr(.forExpr(loopVariable: interner.intern("i"), iterable: eNameUnknown, body: eInt1, range: range))

        let whenBranchTrue = WhenBranch(condition: eBoolTrue, body: eInt1, range: range)
        let whenBranchFalse = WhenBranch(condition: eBoolFalse, body: eInt2, range: range)
        let eWhenNoElse = astArena.appendExpr(.whenExpr(subject: eBoolTrue, branches: [whenBranchTrue], elseExpr: nil, range: range))
        let eWhenElse = astArena.appendExpr(.whenExpr(subject: eBoolTrue, branches: [whenBranchTrue, whenBranchFalse], elseExpr: eInt1, range: range))

        let helperDecl = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: helperName,
            modifiers: [],
            typeParams: [],
            receiverType: nil,
            valueParams: [ValueParamDecl(name: interner.intern("x"), type: intTypeRef)],
            returnType: intTypeRef,
            body: .expr(eInt1, range),
            isSuspend: false,
            isInline: false
        )))

        let calcDecl = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: calcName,
            modifiers: [.inline, .suspend],
            typeParams: [],
            receiverType: nil,
            valueParams: [ValueParamDecl(name: argName, type: intTypeRef)],
            returnType: intTypeRef,
            body: .block([
                eInt1, eBoolTrue, eString, eNameLocal, eNameKnown, eNameUnknown,
                eAdd, eSub, eMul, eDiv, eEq, eNe, eLt, eLe, eGt, eGe, eAnd, eOr, eUnaryPlus, eUnaryMinus, eUnaryNot,
                eCallKnown, eCallUnknown, eCallNonName,
                eWhenNoElse, eWhenElse, eWhile, eDoWhile, eFor
            ], range),
            isSuspend: true,
            isInline: true
        )))

        let propertyDecl = astArena.appendDecl(.propertyDecl(PropertyDecl(
            range: range,
            name: interner.intern("text"),
            modifiers: [],
            type: stringTypeRef
        )))

        let boolProperty = astArena.appendDecl(.propertyDecl(PropertyDecl(
            range: range,
            name: interner.intern("flag"),
            modifiers: [],
            type: boolTypeRef
        )))

        let classDecl = astArena.appendDecl(.classDecl(ClassDecl(
            range: range,
            name: interner.intern("C"),
            modifiers: [],
            typeParams: [],
            primaryConstructorParams: []
        )))

        let astFile = ASTFile(
            fileID: FileID(rawValue: 0),
            packageFQName: [interner.intern("pkg")],
            imports: [],
            topLevelDecls: [helperDecl, calcDecl, propertyDecl, boolProperty, classDecl]
        )
        let module = ASTModule(files: [astFile], arena: astArena, declarationCount: 5, tokenCount: 0)

        let options = CompilerOptions(
            moduleName: "ExprCoverage",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.ast = module
        ctx.sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        try DataFlowSemaPassPhase().run(ctx)
        try TypeCheckSemaPassPhase().run(ctx)
        try BuildKIRPhase().run(ctx)
        try LoweringPhase().run(ctx)

        let kir = try XCTUnwrap(ctx.kir)
        XCTAssertGreaterThanOrEqual(kir.functionCount, 2)
        XCTAssertFalse(kir.executedLowerings.isEmpty)
        XCTAssertFalse(kir.arena.exprTypes.isEmpty)
        XCTAssertFalse((ctx.sema?.bindings.exprTypes ?? [:]).isEmpty)
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eUnaryPlus])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eUnaryMinus])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eUnaryNot])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eNe])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eLt])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eLe])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eGt])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eGe])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eAnd])
        XCTAssertNotNil(ctx.sema?.bindings.exprTypes[eOr])
    }

    func testBuildKIRLowersLoopExpressionsToControlFlowInstructions() throws {
        let source = """
        fun loop(flag: Boolean, items: IntArray): Int {
            while (flag) { break }
            do { continue } while (flag)
            for (item in items) { break }
            return 1
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "LoopIR", emit: .kirDump)
            try runToKIR(ctx)

            let kir = try XCTUnwrap(ctx.kir)
            let interner = ctx.interner
            let loopFunction = kir.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl else {
                    return nil
                }
                return interner.resolve(function.name) == "loop" ? function : nil
            }.first
            let body = try XCTUnwrap(loopFunction?.body)

            let labelCount = body.filter { instruction in
                if case .label = instruction { return true }
                return false
            }.count
            XCTAssertGreaterThanOrEqual(labelCount, 4)

            let jumpCount = body.filter { instruction in
                if case .jump = instruction { return true }
                if case .jumpIfEqual = instruction { return true }
                return false
            }.count
            XCTAssertGreaterThanOrEqual(jumpCount, 4)

            let callees = body.compactMap { instruction -> String? in
                guard case .call(_, let callee, _, _, _) = instruction else {
                    return nil
                }
                return interner.resolve(callee)
            }
            XCTAssertTrue(callees.contains("iterator"))
            XCTAssertTrue(callees.contains("hasNext"))
            XCTAssertTrue(callees.contains("next"))
        }
    }

    func testBuildKIRAddsHiddenTypeTokenForInlineReifiedCalls() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()
        let astArena = ASTArena()
        let range = makeRange()

        let intType = types.make(.primitive(.int, .nonNull))
        let tName = interner.intern("T")
        let valueName = interner.intern("value")
        let pickName = interner.intern("pick")
        let mainName = interner.intern("main")
        let packageName = interner.intern("pkg")

        let valueRefExpr = astArena.appendExpr(.nameRef(valueName, range))
        let pickDeclID = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: pickName,
            modifiers: [.inline],
            typeParams: [TypeParamDecl(name: tName, variance: .invariant, isReified: true)],
            receiverType: nil,
            valueParams: [ValueParamDecl(name: valueName, type: nil)],
            returnType: nil,
            body: .expr(valueRefExpr, range),
            isSuspend: false,
            isInline: true
        )))

        let intArgExpr = astArena.appendExpr(.intLiteral(7, range))
        let pickCalleeExpr = astArena.appendExpr(.nameRef(pickName, range))
        let pickCallExpr = astArena.appendExpr(.call(
            callee: pickCalleeExpr,
            args: [CallArgument(expr: intArgExpr)],
            range: range
        ))
        let mainDeclID = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: mainName,
            modifiers: [],
            typeParams: [],
            receiverType: nil,
            valueParams: [],
            returnType: nil,
            body: .expr(pickCallExpr, range),
            isSuspend: false,
            isInline: false
        )))

        let astFile = ASTFile(
            fileID: FileID(rawValue: 0),
            packageFQName: [packageName],
            imports: [],
            topLevelDecls: [pickDeclID, mainDeclID]
        )
        let astModule = ASTModule(files: [astFile], arena: astArena, declarationCount: 2, tokenCount: 0)

        let pickSymbol = symbols.define(
            kind: .function,
            name: pickName,
            fqName: [packageName, pickName],
            declSite: range,
            visibility: .public,
            flags: [.inlineFunction]
        )
        let mainSymbol = symbols.define(
            kind: .function,
            name: mainName,
            fqName: [packageName, mainName],
            declSite: range,
            visibility: .public
        )
        let valueSymbol = symbols.define(
            kind: .valueParameter,
            name: valueName,
            fqName: [packageName, interner.intern("$pick"), valueName],
            declSite: range,
            visibility: .private
        )
        let typeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: tName,
            fqName: [packageName, interner.intern("$pick"), tName],
            declSite: range,
            visibility: .private,
            flags: [.reifiedTypeParameter]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [valueSymbol],
                typeParameterSymbols: [typeParameterSymbol],
                reifiedTypeParameterIndices: Set([0])
            ),
            for: pickSymbol
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: intType
            ),
            for: mainSymbol
        )

        bindings.bindDecl(pickDeclID, symbol: pickSymbol)
        bindings.bindDecl(mainDeclID, symbol: mainSymbol)
        bindings.bindIdentifier(valueRefExpr, symbol: valueSymbol)
        bindings.bindExprType(valueRefExpr, type: intType)
        bindings.bindExprType(intArgExpr, type: intType)
        bindings.bindExprType(pickCallExpr, type: intType)
        bindings.bindCall(
            pickCallExpr,
            binding: CallBinding(
                chosenCallee: pickSymbol,
                substitutedTypeArguments: [intType],
                parameterMapping: [0: 0]
            )
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "ReifiedTokenKIR",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.ast = astModule
        ctx.sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )

        try BuildKIRPhase().run(ctx)

        let kir = try XCTUnwrap(ctx.kir)
        let pickFunction = try XCTUnwrap(kir.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return function.symbol == pickSymbol ? function : nil
        }.first)
        let mainFunction = try XCTUnwrap(kir.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return function.symbol == mainSymbol ? function : nil
        }.first)

        let expectedTokenSymbol = SymbolID(rawValue: -20_000 - typeParameterSymbol.rawValue)
        XCTAssertEqual(pickFunction.params.count, 2)
        XCTAssertEqual(pickFunction.params.last?.symbol, expectedTokenSymbol)

        guard let callInstruction = mainFunction.body.first(where: { instruction in
            guard case .call(let symbol, _, _, _, _) = instruction else {
                return false
            }
            return symbol == pickSymbol
        }),
        case .call(_, _, let arguments, _, _) = callInstruction else {
            XCTFail("Expected main to call inline reified function.")
            return
        }
        XCTAssertEqual(arguments.count, 2)
        let tokenArgument = arguments[1]
        guard case .intLiteral(let tokenLiteral)? = kir.arena.expr(tokenArgument) else {
            XCTFail("Expected hidden type token argument to be lowered as int literal.")
            return
        }
        XCTAssertEqual(tokenLiteral, Int64(intType.rawValue))
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

        let hiddenTokenSymbol = SymbolID(rawValue: -20_000 - typeParameterSymbol.rawValue)
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
                    canThrow: false
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
            guard case .call(_, let callee, _, _, _) = instruction else {
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
                .call(symbol: nil, callee: interner.intern("iterator"), arguments: [v0], result: v3, canThrow: false),
                .call(symbol: nil, callee: interner.intern("kk_for_lowered"), arguments: [v3], result: v1, canThrow: false),
                .select(condition: v0, thenValue: v1, elseValue: v2, result: v1),
                .call(symbol: nil, callee: interner.intern("get"), arguments: [v0], result: v1, canThrow: false),
                .call(symbol: nil, callee: interner.intern("set"), arguments: [v0], result: v1, canThrow: false),
                .call(symbol: nil, callee: interner.intern("<lambda>"), arguments: [v0], result: v1, canThrow: false),
                .call(symbol: nil, callee: interner.intern("inlineTarget"), arguments: [], result: v1, canThrow: false),
                .call(symbol: nil, callee: interner.intern("suspendTarget"), arguments: [v0], result: v1, canThrow: false),
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
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: v2, canThrow: false),
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

            let artifactBase = workDir.appendingPathComponent("deterministic").path
            let first = try readCodegenArtifact(inputPath: path, emit: emit, outputPath: artifactBase)
            let second = try readCodegenArtifact(inputPath: path, emit: emit, outputPath: artifactBase)
            XCTAssertEqual(first, second)
        }
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
                .call(symbol: nil, callee: interner.intern("println"), arguments: [e3], result: e5, canThrow: false),
                .call(symbol: nil, callee: interner.intern("kk_println_any"), arguments: [e3], result: nil, canThrow: false),
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [e0, e1], result: e5, canThrow: false),
                .call(symbol: nil, callee: interner.intern("kk_op_sub"), arguments: [e0, e1], result: e6, canThrow: false),
                .call(symbol: nil, callee: interner.intern("kk_op_mul"), arguments: [e0, e1], result: e7, canThrow: false),
                .call(symbol: nil, callee: interner.intern("kk_op_div"), arguments: [e0, e1], result: e8, canThrow: false),
                .call(symbol: nil, callee: interner.intern("kk_op_eq"), arguments: [e0, e1], result: e5, canThrow: false),
                .call(symbol: nil, callee: interner.intern("kk_when_select"), arguments: [e2, e0, e1], result: e5, canThrow: false),
                .call(symbol: calleeSym, callee: interner.intern("ignored"), arguments: [], result: e5, canThrow: false),
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

    private func llvmCapiBindingsAvailable() -> Bool {
        guard let bindings = LLVMCAPIBindings.load() else {
            return false
        }
        return bindings.smokeTestContextLifecycle()
    }
}
