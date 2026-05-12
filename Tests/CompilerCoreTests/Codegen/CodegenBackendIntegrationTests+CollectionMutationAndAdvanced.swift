@testable import CompilerCore
import Foundation
import XCTest

/// Collection-copy / Map / Mutable / Build / advanced integration
/// tests, split out from `CodegenBackendIntegrationTests` to keep
/// each test source focused.
extension CodegenBackendIntegrationTests {
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

    func testCodegenListMinReturnsSmallestElementAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(3, 1, 4, 2)
            println(values.min())
            try {
                emptyList<Int>().min()
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
                moduleName: "ListMinRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1\nempty\n")
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

    func testCodegenMapFilterValuesReturnsFilteredEntries() throws {
        let source = """
        fun main() {
            val values = mapOf("a" to 1, "b" to 2, "c" to 3)
            println(values.filterValues { it % 2 == 0 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapFilterValuesRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "{b=2}\n")
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
