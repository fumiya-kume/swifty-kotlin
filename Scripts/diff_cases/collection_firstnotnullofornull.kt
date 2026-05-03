fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3)

    println(values.firstNotNullOfOrNull<String> { value ->
        if (value == 2) "two" else null
    } ?: "missing")
    println(values.firstNotNullOfOrNull<String> { value ->
        if (value == 9) "nine" else null
    } ?: "missing")
}
