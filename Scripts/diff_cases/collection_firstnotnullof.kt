fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3)

    println(values.firstNotNullOf<String> { value ->
        if (value == 2) "two" else null
    })
    try {
        println(values.firstNotNullOf<String> { value ->
            if (value == 9) "nine" else null
        })
    } catch (e: NoSuchElementException) {
        println("missing")
    }
}
