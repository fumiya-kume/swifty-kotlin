fun main() {
    // No-arg toByteArray (UTF-8 default)
    val utf8Bytes = "abc".toByteArray()
    println(utf8Bytes.size)

    // Explicit Charsets.UTF_8
    val utf8Explicit = "hello".toByteArray(Charsets.UTF_8)
    println(utf8Explicit.size)

    // ISO-8859-1 (Latin-1) — ASCII range is same size
    val latin1Bytes = "hello".toByteArray(Charsets.ISO_8859_1)
    println(latin1Bytes.size)

    // US-ASCII
    val asciiBytes = "hello".toByteArray(Charsets.US_ASCII)
    println(asciiBytes.size)

    // UTF-16BE — 2 bytes per BMP char, no BOM
    val utf16beBytes = "ab".toByteArray(Charsets.UTF_16BE)
    println(utf16beBytes.size)

    // UTF-16LE — 2 bytes per BMP char, no BOM
    val utf16leBytes = "ab".toByteArray(Charsets.UTF_16LE)
    println(utf16leBytes.size)

    // encodeToByteArray (always UTF-8)
    val encoded = "hello".encodeToByteArray()
    println(encoded.size)
}
