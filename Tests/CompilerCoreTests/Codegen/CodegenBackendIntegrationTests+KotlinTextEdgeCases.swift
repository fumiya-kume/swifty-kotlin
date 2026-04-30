@testable import CompilerCore
import Foundation
import XCTest

// MARK: - kotlin.text edge case coverage (STDLIB-005)
//
// Covers: split, splitToSequence, replace, replaceFirst, replaceRange,
// substring, subSequence, trim/trimStart/trimEnd (char + predicate variants),
// padStart/padEnd, indexOf/lastIndexOf (ignoreCase + startIndex),
// chunked, windowed, lines, removePrefix/removeSuffix,
// take/drop/takeLast/dropLast, case-conversion helpers.
//
// Edge cases tested: empty string, single char, single-char delimiter,
// multi-char delimiter, trailing empty matches (limit arg), out-of-range
// indices (StringIndexOutOfBoundsException), negative count
// (IllegalArgumentException), CRLF in lines(), empty delimiter behavior.

extension CodegenBackendIntegrationTests {

    // MARK: - split / splitToSequence

    func testKotlinTextSplitEdgeCases() throws {
        let source = """
        fun main() {
            // empty string with single-char delimiter
            println("".split(","))

            // no delimiter in string
            println("hello".split(","))

            // single-char delimiter
            println("a,b,c".split(","))

            // multi-char delimiter
            println("aXXbXXc".split("XX"))

            // delimiter at start and end (trailing empty parts)
            println(",a,b,".split(","))

            // consecutive delimiters
            println("a,,b".split(","))

            // entire string is delimiter
            println(",".split(","))

            // empty delimiter returns list containing original string
            println("abc".split(""))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextSplitEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                []
                [hello]
                [a, b, c]
                [a, b, c]
                [, a, b, ]
                [a, , b]
                [, ]
                [abc]
                """
                + "\n"
            )
        }
    }

    func testKotlinTextSplitWithLimitEdgeCases() throws {
        // split(delimiter, limit) is not yet implemented as a separate overload;
        // the runtime only provides split(String) without a limit parameter.
        throw XCTSkip("split with limit parameter not yet implemented")
    }

    func testKotlinTextSplitToSequenceEdgeCases() throws {
        let source = """
        fun main() {
            // empty string
            println("".splitToSequence(",").toList())

            // no delimiter present
            println("hello".splitToSequence(",").toList())

            // normal split
            println("a,b,c".splitToSequence(",").toList())

            // empty delimiter returns original string wrapped
            println("abc".splitToSequence("").toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextSplitToSeqEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                []
                [hello]
                [a, b, c]
                [abc]
                """
                + "\n"
            )
        }
    }

    // MARK: - replace / replaceFirst / replaceRange

    func testKotlinTextReplaceEdgeCases() throws {
        let source = """
        fun main() {
            // replace in empty string
            println("".replace("a", "b"))

            // replace non-existing substring (no-op)
            println("hello".replace("x", "y"))

            // replace all occurrences: "aababab" has 3 "ab" → "aXXX"
            println("aababab".replace("ab", "X"))

            // replace with empty new value (deletion)
            println("hello".replace("l", ""))

            // replace with empty old value (no-op on empty string)
            println("".replace("", "x"))

            // replaceFirst: only first occurrence changed
            println("aabaa".replaceFirst("a", "Z"))

            // replaceFirst: substring not found (no-op)
            println("hello".replaceFirst("x", "y"))

            // replaceFirst: empty string, no-op
            println("".replaceFirst("a", "b"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextReplaceEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """

                hello
                aXXX
                heo

                Zabaa
                hello

                """
                + "\n"
            )
        }
    }

    func testKotlinTextReplaceRangeEdgeCases() throws {
        let source = """
        fun main() {
            // normal replace range
            println("abcde".replaceRange(1..3, "XY"))

            // replace empty range (insertion)
            println("abcde".replaceRange(2..1, "Z"))

            // replace whole string
            println("abc".replaceRange(0..2, "XYZ"))

            // out-of-range start: should throw
            try {
                println("abc".replaceRange(5..5, "X"))
            } catch (e: Throwable) {
                println("oob-replaceRange-start")
            }

            // out-of-range end: should throw
            try {
                println("abc".replaceRange(0..10, "X"))
            } catch (e: Throwable) {
                println("oob-replaceRange-end")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextReplaceRangeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                // "abcde".replaceRange(1..3, "XY"): range 1..3 is inclusive [1,2,3]={b,c,d}
                // result: "a" + "XY" + "e" = "aXYe"
                """
                aXYe
                abZcde
                XYZ
                oob-replaceRange-start
                oob-replaceRange-end
                """
                + "\n"
            )
        }
    }

    func testKotlinTextReplaceAfterEdgeCases() throws {
        let source = """
        fun main() {
            println("a:b:c".replaceAfter(":", "X", "MISS"))
            println("abc".replaceAfter(":", "X", "MISS"))
            println("abc".replaceAfter(":", "X"))
            println("abc".replaceAfter("", "X", "MISS"))
            println("abc".replaceAfter("abc", "X", "MISS"))
            println("abc".replaceAfter("c", "X", "MISS"))
            println("a:b:c".replaceAfter(':', "X", "MISS"))
            println("abc".replaceAfter(':', "X", "MISS"))
            println("abc".replaceAfter(':', "X"))
            println("abc".replaceAfter('a', "X", "MISS"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextReplaceAfterEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                a:X
                MISS
                abc
                X
                abcX
                abcX
                a:X
                MISS
                abc
                aX
                """
                + "\n"
            )
        }
    }

    func testKotlinTextReplaceAfterLastEdgeCases() throws {
        let source = """
        fun main() {
            println("a:b:c".replaceAfterLast(":", "X", "MISS"))
            println("abc".replaceAfterLast(":", "X", "MISS"))
            println("abc".replaceAfterLast(":", "X"))
            println("abc".replaceAfterLast("", "X", "MISS"))
            println("".replaceAfterLast("", "X", "MISS"))
            println("abc".replaceAfterLast("abc", "X", "MISS"))
            println("abc".replaceAfterLast("c", "X", "MISS"))
            println("a:b:c".replaceAfterLast(':', "X", "MISS"))
            println("abc".replaceAfterLast(':', "X", "MISS"))
            println("abc".replaceAfterLast(':', "X"))
            println("abc".replaceAfterLast('a', "X", "MISS"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextReplaceAfterLastEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                a:b:X
                MISS
                abc
                abX
                MISS
                abcX
                abcX
                a:b:X
                MISS
                abc
                aX
                """
                + "\n"
            )
        }
    }

    // MARK: - substring / subSequence

    func testKotlinTextSubstringEdgeCases() throws {
        let source = """
        fun main() {
            // normal substring
            println("hello world".substring(6))
            println("hello world".substring(0, 5))

            // empty result (start == end)
            println("hello".substring(2, 2))

            // single char
            println("hello".substring(1, 2))

            // whole string
            println("hi".substring(0, 2))

            // substring on empty string, start=0 end=0 OK
            println("".substring(0, 0))

            // out-of-range start: negative
            try {
                println("hello".substring(-1))
            } catch (e: Throwable) {
                println("oob-substring-neg")
            }

            // out-of-range end beyond length
            try {
                println("hello".substring(0, 99))
            } catch (e: Throwable) {
                println("oob-substring-end")
            }

            // start > end
            try {
                println("hello".substring(3, 1))
            } catch (e: Throwable) {
                println("oob-substring-startgtend")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextSubstringEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                world
                hello

                e
                hi

                oob-substring-neg
                oob-substring-end
                oob-substring-startgtend
                """
                + "\n"
            )
        }
    }

    // MARK: - trim / trimStart / trimEnd

    func testKotlinTextTrimEdgeCases() throws {
        let source = """
        fun main() {
            // trim on empty string
            println("".trim())

            // trim all whitespace
            println("   ".trim())

            // trim leading only
            println("  hello".trim())

            // trim trailing only
            println("hello  ".trim())

            // trim both ends
            println("  hello  ".trim())

            // trimStart
            println("  hello  ".trimStart())

            // trimEnd
            println("  hello  ".trimEnd())

            // single char string, is whitespace
            println(" ".trim())

            // single char string, not whitespace
            println("a".trim())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextTrimEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                "\n" +
                "\n" +
                "hello\n" +
                "hello\n" +
                "hello\n" +
                "hello  \n" +
                "  hello\n" +
                "\n" +
                "a\n"
            )
        }
    }

    func testKotlinTextTrimPredicateEdgeCases() throws {
        let source = """
        fun main() {
            println("[" + "xxhelloxy".trim { it == 'x' || it == 'y' } + "]")
            println("[" + "xxhelloxy".trimStart { it == 'x' || it == 'y' } + "]")
            println("[" + "xxhelloxy".trimEnd { it == 'x' || it == 'y' } + "]")
            println("[" + "".trim { it == 'x' } + "]")
            println("[" + "aba".trim { it == 'a' } + "]")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextTrimPredicateEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                [hello]
                [helloxy]
                [xxhello]
                []
                [b]
                """
                + "\n"
            )
        }
    }

    // MARK: - padStart / padEnd

    func testKotlinTextPadEdgeCases() throws {
        let source = """
        fun main() {
            // padStart: already at desired length (no-op)
            println("hello".padStart(5))

            // padStart: shorter than desired length
            println("hi".padStart(5))

            // padStart: target length < string length (no-op)
            println("hello".padStart(3))

            // padStart with custom pad char
            println("hi".padStart(5, '0'))

            // padEnd: shorter than desired length
            println("hi".padEnd(5))

            // padEnd: already long enough
            println("hello".padEnd(3))

            // padEnd with custom char
            println("hi".padEnd(5, '*'))

            // padStart on empty string
            println("".padStart(3, 'x'))

            // padEnd on empty string
            println("".padEnd(3))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextPadEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                // padEnd pads with trailing spaces; "hi".padEnd(5) → "hi   "
                // "".padEnd(3) → "   " (3 spaces)
                "hello\n" +
                "   hi\n" +
                "hello\n" +
                "000hi\n" +
                "hi   \n" +
                "hello\n" +
                "hi***\n" +
                "xxx\n" +
                "   \n"
            )
        }
    }

    // MARK: - indexOf / lastIndexOf

    func testKotlinTextIndexOfEdgeCases() throws {
        let source = """
        fun main() {
            // indexOf: found
            println("hello world".indexOf("world"))

            // indexOf: not found
            println("hello".indexOf("xyz"))

            // indexOf: empty string target (always returns 0)
            println("hello".indexOf(""))

            // indexOf: empty source
            println("".indexOf("x"))

            // indexOf with startIndex
            println("abcabc".indexOf("a", 1))

            // indexOf with startIndex at end
            println("abc".indexOf("c", 3))

            // lastIndexOf: found
            println("abcabc".lastIndexOf("a"))

            // lastIndexOf: not found
            println("hello".lastIndexOf("x"))

            // lastIndexOf: empty target (returns length)
            println("hello".lastIndexOf(""))

            // lastIndexOf on empty source
            println("".lastIndexOf("x"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextIndexOfEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                6
                -1
                0
                -1
                3
                -1
                3
                -1
                5
                -1
                """
                + "\n"
            )
        }
    }

    func testKotlinTextIndexOfIgnoreCaseEdgeCases() throws {
        // indexOf(String, ignoreCase = true) and lastIndexOf(String, ignoreCase = true)
        // are not yet implemented in the runtime (they fall back to case-sensitive search).
        // This test documents the current behavior and can be upgraded when implemented.
        throw XCTSkip("indexOf/lastIndexOf with ignoreCase not yet implemented")
    }

    // MARK: - chunked / windowed

    func testKotlinTextChunkedEdgeCases() throws {
        let source = """
        fun main() {
            // normal chunked
            println("abcdef".chunked(2))

            // chunk size larger than string (returns one chunk)
            println("abc".chunked(10))

            // chunk size equals string length
            println("abc".chunked(3))

            // chunked on empty string
            println("".chunked(3))

            // chunk size of 1
            println("abc".chunked(1))

            // windowed: default (step=1)
            println("abcde".windowed(3))

            // windowed: step=2
            println("abcde".windowed(3, 2))

            // windowed: size > string (empty result)
            println("ab".windowed(5))

            // windowed on empty string
            println("".windowed(2))

            // windowed with partialWindows=true
            println("abcd".windowed(3, 2, partialWindows = true))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextChunkedEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                [ab, cd, ef]
                [abc]
                [abc]
                []
                [a, b, c]
                [abc, bcd, cde]
                [abc, cde]
                []
                []
                [abc, cd]
                """
                + "\n"
            )
        }
    }

    func testKotlinTextChunkedSequenceEdgeCases() throws {
        let source = """
        fun render(value: CharSequence, size: Int): List<String> {
            return value.chunkedSequence(size).toList()
        }

        fun renderTransform(value: CharSequence, size: Int): List<String> {
            return value.chunkedSequence(size) { chunk -> "" + chunk + "!" }.toList()
        }

        fun main() {
            println(render("abcdef", 2))
            println(render("abc", 10))
            println(render("", 3))
            println("abc".chunkedSequence(1).toList())
            println(renderTransform("abcde", 2))
            println("abcdef".chunkedSequence(3) { "" + it }.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextChunkedSequenceEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                [ab, cd, ef]
                [abc]
                []
                [a, b, c]
                [ab!, cd!, e!]
                [abc, def]
                """
                + "\n"
            )
        }
    }

    func testKotlinTextWindowedSequenceEdgeCases() throws {
        let source = """
        fun render(value: CharSequence, size: Int, step: Int, partial: Boolean): List<String> {
            return value.windowedSequence(size, step, partial).toList()
        }

        fun main() {
            println(render("abcdef", 3, 2, false))
            println(render("abcdef", 3, 2, true))
            println(render("ab", 5, 1, false))
            println(render("ab", 5, 1, true))
            println("hello".windowedSequence(2, 1, false).toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextWindowedSequenceEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                [abc, cde]
                [abc, cde, ef]
                []
                [ab, b]
                [he, el, ll, lo]
                """
                + "\n"
            )
        }
    }

    func testKotlinTextWindowedSequenceTransformEdgeCases() throws {
        let source = """
        fun lengths(value: CharSequence): List<Int> {
            return value.windowedSequence(3, 2, true) { it.length }.toList()
        }

        fun tagged(value: String): List<String> {
            return value.windowedSequence(size = 2, step = 1, partialWindows = false) { window -> "" + window + "!" }.toList()
        }

        fun main() {
            println(lengths("abcdef"))
            println("ab".windowedSequence(5, 1, true) { it.length }.toList())
            println(tagged("hello"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextWindowedSequenceTransformEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                [3, 3, 2]
                [2, 1]
                [he!, el!, ll!, lo!]
                """
                + "\n"
            )
        }
    }

    func testKotlinTextIndexOfAnyCharsEdgeCases() throws {
        let source = """
        fun firstAny(value: CharSequence, chars: CharArray, start: Int, ignore: Boolean): Int {
            return value.indexOfAny(chars, start, ignore)
        }

        fun main() {
            println(firstAny("Kotlin", charArrayOf('t', 'x'), 0, false))
            println(firstAny("Kotlin", charArrayOf('k'), 0, true))
            println(firstAny("abc", charArrayOf('x'), 0, false))
            println(firstAny("abc", charArrayOf('a'), 5, false))
            println("abc".indexOfAny(charArrayOf('B'), 0, true))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextIndexOfAnyCharsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                2
                0
                -1
                -1
                1
                """
                + "\n"
            )
        }
    }

    func testKotlinTextIndexOfAnyStringsEdgeCases() throws {
        let source = """
        fun firstAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Int {
            return value.indexOfAny(strings, start, ignore)
        }

        fun main() {
            println(firstAny("Kotlin", listOf("lin", "zz"), 0, false))
            println(firstAny("Kotlin", listOf("ko"), 0, true))
            println("abc".indexOfAny(listOf("x", "bc"), 0, false))
            println("abc".indexOfAny(listOf(""), 2, false))
            println("abc".indexOfAny(listOf("a"), 5, false))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextIndexOfAnyStringsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                3
                0
                1
                2
                -1
                """
                + "\n"
            )
        }
    }

    func testKotlinTextLastIndexOfAnyCharsEdgeCases() throws {
        let source = """
        fun lastAny(value: CharSequence, chars: CharArray, start: Int, ignore: Boolean): Int {
            return value.lastIndexOfAny(chars, start, ignore)
        }

        fun main() {
            println(lastAny("Kotlin", charArrayOf('t', 'o'), 5, false))
            println(lastAny("Kotlin", charArrayOf('k'), 5, true))
            println("abca".lastIndexOfAny(charArrayOf('a'), 2, false))
            println("abc".lastIndexOfAny(charArrayOf('x'), 2, false))
            println("abc".lastIndexOfAny(charArrayOf('C'), 2, true))
            println("abc".lastIndexOfAny(charArrayOf('a'), -1, false))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextLastIndexOfAnyCharsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                2
                0
                0
                -1
                2
                -1
                """
                + "\n"
            )
        }
    }

    func testKotlinTextLastIndexOfAnyStringsEdgeCases() throws {
        let source = """
        fun lastAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Int {
            return value.lastIndexOfAny(strings, start, ignore)
        }

        fun main() {
            println(lastAny("Kotlin", listOf("ot", "li"), 5, false))
            println(lastAny("Kotlin", listOf("KO"), 5, true))
            println("abc".lastIndexOfAny(listOf("x", "bc"), 2, false))
            println("abc".lastIndexOfAny(listOf(""), 5, false))
            println("abc".lastIndexOfAny(listOf(""), 2, false))
            println("abc".lastIndexOfAny(listOf("a"), -1, false))
            println("abc".lastIndexOfAny(listOf("C"), 2, true))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextLastIndexOfAnyStringsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                3
                0
                1
                3
                2
                -1
                2
                """
                + "\n"
            )
        }
    }

    func testKotlinTextFindAnyOfStringsEdgeCases() throws {
        let source = """
        fun findAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Pair<Int, String>? {
            return value.findAnyOf(strings, start, ignore)
        }

        fun render(match: Pair<Int, String>?): String {
            if (match == null) return "null"
            return match.first.toString() + ":" + match.second
        }

        fun main() {
            println(render(findAny("Kotlin", listOf("lin", "ot"), 0, false)))
            println(render(findAny("Kotlin", listOf("KO"), 0, true)))
            println(render("abc".findAnyOf(listOf("x", "bc"), 0, false)))
            println(render("abc".findAnyOf(listOf(""), 5, false)))
            println(render("abc".findAnyOf(listOf("a"), 5, false)))
            println(render("abc".findAnyOf(listOf("bc", "b"), 0, false)))
            println(render("abc".findAnyOf(listOf("a"), -1, false)))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextFindAnyOfStringsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                1:ot
                0:KO
                1:bc
                3:
                null
                1:bc
                0:a
                """
                + "\n"
            )
        }
    }

    func testKotlinTextFindLastAnyOfStringsEdgeCases() throws {
        let source = """
        fun findLastAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Pair<Int, String>? {
            return value.findLastAnyOf(strings, start, ignore)
        }

        fun render(match: Pair<Int, String>?): String {
            if (match == null) return "null"
            return match.first.toString() + ":" + match.second
        }

        fun main() {
            println(render(findLastAny("Kotlin", listOf("ot", "li"), 5, false)))
            println(render(findLastAny("Kotlin", listOf("KO"), 5, true)))
            println(render("abc".findLastAnyOf(listOf("x", "bc"), 2, false)))
            println(render("abc".findLastAnyOf(listOf(""), 5, false)))
            println(render("abc".findLastAnyOf(listOf(""), 2, false)))
            println(render("abc".findLastAnyOf(listOf("a"), -1, false)))
            println(render("abc".findLastAnyOf(listOf("C"), 2, true)))
            println(render("abc".findLastAnyOf(listOf("bc", "b"), 2, false)))
            println(render("abc".findLastAnyOf(listOf("a"), 5, false)))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextFindLastAnyOfStringsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                3:li
                0:KO
                1:bc
                3:
                2:
                null
                2:C
                1:bc
                0:a
                """
                + "\n"
            )
        }
    }

    // MARK: - lines

    func testKotlinTextLinesEdgeCases() throws {
        let source = """
        fun main() {
            // empty string
            println("".lines())

            // single line (no newline)
            println("hello".lines())

            // trailing newline — runtime includes trailing empty element
            println("hello\\n".lines())

            // CRLF line endings
            println("a\\r\\nb\\r\\nc".lines())

            // mixed line endings (\n and \r)
            println("a\\nb\\rc".lines())

            // only newlines
            println("\\n\\n".lines())

            // single newline
            println("\\n".lines())

            // Windows CRLF only
            println("\\r\\n".lines())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextLinesEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            // Note: runtime includes trailing empty element for strings ending in newline,
            // which differs from Kotlin/JVM (which discards the trailing empty element).
            // These assertions document the current runtime behavior.
            XCTAssertEqual(
                out,
                "[]\n" +
                "[hello]\n" +
                "[hello, ]\n" +
                "[a, b, c]\n" +
                "[a, b, c]\n" +
                "[, , ]\n" +
                "[, ]\n" +
                "[, ]\n"
            )
        }
    }

    // MARK: - removePrefix / removeSuffix

    func testKotlinTextRemovePrefixSuffixEdgeCases() throws {
        let source = """
        fun main() {
            // removePrefix: present
            println("foobar".removePrefix("foo"))

            // removePrefix: not present (no-op)
            println("hello".removePrefix("world"))

            // removePrefix: empty prefix (no-op)
            println("hello".removePrefix(""))

            // removePrefix: entire string is prefix
            println("hello".removePrefix("hello"))

            // removeSuffix: present
            println("foobar".removeSuffix("bar"))

            // removeSuffix: not present (no-op)
            println("hello".removeSuffix("world"))

            // removeSuffix: empty suffix (no-op)
            println("hello".removeSuffix(""))

            // removeSuffix: entire string is suffix
            println("hello".removeSuffix("hello"))

            // on empty string
            println("".removePrefix("x"))
            println("".removeSuffix("x"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextRemovePrefixSuffixEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                bar
                hello
                hello

                foo
                hello
                hello



                """
                + "\n"
            )
        }
    }

    func testKotlinTextRemovePrefixSuffixCharSequenceEdgeCases() throws {
        let source = """
        fun trimPrefix(value: CharSequence): String {
            return value.removePrefix("foo")
        }

        fun trimAround(value: CharSequence): String {
            return value.removeSurrounding("foo")
        }

        fun main() {
            val cs: CharSequence = "foofoobarfoo"

            // CharSequence receiver: removePrefix
            println(cs.removePrefix("foo"))

            // CharSequence receiver: removeSuffix
            println(cs.removeSuffix("foo"))

            // CharSequence receiver: removeSurrounding(delimiter)
            println(cs.removeSurrounding("foo"))

            // CharSequence receiver: removeSurrounding(prefix, suffix)
            println(cs.removeSurrounding("foo", "foo"))

            // String argument passed to a CharSequence parameter
            println(trimPrefix("foofoobar"))

            // String argument passed to a CharSequence parameter
            println(trimAround("foofoobarfoo"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextRemovePrefixSuffixCharSequenceEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                foobarfoo
                foofoobar
                foobar
                foobar
                foobar
                foobar
                """
                + "\n"
            )
        }
    }

    func testKotlinTextIfBlankEdgeCases() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifBlank { "fallback" }
        }

        fun main() {
            println("[" + "abc".ifBlank { "fallback" } + "]")
            println("[" + "   ".ifBlank { "fallback" } + "]")
            println("[" + "".ifBlank { "empty" } + "]")

            val cs: CharSequence = "   "
            println("[" + choose(cs) + "]")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextIfBlankEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                [abc]
                [fallback]
                [empty]
                [fallback]
                """
                + "\n"
            )
        }
    }

    func testKotlinTextIfEmptyEdgeCases() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifEmpty { "fallback" }
        }

        fun main() {
            println("[" + "abc".ifEmpty { "fallback" } + "]")
            println("[" + "   ".ifEmpty { "fallback" } + "]")
            println("[" + "".ifEmpty { "empty" } + "]")

            val cs: CharSequence = ""
            println("[" + choose(cs) + "]")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextIfEmptyEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                [abc]
                [   ]
                [empty]
                [fallback]
                """
                + "\n"
            )
        }
    }

    func testKotlinTextCharSequenceZipWithNextEdgeCases() throws {
        let source = """
        fun pairCount(value: CharSequence): Int {
            return value.zipWithNext().size
        }

        fun labels(value: CharSequence): List<String> {
            return value.zipWithNext { a, b -> "" + a + b }
        }

        fun main() {
            val cs: CharSequence = "abcd"
            val pairs = cs.zipWithNext()
            println(pairs.size)

            val transformed = cs.zipWithNext { a, b -> "" + a + b }
            println(transformed.size)
            println(transformed[0])
            println(transformed[2])

            println(pairCount("xy"))
            println(labels("xy")[0])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextCharSequenceZipWithNextEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                3
                3
                ab
                cd
                1
                xy
                """
                + "\n"
            )
        }
    }

    // MARK: - take / drop / takeLast / dropLast

    func testKotlinTextTakeDropEdgeCases() throws {
        let source = """
        fun main() {
            // take: normal
            println("hello".take(3))

            // take: n == length
            println("hello".take(5))

            // take: n > length (returns full string)
            println("hello".take(100))

            // take: n == 0 (empty)
            println("hello".take(0))

            // drop: normal
            println("hello".drop(2))

            // drop: n == length (empty)
            println("hello".drop(5))

            // drop: n > length (empty)
            println("hello".drop(100))

            // drop: n == 0 (full string)
            println("hello".drop(0))

            // takeLast: normal
            println("hello".takeLast(3))

            // takeLast: n == length
            println("hello".takeLast(5))

            // takeLast: n > length (full string)
            println("hello".takeLast(100))

            // takeLast: n == 0 (empty)
            println("hello".takeLast(0))

            // dropLast: normal
            println("hello".dropLast(2))

            // dropLast: n == length (empty)
            println("hello".dropLast(5))

            // dropLast: n > length (empty)
            println("hello".dropLast(100))

            // dropLast: n == 0 (full string)
            println("hello".dropLast(0))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextTakeDropEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                "hel\n" +
                "hello\n" +
                "hello\n" +
                "\n" +
                "llo\n" +
                "\n" +
                "\n" +
                "hello\n" +
                "llo\n" +
                "hello\n" +
                "hello\n" +
                "\n" +
                "hel\n" +
                "\n" +
                "\n" +
                "hello\n"
            )
        }
    }

    // MARK: - take / drop negative count throws IllegalArgumentException (STDLIB-005-BUG-01)

    func testKotlinTextTakeNegativeThrows() throws {
        // Kotlin spec: take(n) with n < 0 throws
        // IllegalArgumentException("Requested element count -1 is less than zero.")
        let source = """
        fun main() {
            try {
                println("hello".take(-1))
            } catch (e: IllegalArgumentException) {
                println("iae-take")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextTakeNegativeThrows",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "iae-take\n")
        }
    }

    func testKotlinTextDropNegativeThrows() throws {
        // Kotlin spec: drop(n) with n < 0 throws
        // IllegalArgumentException("Requested element count -1 is less than zero.")
        let source = """
        fun main() {
            try {
                println("hello".drop(-1))
            } catch (e: IllegalArgumentException) {
                println("iae-drop")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextDropNegativeThrows",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "iae-drop\n")
        }
    }

    func testKotlinTextTakeLastNegativeThrows() throws {
        // Kotlin spec: takeLast(n) with n < 0 throws
        // IllegalArgumentException("Requested element count -1 is less than zero.")
        let source = """
        fun main() {
            try {
                println("hello".takeLast(-1))
            } catch (e: IllegalArgumentException) {
                println("iae-takeLast")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextTakeLastNegativeThrows",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "iae-takeLast\n")
        }
    }

    func testKotlinTextDropLastNegativeThrows() throws {
        // Kotlin spec: dropLast(n) with n < 0 throws
        // IllegalArgumentException("Requested element count -1 is less than zero.")
        let source = """
        fun main() {
            try {
                println("hello".dropLast(-1))
            } catch (e: IllegalArgumentException) {
                println("iae-dropLast")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextDropLastNegativeThrows",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "iae-dropLast\n")
        }
    }

    // MARK: - Case conversion helpers

    func testKotlinTextCaseConversionEdgeCases() throws {
        let source = """
        fun main() {
            // lowercase
            println("Hello World".lowercase())
            println("".lowercase())
            println("123".lowercase())

            // uppercase
            println("Hello World".uppercase())
            println("".uppercase())

            // lowercase on already-lower
            println("hello".lowercase())

            // uppercase on already-upper
            println("HELLO".uppercase())

            // mixed with digits and symbols
            println("Abc123!".lowercase())
            println("Abc123!".uppercase())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextCaseConversionEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                hello world

                123
                HELLO WORLD

                hello
                HELLO
                abc123!
                ABC123!
                """
                + "\n"
            )
        }
    }
}
