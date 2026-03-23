import kotlin.random.Random

fun main() {
    // nextDouble(until) - 0 until 5.0
    var ok = true
    repeat(100) {
        val x = Random.nextDouble(5.0)
        if (x < 0.0 || x >= 5.0) {
            ok = false
        }
    }
    println("nextDouble(5.0) in range: $ok")

    // nextDouble(from, until) - 1.0 until 10.0
    var ok2 = true
    repeat(100) {
        val x = Random.nextDouble(1.0, 10.0)
        if (x < 1.0 || x >= 10.0) {
            ok2 = false
        }
    }
    println("nextDouble(1.0, 10.0) in range: $ok2")

    println("OK")
}
