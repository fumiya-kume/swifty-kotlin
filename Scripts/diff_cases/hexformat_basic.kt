@OptIn(ExperimentalStdlibApi::class)
fun main() {
    // Int.toHexString with default format
    val hex1 = 255.toHexString()
    println(hex1)  // ff

    val hex2 = 4096.toHexString()
    println(hex2)  // 1000

    // Negative Int produces two's complement
    val hex3 = (-1).toHexString()
    println(hex3)  // ffffffff

    // String.hexToInt
    val num1 = "ff".hexToInt()
    println(num1)  // 255

    val num2 = "1000".hexToInt()
    println(num2)  // 4096

    // HexFormat.Default
    val defaultFmt = HexFormat.Default
    val hex4 = 42.toHexString(defaultFmt)
    println(hex4)  // 2a

    // Round-trip
    val original = 12345
    val hexStr = original.toHexString()
    val back = hexStr.hexToInt()
    println(back == original)  // true
}
