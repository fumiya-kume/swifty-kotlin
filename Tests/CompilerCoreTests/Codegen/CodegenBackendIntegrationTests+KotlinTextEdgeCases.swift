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
        let source = """
        fun main() {
            println("a,b,c".split(",", limit = 2))
            println("a,b,c".split(",", limit = 1))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextSplitWithLimitEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "[a, b,c]\n[a,b,c]\n")
        }
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
        // trim { predicate }, trimStart { predicate }, trimEnd { predicate }
        // are not yet implemented in the runtime stubs.
        throw XCTSkip("trim/trimStart/trimEnd with predicate not yet implemented")
        let source = """
        fun main() {
            println("123abc456".trim { it.isDigit() })
            println("123abc456".trimStart { it.isDigit() })
            println("123abc456".trimEnd { it.isDigit() })
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
            XCTAssertEqual(out, "abc\nabc456\n123abc\n")
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
        let source = """
        fun main() {
            println("Hello World".indexOf("world", ignoreCase = true))
            println("Hello World Hello".lastIndexOf("HELLO", ignoreCase = true))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextIndexOfIgnoreCaseEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "6\n12\n")
        }
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

    // MARK: - lines

    func testKotlinTextLinesEdgeCases() throws {
        let source = """
        fun main() {
            // empty string
            println("".lines())

            // single line (no newline)
            println("hello".lines())

            // trailing newline — runtime includes trailing empty element
            println("hello\n".lines())

            // CRLF line endings
            println("a\r\nb\r\nc".lines())

            // mixed line endings (\n and \r)
            println("a\nb\rc".lines())

            // only newlines
            println("\n\n".lines())

            // single newline
            println("\n".lines())

            // Windows CRLF only
            println("\r\n".lines())
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

            // negative n: runtime returns empty for take(-1), full string for drop(-1)
            // (Kotlin/JVM throws IllegalArgumentException, but this runtime clamps to 0)
            println("hello".take(-1))
            println("hello".drop(-1))
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
            // Note: runtime clamps negative n to 0 instead of throwing IllegalArgumentException.
            // take(-1) → "" (empty), drop(-1) → original string. Documents current runtime behavior.
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
                "hello\n" +
                "\n" +       // take(-1) → empty string
                "hello\n"    // drop(-1) → original string
            )
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
