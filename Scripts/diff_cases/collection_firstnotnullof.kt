fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3, 4)
    println(values.firstNotNullOf<String> { value ->
        if (value == 2) "two" else null
    })

    try {
        val missing: Iterable<Int> = listOf(1, 2)
        println(missing.firstNotNullOf<String> { value ->
            if (value == 99) "hit" else null
        })
    } catch (e: Throwable) {
        println("missing")
    }
}
