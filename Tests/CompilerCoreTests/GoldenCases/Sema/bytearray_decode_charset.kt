fun main() {
    val bytes = byteArrayOf(72, 101, 108, 108, 111)
    val s1 = bytes.decodeToString()
    val s2 = bytes.decodeToString(Charsets.UTF_8)
    val s3 = bytes.decodeToString(Charsets.ISO_8859_1)
    val s4 = bytes.decodeToString(Charsets.US_ASCII)
    println(s1)
    println(s2)
    println(s3)
    println(s4)
}
