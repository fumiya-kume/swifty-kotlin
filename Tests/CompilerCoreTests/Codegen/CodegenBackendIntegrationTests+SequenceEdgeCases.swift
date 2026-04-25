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
