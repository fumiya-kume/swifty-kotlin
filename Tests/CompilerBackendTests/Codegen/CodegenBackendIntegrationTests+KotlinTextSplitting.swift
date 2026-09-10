#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendKotlinTextSplittingEdgeCasesTests {

    @Test func testKotlinTextSplitEdgeCases() throws {
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

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSplitEdgeCases",
            expected:
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

    @Test func testKotlinTextSplitWithLimitEdgeCases() throws {
        let source = """
        fun main() {
            println("a,b,c,d".split(",", limit = 2))
            println("a,b,c".split(",", limit = 0))
            println("a,b,c".split(",", limit = -1))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSplitWithLimitEdgeCases",
            expected:
                """
                [a, b,c,d]
                [a, b, c]
                [a, b, c]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextSplitToSequenceEdgeCases() throws {
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

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSplitToSeqEdgeCases",
            expected:
                """
                []
                [hello]
                [a, b, c]
                [abc]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextChunkedEdgeCases() throws {
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

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkedEdgeCases",
            expected:
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

    @Test func testKotlinTextChunkedSequenceTransformEdgeCases() throws {
        let source = """
        fun main() {
            val lengths: kotlin.sequences.Sequence<Int> =
                "abcdef".chunkedSequence(2) { _: CharSequence -> 2 }
            println(lengths.toList())

            val text: CharSequence = "abcde"
            println(text.chunkedSequence(2) { _: CharSequence -> "chunk" }.toList())

            println("".chunkedSequence(3) { _: CharSequence -> 1 }.toList())
            println("abc".chunkedSequence(10) { _: CharSequence -> "single" }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkedSequenceTransformEdgeCases",
            expected:
                """
                [2, 2, 2]
                [chunk, chunk, chunk]
                []
                [single]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextChunkedSequenceEdgeCases() throws {
        let source = """
        fun render(value: CharSequence, size: Int): List<String> {
            return value.chunkedSequence(size).toList()
        }

        fun renderTransform(value: CharSequence, size: Int): List<String> {
            return value.chunkedSequence(size) { chunk -> "" + chunk + "!" }.toList()
        }

        fun main() {
            println("abcdef".chunkedSequence(2).toList())

            val text: CharSequence = "abcde"
            val chunks: kotlin.sequences.Sequence<String> = text.chunkedSequence(2)
            println(chunks.toList())

            println("".chunkedSequence(3).toList())
            println("abc".chunkedSequence(10).toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkedSequenceEdgeCases",
            expected:
                """
                [ab, cd, ef]
                [ab, cd, e]
                []
                [abc]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextWindowedSequenceEdgeCases() throws {
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

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextWindowedSequenceEdgeCases",
            expected:
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

    @Test func testKotlinTextWindowedSequenceTransformEdgeCases() throws {
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

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextWindowedSequenceTransformEdgeCases",
            expected:
                """
                [3, 3, 2]
                [2, 1]
                [he!, el!, ll!, lo!]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextChunkWindowZipAcrossCharSequences() throws {
        let source = """
        fun main() {
            val string = "abcde"
            val chars: CharSequence = StringBuilder("abcde")

            println(string.chunked(2))
            println(chars.chunked(2))
            println(string.chunked(2) { it.toString().uppercase() })
            println(chars.chunked(2) { it.toString().uppercase() })

            println(string.windowed(3, 2, true))
            println(chars.windowed(3, 2, true))
            println(string.windowed(3, 2, true) { it.length })
            println(chars.windowed(3, 2, true) { it.length })

            println(string.chunkedSequence(2).toList())
            println(chars.chunkedSequence(2).toList())
            println(string.chunkedSequence(2) { it.toString().uppercase() }.toList())
            println(chars.chunkedSequence(2) { it.toString().uppercase() }.toList())
            println(string.windowedSequence(3, 2, false).toList())
            println(chars.windowedSequence(3, 2, false).toList())
            println(string.windowedSequence(3, 2, true) { it.length }.toList())
            println(chars.windowedSequence(3, 2, true) { it.length }.toList())

            println(string.zip("XYZ"))
            println(chars.zip("XYZ"))
            println(string.zip("XYZ") { left, right -> "$left$right" })
            println(chars.zip("XYZ") { left, right -> "$left$right" })
            println(string.zipWithNext())
            println(chars.zipWithNext())
            println(string.zipWithNext { left, right -> "$left$right" })
            println(chars.zipWithNext { left, right -> "$left$right" })

            var transformCalls = 0
            val lazy: Sequence<String> = chars.windowedSequence(2) { window: CharSequence ->
                transformCalls++
                window.toString()
            }
            println(transformCalls)
            println(lazy.iterator().next())
            println(transformCalls)

            try {
                chars.chunked(0)
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
            try {
                chars.windowed(2, 0)
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
            try {
                chars.windowedSequence(0).toList()
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
            try {
                chars.windowedSequence(2, 0).toList()
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkWindowZipAcrossCharSequences",
            expected:
                """
                [ab, cd, e]
                [ab, cd, e]
                [AB, CD, E]
                [AB, CD, E]
                [abc, cde, e]
                [abc, cde, e]
                [3, 3, 1]
                [3, 3, 1]
                [ab, cd, e]
                [ab, cd, e]
                [AB, CD, E]
                [AB, CD, E]
                [abc, cde]
                [abc, cde]
                [3, 3, 1]
                [3, 3, 1]
                [(a, X), (b, Y), (c, Z)]
                [(a, X), (b, Y), (c, Z)]
                [aX, bY, cZ]
                [aX, bY, cZ]
                [(a, b), (b, c), (c, d), (d, e)]
                [(a, b), (b, c), (c, d), (d, e)]
                [ab, bc, cd, de]
                [ab, bc, cd, de]
                0
                ab
                1
                size must be positive, but was 0
                step must be positive, but was 0
                size must be positive, but was 0
                step must be positive, but was 0
                """
                + "\n"
        )
    }

    @Test func testKotlinTextWindowedTransformDefaultArgsAndInvalidSize() throws {
        let source = """
        fun main() {
            println("hello".windowed(2) { it.length })
            println("hello".windowed(3, 2) { it.length })
            println("hello".windowed(3, 2, true) { it.length })

            val chars: CharSequence = "hello"
            println(chars.windowed(2) { it.length })
            println(chars.windowed(3, 2) { it.length })
            println("hello".windowedSequence(2) { it.length }.toList())
            println("hello".windowedSequence(3, 2) { it.length }.toList())

            try {
                "abc".chunked(0) { it.length }
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
            try {
                "abc".windowed(0) { it.length }
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
            try {
                "abc".windowed(2, 0) { it.length }
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
            try {
                chars.windowed(0, 1, false) { it.length }
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextWindowedTransformDefaultArgsAndInvalidSize",
            expected:
                """
                [2, 2, 2, 2]
                [3, 3]
                [3, 3, 1]
                [2, 2, 2, 2]
                [3, 3]
                [2, 2, 2, 2]
                [3, 3]
                size 0 must be greater than zero.
                size must be positive, but was 0
                step must be positive, but was 0
                size must be positive, but was 0
                """
                + "\n"
        )
    }

    @Test func testSourceIteratorCapturingStringPreservesIntElements() throws {
        let source = """
        class StringBackedIntSequence(private val source: String) : Sequence<Int> {
            override fun iterator(): Iterator<Int> {
                val capturedSource = source
                return object : Iterator<Int> {
                    private var index = 0

                    override fun hasNext(): Boolean = index < capturedSource.length

                    override fun next(): Int {
                        val value = index + 1
                        index++
                        return value
                    }
                }
            }
        }

        fun main() {
            println(StringBackedIntSequence("abc").toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBackedIntSequence",
            expected: "[1, 2, 3]\n"
        )
    }

    @Test func testKotlinTextLinesEdgeCases() throws {
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

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextLinesEdgeCases",
            expected:
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
#endif
