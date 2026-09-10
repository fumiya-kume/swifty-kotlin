import kotlin.time.Duration
import kotlin.time.ExperimentalTime
import kotlin.time.TimedValue
import kotlin.time.TimeSource
import kotlin.time.measureTime
import kotlin.time.measureTimedValue

@OptIn(ExperimentalTime::class)
fun measureTimeReceiver(source: TimeSource): Duration =
    source.measureTime { }

@OptIn(ExperimentalTime::class)
fun measureTimedValueReceiver(source: TimeSource): TimedValue<String> =
    source.measureTimedValue { "value" }
