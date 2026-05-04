fun main() {
    val values: List<Int> = listOf(1, 2, 3)
    println(values.firstNotNullOfOrNull { value ->
        if (value == 2) "two" else null
    } ?: "missing")

    println(listOf(1, 3).firstNotNullOfOrNull { value ->
        if (value == 2) "two" else null
    } ?: "missing")
}
