import kotlin.time.measureTimedValue

fun main() {
    // Basic measureTimedValue with simple expression
    val result = measureTimedValue {
        "hello"
    }
    println(result.value)
    println(result.duration.inWholeMilliseconds >= 0)

    // measureTimedValue with integer computation
    val result2 = measureTimedValue {
        3 + 4
    }
    println(result2.value)
    println(result2.duration.inWholeMilliseconds >= 0)
}
