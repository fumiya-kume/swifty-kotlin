// SKIP-DIFF: advanced coroutine APIs (CoroutineScope, ReceiveChannel, produce) not yet implemented
private fun hex(bytes: ByteArray): String {
    val sb = StringBuilder()
    for (i in 0..bytes.size - 1) {
        val b = bytes[i]
        val v = ((b.toInt()) + 256) % 256
        val s = v.toString(16).padStart(2, '0')
        sb.append(s)
    }
    return sb.toString()
}

fun main() {
    // Known MD5("abc") bytes (big-endian)
    val md5Abc = byteArrayOf(
        -112, 1, 80, -104, 60, -46, 79, -80,
        -42, -106, 63, 125, 40, -31, 127, 114
    )
    println(hex(md5Abc))

    // Known SHA-1("abc") bytes
    val sha1Abc = byteArrayOf(
        -87, -103, 62, 54, 71, 6, -127, 106,
        -70, 62, 37, 113, 120, 80, -62, 108,
        -100, -48, -40, -99
    )
    println(hex(sha1Abc))

    // Known SHA-256("abc") bytes
    val sha256Abc = byteArrayOf(
        -70, 120, 22, -65, 97, 43, -41, 93,
        -14, 81, 107, -18, 7, -50, -114, -88,
        -82, -76, 91, -27, 119, -60, -41, -31,
        90, -106, -54, 88, 25, -22, 79, 44
    )
    println(hex(sha256Abc))
}
