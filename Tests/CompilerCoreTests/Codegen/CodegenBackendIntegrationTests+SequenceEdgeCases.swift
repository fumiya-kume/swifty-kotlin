@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesSequenceEdgeCases() throws {
        let source = """
        fun main() {
            val generated = generateSequence(1) { current -> if (current >= 3) null else current + 1 }
            println(generated.take(2).toList())

            val filtered = sequenceOf(1, 2, 3, 4)
                .map { it * 2 }
                .filter { it % 4 == 0 }

            println(filtered.take(1).toList())
            println(filtered.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 2]
                [4]
                [4, 8]
                """
                + "\n"
            )
        }
    }

    func testCodegenSequenceNoneOverloads() throws {
        let source = """
        fun main() {
            println(emptySequence<Int>().none())
            println(sequenceOf(1, 2, 3).none())
            println(sequenceOf(1, 3, 5).none { value -> value % 2 == 0 })
            println(sequenceOf(1, 2, 3).none { value -> value % 2 == 0 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceNoneOverloads",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\nfalse\ntrue\nfalse\n")
        }
    }

    func testCodegenSequenceReduceIndexedOrNull() throws {
        let source = """
        fun main() {
            val reduced = sequenceOf(1, 2, 3, 4)
                .reduceIndexedOrNull { index, acc, value -> acc + index * value }
            val empty = emptySequence<Int>()
                .reduceIndexedOrNull { index, acc, value -> acc + index * value }
            val single = sequenceOf(42)
                .reduceIndexedOrNull { index, acc, value -> acc + index * value }

            println(reduced)
            println(empty)
            println(single)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceReduceIndexedOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "21\nnull\n42\n")
        }
    }

    func testCodegenSequenceFlatMapIndexedUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_flatmap_indexed.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFlatMapIndexed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [0, 10, 1, 20]
                [1, 100, 3, 200]
                [0, 1, 1]
                []
                """
                    + "\n"
            )
        }
    }

    func testCodegenSequenceFirstNotNullOfUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_firstnotnullof.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFirstNotNullOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                three
                missing
                """
                + "\n"
            )
        }
    }

    func testCodegenSequenceFirstNotNullOfOrNullUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_firstnotnullofornull.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFirstNotNullOfOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                three
                missing
                """
                + "\n"
            )
        }
    }

    func testCodegenSequenceMinusElementUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_minuselement.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceMinusElement",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 3, 2]
                [1, 2, 3, 2]
                []
                """
                + "\n"
            )
        }
    }

    func testCodegenSequenceSumByUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_sumby.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceSumBy",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                14
                0
                """
                + "\n"
            )
        }
    }

    func testCodegenSequenceSumByDoubleUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_sumbydouble.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceSumByDouble",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                2.0
                0.0
                """
                + "\n"
            )
        }
    }

    func testSequenceRunningReduceIndexedAccumulatesWithIndex() throws {
        let source = """
        fun main() {
            val reduced = sequenceOf(1, 2, 3, 4)
                .runningReduceIndexed { index, acc, value -> acc + index * value }
            val empty = emptySequence<Int>()
                .runningReduceIndexed { index, acc, value -> acc + index * value }

            println(reduced)
            println(empty)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceRunningReduceIndexed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 3, 9, 21]\n[]\n")
        }
    }

    func testCodegenSequenceShuffledUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_shuffled.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceShuffled",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                4
                [1, 2, 3, 4]
                4
                [1, 2, 3, 4]
                []
                [42]
                """
                    + "\n"
            )
        }
    }

    func testSequenceToCollectionAppendsIntoDestination() throws {
        let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 2, 3)

            val listDest = mutableListOf(0)
            val listResult = seq.toCollection(listDest)
            listResult.add(4)
            println(listDest)

            val setDest = mutableSetOf(10, 2)
            val setResult = sequenceOf(1, 2, 2, 3).toCollection(setDest)
            setResult.add(4)
            println(setDest)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceToCollectionEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [0, 1, 2, 2, 3, 4]
                [10, 2, 1, 3, 4]
                """
                + "\n"
            )
        }
    }

    func testSequenceFlatMapIndexedSupportsIterableAndSequenceTransforms() throws {
        let source = """
        fun main() {
            val iterableResult = sequenceOf("a", "bc")
                .flatMapIndexed { index, value -> listOf(index.toString() + ":" + value, value + value) }
                .toList()

            val sequenceResult = sequenceOf("x", "yz")
                .flatMapIndexed { index, value -> sequenceOf(index.toString(), value) }
                .toList()

            println(iterableResult)
            println(sequenceResult)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFlatMapIndexedEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [0:a, aa, 1:bc, bcbc]
                [0, x, 1, yz]
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesSequenceWindowedTransformOverload() throws {
        let source = """
        fun main() {
            val sums = sequenceOf(1, 2, 3, 4, 5).windowed(3, 2, true) { window ->
                window[0] + window.size
            }
            println(sums.toList())

            val labels = sequenceOf("ab", "cd", "ef", "gh").windowed(2, 3, true) { window ->
                window.joinToString("|")
            }
            println(labels.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceWindowedTransformEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [4, 6, 6]
                [ab|cd, gh]
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesSequenceChunked() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 2, 3, 4, 5).chunked(2).toList())
            println(emptySequence<Int>().chunked(3).toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceChunkedEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [[1, 2], [3, 4], [5]]
                []
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesSequenceChunkedTransformOverload() throws {
        let source = """
        fun main() {
            val sums = sequenceOf(1, 2, 3, 4, 5).chunked(2) { chunk ->
                chunk[0] + chunk.size
            }
            println(sums.toList())

            val labels = sequenceOf("ab", "cd", "ef").chunked(2) { chunk ->
                chunk.joinToString("|")
            }
            println(labels.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceChunkedTransformEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [3, 5, 6]
                [ab|cd, ef]
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesSequenceOrEmpty() throws {
        let source = """
        fun main() {
            val missing: Sequence<Int>? = null
            val present: Sequence<Int>? = sequenceOf(1, 2, 3)

            println(missing.orEmpty().toList())
            println(present.orEmpty().toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceOrEmptyEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                []
                [1, 2, 3]
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesSequenceShuffledOverloads() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            println(sequenceOf(3, 1, 2).shuffled().toList().sorted())
            println(sequenceOf(6, 4, 5).shuffled(Random(42)).toList().sorted())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceShuffledEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 2, 3]
                [4, 5, 6]
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesSequenceRequireNoNulls() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, 2, 3)
                .requireNoNulls()
                .toList()

            println(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceRequireNoNullsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3]\n")
        }
    }

    func testCodegenCompilesSequenceFirstNotNullOfOrNull() throws {
        let source = """
        fun main() {
            val result: String? = sequenceOf(1, 2, 3)
                .firstNotNullOfOrNull { if (it > 1) "hit" else null }
            println(result)

            val missing: String? = sequenceOf(1, 3, 5)
                .firstNotNullOfOrNull { if (it % 2 == 0) "even" else null }
            println(missing)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFirstNotNullOfOrNullEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                hit
                null
                """
                + "\n"
            )
        }
    }

    func testSequenceFirstNotNullOfReturnsFirstValueOrThrows() throws {
        let source = """
        fun main() {
            val result: String = sequenceOf(1, 2, 3)
                .firstNotNullOf { if (it > 1) "hit" else null }
            println(result)

            try {
                sequenceOf(1, 3, 5)
                    .firstNotNullOf { if (it % 2 == 0) "even" else null }
                println("unexpected")
            } catch (e: NoSuchElementException) {
                println("missing")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFirstNotNullOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hit\nmissing\n")
        }
    }

    func testSequenceRandomOrNullReturnsOnlyElementOrNullOnEmpty() throws {
        let source = """
        fun main() {
            println(sequenceOf(42).randomOrNull())
            println(emptySequence<Int>().randomOrNull() == null)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceRandomOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "42\ntrue\n")
        }
    }

    func testSequenceZipWithNextTransformReturnsAdjacentResults() throws {
        let source = """
        fun main() {
            val transformed = sequenceOf(1, 2, 4, 8)
                .zipWithNext { left, right -> right - left }
            val empty = emptySequence<Int>()
                .zipWithNext { left, right -> right - left }
            val single = sequenceOf(42)
                .zipWithNext { left, right -> right - left }

            println(transformed)
            println(empty)
            println(single)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceZipWithNextTransform",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 4]\n[]\n[]\n")
        }
    }

    func testSequenceOnEachIndexedPreservesElementsAndLaziness() throws {
        let source = """
        fun main() {
            var trace = ""
            val result = sequenceOf(10, 20, 30)
                .onEachIndexed { index, value -> trace += "$index:$value;" }
                .take(2)
                .toList()

            println(result)
            println(trace)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceOnEachIndexed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [10, 20]
                0:10;1:20;
                """
                + "\n"
            )
        }
    }

    func testSequenceOnEachPreservesElementsAndLaziness() throws {
        let source = """
        fun main() {
            var trace = ""
            val result = sequenceOf(10, 20, 30)
                .onEach { value -> trace += "$value;" }
                .take(2)
                .toList()

            println(result)
            println(trace)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceOnEach",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [10, 20]
                10;20;
                """
                + "\n"
            )
        }
    }

    func testCodegenSequenceRequireNoNullsUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_require_no_nulls.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceRequireNoNulls",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 2, 3]
                [1]
                caught
                """
                    + "\n"
            )
        }
    }

    func testSequencePlusOperatorAndPlusElementAppendElements() throws {
        let source = """
        fun main() {
            val withPlus = sequenceOf(1, 2) + 3
            val result = withPlus
                .plusElement(4)
                .toList()

            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequencePlusElement",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3, 4]\n")
        }
    }
}
