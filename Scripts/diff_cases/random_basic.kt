import kotlin.random.Random

fun main() {
    // nextInt(from, until) - 1 until 10 -> values in [1, 9]
    var ok = true
    repeat(100) {
        val x = Random.nextInt(1, 10)
        if (x < 1 || x >= 10) {
            ok = false
        }
    }
    println("nextInt(1,10) in range: $ok")

    // nextInt(until) - 0 until 5
    var ok2 = true
    repeat(100) {
        val x = Random.nextInt(5)
        if (x < 0 || x >= 5) {
            ok2 = false
        }
    }
    println("nextInt(5) in range: $ok2")

    // nextDouble in [0, 1)
    var ok3 = true
    repeat(100) {
        val x = Random.nextDouble()
        if (x < 0.0 || x >= 1.0) {
            ok3 = false
        }
    }
    println("nextDouble in range: $ok3")

    println("OK")
}
