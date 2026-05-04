fun main() {
    val values = sequenceOf(1, 2, 3)

    println(values.firstNotNullOfOrNull { value ->
        if (value == 3) "three" else null
    } ?: "missing")
    println(values.firstNotNullOfOrNull { value ->
        if (value == 9) "nine" else null
    } ?: "missing")
}
