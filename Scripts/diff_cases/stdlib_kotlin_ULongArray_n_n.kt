@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val empty = ULongArray(0)
    println("empty=${empty.size}")

    val zeroInitialized = ULongArray(3)
    println("zero=${zeroInitialized[0].toLong()},${zeroInitialized[1].toLong()},${zeroInitialized[2].toLong()}")

    try {
        ULongArray(-1)
        println("negative=NO_THROW")
    } catch (e: NegativeArraySizeException) {
        println("negative=NegativeArraySizeException")
    }

    val signed = longArrayOf(1L, -1L, Long.MIN_VALUE)
    val view = signed.asULongArray()
    println("viewBits=${view[0].toLong()},${view[1].toLong()}")
    println("minBitPattern=${view[2].toLong() == Long.MIN_VALUE}")
    signed[1] = 99L
    println("viewAfterWrite=${view[1]}")
}
