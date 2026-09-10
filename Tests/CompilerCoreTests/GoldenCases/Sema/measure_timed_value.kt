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

    // KSP-1475 regression: a nullable-returning lambda must still see the
    // top-level overload's declared `() -> Any?` parameter type. A same-named
    // extension elsewhere (TimeSource.measureTimedValue<T>) must not narrow
    // this unqualified call's expected type to non-null Any.
    val result3 = measureTimedValue {
        if (3 + 4 >= 0) "present" else null
    }
    println(result3.value)
}
