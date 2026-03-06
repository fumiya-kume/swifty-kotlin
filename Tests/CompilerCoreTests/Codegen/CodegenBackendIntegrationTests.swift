@testable import CompilerCore
import Foundation
import XCTest

final class CodegenBackendIntegrationTests: XCTestCase {
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

    func testCodegenCompilesStringStdlibMixedThrowCalls() throws {
        let source = """
        fun main() {
            val maybe: String? = null
            println("  hello  ".trim())
            println("banana".replace("na", "NA"))
            println("1,2,3".split(","))
            println(maybe.isNullOrEmpty())
            println(maybe.isNullOrBlank())
            println("42".toInt())
            println("3.14".toDouble())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringStdlibMixedThrowCalls",
                emit: .object,
                outputPath: outputBase
            )
            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
        }
    }

    func testCodegenGenericComparableTreatsNaNAsGreaterThanFiniteValues() throws {
        let source = """
        fun <T> pickGreater(a: T, b: T): T where T : Comparable<T> = if (a > b) a else b

        fun main() {
            val nan = "NaN".toDouble()
            println(pickGreater(nan, 1.0))
            println(pickGreater(1.0, nan))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "NaNComparable",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "nan\nnan\n")
        }
    }

    func testLLVMBackendCollectExternalCalleesSkipsRuntimeABIExterns() {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let formatString = interner.intern("%s")
        let formatLiteral = arena.appendExpr(.stringLiteral(formatString))
        let formatResult = arena.appendExpr(.temporary(0))
        let externalResult = arena.appendExpr(.temporary(1))

        let main = KIRFunction(
            symbol: SymbolID(rawValue: 1300),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: formatLiteral, value: .stringLiteral(formatString)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_string_format"),
                    arguments: [formatLiteral, formatLiteral],
                    result: formatResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("external_helper"),
                    arguments: [],
                    result: externalResult,
                    canThrow: false,
                    thrownResult: nil
                ),
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

        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )

        let callees = backend.collectExternalCallees(module: module, interner: interner, functionSymbols: [:])
        XCTAssertEqual(callees, ["external_helper"])
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

    func testCodegenBackendSelectionRejectsUnknownBackend() throws {
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
            XCTAssertThrowsError(try CodegenPhase().run(ctx))
            XCTAssertNil(ctx.generatedObjectPath)
            XCTAssertTrue(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-1008" })
        }
    }

    func testCodegenBackendSelectionRejectsSyntheticBackendFlag() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "SyntheticBackendFlag",
                inputs: [path],
                outputPath: outputBase,
                emit: .object,
                target: defaultTargetTriple(),
                irFlags: ["backend=synthetic-c"]
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            XCTAssertThrowsError(try CodegenPhase().run(ctx))
            XCTAssertNil(ctx.generatedObjectPath)
            XCTAssertTrue(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-1008" })
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
              bindings.smokeTestContextLifecycle()
        else {
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

    func testCodegenBackendSelectionDefaultAndExplicitLlvmCApiObjectCompatibilitySmoke() throws {
        guard llvmCapiBindingsAvailable() else {
            throw XCTSkip("LLVM C API bindings are unavailable in this environment.")
        }

        let source = """
        fun helper(v: Int) = v + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory

            let defaultBase = tempDir.appendingPathComponent(UUID().uuidString).path
            let defaultOptions = CompilerOptions(
                moduleName: "CompatDefault",
                inputs: [path],
                outputPath: defaultBase,
                emit: .object,
                target: defaultTargetTriple()
            )
            let defaultCtx = CompilationContext(
                options: defaultOptions,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(defaultCtx)
            try LoweringPhase().run(defaultCtx)
            try CodegenPhase().run(defaultCtx)
            let defaultObject = try XCTUnwrap(defaultCtx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: defaultObject))

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

            let defaultSize = (try? FileManager.default.attributesOfItem(atPath: defaultObject)[.size] as? NSNumber)?.intValue ?? 0
            let llvmCapiSize = (try? FileManager.default.attributesOfItem(atPath: llvmCapiObject)[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(defaultSize, 0)
            XCTAssertGreaterThan(llvmCapiSize, 0)
        }
    }

    // MARK: - Private Helpers
}
