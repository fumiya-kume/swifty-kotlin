fun main() {
    // encodeToByteArray() — always UTF-8
    val utf8 = "Hello".encodeToByteArray()
    println(utf8.size)

    // toByteArray with Charsets
    val utf8Explicit = "Hello".toByteArray(Charsets.UTF_8)
    println(utf8Explicit.size)

    val ascii = "Hello".toByteArray(Charsets.US_ASCII)
    println(ascii.size)

    val iso = "Hello".toByteArray(Charsets.ISO_8859_1)
    println(iso.size)

    val utf16 = "Hello".toByteArray(Charsets.UTF_16)
    println(utf16.size)

    val utf16be = "Hello".toByteArray(Charsets.UTF_16BE)
    println(utf16be.size)

    val utf16le = "Hello".toByteArray(Charsets.UTF_16LE)
    println(utf16le.size)

    // Verify content: ASCII "A" in UTF-8 is [65]
    val a = "A".toByteArray(Charsets.UTF_8)
    println(a[0])
}
