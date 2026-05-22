@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-020: Sequence lazy evaluation order and sequence builder semantics.
extension CodegenBackendIntegrationTests {

    // MARK: - Lazy counter: map + take touches exactly N elements

    func testSequenceMapTakeEvaluatesOnlyNeededElements() throws {
        let source = """
        var counter = 0

        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5)
                .map { counter++; it * 2 }
                .take(3)
                .toList()
            println(result)
            println(counter)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceMapTakeLazy",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            // Only 3 elements should be evaluated by map (lazy)
            XCTAssertEqual(
                normalizedStdout,
                """
                [2, 4, 6]
                3
                """ + "\n"
            )
        }
    }

    // MARK: - Lazy counter: filter + take short-circuits

    func testSequenceFilterTakeEvaluatesOnlyNeededElements() throws {
        let source = """
        var counter = 0

        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5, 6)
                .filter { counter++; it % 2 == 0 }
                .take(2)
                .toList()
            println(result)
            // filter checks 1,2,3,4 to find two even numbers; counter must be <= 4
            println(counter <= 4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFilterTakeLazy",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [2, 4]
                true
                """ + "\n"
            )
        }
    }

    // MARK: - Infinite generateSequence + take terminates

    func testInfiniteGenerateSequenceWithTakeTerminates() throws {
        let source = """
        fun main() {
            val naturals = generateSequence(1) { it + 1 }
            val first5 = naturals.take(5).toList()
            println(first5)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "InfiniteGenerateSequenceTake",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3, 4, 5]\n")
        }
    }

    // MARK: - generateSequence terminates on null

    func testGenerateSequenceTerminatesOnNull() throws {
        let source = """
        fun main() {
            val counted = generateSequence(1) { current ->
                if (current >= 4) null else current + 1
            }
            println(counted.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GenerateSequenceNullTermination",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3, 4]\n")
        }
    }

    // MARK: - sequence builder: yield and yieldAll

    func testSequenceBuilderYieldAndYieldAll() throws {
        let source = """
        fun main() {
            val seq = sequence {
                yield(1)
                yieldAll(listOf(2, 3, 4))
                yield(5)
            }
            println(seq.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceBuilderYieldAll",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3, 4, 5]\n")
        }
    }

    // MARK: - sequence builder: yieldAll preserves lazy nested sequence

    func testSequenceBuilderYieldAllPreservesLazyNested() throws {
        let source = """
        var counter = 0

        fun main() {
            val inner = sequence { counter++; yield(10); counter++; yield(20); counter++; yield(30) }
            val outer = sequence { yieldAll(inner) }
            // consume only first element — inner should evaluate lazily
            val first = outer.take(1).toList()
            println(first)
            println(counter <= 1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceBuilderYieldAllLazy",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [10]
                true
                """ + "\n"
            )
        }
    }

    // MARK: - flatMap laziness

    func testSequenceFlatMapIsLazy() throws {
        let source = """
        var counter = 0

        fun main() {
            val result = sequenceOf(1, 2, 3)
                .flatMap { x -> counter++; sequenceOf(x, x * 10) }
                .take(2)
                .toList()
            println(result)
            // flatMap of first input (1) produces [1, 10]; take(2) gets them → counter == 1
            println(counter)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFlatMapLazy",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 10]
                1
                """ + "\n"
            )
        }
    }

    // MARK: - distinct preserves first occurrence

    func testSequenceDistinctPreservesOrder() throws {
        let source = """
        fun main() {
            val result = sequenceOf(3, 1, 2, 1, 3, 4).distinct().toList()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceDistinct",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[3, 1, 2, 4]\n")
        }
    }

    func testSequenceDistinctByPreservesFirstKeyOrder() throws {
        let source = """
        fun main() {
            val result = sequenceOf(3, 1, 2, 5, 4, 7).distinctBy { it % 2 }.toList()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceDistinctBy",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[3, 2]\n")
        }
    }

    // MARK: - zip stops at shorter sequence

    func testSequenceZipStopsAtShorterSequence() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 4)
                .zip(sequenceOf("a", "b"))
                .toList()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceZip",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[(1, a), (2, b)]\n")
        }
    }

    // MARK: - drop skips first N

    func testSequenceDropSkipsFirstN() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5).drop(2).toList()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceDrop",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[3, 4, 5]\n")
        }
    }

    // MARK: - filterIndexed keeps indexed matches

    func testSequenceFilterIndexedKeepsIndexedMatches() throws {
        let source = """
        fun main() {
            val result = sequenceOf(10, 20, 30, 40)
                .filterIndexed { index, value -> index % 2 == 0 || value > 30 }
                .toList()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFilterIndexed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[10, 30, 40]\n")
        }
    }

    func testSequenceElementAtOrNullReturnsValueOrNull() throws {
        let source = """
        fun main() {
            val values = sequenceOf(10, 20, 30)
            println(values.elementAtOrNull(1) ?: -1)
            println(values.elementAtOrNull(5) ?: -1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceElementAtOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "20\n-1\n")
        }
    }

    // MARK: - filterIsInstance keeps matching runtime types

    func testSequenceFilterIsInstanceKeepsMatchingTypes() throws {
        let source = """
        fun main() {
            val values: Sequence<Any> = sequenceOf(1, "two", 3)
            println(values.filterIsInstance<Int>().toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFilterIsInstance",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 3]\n")
        }
    }

    // MARK: - terminal ops: count, forEach, fold

    func testSequenceTerminalOps() throws {
        let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 3, 4, 5)

            println(seq.count())
            println(seq.indexOfLast { it % 2 == 0 })
            println(seq.indexOfLast { it > 10 })

            var sum = 0
            seq.forEach { sum += it }
            println(sum)

            val folded = seq.fold(0) { acc, x -> acc + x }
            println(folded)

            println(seq.intersect(listOf(2, 4, 6)))
            val foldedIndexed = seq.foldIndexed(0) { index, acc, x -> acc + index * x }
            println(foldedIndexed)
            val grouped = seq.groupBy { if (it % 2 == 0) "even" else "odd" }
            println(grouped["odd"])
            println(grouped["even"])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceTerminalOps",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                5
                3
                -1
                15
                15
                [2, 4]
                40
                [1, 3, 5]
                [2, 4]
                """ + "\n"
            )
        }
    }

    // MARK: - empty sequence terminals

    func testEmptySequenceTerminals() throws {
        let source = """
        fun main() {
            val empty = emptySequence<Int>()

            println(empty.count())
            println(empty.toList())
            println(empty.firstOrNull())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "EmptySequenceTerminals",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                0
                []
                null
                """ + "\n"
            )
        }
    }

    // MARK: - first() on empty throws NoSuchElementException

    func testSequenceFirstReturnsFirstValue() throws {
        let source = """
        fun main() {
            val result = sequenceOf(4, 5, 6).first()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFirstRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "4\n")
        }
    }

    func testSequenceFirstOnEmptyThrows() throws {
        let source = """
        fun main() {
            try {
                emptySequence<Int>().first()
                println("unexpected")
            } catch (e: NoSuchElementException) {
                println("no-element")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFirstOnEmpty",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "no-element\n")
        }
    }

    // MARK: - firstOrNull returns null on empty

    func testSequenceFirstOrNullOnEmpty() throws {
        let source = """
        fun main() {
            val result = emptySequence<Int>().firstOrNull()
            println(result)
            val result2 = sequenceOf(1, 2, 3).firstOrNull { it > 10 }
            println(result2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFirstOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                null
                null
                """ + "\n"
            )
        }
    }

    // MARK: - asSequence() from collection

    func testAsSequenceFromList() throws {
        let source = """
        fun main() {
            val list = listOf(10, 20, 30)
            val result = list.asSequence()
                .map { it + 1 }
                .toList()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "AsSequenceFromList",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[11, 21, 31]\n")
        }
    }
    // MARK: - asIterable() from sequence

    func testSequenceAsIterableToList() throws {
        let source = """
        fun main() {
            val iterable = sequenceOf(1, 2, 3).asIterable()
            println(iterable.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAsIterableToList",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2, 3]\n")
        }
    }

    // MARK: - asSequence() from sequence

    func testSequenceAsSequenceReturnsSameSequenceSurface() throws {
        let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 3).asSequence()
            println(seq.map { it + 1 }.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAsSequence",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[2, 3, 4]\n")
        }
    }

    // MARK: - constrainOnce throws on second iteration

    func testConstrainOnceThrowsOnSecondIteration() throws {
        let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 3).constrainOnce()
            println(seq.toList())
            try {
                seq.toList()
                println("unexpected")
            } catch (e: IllegalStateException) {
                println("constrain-once-error")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ConstrainOnce",
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
                constrain-once-error
                """ + "\n"
            )
        }
    }

    // MARK: - any/all short-circuit

    func testSequenceAnyShortCircuits() throws {
        let source = """
        var counter = 0

        fun main() {
            val found = sequenceOf(1, 2, 3, 4, 5).any { counter++; it == 2 }
            println(found)
            // any stops at element 2 → counter should be <= 2
            println(counter <= 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAnyShortCircuit",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                true
                true
                """ + "\n"
            )
        }
    }

    func testSequenceAllShortCircuits() throws {
        let source = """
        var counter = 0

        fun main() {
            val allPositive = sequenceOf(1, -2, 3, 4, 5).all { counter++; it > 0 }
            println(allPositive)
            // all stops at element -2 → counter should be <= 2
            println(counter <= 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAllShortCircuit",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                false
                true
                """ + "\n"
            )
        }
    }

    func testSequenceFindShortCircuits() throws {
        let source = """
        var counter = 0

        fun main() {
            val found = sequenceOf(1, 2, 3, 4, 5).find { counter++; it == 3 }
            println(found)
            // find stops at element 3 → counter should be <= 3
            println(counter <= 3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFindShortCircuit",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                3
                true
                """ + "\n"
            )
        }
    }

    func testSequenceFilterNotKeepsRejectedPredicateValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, 2, 3, 4, 5)
            println(values.filterNot { value -> value % 2 == 0 }.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFilterNotRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 3, 5]\n")
        }
    }

    func testSequenceFilterIsInstanceToAppendsMatchingTypes() throws {
        let source = """
        fun main() {
            val values: Sequence<Any> = sequenceOf(1, "two", 3)
            val destination = mutableListOf<Int>(0)
            val result = values.filterIsInstanceTo(destination)
            println(result)
            println(destination)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFilterIsInstanceToRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[0, 1, 3]\n[0, 1, 3]\n")
        }
    }

    func testSequenceFilterNotToAppendsNonMatchingValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, 2, 3, 4, 5)
            val destination = mutableListOf<Int>(99)
            val result = values.filterNotTo(destination) { value -> value % 2 == 0 }
            println(result)
            println(destination)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFilterNotToRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[99, 1, 3, 5]\n[99, 1, 3, 5]\n")
        }
    }
}
