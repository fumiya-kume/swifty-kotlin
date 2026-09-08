fun main() {
    val iterator = iterator {
        yield(2)
        yield(3)
    }
    val values = listOf(4, 5)
    val source = sequenceOf(6, 7)
    val result = sequence {
        yield(1)
        yieldAll(iterator)
        yieldAll(values)
        yieldAll(source)
    }
    println(result.toList())
}
