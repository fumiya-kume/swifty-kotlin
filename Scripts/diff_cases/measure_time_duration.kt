import kotlin.time.measureTime

fun doWork() {
    var sum = 0
    for (i in 1..1000) sum += i
}

fun main() {
    // Inline lambda path
    val duration = measureTime {
        var sum = 0
        for (i in 1..1000) sum += i
    }
    println(duration.inWholeMilliseconds >= 0)

    // Function reference path
    val duration2 = measureTime(::doWork)
    println(duration2.inWholeMilliseconds >= 0)

    // Exception propagation path
    try {
        val duration3 = measureTime {
            throw RuntimeException("test error")
        }
        println(duration3.inWholeMilliseconds)
    } catch (e: RuntimeException) {
        println(e.message)
    }
}
