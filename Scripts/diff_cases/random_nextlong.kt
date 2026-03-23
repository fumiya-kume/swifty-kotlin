import kotlin.random.Random

fun main() {
    // nextLong() - unbounded
    val a = Random.nextLong()
    println("nextLong called: true")

    // nextLong(until) with Long literal
    var ok1 = true
    repeat(100) {
        val x = Random.nextLong(50L)
        if (x < 0L || x >= 50L) {
            ok1 = false
        }
    }
    println("nextLong(50) in range: $ok1")

    // nextLong(from, until) with Long literals
    var ok2 = true
    repeat(100) {
        val x = Random.nextLong(10L, 20L)
        if (x < 10L || x >= 20L) {
            ok2 = false
        }
    }
    println("nextLong(10,20) in range: $ok2")

    println("OK")
}
