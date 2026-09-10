import kotlin.time.Clock
import kotlin.time.Instant

class FixedClock : Clock {
    override fun now(): Instant = Instant.fromEpochMilliseconds(1234L)
}

fun main() {
    val clock: Clock = FixedClock()
    println(clock.now().epochSeconds)
}
