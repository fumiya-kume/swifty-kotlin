fun main() {
    // === String.chunked(size) ===
    // Basic chunked
    println("abcdef".chunked(2))
    println("abcdefg".chunked(3))
    println("abcde".chunked(1))
    println("abcde".chunked(5))
    println("abcde".chunked(10))

    // Empty string
    println("".chunked(3))

    // Single character chunks
    println("abc".chunked(1))

    // Chunk size equals string length
    println("hello".chunked(5))

    // Chunk size greater than string length
    println("hi".chunked(100))

    // Various sizes
    println("abcdefghij".chunked(3))
    println("abcdefghij".chunked(4))

    // Verify list type behavior
    val chunks = "abcdef".chunked(2)
    println(chunks.size)
    println(chunks[0])
    println(chunks[1])
    println(chunks[2])

    // Partial last chunk
    val partial = "abcde".chunked(2)
    println(partial)
    println(partial.size)
    println(partial.last())

    // CharSequence.chunkedSequence(size)
    val chars: CharSequence = "abcdef"
    println(chars.chunkedSequence(2).toList())
    println(chars.chunkedSequence(4).toList())
    println("".chunkedSequence(3).toList())
    println(chars.chunkedSequence(2) { "" + it + "!" }.toList())
    println("abcdef".chunkedSequence(3) { "" + it }.toList())

    // Large chunk size
    println("x".chunked(1))
    println("xy".chunked(5))

    // chunked with transform
    println("abcdef".chunked(2) { it.uppercase() })
    println("abcdefg".chunked(3) { it.length })

    // === windowed: basic ===
    println("abcde".windowed(3, 1))
    println("abcde".windowed(3, 2))
    println("abcde".windowed(2, 1))
    println("abcde".windowed(5, 1))

    // windowed: step larger than size
    println("abcdef".windowed(2, 3))

    // windowed: partialWindows = false (default)
    println("abcde".windowed(3, 2, false))

    // windowed: partialWindows = true
    println("abcde".windowed(3, 2, true))
    println("abcdef".windowed(4, 3, true))
    println("abcdefg".windowed(3, 2, true))

    // windowed: size equals string length
    println("abc".windowed(3, 1))
    println("abc".windowed(3, 1, true))

    // windowed: size > string length, partialWindows false
    println("ab".windowed(5, 1))

    // windowed: size > string length, partialWindows true
    println("ab".windowed(5, 1, true))

    // windowed: step = 1 (sliding window)
    println("hello".windowed(2))
    println("hello".windowed(3))

    // windowed with transform
    println("abcde".windowed(3, 1) { it.uppercase() })
    println("12345".windowed(2, 1) { it.toInt() })
    println("abcde".windowed(3, 2, true) { it.length })

    // windowed: empty string
    println("".windowed(3, 1))
    println("".windowed(3, 1, true))

    // windowed: single char
    println("x".windowed(1, 1))
    println("x".windowed(1, 1, true))

    // windowed: large step
    println("abcdefghij".windowed(2, 5))
    println("abcdefghij".windowed(2, 5, true))

    // windowed: step equals size (non-overlapping)
    println("abcdef".windowed(2, 2))
    println("abcdefg".windowed(2, 2))
    println("abcdefg".windowed(2, 2, true))
}
