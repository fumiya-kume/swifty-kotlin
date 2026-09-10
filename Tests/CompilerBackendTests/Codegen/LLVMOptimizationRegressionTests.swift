#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Regression probes for the malformed IR that was exposed when the LLVM pass
/// pipeline first ran against the bundled standard library.
@Suite
struct LLVMOptimizationRegressionTests {
    @Test
    func optimizedStdlibArtifactRetainsExternallyCalledEntryPoints() throws {
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("llvm-optimization-stdlib-\(UUID().uuidString)")
            .path
        defer { try? FileManager.default.removeItem(atPath: outputBase + ".kklib") }

        let options = CompilerOptions(
            moduleName: "KSwiftKStdlib",
            inputs: [],
            outputPath: outputBase,
            emit: .library,
            target: defaultTargetTriple(),
            optLevel: .O2,
            stdlibOnly: true,
            allowDefaultStdlibLibrary: false
        )
        let context = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(context)
        try LoweringPhase().run(context)
        try CodegenPhase().run(context)

        let source = """
        enum class Status(val code: Int) {
            OK(200),
            NOT_FOUND(404)
        }

        class Outer {
            class Inner {
                fun value(): Int = 7
            }
        }

        fun main() {
            println(Status.OK.code)
            println(Status.NOT_FOUND.code)
            println(Outer.Inner().value())
        }
        """
        try assertOutput(
            source,
            moduleName: "LLVMOptimizationStdlibConsumer",
            expected: "200\n404\n7\n",
            optimization: .O2,
            stdlibPath: outputBase + ".kklib"
        )
    }

    @Test(arguments: [0, 2])
    func enumConstructorDelegationRemainsValidAtEachOptimizationLevel(optimization: Int) throws {
        let source = """
        enum class Status(val code: Int) {
            OK(200),
            NOT_FOUND(404)
        }

        fun main() {
            println(Status.OK.code)
            println(Status.NOT_FOUND.code)
        }
        """
        try assertOutput(
            source,
            moduleName: "LLVMOptimizationEnumConstructor",
            expected: "200\n404\n",
            optimization: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    @Test(arguments: [0, 2])
    func nestedConstructorIsEmittedExactlyOnceAtEachOptimizationLevel(optimization: Int) throws {
        let source = """
        class Outer {
            class Inner {
                fun value(): Int = 7
            }
        }

        fun main() {
            println(Outer.Inner().value())
        }
        """
        try assertOutput(
            source,
            moduleName: "LLVMOptimizationNestedConstructor",
            expected: "7\n",
            optimization: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    @Test(arguments: [0, 2])
    func stringVarargConstructorUsesPackedListABIAtEachOptimizationLevel(optimization: Int) throws {
        let source = """
        class TextBundle(vararg values: String) {
            val count: Int = values.size
        }

        fun main() {
            println(TextBundle("a", "b", "c").count)
        }
        """
        try assertOutput(
            source,
            moduleName: "LLVMOptimizationStringVarargConstructor",
            expected: "3\n",
            optimization: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    @Test(arguments: [0, 2])
    func branchingSuspendStateMachineRemainsValidAtEachOptimizationLevel(optimization: Int) throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun branch(flag: Boolean): Int {
            if (flag) {
                return suspendCoroutine<Int> { cont: Continuation<Int> ->
                    cont.resume(1)
                }
            }
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resume(2)
            }
        }

        suspend fun branchTrue(): Int = branch(true)
        suspend fun branchFalse(): Int = branch(false)

        fun main() {
            println(runBlocking(branchTrue))
            println(runBlocking(branchFalse))
        }
        """
        try assertOutput(
            source,
            moduleName: "LLVMOptimizationBranchingSuspend",
            expected: "1\n2\n",
            optimization: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    private func assertOutput(
        _ source: String,
        moduleName: String,
        expected: String,
        optimization: OptimizationLevel,
        stdlibPath: String? = nil
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("llvm-optimization-\(UUID().uuidString)")
                .path
            let libraryPath: String
            if let stdlibPath {
                libraryPath = stdlibPath
            } else {
                libraryPath = try testStdlibArtifactPath()
            }
            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: [path],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: optimization,
                stdlibLibraryPath: libraryPath
            )
            let context = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            let normalized = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalized == expected)
        }
    }
}
#endif
