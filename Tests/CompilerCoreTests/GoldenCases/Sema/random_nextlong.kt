import kotlin.random.Random

fun useRandomLong() {
    val a = Random.nextLong()
    val b = Random.nextLong(100L)
    val c = Random.nextLong(10L, 100L)
}
