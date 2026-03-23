import kotlin.random.Random

fun main() {
    // nextFloat() returns a value in [0.0, 1.0)
    var ok = true
    repeat(100) {
        val f = Random.nextFloat()
        if (f < 0.0f || f >= 1.0f) {
            ok = false
        }
    }
    println("nextFloat in range: $ok")
    println("OK")
}
