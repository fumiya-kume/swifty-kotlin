fun main() {
    // toByteArray() default (UTF-8)
    val defaultBytes = "hello".toByteArray()
    println(defaultBytes.size)

    // toByteArray(Charsets.UTF_8)
    val utf8Bytes = "hello".toByteArray(Charsets.UTF_8)
    println(utf8Bytes.size)

    // toByteArray(Charsets.ISO_8859_1)
    val isoBytes = "hello".toByteArray(Charsets.ISO_8859_1)
    println(isoBytes.size)

    // toByteArray(Charsets.UTF_16) — includes BOM (2 bytes) + 2 bytes per char = 12 bytes for "hello"
    val utf16Bytes = "hello".toByteArray(Charsets.UTF_16)
    println(utf16Bytes.size)

    // Round-trip: String(ByteArray, Charset) decodes bytes back to string
    val bytes = "hello".toByteArray(Charsets.UTF_8)
    val decoded = String(bytes, Charsets.UTF_8)
    println(decoded)

    // Round-trip equality
    println("hello" == decoded)

    // toByteArray().size for ASCII
    val sizeCheck = "hello".toByteArray().size
    println(sizeCheck)

    // Verify byte values of ASCII "A" in UTF-8
    val aBytes = "A".toByteArray(Charsets.UTF_8)
    println(aBytes[0])

    // ISO-8859-1 byte values are same as UTF-8 for ASCII
    val isoA = "A".toByteArray(Charsets.ISO_8859_1)
    println(isoA[0])
}
