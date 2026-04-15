fun main() {
    val zipped = listOf(1, 2, 3).zip(listOf("a", "b"))
    println(zipped)
    println(zipped.unzip().first)
    println(zipped.unzip().second)

    val map = mutableMapOf("a" to 1)
    map.putAll(mutableMapOf("b" to 2, "c" to 3))
    println(map.keys.toList())
    println(map.values.toList())

    val numbers = mutableListOf(1, 2, 3, 4, 5)
    numbers.removeAll(listOf(2, 5))
    println(numbers)

    numbers.retainAll(listOf(1, 4))
    println(numbers)
}
