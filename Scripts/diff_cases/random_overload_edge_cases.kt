import kotlin.random.Random

fun main() {
    val seeded1 = Random(99)
    val seeded2 = Random(99)

    println(seeded1.nextLong() == seeded2.nextLong())
    println(seeded1.nextFloat() == seeded2.nextFloat())

    val bytes1 = Random(5).nextBytes(ByteArray(4))
    val bytes2 = Random(5).nextBytes(ByteArray(4))
    println(bytes1.toList() == bytes2.toList())

    val r = Random(7)
    val longVal = r.nextLong(10L, 20L)
    val floatVal = r.nextFloat(1.0f, 2.0f)
    println(longVal in 10L until 20L)
    println(floatVal >= 1.0f && floatVal < 2.0f)
}
