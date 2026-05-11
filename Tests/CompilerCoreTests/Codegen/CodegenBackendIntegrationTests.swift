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

    func testCodegenLibraryMetadataIncludesCompilerMetadataAnnotation() throws {
        let source = """
        class Plain
        interface Face
        object Singleton
        enum class Color { RED }
        annotation class Marker
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory
            let libBase = tempDir.appendingPathComponent(UUID().uuidString).path
            _ = try runCodegenPipeline(inputPath: path, moduleName: "MetadataLib", emit: .library, outputPath: libBase)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
            XCTAssertTrue(metadata.contains("kotlin.Metadata"))
            XCTAssertTrue(metadata.contains("fq=Plain"))
            XCTAssertTrue(metadata.contains("fq=Face"))
            XCTAssertTrue(metadata.contains("fq=Singleton"))
            XCTAssertTrue(metadata.contains("fq=Color"))
            XCTAssertTrue(metadata.contains("fq=Marker"))
        }
    }

    func testCodegenAnnotationReflectionHidesCompilerMetadata() throws {
        let source = """
        annotation class Label(val value: String = "ok")

        @Label("hello")
        class Tagged

        class Plain

        fun main() {
            println(Tagged::class.annotations.size)
            println(Plain::class.annotations.size)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MetadataReflection",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1\n0\n")
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

    func testCodegenDataClassSynthesizesCorrectToStringAndEqualityWithoutExplicitSuperclass() throws {
        let source = """
        data class Person(val name: String, val age: Int)
        fun main() {
            val p = Person("Alice", 30)
            println(p.toString())
            println(p.hashCode() != 0)
            val p2 = Person("Alice", 30)
            println(p == p2)
            println(p.equals(p2))
            val (name, age) = p
            println("$name is $age")
            println(p.component1())
            println(p.component2())
            val p3 = p.copy(age = 31)
            println(p3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DataClassToString",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                Person(name=Alice, age=30)
                true
                true
                true
                Alice is 30
                Alice
                30
                Person(name=Alice, age=31)

                """
            )
        }
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

    func testCodegenCompilesMathTopLevelCalls() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            println(abs(-5))
            println(abs(-5.0))
            println(sqrt(4.0))
            println(pow(2.0, 3.0))
            println(ceil(2.3))
            println(floor(-2.3))
            println(round(2.7))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MathTopLevelCalls",
                emit: .object,
                outputPath: outputBase
            )
            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
        }
    }

    func testCodegenCompilesIntPrimitiveConversions() throws {
        let source = """
        fun main() {
            println(42.toFloat())
            println(300.toByte())
            println(32768.toShort())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IntPrimitiveConversions",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "42.0\n44\n-32768\n")
        }
    }

    func testCodegenCompilesComparisonTopLevelCalls() throws {
        let source = """
        fun main() {
            println(maxOf(3, 7))
            println(minOf(3, 7))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparisonTopLevelCalls",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "7\n3\n")
        }
    }

    func testCodegenCompilesUnsignedMaxOfTopLevelCalls() throws {
        let source = """
        fun main() {
            println(maxOf(1u, 4000000000u) == 4000000000u)
            println(maxOf(1u, 3u, 4000000000u) == 4000000000u)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnsignedComparisonMaxOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\n")
        }
    }

    func testCodegenCompilesComparatorMaxOfTopLevelCalls() throws {
        let source = """
        fun main() {
            println(maxOf(1, 2, reverseOrder<Int>()) == 1)
            println(maxOf(1, 4, 2, 3, reverseOrder<Int>()) == 1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparatorComparisonMaxOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\n")
        }
    }

    func testCodegenCompilesComparatorSortedWithTopLevelCalls() throws {
        let source = """
        fun main() {
            val list = listOf(3, 1, 4, 1, 5, 9)
            println(list.sortedWith(naturalOrder()))
            println(list.sortedWith(reverseOrder()))
            val comparator = compareBy<Int> { it }
            println(list.sortedWith(comparator.reversed()))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparatorComparisonSortedWith",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 1, 3, 4, 5, 9]
                [9, 5, 4, 3, 1, 1]
                [9, 5, 4, 3, 1, 1]

                """
            )
        }
    }

    func testCodegenCompilesGenericMaxOfTopLevelCalls() throws {
        let source = """
        fun main() {
            println(maxOf("b", "a") == "b")
            println(maxOf("d", "b", "a", "c") == "d")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GenericComparisonMaxOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\n")
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
            XCTAssertEqual(normalizedStdout, "NaN\nNaN\n")
        }
    }

    func testCodegenListOfIndexingUsesListRuntimeGet() throws {
        throw XCTSkip("List indexing test temporarily disabled on Linux")
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            println(list.size)
            println(list.get(0))
            println(list.get(1))
            println(list.get(2))
            println(list.contains(2))
            println(list.contains(5))
            println(list.isEmpty())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListGetRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\n1\n2\n3\ntrue\nfalse\nfalse\n")
        }
    }

    func testCodegenEnumNameAndOrdinal() throws {
        let source = """
        enum class Color { RED, GREEN, BLUE }

        fun main() {
            println(Color.RED.name)
            println(Color.RED.ordinal)
            println(Color.GREEN.name)
            println(Color.GREEN.ordinal)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "EnumNameOrdinal",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "RED\n0\nGREEN\n1\n")
        }
    }

    func testCodegenEnumValuesAndValueOf() throws {
        // Test enumValueOf (no map dependency)
        let sourceValueOf = """
        enum class Color { RED, GREEN, BLUE }

        fun main() {
            println(enumValueOf<Color>("GREEN"))
        }
        """
        try withTemporaryFile(contents: sourceValueOf) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "EnumValueOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "GREEN\n")
        }

        // Test enumValues
        let sourceValues = """
        enum class Color { RED, GREEN, BLUE }

        fun main() {
            val values = enumValues<Color>()
            println(values.size)
            println(values.get(0))
            println(values.get(1))
        }
        """
        try withTemporaryFile(contents: sourceValues) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "EnumValues",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\nRED\nGREEN\n")
        }
    }

    func testCodegenMutableListBasicMutationsUseRuntimeListBox() throws {
        let source = """
        fun main() {
            val list = mutableListOf(1, 2)
            list.add(3)
            println(list)
            val removed = list.removeAt(1)
            println(removed)
            println(list)
            list.clear()
            println(list)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableListBasicRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3]\n2\n[1, 3]\n[]\n")
        }
    }

    func testCodegenListComponentNUsesRuntimeAccessors() throws {
        let source = """
        fun main() {
            val values = listOf("a", "b", "c", "d", "e")
            println(values.component1())
            println(values.component2())
            println(values.component3())
            println(values.component4())
            println(values.component5())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListComponentNRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "a\nb\nc\nd\ne\n")
        }
    }

    func testCodegenListFilterIsInstanceToUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values: List<Any> = listOf(1, "two", 3, "four")
            val dest = mutableListOf<Int>(99)
            val result = values.filterIsInstanceTo(dest)
            println(result)
            println(dest)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListFilterIsInstanceToRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[99, 1, 3]\n[99, 1, 3]\n")
        }
    }

    func testCodegenCollectionContainsAndContainsAllUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            println(list.contains(2))
            println(list.contains(9))
            println(list.containsAll(listOf(1, 3)))
            println(list.containsAll(listOf(1, 9)))

            val set = setOf("a", "b")
            println(set.contains("a"))
            println(set.containsAll(listOf("a", "b")))
            println(set.containsAll(listOf("a", "c")))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionContainsRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\nfalse\ntrue\nfalse\ntrue\ntrue\nfalse\n")
        }
    }


    func testCodegenMutableListRemoveFirstOrNullUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/mutable_list_removefirstornull.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableListRemoveFirstOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1
                [2]
                2
                []
                -1
                []
                """ + "\n"
            )
        }
    }

    func testCodegenMutableListRemoveLastOrNullUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/mutable_list_removelastornull.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableListRemoveLastOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                2
                [1]
                1
                []
                -1
                []
                """ + "\n"
            )
        }
    }

    func testCodegenMutableListSortWithUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/mutable_list_sortwith.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableListSortWith",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 3, 4]
                [4, 3, 1]
                [fig, pear, apple]
                """ + "\n"
            )
        }
    }

    func testCodegenSetFactoriesAndMutableSetMutationsUseRuntimeSetBox() throws {
        let source = """
        fun main() {
            val set = setOf(1, 2, 2, 3)
            println(set)
            println(set.size)
            println(set.contains(2))
            println(set.isEmpty())

            val mutable = mutableSetOf(1, 2)
            println(mutable.add(2))
            println(mutable.add(3))
            println(mutable.remove(1))
            println(mutable)
            println(emptySet<Int>().isEmpty())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SetRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3]\n3\ntrue\nfalse\nfalse\ntrue\ntrue\n[2, 3]\ntrue\n")
        }
    }

    func testCodegenSetOfNotNullFiltersNullsAndDeduplicates() throws {
        let source = """
        fun main() {
            val values = setOfNotNull("a", null, "b", null, "a")
            println(values)
            println(values.size)

            val empty = setOfNotNull<String>(null)
            println(empty)
            println(empty.isEmpty())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SetOfNotNullRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[a, b]\n2\n[]\ntrue\n")
        }
    }

    func testCodegenLinkedSetOfFactoryUsesMutableRuntimeSet() throws {
        let source = """
        fun main() {
            val set = linkedSetOf(1, 2, 2)
            println(set)
            println(set.add(3))
            println(set)

            val empty = linkedSetOf<String>()
            empty.add("x")
            println(empty)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "LinkedSetOfFactoryRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2]\ntrue\n[1, 2, 3]\n[x]\n")
        }
    }

    func testCodegenHashSetOfFactoryUsesMutableRuntimeSet() throws {
        let source = """
        fun main() {
            val set = hashSetOf(1, 2, 2)
            println(set)
            println(set.add(3))
            println(set)

            val empty = hashSetOf<String>()
            empty.add("x")
            println(empty)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "HashSetOfFactoryRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2]\ntrue\n[1, 2, 3]\n[x]\n")
        }
    }

    func testCodegenMutableSetAddAllAcceptsSetAndListCollections() throws {
        let source = """
        fun main() {
            val values = mutableSetOf(1, 2)
            println(values.addAll(listOf(2, 3, 4)))
            println(values)
            println(values.addAll(setOf(4, 5)))
            println(values)
            values.clear()
            println(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableSetAddAllRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\n[1, 2, 3, 4]\ntrue\n[1, 2, 3, 4, 5]\n[]\n")
        }
    }

    func testCodegenIterableFirstNotNullOfReturnsFirstValueAndThrowsWhenMissing() throws {
        let source = """
        fun main() {
            val result: String = listOf(1, 2, 3).firstNotNullOf { if (it > 1) "hit" else null }
            println(result)
            try {
                listOf(1, 3, 5).firstNotNullOf { if (it % 2 == 0) it else null }
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IterableFirstNotNullOfRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            do {
                try LinkPhase().run(ctx)
            } catch {
                let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
                XCTFail("Link failed for firstNotNullOf: \(diagnostics)")
                throw error
            }

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hit\nempty\n")
        }
    }

    func testCodegenListPlusSetAppendsSetElements() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2)
            val set = setOf(4, 5)
            println(list + set)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListPlusSetRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 4, 5]\n")
        }
    }

    func testCodegenMutableMapBasicMutationsUseRuntimeMapBox() throws {
        let source = """
        fun main() {
            val map = mutableMapOf("a" to 1)
            map["b"] = 2
            println(map)
            println(map.containsKey("a"))
            println(map.put("a", 3))
            println(map)
            println(map.remove("b"))
            println(map)
            println(map.getOrPut("a") { 7 })
            println(map.getOrPut("c") { 7 })
            println(map)
            println(emptyMap<String, Int>().isEmpty())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableMapBasicRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "{a=1, b=2}\ntrue\n1\n{a=3, b=2}\n2\n{a=3}\n3\n7\n{a=3, c=7}\ntrue\n")
        }
    }

    func testCodegenLinkedMapOfFactoryUsesMutableRuntimeMap() throws {
        let source = """
        fun main() {
            val map = linkedMapOf("a" to 1)
            map["b"] = 2
            println(map)
            println(map.put("a", 3))
            println(map)

            val empty = linkedMapOf<String, Int>()
            empty["z"] = 9
            println(empty)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "LinkedMapOfFactoryRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "{a=1, b=2}\n1\n{a=3, b=2}\n{z=9}\n")
        }
    }

    func testCodegenHashMapOfFactoryUsesMutableRuntimeMap() throws {
        let source = """
        fun main() {
            val map = hashMapOf("a" to 1)
            map["b"] = 2
            println(map)
            println(map.put("a", 3))
            println(map)

            val empty = hashMapOf<String, Int>()
            empty["z"] = 9
            println(empty)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "HashMapOfFactoryRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "{a=1, b=2}\n1\n{a=3, b=2}\n{z=9}\n")
        }
    }

    func testCodegenBuildMapUseRuntimeBuilder() throws {
        let source = """
        fun main() {
            val m = buildMap {
                put("a", 1)
                put("b", 2)
            }
            println(m)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "BuildMapRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "{a=1, b=2}\n")
        }
    }

    func testCodegenBuildSetUseRuntimeBuilder() throws {
        let source = """
        fun main() {
            val s = buildSet {
                add("a")
                add("b")
                add("a")
                addAll(setOf("c", "b"))
            }
            println(s)
            println(s.size)
            println(s.contains("c"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "BuildSetRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[a, b, c]\n3\ntrue\n")
        }
    }

    func testCodegenMapWithDefaultUsesRuntimeDefaultForGetValue() throws {
        let source = """
        fun main() {
            val factor = 100
            val values = mapOf(1 to 10).withDefault { it * factor }
            println(values.getValue(1))
            println(values.getValue(2))
            println(values[2])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapWithDefaultRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "10\n200\nnull\n")
        }
    }

    func testCodegenCollectionCopiesProduceIndependentMutableAndSetViews() throws {
        let source = """
        fun main() {
            val sourceList = listOf(1, 2, 2)
            val copiedList = sourceList.toMutableList()
            copiedList.add(3)
            println(sourceList)
            println(copiedList)

            val copiedSet = sourceList.toSet()
            println(copiedSet)
            println(copiedSet.contains(2))

            val sourceMap = mapOf("a" to 1)
            val copiedMap = sourceMap.toMutableMap()
            copiedMap["b"] = 2
            println(sourceMap)
            println(copiedMap)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionCopiesRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 2]\n[1, 2, 2, 3]\n[1, 2]\ntrue\n{a=1}\n{a=1, b=2}\n")
        }
    }

    func testCodegenListToMapKeepsLastValueForDuplicateKeys() throws {
        let source = """
        fun main() {
            val map = listOf(1 to "one", 2 to "two", 1 to "uno").toMap()
            println(map.size)
            println(map[1])
            println(map[2])
            println(map.containsKey(3))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListToMapRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "2\nuno\ntwo\nfalse\n")
        }
    }

    func testCodegenListUnionUsesRuntimeSetOperation() throws {
        let source = """
        fun main() {
            val values: List<Int> = listOf(1, 2, 2, 3)
            val other: List<Int> = listOf(3, 4, 2, 5)
            val unioned = values.union(other)
            println(unioned.size)
            println(unioned.contains(1))
            println(unioned.contains(4))
            println(unioned.contains(9))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListUnionRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            do {
                try LinkPhase().run(ctx)
            } catch {
                let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
                XCTFail("Link failed for List.union: \(diagnostics)")
                throw error
            }

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "5\ntrue\ntrue\nfalse\n")
        }
    }

    func testCodegenCollectionAndIterableToMutableListReturnIndependentCopies() throws {
        let source = """
        fun main() {
            val sourceCollection: Collection<Int> = listOf(1, 2, 3)
            val collectionCopy = sourceCollection.toMutableList()
            collectionCopy.add(4)
            println(sourceCollection)
            println(collectionCopy)

            val sourceIterable: Iterable<Int> = setOf(3, 1, 2)
            val iterableCopy = sourceIterable.toMutableList()
            iterableCopy.add(9)
            println(sourceIterable)
            println(iterableCopy)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionIterableToMutableListRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3]\n[1, 2, 3, 4]\n[3, 1, 2]\n[3, 1, 2, 9]\n")
        }
    }

    func testCodegenCollectionToListCopiesListAndSetReceivers() throws {
        let source = """
        fun main() {
            val sourceList = listOf(1, 2, 3)
            val copiedList = sourceList.toList()
            println(copiedList)

            val sourceSet = setOf(3, 1, 3, 2)
            val copiedSetList = sourceSet.toList()
            println(copiedSetList)
            println(copiedSetList.contains(2))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionToListRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3]\n[3, 1, 2]\ntrue\n")
        }
    }

    func testCodegenIterableToMutableSetDeduplicatesAndReturnsIndependentCopy() throws {
        let source = """
        fun main() {
            val sourceIterable: Iterable<Int> = listOf(3, 1, 2, 1)
            val mutableSet = sourceIterable.toMutableSet()
            mutableSet.add(9)
            println(sourceIterable)
            println(mutableSet)
            println(mutableSet.contains(1))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IterableToMutableSetRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[3, 1, 2, 1]\n[3, 1, 2, 9]\ntrue\n")
        }
    }

    func testCodegenListJoinToStringUsesRuntimeDefaultsAndNamedArguments() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            println(list.joinToString())
            println(list.joinToString(" | "))
            println(list.joinToString(prefix = "<", postfix = ">"))
            println(list.joinToString(separator = ":", prefix = "[", postfix = "]"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListJoinToStringRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1, 2, 3\n1 | 2 | 3\n<1, 2, 3>\n[1:2:3]\n")
        }
    }

    func testCodegenSequenceJoinToStringUsesRuntimeDefaultsAndNamedArguments() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 2, 3).joinToString(", "))
            println(sequenceOf("a", "b", "c").joinToString("-"))
            println(listOf<String>().asSequence().joinToString(prefix = "<", postfix = ">"))
            println(sequenceOf(1, 2, 3).joinToString(separator = ":", prefix = "[", postfix = "]"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceJoinToStringRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1, 2, 3\na-b-c\n<>\n[1:2:3]\n")
        }
    }

    func testCodegenListMapNotNullAndFilterNotNullUseRuntimeHOFs() throws {
        let source = """
        fun main() {
            val values = listOf(1, 0, 2)
            val numbers = values.mapNotNull { it }
            println(numbers)

            val nullable = listOf("a", null, "b", null)
            println(nullable.filterNotNull())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListMapNotNullAndFilterNotNullRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 0, 2]\n[a, b]\n")
        }
    }

    func testCodegenListMaxByReturnsSelectedElementAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(3, 1, 4, 2)
            println(values.maxBy { -it })
            try {
                emptyList<Int>().maxBy { -it }
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListMaxByRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1\nempty\n")
        }
    }

    func testCodegenListFilterNotUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4)
            println(values.filterNot { it % 2 == 0 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListFilterNotRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 3]\n")
        }
    }

    func testCodegenListMaxByOrNullReturnsSelectedElementOrNull() throws {
        let source = """
        fun main() {
            val values = listOf(3, 1, 4, 2)
            println(values.maxByOrNull { -it })
            println(emptyList<Int>().maxByOrNull { -it })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListMaxByOrNullRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1\nnull\n")
        }
    }

    func testCodegenIterableFirstNotNullOfOrNullReturnsFirstValueOrNull() throws {
        let source = """
        fun main() {
            val result: String? = listOf(1, 2, 3).firstNotNullOfOrNull { if (it > 1) "hit" else null }
            println(result)
            val missing: String? = listOf(1, 3, 5).firstNotNullOfOrNull { if (it % 2 == 0) "even" else null }
            println(missing)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IterableFirstNotNullOfOrNullRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            do {
                try LinkPhase().run(ctx)
            } catch {
                let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
                XCTFail("Link failed for firstNotNullOfOrNull: \(diagnostics)")
                throw error
            }

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hit\nnull\n")
        }
    }

    func testCodegenListZipAndUnzipUseRuntimeHOFs() throws {
        let source = """
        fun main() {
            val left = listOf(1, 2, 3)
            val right = listOf("a", "b")
            val zipped = left.zip(right)
            println(zipped)
            println(zipped.unzip())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListZipAndUnzipRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[(1, a), (2, b)]\n([1, 2], [a, b])\n")
        }
    }

    func testCodegenListTransformsUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val list = listOf(3, 1, 2, 1)
            println(list.take(3))
            println(list.drop(2))
            println(list.reversed())
            println(list.sorted())
            println(list.distinct())
            println(list.takeWhile { it > 2 })
            renderPrefix(list)
            try {
                println(list.take(-1))
                println("missing-take")
            } catch (e: IllegalArgumentException) {
                println("negative-take")
            }
            try {
                println(list.drop(-1))
                println("missing-drop")
            } catch (e: IllegalArgumentException) {
                println("negative-drop")
            }
            render(list)
        }

        fun render(values: List<Int>) {
            try {
                println(values.take(-1))
                println("missing-param-take")
            } catch (e: IllegalArgumentException) {
                println("negative-param-take")
            }
        }

        fun renderPrefix(values: List<Int>) {
            println(values.takeWhile { it > 2 })
            try {
                println(values.takeWhile {
                    if (it == 3) {
                        throw IllegalArgumentException("prefix")
                    }
                    true
                })
                println("missing-prefix")
            } catch (e: IllegalArgumentException) {
                println("negative-prefix")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListTransformsRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                "[3, 1, 2]\n[2, 1]\n[1, 2, 1, 3]\n[1, 1, 2, 3]\n[3, 1, 2]\n[3]\n[3]\nnegative-prefix\nnegative-take\nnegative-drop\nnegative-param-take\n"
            )
        }
    }

    func testCodegenListElementAtUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val list = listOf(10, 20, 30)
            println(list.elementAt(1))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListElementAtRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "20\n")
        }
    }

    func testCodegenMutableListFillUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val list = mutableListOf(1, 2, 3)
            list.fill(9)
            println(list)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableListFillRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[9, 9, 9]\n")
        }
    }
    func testCodegenListElementAtOrNullUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val list = listOf(10, 20, 30)
            println(list.elementAtOrNull(1) ?: -1)
            println(list.elementAtOrNull(5) ?: -1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListElementAtOrNullRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "20\n-1\n")
        }
    }

    func testCodegenListAggregateHelpersUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val list = listOf(3, 1, 2)
            println(list.flatMap { listOf(it, it * 10) })
            println(list.sumOf { it * 2 })
            println(list.minBy { it % 3 })
            println(list.maxOrNull())
            println(list.minOrNull())
            println(list.minOfOrNull { it * 10 })
            println(list.minByOrNull { it % 3 })
            println(list.foldRight(0) { value, acc -> value * 10 + acc })
            println(list.foldIndexed(0) { index, acc, value -> acc + index * value })
            println(list.foldRightIndexed(0) { index, value, acc -> index + value + acc })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ListAggregateRuntime", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_list_flatMap"))
            XCTAssertTrue(callees.contains("kk_list_sumOf") || callees.contains("sumOf"))
            XCTAssertTrue(callees.contains("kk_list_minBy"))
            XCTAssertTrue(callees.contains("kk_list_maxOrNull"))
            XCTAssertTrue(callees.contains("kk_list_minOrNull"))
            XCTAssertTrue(callees.contains("kk_list_minOfOrNull"))
            XCTAssertTrue(callees.contains("kk_list_minByOrNull"))
            XCTAssertTrue(callees.contains("kk_list_foldRight"))
            XCTAssertTrue(callees.contains("kk_list_foldIndexed"))
            XCTAssertTrue(callees.contains("kk_list_foldRightIndexed"))
        }
    }

    func testCodegenListAverageUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val list = listOf(2, 4, 6)
            println(list.average())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListAverageRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "4.0\n")
        }
    }

    func testCodegenListMinOrNullReturnsSmallestElementAndNullOnEmpty() throws {
        let source = """
        fun main() {
            println(listOf(5, 2, 3).minOrNull())
            println(emptyList<Int>().minOrNull() == null)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListMinOrNullRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "2\ntrue\n")
        }
    }

    func testCodegenListMinByOrNullReturnsSmallestSelectedElementAndNullOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(5, 2, 3)
            println(values.minByOrNull { it % 3 })
            val empty = emptyList<Int>()
            println(empty.minByOrNull { it % 3 } == null)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListMinByOrNullRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\ntrue\n")
        }
    }

    func testCodegenListMinByReturnsSmallestSelectedElementAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(5, 2, 3)
            println(values.minBy { it % 3 })
            try {
                emptyList<Int>().minBy { it }
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListMinByRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\nempty\n")
        }
    }

    func testCodegenListMinOfWithOrNullReturnsComparatorSelectedValueAndNullOnEmpty() throws {
        let source = """
        fun main() {
            println(listOf(5, 2, 3).minOfOrNull { it * 10 })
            println(emptyList<Int>().minOfOrNull { it * 10 } == null)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListMinOfOrNullRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "20\ntrue\n")
        }
    }

    func testCodegenMapHigherOrderHelpersUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val values = mapOf("a" to 1, "b" to 2)
            values.forEach {
                println("${it.key}=${it.value}")
            }
            println(values.map { it.key + ":" + (it.value * 10) })
            println(values.filter { it.value % 2 == 0 })
            println(values.mapValues { it.value * 10 })
            println(values.mapKeys { it.key + "!" })
            println(values.filterKeys { it == "b" })
            println(values.toList())
            println(values.map { it.toPair().first + ":" + (it.toPair().second + 1) })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapHigherOrderRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "a=1\nb=2\n[a:10, b:20]\n{b=2}\n{a=10, b=20}\n{a!=1, b!=2}\n{b=2}\n[(a, 1), (b, 2)]\n[a:2, b:3]\n")
        }
    }

    func testCodegenMapPropertyAccessesUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val values = mapOf("a" to 1, "b" to 2)
            println(values.keys)
            println(values.values)
            println(values.entries)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapPropertyRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[a, b]\n[1, 2]\n[a=1, b=2]\n")
        }
    }

    func testCodegenListAssociateHelpersUseRuntimeMapBuilders() throws {
        throw XCTSkip("List associate helpers feature not yet implemented")
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.associateBy { it % 2 })
            println(values.associateWith { it * 10 })
            println(values.associate { (it % 2) to (it * 10) })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListAssociateRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "{1=3, 0=2}\n{1=10, 2=20, 3=30}\n{1=30, 0=20}\n")
        }
    }

    func testCodegenListIndexedHelpersUseRuntimeHOFs() throws {
        let source = """
        fun main() {
            val values = listOf("a", "bb")
            values.forEachIndexed { index, value ->
                println(index * 10 + value.length)
            }
            println(values.mapIndexed { index, value -> index + value.length })
            println(listOf(10, 20, 30, 40).filterIndexed { index, value -> index + value > 21 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListIndexedHelpersRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1\n12\n[1, 3]\n[30, 40]\n")
        }
    }

    func testCodegenListFilterIsInstanceUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values: List<Any> = listOf(1, "two", 3)
            println(values.filterIsInstance<Int>())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListFilterIsInstanceRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 3]\n")
        }
    }

    func testCodegenStringContainsEmptyNeedleReturnsTrue() throws {
        let source = """
        fun main() {
            println("hello world".contains(""))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringContainsEmptyNeedle",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\n")
        }
    }

    func testCodegenRepeatDelayCancellationReachesLocalCatch() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.channels.*
        import kotlin.coroutines.cancellation.cancel

        fun main() = runBlocking {
            val started = Channel<Int>()
            val job = launch {
                try {
                    started.send(1)
                    repeat(1000) {
                        delay(10)
                    }
                } catch (e: CancellationException) {
                    println("cancelled")
                }
            }
            val jobContext = job + Dispatchers.Default
            started.receive()
            jobContext.cancel()
            job.join()
            println("done")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RepeatDelayCancellation",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "cancelled\ndone\n")
        }
    }

    func testCodegenCoroutineCancellationExtensionImportWorks() throws {
        let source = """
        import kotlin.coroutines.cancellation.cancel
        import kotlinx.coroutines.*
        import kotlinx.coroutines.channels.*

        fun main() = runBlocking {
            val started = Channel<Int>()
            val job = launch {
                try {
                    started.send(1)
                    repeat(1000) {
                        delay(10)
                    }
                } catch (e: CancellationException) {
                    println("cancelled")
                }
            }
            started.receive()
            job.cancel()
            job.join()
            println("done")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CoroutineCancellationExtensionImportWorks",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "cancelled\ndone\n")
        }
    }

    func testCodegenSuspendCoroutineReturnsResumedValue() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resume(42)
            }
        }

        fun main() {
            println(runBlocking(probe))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SuspendCoroutineRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "42\n")
        }
    }

    func testCodegenSuspendCoroutinePropagatesResumedException() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resumeWithException(IllegalStateException("boom"))
            }
        }

        fun main() {
            try {
                println(runBlocking(probe))
            } catch (e: Throwable) {
                println(e.message ?: "missing")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SuspendCoroutineRuntimeException",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "boom\n")
        }
    }

    func testCodegenEmitsObjectWhenLlvmBindingsAreRequired() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "LLVMRequired",
                inputs: [path],
                outputPath: outputBase,
                emit: .object,
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

            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
            XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
        }
    }

    func testLLVMBackendNativeFailureReportsEmissionError() throws {
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

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: diagnostics
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

    // MARK: - Private Helpers
}
