// RF-FIXTURE-002: every primitive array factory returns its own primitive array type.
// Byte / Short take their elements from typed parameters because neither type has a
// literal form; the other six use literals and need no toByte / toShort conversion.

fun intArrayOfLiteral() {
    val ints = intArrayOf(10, 20, 30)
    val checked: IntArray = ints
}

fun longArrayOfLiteral() {
    val longs = longArrayOf(1L, 2L, 3L)
    val checked: LongArray = longs
}

fun doubleArrayOfLiteral() {
    val doubles = doubleArrayOf(1.5, 2.5, 3.5)
    val checked: DoubleArray = doubles
}

fun floatArrayOfLiteral() {
    val floats = floatArrayOf(1.5f, 2.5f, 3.5f)
    val checked: FloatArray = floats
}

fun booleanArrayOfLiteral() {
    val booleans = booleanArrayOf(true, false, true)
    val checked: BooleanArray = booleans
}

fun charArrayOfLiteral() {
    val chars = charArrayOf('a', 'b', 'c')
    val checked: CharArray = chars
}

fun shortArrayOfValues(first: Short, second: Short) {
    val shorts = shortArrayOf(first, second)
    val checked: ShortArray = shorts
}

fun byteArrayOfValues(first: Byte, second: Byte) {
    val bytes = byteArrayOf(first, second)
    val checked: ByteArray = bytes
}
