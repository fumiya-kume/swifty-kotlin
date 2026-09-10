import kotlin.time.Clock
import kotlin.time.Instant

class FixedClock : Clock {
    override fun now(): Instant = Instant.fromEpochMilliseconds(1234L)
}

fun readClock(clock: Clock): Instant = clock.now()
