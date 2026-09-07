import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.ExperimentalTime
import kotlin.time.TestTimeSource
import kotlin.time.TimeSource

@OptIn(ExperimentalTime::class)
fun main() {
    val first: ComparableTimeMark = TimeSource.Monotonic.markNow()
    val absent: Any? = null
    println(first.equals(first))
    println(first.equals(absent))
    println(first.hashCode() == first.hashCode())

    val shifted: ComparableTimeMark = first + Duration.ZERO
    println(shifted.equals(shifted))
    println(shifted.hashCode() == shifted.hashCode())

    val heap: ComparableTimeMark = TestTimeSource().markNow()
    println(heap.equals(heap))
    println(heap.hashCode() == heap.hashCode())
}
