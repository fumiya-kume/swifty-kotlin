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

    func testCodegenCompilesMathTopLevelCalls() throws {
        let source = """
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
            XCTAssertEqual(normalizedStdout, "{a=1, b=2}\ntrue\n1\n{a=3, b=2}\n2\n{a=3}\ntrue\n")
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
            XCTAssertEqual(normalizedStdout, "[3, 1, 2]\n[2, 1]\n[1, 2, 1, 3]\n[1, 1, 2, 3]\n[3, 1, 2]\n")
        }
    }

    func testCodegenListAggregateHelpersUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val list = listOf(3, 1, 2)
            println(list.sumOf { it * 2 })
            println(list.maxOrNull())
            println(list.minOrNull())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListAggregateRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "12\n3\n1\n")
        }
    }

    func testCodegenMapHigherOrderHelpersUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val values = mapOf("a" to 1, "b" to 2)
            values.forEach { (k, v) ->
                println("$k=$v")
            }
            println(values.map { (k, v) -> "$k:${v * 10}" })
            println(values.filter { (_, v) -> v % 2 == 0 })
            println(values.mapValues { it.value * 10 })
            println(values.mapKeys { it.key + "!" })
            println(values.toList())
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
            XCTAssertEqual(normalizedStdout, "a=1\nb=2\n[a:10, b:20]\n{b=2}\n{a=10, b=20}\n{a!=1, b!=2}\n[(a, 1), (b, 2)]\n")
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
            XCTAssertEqual(normalizedStdout, "[a, b]\n[1, 2]\n[(a, 1), (b, 2)]\n")
        }
    }

    func testCodegenListAssociateHelpersUseRuntimeMapBuilders() throws {
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
            XCTAssertEqual(normalizedStdout, "1\n12\n[1, 3]\n")
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
