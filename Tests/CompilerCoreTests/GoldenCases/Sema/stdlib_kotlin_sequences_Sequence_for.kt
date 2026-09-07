fun main() {
    val values = sequenceOf(1, 2, 3)

    values.forEach { value -> println(value) }
    values.forEachIndexed { index, value -> println(index + value) }
}
