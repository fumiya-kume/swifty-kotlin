import kotlin.random.Random

fun main() {
    val r1 = Random(1234)
    val r2 = Random(1234)

    println(r1.nextInt(100) == r2.nextInt(100))
    println(r1.nextInt(10, 20) == r2.nextInt(10, 20))
    println(r1.nextBoolean() == r2.nextBoolean())

    val ranged = Random(7)
    val nextInt = ranged.nextInt(5, 10)
    val nextDouble = ranged.nextDouble(1.0, 2.0)
    println(nextInt >= 5 && nextInt < 10)
    println(nextDouble >= 1.0 && nextDouble < 2.0)
}
