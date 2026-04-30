fun main() {
    val values = sequenceOf(1, 2, 3, 4)
    println(values.firstNotNullOfOrNull<String> { value ->
        if (value == 3) "three" else null
    } ?: "missing")

    println(sequenceOf(1, 2).firstNotNullOfOrNull<String> { value ->
        if (value == 5) "five" else null
    } ?: "missing")
}
