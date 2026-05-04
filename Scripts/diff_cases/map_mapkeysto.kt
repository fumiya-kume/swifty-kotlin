fun main() {
    val source = mapOf(1 to "one", 2 to "two")
    val destination = mutableMapOf(0 to "zero")
    val result = source.mapKeysTo(destination) { entry -> entry.key * 10 }

    println(result[0])
    println(destination[0])
    println(destination[10])
    println(destination[20])
    println(destination.size)
}
