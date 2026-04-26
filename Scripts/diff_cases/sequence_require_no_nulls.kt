fun main() {
    val cleaned = sequenceOf(1, 2, 3).requireNoNulls().toList()
    println(cleaned)

    val nullable = sequenceOf(1, null, 3).requireNoNulls()
    println(nullable.take(1).toList())

    try {
        println(nullable.toList())
    } catch (e: IllegalArgumentException) {
        println("caught")
    }
}
