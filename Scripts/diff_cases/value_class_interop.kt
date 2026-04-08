// SKIP-DIFF
@JvmInline
value class Millis(val value: Long)

@JvmInline
value class Seconds(val value: Double)

fun millisToSeconds(ms: Millis): Seconds = Seconds(ms.value / 1000.0)

fun secondsToMillis(s: Seconds): Millis = Millis((s.value * 1000).toLong())

fun elapsed(start: Millis, end: Millis): Millis = Millis(end.value - start.value)

fun formatSeconds(s: Seconds): String = "${s.value}s"

fun main() {
    val ms = Millis(1500)
    val sec = millisToSeconds(ms)
    println(sec.value)

    val back = secondsToMillis(sec)
    println(back.value)

    val start = Millis(1000)
    val end = Millis(3500)
    val diff = elapsed(start, end)
    println(diff.value)

    val formatted = formatSeconds(Seconds(2.5))
    println(formatted)

    val times: List<Millis> = listOf(Millis(500), Millis(1000), Millis(2000))
    val inSeconds = times.map { millisToSeconds(it) }
    for (s in inSeconds) {
        println(s.value)
    }
}
