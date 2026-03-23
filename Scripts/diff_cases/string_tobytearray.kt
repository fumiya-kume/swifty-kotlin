fun main() {
    // Basic encodeToByteArray
    val abc = "abc".encodeToByteArray()
    println(abc.size)
    println(abc[0])
    println(abc[1])
    println(abc[2])

    // Empty string
    val empty = "".encodeToByteArray()
    println(empty.size)

    // ASCII printable characters
    val hello = "hello".encodeToByteArray()
    println(hello.size)
    println(hello.joinToString(","))

    // Digits
    val digits = "0123456789".encodeToByteArray()
    println(digits.size)
    println(digits[0])
    println(digits[9])

    // Special ASCII characters
    val special = "!@#".encodeToByteArray()
    println(special.size)
    println(special[0])
    println(special[1])
    println(special[2])

    // Newline and tab
    val whitespace = "\n\t\r".encodeToByteArray()
    println(whitespace.size)
    println(whitespace[0])
    println(whitespace[1])
    println(whitespace[2])

    // Multi-byte UTF-8 (2-byte: e.g. ñ = C3 B1)
    val twoByte = "\u00F1".encodeToByteArray()
    println(twoByte.size)
    println(twoByte[0])
    println(twoByte[1])

    // Multi-byte UTF-8 (3-byte: e.g. あ = E3 81 82)
    val threeByte = "あ".encodeToByteArray()
    println(threeByte.size)
    println(threeByte[0])
    println(threeByte[1])
    println(threeByte[2])

    // Multi-byte UTF-8 (4-byte: e.g. 𝄞 U+1D11E)
    val fourByte = "\uD834\uDD1E".encodeToByteArray()
    println(fourByte.size)
    println(fourByte[0])
    println(fourByte[1])
    println(fourByte[2])
    println(fourByte[3])

    // Mixed ASCII and multi-byte
    val mixed = "aあb".encodeToByteArray()
    println(mixed.size)

    // encodeToByteArray with startIndex and endIndex
    val partial = "Hello, World!".encodeToByteArray(0, 5)
    println(partial.size)
    println(partial.joinToString(","))

    // encodeToByteArray partial from middle
    val mid = "Hello, World!".encodeToByteArray(7, 12)
    println(mid.size)
    println(mid.joinToString(","))

    // encodeToByteArray with same start and end (empty result)
    val emptySlice = "Hello".encodeToByteArray(2, 2)
    println(emptySlice.size)

    // encodeToByteArray full range
    val full = "Hi".encodeToByteArray(0, 2)
    println(full.size)
    println(full.joinToString(","))

    // toByteArray alias
    val tba = "abc".toByteArray()
    println(tba.size)
    println(tba[0])

    // Verify encodeToByteArray and toByteArray produce same result
    val s = "test"
    val a = s.encodeToByteArray()
    val b = s.toByteArray()
    println(a.size == b.size)
    println(a.contentEquals(b))

    // String with null byte
    val withNull = "a\u0000b".encodeToByteArray()
    println(withNull.size)
    println(withNull[0])
    println(withNull[1])
    println(withNull[2])

    // Longer string
    val long = "The quick brown fox jumps over the lazy dog".encodeToByteArray()
    println(long.size)
}
