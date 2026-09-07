#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// RF-LOWER-CALL-001: end-to-end counterpart of
/// `BuilderDSLLoweringRoutingTests`.  The existing backend coverage
/// (`CodegenBackendIOHelpersTests.testCodegenBuildListProducesCorrectly`,
/// `testCodegenBuildMapUseRuntimeBuilder`, `testCodegenBuildSetUseRuntimeBuilder`)
/// only exercises the no-capacity overloads and never asserts *which* runtime
/// helper runs.  The capacity, negative-capacity and freeze contracts lived
/// solely in `Scripts/diff_cases/ksp950_build_family.kt`, whose CI step is
/// `continue-on-error`; the execution tests below make them blocking.  Those
/// execution tests run through `assertKotlinOutput`, i.e. `emit == .executable`
/// with the process-wide default stdlib artifact.
@Suite
struct CodegenBackendCollectionBuilderDSLTests {
    /// Legacy runtime entry points the `CollectionLiteralLoweringPass` rewrite
    /// substitutes.  The trailing `(` keeps `__kk_build_list` from matching
    /// `__kk_build_list_with_capacity`, and none of them match the source-backed
    /// `__kk_builder_*` helpers.
    private static let legacyBuilderIRCallees = [
        "@__kk_build_list(", "@__kk_build_list_with_capacity(",
        "@__kk_build_set(", "@__kk_build_set_with_capacity(",
        "@__kk_build_map(", "@__kk_build_map_with_capacity(",
    ]

    private static let allOverloadsSource = """
    fun main() {
        val listNoCapacity = buildList { add(1) }
        val listWithCapacity = buildList(4) { add(2) }
        val setNoCapacity = buildSet { add("x") }
        val setWithCapacity = buildSet(4) { add("y") }
        val mapNoCapacity = buildMap { put("k", 1) }
        val mapWithCapacity = buildMap(4) { put("k", 2) }
        println(listNoCapacity.size + listWithCapacity.size)
        println(setNoCapacity.size + setWithCapacity.size)
        println(mapNoCapacity.size + mapWithCapacity.size)
    }
    """

    private func expectSourceBackedBuilderIR(_ ir: String) {
        for kind in ["list", "set", "map"] {
            #expect(ir.contains("@__kk_builder_\(kind)_new("), "expected the CollectionBuilders.kt allocator for \(kind)")
            #expect(ir.contains("@__kk_builder_\(kind)_freeze("), "expected the CollectionBuilders.kt freeze for \(kind)")
        }
        for legacy in Self.legacyBuilderIRCallees {
            #expect(!ir.contains(legacy), "the legacy rewrite \(legacy) must not reach codegen")
        }
    }

    private func readGeneratedIR(_ ctx: CompilationContext) throws -> String {
        #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
        let llvmPath = try #require(ctx.generatedLLVMIRPath)
        return try String(contentsOfFile: llvmPath, encoding: .utf8)
    }

    /// Artifact path: the stdlib comes from a precompiled `.kklib`, passed
    /// explicitly through `stdlibLibraryPath`.  The process-wide default
    /// artifact only applies to `emit == .executable`
    /// (`CompilerOptions.shouldUseDefaultStdlib`), so an IR-emitting test has
    /// to name the artifact itself to actually exercise this path.
    @Test
    func builderDSLLowersToSourceBackedHelpersThroughStdlibArtifact() throws {
        try withTemporaryFile(contents: Self.allOverloadsSource) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "BuilderDSLArtifactIR",
                emit: .llvmIR,
                outputPath: outputBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            expectSourceBackedBuilderIR(try readGeneratedIR(ctx))
        }
    }

    /// Source path: the bundled stdlib is compiled alongside the module.
    @Test
    func builderDSLLowersToSourceBackedHelpersWithStdlibFromSource() throws {
        try withTemporaryFile(contents: Self.allOverloadsSource) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "BuilderDSLSourceIR",
                emit: .llvmIR,
                outputPath: outputBase,
                allowDefaultStdlibLibrary: false
            )

            expectSourceBackedBuilderIR(try readGeneratedIR(ctx))
        }
    }

    // MARK: - execution contracts

    /// The capacity overloads are a reservation hint only: element count,
    /// `Set` de-duplication and `Map` key overwrite stay identical.
    @Test
    func buildFamilyCapacityOverloadsPreserveContents() throws {
        let source = """
        fun main() {
            val list = buildList(4) { add(1); add(2) }
            println(list)
            println(list.size)
            val set = buildSet(4) { add("a"); add("a"); add("b") }
            println(set)
            println(set.size)
            val map = buildMap(4) { put("a", 1); put("a", 2); put("b", 3) }
            println(map)
            println(map.size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BuildFamilyCapacityRuntime",
            expected: "[1, 2]\n2\n[a, b]\n2\n{a=2, b=3}\n2\n"
        )
    }

    /// `require(capacity >= 0)` in `CollectionBuilders.kt` must surface as a
    /// catchable `IllegalArgumentException` for all three builders.
    @Test
    func buildFamilyNegativeCapacityThrowsIllegalArgumentException() throws {
        let source = """
        fun main() {
            try {
                buildList(-1) { add(1) }
                println("list-not-thrown")
            } catch (e: IllegalArgumentException) {
                println("list-thrown")
            }
            try {
                buildSet(-1) { add(1) }
                println("set-not-thrown")
            } catch (e: IllegalArgumentException) {
                println("set-thrown")
            }
            try {
                buildMap(-1) { put("a", 1) }
                println("map-not-thrown")
            } catch (e: IllegalArgumentException) {
                println("map-thrown")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BuildFamilyNegativeCapacityRuntime",
            expected: "list-thrown\nset-thrown\nmap-thrown\n"
        )
    }

    /// A builder receiver captured out of the lambda must observe the freeze
    /// applied to the same box before it is returned as read-only.
    @Test
    func buildFamilyFreezesReceiverLeakedFromBuilder() throws {
        let source = """
        fun main() {
            var leakedList: MutableList<Int>? = null
            val readOnlyList = buildList { leakedList = this; add(7) }
            try {
                leakedList!!.add(8)
                println("list-mutated")
            } catch (e: UnsupportedOperationException) {
                println("list-read-only")
            }
            println(readOnlyList)

            var leakedSet: MutableSet<Int>? = null
            val readOnlySet = buildSet { leakedSet = this; add(9) }
            try {
                leakedSet!!.add(10)
                println("set-mutated")
            } catch (e: UnsupportedOperationException) {
                println("set-read-only")
            }
            println(readOnlySet)

            var leakedMap: MutableMap<String, Int>? = null
            val readOnlyMap = buildMap { leakedMap = this; put("x", 1) }
            try {
                leakedMap!!.put("y", 2)
                println("map-mutated")
            } catch (e: UnsupportedOperationException) {
                println("map-read-only")
            }
            println(readOnlyMap)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BuildFamilyFreezeRuntime",
            expected: "list-read-only\n[7]\nset-read-only\n[9]\nmap-read-only\n{x=1}\n"
        )
    }
}
#endif
