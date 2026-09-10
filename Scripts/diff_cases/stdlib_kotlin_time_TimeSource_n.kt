import kotlin.time.ExperimentalTime
import kotlin.time.TimeSource
import kotlin.time.measureTime
import kotlin.time.measureTimedValue

@OptIn(ExperimentalTime::class)
fun main() {
    val source: TimeSource = TimeSource.Monotonic
    var calls = 0

    val elapsed = source.measureTime {
        calls += 1
    }
    val timed = source.measureTimedValue {
        "value"
    }

    println(calls == 1)
    println(elapsed.inWholeNanoseconds >= 0L)
    println(timed !== null)
}
