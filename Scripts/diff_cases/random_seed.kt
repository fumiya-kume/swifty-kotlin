import kotlin.random.Random

fun main() {
    val r1 = Random(42)
    val r2 = Random(42)
    // Same seed produces identical sequences
    println(r1.nextInt(100) == r2.nextInt(100))
    println(r1.nextInt(100) == r2.nextInt(100))
    println(r1.nextInt(100) == r2.nextInt(100))
    println(r1.nextBoolean() == r2.nextBoolean())
    // Different seed produces divergent sequences
    val r3 = Random(0)
    val r4 = Random(42)
    var differ = false
    for (i in 0..4) {
        if (r3.nextInt(1000) != r4.nextInt(1000)) {
            differ = true
        }
    }
    println(differ)
}
