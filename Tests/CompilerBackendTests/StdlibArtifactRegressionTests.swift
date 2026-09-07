@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// STDLIB-ARTIFACT-001: shared stdlib artifact (.kklib) is correctly consumed
/// by a user module. This is a regression test for the `uuid_basic` shared-path
/// failure where imported globals such as `Uuid.Companion.NIL` were not declared
/// in the consumer module, causing `kk_array_get_inbounds` to receive a null
/// array pointer.
@Suite
struct StdlibArtifactRegressionTests {

    private static let sharedArtifactLock = NSLock()
    nonisolated(unsafe) private static var sharedArtifactPath: String?

    private static func buildStdlibArtifact() throws -> String {
        sharedArtifactLock.lock()
        defer { sharedArtifactLock.unlock() }

        if let cached = sharedArtifactPath {
            return cached
        }

        let artifactBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "KSwiftKStdlib",
            emit: .library,
            outputPath: artifactBase,
            includeStdlib: true,
            stdlibOnly: true
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)

        let artifactPath = artifactBase + ".kklib"
        #expect(FileManager.default.fileExists(atPath: artifactPath), "stdlib artifact directory should be emitted")
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/manifest.json"), "stdlib artifact should contain manifest.json")
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/metadata.bin"), "stdlib artifact should contain metadata.bin")
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/objects"), "stdlib artifact should contain objects directory")
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/inline-kir"), "stdlib artifact should contain inline-kir directory")

        sharedArtifactPath = artifactPath
        return artifactPath
    }

    private static let abstractCollectionSource = """
    import kotlin.collections.AbstractCollection
    import kotlin.collections.Iterator

    class EmptyIntIterator : Iterator<Int> {
        override fun hasNext(): Boolean = false
        override fun next(): Int = 0
    }

    class EvenNumbers : AbstractCollection<Int>() {
        override val size: Int
            get() = 0

        override fun iterator(): Iterator<Int> = EmptyIntIterator()
    }

    fun main() {
        println(EvenNumbers().size)
    }
    """

    /// KSP-697: inferred mutable collection factories must preserve their
    /// MutableIterable supertype when the stdlib is consumed as an artifact.
    @Test
    func testMutableFactoriesWidenThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        try withTemporaryFile(contents: """
        fun main() {
            val list = mutableListOf(1, 2, 3)
            val listIterable: MutableIterable<Int> = list
            val set = mutableSetOf(1, 2, 3)
            val setIterable: MutableIterable<Int> = set
        }
        """) { userPath in
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "MutableCollectionFactoryArtifact",
                emit: .kirDump,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Mutable collection factories should widen through MutableIterable: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    /// KSP-1165: a named companion object must remain an exact nested type when
    /// the stdlib is consumed through a precompiled artifact.
    @Test
    func testBase64NamedCompanionTypeThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi

        @OptIn(ExperimentalEncodingApi::class)
        fun main() {
            val default: Base64.Default = Base64.Default
            val padding: Base64.PaddingOption = Base64.PaddingOption.ABSENT
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "Base64NestedArtifact",
                emit: .kirDump,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// Devin review: a regular nested object must use its own initializer
    /// linkage decision, even when its enclosing class has a companion.
    @Test
    func testRegularNestedObjectDoesNotUseParentCompanionInitializerForGlobalLinkage() throws {
        let source = """
        open class Base {
            open fun value(): Int = 0
        }

        class ContainerWithNestedObject {
            companion object {
                val companionMarker: Int = 1
            }

            object Nested : Base() {
                override fun value(): Int = 42
            }
        }
        """
        try withTemporaryFile(contents: source) { sourcePath in
            let ctx = makeCompilationContext(inputs: [sourcePath])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let nestedFQName = [
                "ContainerWithNestedObject", "Nested"
            ].map(ctx.interner.intern)
            let parentFQName = ["ContainerWithNestedObject"].map(ctx.interner.intern)
            let nestedSymbol = try #require(sema.symbols.lookup(fqName: nestedFQName))
            let parentSymbol = try #require(sema.symbols.lookup(fqName: parentFQName))
            let nestedLayout = try #require(sema.symbols.nominalLayout(for: nestedSymbol))
            #expect(nestedLayout.vtableSize > 0)
            #expect(sema.symbols.companionObjectSymbol(for: parentSymbol) != nestedSymbol)

            let initializerName = ctx.interner.intern("__test_companion_init")
            let initializer = sema.symbols.define(
                kind: .function,
                name: initializerName,
                fqName: parentFQName + [initializerName],
                declSite: nil,
                visibility: .public
            )
            sema.symbols.setCompanionObjectInitializerSymbol(initializer, for: parentSymbol)

            #expect(
                NativeEmitter.shouldUseWeakImportedObjectGlobalReference(
                    for: nestedSymbol,
                    symbols: sema.symbols
                )
            )

            let objectInitializerName = ctx.interner.intern("__test_object_init")
            let objectInitializer = sema.symbols.define(
                kind: .function,
                name: objectInitializerName,
                fqName: nestedFQName + [objectInitializerName],
                declSite: nil,
                visibility: .public
            )
            sema.symbols.setObjectInitializerSymbol(objectInitializer, for: nestedSymbol)
            #expect(
                !NativeEmitter.shouldUseWeakImportedObjectGlobalReference(
                    for: nestedSymbol,
                    symbols: sema.symbols
                )
            )

            let companionSymbol = try #require(
                sema.symbols.companionObjectSymbol(for: parentSymbol)
            )
            #expect(
                !NativeEmitter.shouldUseWeakImportedObjectGlobalReference(
                    for: companionSymbol,
                    symbols: sema.symbols
                )
            )
        }
    }

    /// BUG-200: bundled source and precompiled stdlib metadata must agree on
    /// abstract member modality and on the owner's type argument in overrides.
    @Test
    func testAbstractCollectionOverrideThroughBundledSource() throws {
        try withTemporaryFile(contents: Self.abstractCollectionSource) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "Bug200Source",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: true
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "0\n")
        }
    }

    /// BUG-200: the same source must compile and run when AbstractCollection
    /// and its members come from a stdlib library artifact.
    @Test
    func testAbstractCollectionOverrideThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        try withTemporaryFile(contents: Self.abstractCollectionSource) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "Bug200Artifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "0\n")
        }
    }

    @Test
    func testUuidBasicSharedPathPrintsOk() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            val uuidStr = "550e8400-e29b-41d4-a716-446655440000"
            val nilStr = "00000000-0000-0000-0000-000000000000"

            val parsed = Uuid.parse(uuidStr)
            println("parse roundtrip: ${parsed.toString() == uuidStr}")

            val nil = Uuid.NIL
            println("nil string: ${nil.toString() == nilStr}")
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "parse roundtrip: true\nnil string: true\n")
        }
    }

    /// STDLIB-ARTIFACT-003: built-in exception constructors are runtime factories
    /// (`kk_*_exception_new_message`) and must not receive an implicit `this`
    /// allocated by `kk_object_new`; otherwise the message handle is misread and
    /// `Throwable.message` is empty in the consumer.
    @Test
    func testExceptionMessageThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            try {
                throw IllegalStateException("shared boom")
            } catch (e: IllegalStateException) {
                println("caught: ${e.message}")
            }
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "caught: shared boom\n")
        }
    }

    /// STDLIB-ARTIFACT-004: generic `maxOf`/`minOf` overloads on `Comparable`
    /// work through the shared stdlib artifact even though their `Comparable<T>`
    /// upper bound is not preserved in metadata; the CallLowerer recognizes the
    /// uniform type-parameter signature and lowers the comparison inline.
    @Test
    func testMaxOfComparableThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println(maxOf("banana", "apple"))
            println(maxOf("cherry", "apple", "banana"))
            println(maxOf("date", "banana", "apple", "cherry"))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "banana\ncherry\ndate\n")
        }
    }

    /// STDLIB-ARTIFACT-005: synthetic singleton objects without backing state
    /// (e.g. `kotlin.system.System`) do not require a global root slot in the
    /// consumer. The CallLowerer emits their `symbolRef`, but the backend must
    /// not declare an external global for an object that has no initializer,
    /// no external factory, and no fields.
    @Test
    func testSyntheticSingletonObjectSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val millis = System.currentTimeMillis()
            println(millis > 0)

            val t1 = System.nanoTime()
            val t2 = System.nanoTime()
            println(t2 >= t1)

            val millis2 = System.currentTimeMillis()
            println(millis2 >= millis)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "true\ntrue\ntrue\n")
        }
    }

    /// STDLIB-ARTIFACT-006: enum entry references from a precompiled stdlib
    /// artifact must have their global ordinal slots initialized. The shared
    /// artifact contains the `__enum_static_init_*` function; the consumer's
    /// top-level initializer must call it before `main` so that enum entry
    /// objects such as `Base64.PaddingOption.ABSENT` behave correctly.
    @Test
    func testEnumEntryStaticInitializerSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi

        @OptIn(ExperimentalEncodingApi::class)
        fun main() {
            val noPad = Base64.Default.withPadding(Base64.PaddingOption.ABSENT)
            println(noPad.encode("foob".encodeToByteArray()))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "Zm9vYg\n")
        }
    }

    /// STDLIB-ARTIFACT-007: imported source-backed stdlib extension functions
    /// (e.g. `Duration.compareTo`) must be visible in the consumer's default-import
    /// scope so member-style calls resolve to the concrete extension instead of
    /// falling back to a broad short-name lookup that also sees `Comparable<T>.compareTo`
    /// and reports an ambiguous overload.
    @Test
    func testDurationCompareToSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val d1 = 1.seconds
            val d2 = 2.seconds
            println(d2.compareTo(d1))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "1\n")
        }
    }

    /// STDLIB-ARTIFACT-008: `java.io.Closeable` imported as a synthetic nominal
    /// anchor from a prebuilt stdlib artifact must retain its `kotlin.io.Closeable`
    /// supertype so that user implementations are recognised as `Closeable` and
    /// `.use {}` resolves and runs correctly.
    @Test
    func testCloseableUseSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import java.io.Closeable

        class MyResource(val name: String) : Closeable {
            override fun close() {
                println("$name closed")
            }
        }

        fun main() {
            val result = MyResource("r1").use {
                println("using r1")
                42
            }
            println("result=$result")
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "using r1\nr1 closed\nresult=42\n")
        }
    }

    /// STDLIB-ARTIFACT-009: synthetic operator extension functions (e.g.
    /// `CharSequence.get`) must not shadow source-backed member functions
    /// (e.g. `StringBuilder.get`) in the default-import scope. Inside
    /// `buildString { append(get(1)) }`, `get(1)` must resolve to the real
    /// `StringBuilder.get` member and print the correct character.
    @Test
    func testBuildStringReceiverGetSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println(buildString { append("abc"); append(get(1)) })
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "abcb\n")
        }
    }

    /// STDLIB-ARTIFACT-010: `emptySequence()` must resolve to the source-backed
    /// stdlib factory (not a runtime `RuntimeSequenceBox`) so that `withIndex()`
    /// and other source-implemented `Sequence` extensions can call `source.iterator()`
    /// through normal virtual dispatch.
    @Test
    func testEmptySequenceWithIndexSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val indexed = sequenceOf(10, 20, 30).withIndex().toList()
            println(indexed)

            val first = sequenceOf(10, 20, 30).withIndex().take(1).toList()
            println(first)

            val empty = emptySequence<Int>().withIndex().toList()
            println(empty)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "[IndexedValue(index=0, value=10), IndexedValue(index=1, value=20), IndexedValue(index=2, value=30)]\n[IndexedValue(index=0, value=10)]\n[]\n")
        }
    }

    /// STDLIB-ARTIFACT-011: synthetic `String.contains` extension must bind a real
    /// call symbol through the shared stdlib artifact so KIR lowering emits the
    /// dedicated `kk_string_contains_str_flat` helper instead of a generic
    /// `kk_op_contains` dispatch. This regresses when pure synthetic operator
    /// extensions are excluded from the default-import scope and the string
    /// fallback returns a type without a `CallBinding`.
    @Test
    func testStringContainsSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println("Kotlin".contains("otl"))
            println("Kotlin".contains("abc"))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "true\nfalse\n")
        }
    }

    /// STDLIB-ARTIFACT-012: `Array.asSequence()` must lower to the runtime
    /// `kk_array_asSequence` bridge through the shared stdlib artifact so that
    /// downstream `Sequence.filterIsInstance`/`toList` operate on the array
    /// elements instead of silently producing an empty list.
    @Test
    func testArrayAsSequenceFilterIsInstanceSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val values: Array<Any> = arrayOf(1, "two", 3)
            println(values.asSequence().filterIsInstance<Int>().toList())
            println(values.asSequence().filterIsInstance<String>().toList())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "[1, 3]\n[two]\n")
        }
    }

    /// STDLIB-ARTIFACT-013: imported inline-KIR bodies must preserve floating-point
    /// and character literals. `sumByDouble` uses `double:0.0` as its loop
    /// accumulator; if `LibraryInlineImport` drops `double:` tokens the accumulator
    /// is left uninitialized, so the second `sumByDouble` call reuses the first
    /// call's result.
    @Test
    func testSumByDoubleLiteralInImportedInlineKIR() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println("abc".sumByDouble { it.code.toDouble() / 2 })
            println("".sumByDouble { it.code.toDouble() / 2 })
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "147.0\n0.0\n")
        }
    }

    /// STDLIB-ARTIFACT-014: member properties with custom getters (e.g.
    /// `Result.isSuccess`/`isFailure`) must round-trip through the shared stdlib
    /// artifact with `propertyGetterExternalLinkName`. Otherwise the consumer
    /// falls back to a field-offset read and crashes or misreads the value.
    @Test
    func testResultMemberPropertyGetterSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val s = runCatching { 10 }
            val f = runCatching { throw RuntimeException("x") }
            println("s.isSuccess=${s.isSuccess} s.isFailure=${s.isFailure}")
            println("f.isSuccess=${f.isSuccess} f.isFailure=${f.isFailure}")
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "s.isSuccess=true s.isFailure=false\nf.isSuccess=false f.isFailure=true\n")
        }
    }

    /// Imported runtime-backed interface getters retain a direct external link
    /// in the shared artifact. They must not be redirected to an itable property
    /// slot that the runtime collection boxes do not register.
    @Test
    func testImportedCollectionSizeGetterUsesDirectBridge() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun collectionSize(values: Collection<Int>): Int = values.size

        fun main() {
            println(collectionSize(listOf(1, 2, 3)))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ImportedCollectionSizeGetter",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let body = try findKIRFunctionBody(
                named: "collectionSize",
                in: module,
                interner: ctx.interner
            )
            let directGetterLinks = body.compactMap { instruction -> String? in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction,
                      let symbol
                else {
                    return nil
                }
                return sema.symbols.externalLinkName(for: symbol)
            }
            #expect(directGetterLinks.contains("__kk_collection_size"))
            #expect(!body.contains { instruction in
                guard case .virtualCall = instruction else { return false }
                return true
            })

            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "3\n")
        }
    }

    /// STDLIB-ARTIFACT-022: direct construction must use RuntimeResultBox rather
    /// than the ordinary Kotlin object allocation path.
    @Test
    func testResultConstructorUsesRuntimeSuccessFactory() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        fun main() {
            val result: Result<Int> = Result(7)
            println(result.isSuccess)
            println(result.getOrThrow())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "true\n7\n")
        }
    }

    /// STDLIB-ARTIFACT-015: imported synthetic enum entries (e.g.
    /// `RegexOption`) must carry `.constValue` and an ordinal expression so
    /// the shared stdlib path emits `intLiteral` values instead of unresolved
    /// `symbolRef` constants. Otherwise `Regex(..., RegexOption.XXX)` is passed
    /// an object pointer or ignored by the runtime.
    @Test
    func testRegexOptionConstantsSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlin.text.RegexOption

        fun main() {
            println(Regex("[a-z]+", RegexOption.IGNORE_CASE).matches("ABC"))
            println(Regex("^line", RegexOption.MULTILINE).containsMatchIn("first\\nline two"))
            println(Regex("a.b", RegexOption.DOT_MATCHES_ALL).containsMatchIn("a\\nb"))
            println(Regex("[a-z]+", RegexOption.LITERAL).containsMatchIn("[a-z]+"))
            println(Regex(".", RegexOption.UNIX_LINES).containsMatchIn("a"))
            println(Regex("a b  # match ab", RegexOption.COMMENTS).containsMatchIn("ab"))
            println(Regex("[a-z]+", setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE)).matches("HELLO"))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n")
        }
    }

    /// STDLIB-ARTIFACT-016: imported synthetic enum entries for
    /// `CharDirectionality` must round-trip as compile-time ordinals so the
    /// shared stdlib `Char.directionality` extension can compare directionality
    /// values by ordinal.
    @Test
    func testCharDirectionalityConstantsSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlin.text.CharDirectionality

        fun main() {
            println('A'.directionality == CharDirectionality.LEFT_TO_RIGHT)
            println('\\u05D0'.directionality == CharDirectionality.RIGHT_TO_LEFT)
            println('5'.directionality == CharDirectionality.EUROPEAN_NUMBER)
            println(' '.directionality == CharDirectionality.WHITESPACE)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "true\ntrue\ntrue\ntrue\n")
        }
    }

    /// STDLIB-ARTIFACT-017: source-implemented `Sequence` HOFs (`flatMap`,
    /// `flatMapIndexed`) dispatch `Sequence.iterator()` on runtime-backed
    /// collections (`List`) returned by their lambdas. Runtime-backed
    /// collection boxes must advertise the `Sequence` itable so the generated
    /// interface dispatch resolves even when the type checker picks the
    /// `Sequence` overload for an `Iterable`/`List` result. `String.lineSequence()`
    /// also relies on `RuntimeSequenceBox`/`RuntimeSequenceIteratorBox` itables.
    @Test
    func testSequenceFlatMapAndLineSequenceSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println(sequenceOf(1, 2).flatMap { listOf(it, it * 10) }.toList())
            println(sequenceOf(1, 2).flatMapIndexed { index, value -> listOf(index, value * 10) }.toList())
            println("line1\nline2".lineSequence().toList())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "[1, 10, 2, 20]\n[0, 10, 1, 20]\n[line1, line2]\n")
        }
    }

    /// STDLIB-ARTIFACT-018: `Random.nextBytes(size: Int)` is an open method with
    /// multiple `nextBytes` overloads. The shared stdlib artifact's vtable slot
    /// layout must round-trip with enough type information to disambiguate
    /// overloads that have the same arity, so that `nextBytes(size)` dispatches to
    /// the correct `nextBytes(array)` implementation instead of an unmapped slot.
    @Test
    func testRandomNextBytesSizeSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlin.random.Random

        fun main() {
            println(Random(99).nextBytes(8).size)
            println(Random.nextBytes(8).size)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "8\n8\n")
        }
    }

    /// STDLIB-ARTIFACT-019: `List.filterIsInstance<R>()` is an inline reified HOF.
    /// The shared stdlib artifact's function metadata must round-trip the set of
    /// reified type parameter indices, so the consumer's call lowerer appends the
    /// runtime type-token argument required by the imported inline KIR body.
    @Test
    func testFilterIsInstanceSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val mixed: List<Any> = listOf(1, "hello", 2, "world", 3)
            val strings = mixed.filterIsInstance<String>()
            val ints = mixed.filterIsInstance<Int>()
            println(strings)
            println(ints)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "[hello, world]\n[1, 2, 3]\n")
        }
    }

    /// STDLIB-ARTIFACT-020: variance generics with `String` crossing interface
    /// dispatch boundaries (covariant `Producer`, contravariant `Consumer`,
    /// invariant `Container`) require the `virtualCall` emission to bridge
    /// `String` aggregate values to/from the erased raw-pointer ABI used by the
    /// itable function pointer. A user-defined method named `produce` must not
    /// be mistaken for the coroutine builder `produce` during lowering.
    @Test
    func testVarianceGenericsStringItableBridgeSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        interface Producer<out T> {
            fun produce(): T
        }

        interface Consumer<in T> {
            fun consume(value: T)
        }

        interface Container<T> {
            fun fetch(): T
            fun store(value: T)
        }

        class StringProducer(val value: String) : Producer<String> {
            override fun produce(): String = value
        }

        class AnyPrinter : Consumer<Any> {
            override fun consume(value: Any) {
                println("consumed: $value")
            }
        }

        class StringContainer(val initial: String) : Container<String> {
            override fun fetch(): String = initial
            override fun store(value: String) = println("stored: $value")
        }

        fun printAnyProduced(producer: Producer<Any>) {
            println(producer.produce())
        }

        fun feedStringConsumer(consumer: Consumer<String>) {
            consumer.consume("hello from feeder")
        }

        fun main() {
            val stringProducer: Producer<String> = StringProducer("variance test")
            val anyProducer: Producer<Any> = stringProducer
            printAnyProduced(anyProducer)

            val anyConsumer: Consumer<Any> = AnyPrinter()
            val stringConsumer: Consumer<String> = anyConsumer
            feedStringConsumer(stringConsumer)

            val container: Container<String> = StringContainer("invariant value")
            container.store("new value")
            println(container.fetch())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "variance test\nconsumed: hello from feeder\nstored: new value\ninvariant value\n")
        }
    }

    /// STDLIB-ARTIFACT-CHARSEQUENCE-SUBSEQUENCE: `subSequence` reached through a
    /// value statically typed as `CharSequence` (backed by `String`) must resolve
    /// to bundled Kotlin source (`Stdlib/kotlin/text/StringSubstringSlice.kt`) when
    /// compiling against a prebuilt stdlib artifact, not the removed
    /// `kk_string_subSequence_flat` runtime ABI (KSP-406). This is the shared-path
    /// analogue of `Scripts/diff_cases/char_sequence_member_access.kt`: the flake it
    /// guards only surfaced through `--no-stdlib --stdlib-library` linking, where an
    /// undefined reference to `kk_string_subSequence_flat` failed the link.
    @Test
    func testCharSequenceSubSequenceThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun printLength(cs: CharSequence) {
            println(cs.length)
        }

        fun main() {
            printLength("hello")
            val cs: CharSequence = "world!"
            println(cs.length)
            println(cs.get(1))
            println(cs[2])
            println(cs.subSequence(1, 3))
            val sb: CharSequence = StringBuilder("abc")
            println(sb.length)
            println(sb.get(1))
            println(sb[2])
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "5\n6\no\nr\nor\n3\nb\nc\n")
        }
    }

    /// STDLIB-ARTIFACT-STRING-INDENT: the indent-formatting family
    /// (`trimIndent`/`trimMargin`/`prependIndent`/`replaceIndent`/
    /// `replaceIndentByMargin`) must resolve to bundled Kotlin source
    /// (`Stdlib/kotlin/text/StringIndentFormat.kt`) when compiling against a
    /// prebuilt stdlib artifact, not the removed `kk_string_*_flat` runtime ABI.
    /// This is the shared-path analogue of the `raw_string_basic`,
    /// `string_indent`, `trim_margin` and `string_replaceindentbymargin` diff
    /// cases, whose failure mode was an undefined reference to
    /// `kk_string_trimIndent_flat` (and friends) at link time under
    /// `--no-stdlib --stdlib-library`.
    @Test
    func testStringIndentFormattingThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = #"""
        fun marker(value: String) {
            println(value.replace("\n", "/"))
        }

        fun main() {
            val raw = """
                line1
                line2
            """.trimIndent()
            marker(raw)
            marker("\n    |alpha\n    |beta\n".trimMargin())
            marker("\n    >alpha\n    >beta\n".trimMargin(">"))
            marker("Hello\nWorld".prependIndent())
            marker("Hello\nWorld".prependIndent(">>"))
            marker("  Hello\n  World".replaceIndent())
            marker("  Hello\n  World".replaceIndent("--"))
            marker("\n    |alpha\n    |beta\n".replaceIndentByMargin())
            marker("\n    |alpha\n    |beta\n".replaceIndentByMargin("> ", "|"))
        }
        """#

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                line1/line2
                alpha/beta
                alpha/beta
                    Hello/    World
                >>Hello/>>World
                Hello/World
                --Hello/--World
                alpha/beta
                > alpha/> beta

                """)
        }
    }

    /// KSP-625: `ArrayDeque<E>` is bundled Kotlin source, so the shared artifact
    /// path exercises two imported-library gaps it surfaced: a constructor call
    /// with explicit type arguments (`ArrayDeque<Int>()`) was rejected because
    /// imported constructor signatures reported zero class type parameters, and
    /// `println(deque)` printed `<object 0x...>` because the imported
    /// `toString()` override was skipped for being flagged synthetic.
    @Test
    func testArrayDequeThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val deque = ArrayDeque<Int>()
            deque.addLast(2)
            deque.addFirst(1)
            deque.addLast(3)
            println(deque.size)
            println(deque.first())
            println(deque.last())
            println(deque[1])
            println(deque)
            println(deque.removeFirst())
            println(deque.removeLast())
            println(deque.isEmpty())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                3
                1
                3
                2
                [1, 2, 3]
                1
                3
                false

                """)
        }
    }

    /// KSP-675: `SharedFlow`/`MutableSharedFlow` are bundled Kotlin source, so
    /// their members must keep working when the consumer only sees them through
    /// a prebuilt stdlib artifact. Reading `replayCache` through the interface
    /// needs the imported nominal's generic shape plus its itable property
    /// getter slot; calling `collect` needs the imported member to stay
    /// virtually dispatched and to keep the Kotlin (not runtime-bridge)
    /// argument shape, whose failure modes were an undefined reference to
    /// `replayCache`, a silently skipped `collect`, and a segfault in the HOF
    /// adapter.
    @Test
    func testSharedFlowThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlinx.coroutines.runBlocking
        import kotlinx.coroutines.flow.MutableSharedFlow
        import kotlinx.coroutines.flow.SharedFlow
        import kotlinx.coroutines.flow.flowOf
        import kotlinx.coroutines.flow.shareIn

        fun main() = runBlocking {
            val shared = MutableSharedFlow<Int>(2)
            println(shared.tryEmit(1))
            shared.emit(2)
            shared.emit(3)
            println(shared.replayCache)
            shared.collect { value -> println("class=$value") }

            val view: SharedFlow<Int> = shared
            println(view.replayCache)
            view.collect { value -> println("iface=$value") }

            println(flowOf(4, 5, 6).shareIn(2).replayCache)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                true
                [2, 3]
                class=2
                class=3
                [2, 3]
                iface=2
                iface=3
                [5, 6]

                """)
        }
    }

    /// STDLIB-ARTIFACT-003: an inline stdlib function whose body reads a
    /// property of a bundled Kotlin class (`Map.plus` reading `pair.first` /
    /// `pair.second`) links through the shared artifact.
    ///
    /// The inline body is serialized as KIR text and re-lowered in the consumer.
    /// Its getter call is recorded with the pre-mangling callee spelling
    /// (`get`) plus the library's link name for it (`kk_fn_get_<id>`). Only the
    /// latter names anything the consumer can call: the accessor is compiled
    /// into the library's own object and the consumer owns no symbol for it, so
    /// dropping the link name left an `undefined reference to 'get'` at link
    /// time. This only became reachable once `Pair`/`Triple` moved from
    /// synthetic runtime stubs (whose accessors were external `kk_pair_*`
    /// bridges, named identically in both modules) to bundled Kotlin source.
    @Test
    func testInlineStdlibFunctionReadingBundledClassPropertySharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val base: Map<String, Int> = mapOf("a" to 1)
            println(base.plus("b" to 2))
            println(emptyMap<String, Int>().plus("c" to 3))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "{a=1, b=2}\n{c=3}\n")
        }
    }

    /// STDLIB-ARTIFACT-021: `Sequence<T>.reduce`'s bundled source body iterated
    /// its receiver with a direct `for (elem in this)` loop. Through the shared
    /// stdlib artifact, that loop silently ran zero times (the receiver's
    /// `Iterator` itable dispatch does not round-trip through the artifact),
    /// so `reduce` always threw "Empty sequence can't be reduced." even for a
    /// non-empty sequence. `fold`/`scan` were unaffected because their bodies
    /// materialize the receiver via `toList()` first. Rewrote `reduce` to do
    /// the same.
    @Test
    func testSequenceReduceSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val seq = generateSequence(1) { if (it < 5) it + 1 else null }
            println(seq.reduce { acc, v -> acc + v })
            println(sequenceOf(1, 2, 3).reduce { acc, v -> acc + v })
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "15\n6\n")
        }
    }

    /// STDLIB-ARTIFACT-INLINE-ONLY-LAMBDA: `joinToString(separator) { ... }` is
    /// an auto-inline overload of the bundled `kotlin.collections` source, so no
    /// standalone body reaches the stdlib artifact. When such a call sits inside
    /// a lambda that is itself spliced into its caller (here the `let` body),
    /// the spliced instructions must be re-scanned for inline expansion;
    /// otherwise the consumer keeps an undefined reference to `kk_fn_joinToString_*`
    /// at link time (the `compiler_plugin_api` diff case failure mode).
    @Test
    func testInlineOnlyCallInsideSplicedLambdaThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val options: Map<String, String> = mapOf("k" to "v", "a" to "b")
            val summary = options.entries.let { entries ->
                entries.sortedBy { it.key }.joinToString(",") { "${it.key}=${it.value}" }
            }
            println(summary)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "a=b,k=v\n")
        }
    }

    /// STDLIB-ARTIFACT-KOTLIN-VERSION: `kotlin.KotlinVersion` is bundled Kotlin
    /// source (`Stdlib/kotlin/KotlinVersion.kt`) whose only runtime dependency
    /// is the `__kk_kotlin_version_current` build-time constant. Through the
    /// shared artifact the class arrives as an imported (synthetic-flagged)
    /// symbol, which used to make `println(version)` fall back to
    /// `kk_any_to_string` and print `<object 0x...>` instead of dispatching the
    /// imported `toString()` override.
    @Test
    func testKotlinVersionThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val short = KotlinVersion(2, 1)
            val full = KotlinVersion(2, 1, 20)
            println(short)
            println(full)
            println(full.major.toString() + "/" + full.minor.toString() + "/" + full.patch.toString())
            println(KotlinVersion.MAX_COMPONENT_VALUE)
            println(short < full)
            println(full.compareTo(short) > 0)
            println(full.isAtLeast(2, 1))
            println(full.isAtLeast(2, 1, 21))
            println(full == KotlinVersion(2, 1, 20))
            println(KotlinVersion.CURRENT.isAtLeast(1, 0))
            println(KotlinVersion.CURRENT.toString())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                2.1.0
                2.1.20
                2/1/20
                255
                true
                true
                true
                false
                true
                true
                2.3.10

                """)
        }
    }

    /// KSP-676: `StateFlow`/`MutableStateFlow`/`Flow.stateIn` are bundled Kotlin source, so
    /// they must keep working when the consumer only sees them through a prebuilt stdlib artifact.
    /// This covers `value`, `tryEmit`, `emit`, `replayCache`, `collect`, and the `stateIn` extension
    /// lowered to `kk_flow_collect` on an explicit local receiver.
    func testStateFlowThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlinx.coroutines.runBlocking
        import kotlinx.coroutines.flow.*

        fun main() = runBlocking {
            val state = MutableStateFlow(10)
            println(state.value)

            state.tryEmit(20)
            println(state.value)

            state.emit(30)
            println(state.value)

            val view: StateFlow<Int> = state
            println(view.value)
            println(view.replayCache)

            val initial = 0
            val stateFromFlow = flowOf(1, 2, 3).stateIn(initial)
            println(stateFromFlow.value)

            val shared = flowOf(4, 5, 6).shareIn(1)
            println(shared.replayCache)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                10
                20
                30
                30
                [30]
                3
                [6]

                """)
        }
    }

    /// KSP-707: symbols loaded from a precompiled stdlib library artifact carry
    /// both `.importedLibrary` and `.synthetic`, so `require`/`check`/`assert`'s
    /// `ContractNonNullEffect` (which powers `require(x != null)`-style smart-cast
    /// narrowing) must still be attached to those symbols and not skipped by a
    /// synthetic-only filter. Regression test for a bug introduced while
    /// relocating `patchSourceBackedPreconditionContractEffects` out of the
    /// now-deleted `HeaderHelpers+SyntheticPreconditionStubs.swift`: narrowing
    /// after `require`/`check` silently stopped resolving when compiling a
    /// consumer module against a shared `.kklib` artifact (the exact mode
    /// `Scripts/diff_kotlinc.sh` uses), while the inline-bundled-source
    /// compilation path kept working.
    @Test
    func testPreconditionSmartCastThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val x: String? = "hello"
            require(x != null)
            println(x.length)

            val y: String? = "world"
            check(y != null)
            println(y.length)

            val a: Any = "kotlin"
            require(a is String)
            println(a.length)

            val c: String? = "lazy"
            require(c != null) { "c must not be null" }
            println(c.length)

            val d: String? = "compound"
            val e: String? = "both"
            require(d != null && e != null)
            println(d.length + e.length)

            val f: String? = "asserted"
            assert(f != null)
            println(f.length)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                5
                5
                6
                4
                12
                8

                """)
        }
    }

    /// KSP-1022: an imported non-inline range iterator must not be redirected
    /// by InlineLoweringPass to the same-named MutableMap inline extension.
    /// The name fallback is only valid when the call has no known semantic
    /// symbol; artifact consumers otherwise lose the receiver-specific binding.
    @Test
    func testRangeHOFDoesNotUseSameNamedMutableMapIteratorFromArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println((1..5).reduce { acc, value -> acc + value })
            println((1..5).reduceIndexed { index, acc, value -> acc + index * value })
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KSP1022RangeArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "15\n41\n")
        }
    }
}
