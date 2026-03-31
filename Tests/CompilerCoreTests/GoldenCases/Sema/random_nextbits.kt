import kotlin.random.Random

fun useRandomNextBits() {
    val r = Random(42)
    val a = r.nextBits(8)
    val b = r.nextBits(16)
    val c = r.nextBits(32)
    val d = Random.nextBits(1)
}
