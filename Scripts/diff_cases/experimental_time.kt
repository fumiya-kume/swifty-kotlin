import kotlin.time.ExperimentalTime
import kotlin.time.TimeSource
import kotlin.time.milliseconds

@OptIn(ExperimentalTime::class)
fun main() {
    val start = TimeSource.Monotonic.markNow()
    val shifted = start + 200.milliseconds
    val rewound = shifted - 10.milliseconds

    println(start.elapsedNow().inWholeNanoseconds >= 0L)
    println(shifted.hasNotPassedNow())
    println(rewound.hasPassedNow())

    val diff = shifted - start
    println(diff.inWholeMilliseconds >= 0L)
    println(shifted > start)
}
