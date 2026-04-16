import kotlin.random.Random

fun main() {
    val r1 = Random(42)
    val r2 = Random(42)
    println(r1.nextInt() == r2.nextInt())
    println(r1.nextInt(256) == r2.nextInt(256))

    val rangedBits = Random(7)
    val b1 = rangedBits.nextInt(2)
    val b8 = rangedBits.nextInt(256)
    println(b1 == 0 || b1 == 1)
    println(b8 >= 0 && b8 < 256)
}
