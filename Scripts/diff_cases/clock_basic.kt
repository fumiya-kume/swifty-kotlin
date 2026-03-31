import kotlin.time.Clock
import kotlin.time.Instant

fun main() {
    val t1 = Clock.System.now()
    val t2 = Clock.System.now()
    // Time progresses: t2 >= t1
    println(t2.compareTo(t1) >= 0)
    // epochSeconds is a positive Long (after year 2000)
    println(t1.epochSeconds > 0)
}
