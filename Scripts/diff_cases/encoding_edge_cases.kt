@OptIn(ExperimentalStdlibApi::class)
fun main() {
    val original = "こんにちは"
    val encoded = original.encodeToByteArray()
    println(encoded.decodeToString())

    val ascii = "ABC".encodeToByteArray()
    println(String(ascii, Charsets.US_ASCII))

    val hex = 255.toHexString()
    println(hex)
    println(hex.hexToInt())
    println("gg".hexToInt())
}
