fun main() {
    // Default (UTF-8) decoding
    val utf8Bytes = byteArrayOf(72, 101, 108, 108, 111)
    println(utf8Bytes.decodeToString()) // Hello

    // Explicit UTF-8 charset
    println(utf8Bytes.decodeToString(Charsets.UTF_8)) // Hello

    // ISO-8859-1 (Latin-1) decoding: byte 0xE9 = U+00E9 (e-acute)
    val latin1Bytes = byteArrayOf(0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xE9.toByte())
    println(latin1Bytes.decodeToString(Charsets.ISO_8859_1)) // Hello followed by e-acute

    // US-ASCII decoding
    val asciiBytes = byteArrayOf(65, 66, 67)
    println(asciiBytes.decodeToString(Charsets.US_ASCII)) // ABC

    // Empty array
    val empty = byteArrayOf()
    println(empty.decodeToString(Charsets.UTF_8)) // (empty)

    // Round-trip with UTF-8
    val original = "Hello, World!"
    val encoded = original.encodeToByteArray()
    println(encoded.decodeToString(Charsets.UTF_8)) // Hello, World!
}
