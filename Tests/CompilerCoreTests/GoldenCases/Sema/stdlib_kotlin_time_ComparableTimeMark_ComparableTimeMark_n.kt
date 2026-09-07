import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.ExperimentalTime
import kotlin.time.TestTimeSource
import kotlin.time.TimeSource

@OptIn(ExperimentalTime::class)
fun comparableTimeMarkProbe(): Boolean {
    val first: ComparableTimeMark = TimeSource.Monotonic.markNow()
    val absent: Any? = null
    val shifted: ComparableTimeMark = first + Duration.ZERO
    val heap: ComparableTimeMark = TestTimeSource().markNow()
    return first.equals(first) &&
        !first.equals(absent) &&
        first.hashCode() == first.hashCode() &&
        shifted.equals(shifted) &&
        shifted.hashCode() == shifted.hashCode() &&
        heap.equals(heap) &&
        heap.hashCode() == heap.hashCode()
}
