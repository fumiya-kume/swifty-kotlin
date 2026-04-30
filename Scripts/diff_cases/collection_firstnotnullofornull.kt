fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3, 4)
    println(values.firstNotNullOfOrNull<String> { value ->
        if (value == 2) "two" else null
    })

    val missing: Iterable<Int> = listOf(1, 2)
    println(missing.firstNotNullOfOrNull<String> { value ->
        if (value == 99) "hit" else null
    } ?: "missing")
}
