import kotlin.random.Random

fun main() {
    val r1 = Random(42)
    val r2 = Random(42)
    println(r1.nextBits(8) == r2.nextBits(8))
    println(r1.nextBits(16) == r2.nextBits(16))

    val rangedBits = Random(7)
    val b1 = rangedBits.nextBits(1)
    val b8 = rangedBits.nextBits(8)
    println(b1 == 0 || b1 == 1)
    println(b8 in 0 until 256)

    val bytes1 = Random(99).nextBytes(ByteArray(6), 1, 5)
    val bytes2 = Random(99).nextBytes(ByteArray(6), 1, 5)
    println(bytes1.toList() == bytes2.toList())
    println(bytes1.size)
}
