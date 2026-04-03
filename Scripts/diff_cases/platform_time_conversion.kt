import java.time.Duration as JavaDuration
import java.time.Instant as JavaInstant
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Instant
import kotlin.time.toJSDate
import kotlin.time.toJavaDuration
import kotlin.time.toJavaInstant
import kotlin.time.toKotlinDuration
import kotlin.time.toKotlinInstant

fun main() {
    val instant = Instant.fromEpochMilliseconds(1_234)
    val javaInstant: JavaInstant = instant.toJavaInstant()
    val instantRoundTrip = javaInstant.toKotlinInstant()
    println(instantRoundTrip.epochSeconds == 1L)
    println(instantRoundTrip.nanoOfSecond == 234_000_000)

    val duration = 1_500.milliseconds
    val javaDuration: JavaDuration = duration.toJavaDuration()
    val durationRoundTrip = javaDuration.toKotlinDuration()
    println(durationRoundTrip.inWholeMilliseconds == 1_500L)

    val jsDate = instant.toJSDate()
    val jsRoundTrip = jsDate.toKotlinInstant()
    println(jsRoundTrip.epochSeconds == 1L)
    println(jsRoundTrip.nanoOfSecond == 234_000_000)
}
