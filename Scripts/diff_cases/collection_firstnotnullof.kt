fun main() {
    val values: List<Int> = listOf(1, 2, 3)
    println(values.firstNotNullOf { value ->
        if (value == 2) "two" else null
    })

    try {
        println(listOf(1, 3).firstNotNullOf { value ->
            if (value == 2) "two" else null
        })
    } catch (_: NoSuchElementException) {
        println("missing")
    }
}
