fun main() {
    val source = mapOf(1 to 10, 2 to 20)
    val destination = mutableMapOf(0 to 5)
    val result = source.mapValuesTo(destination) { entry -> entry.value + 1 }

    println(result[0])
    println(destination[0])
    println(destination[1])
    println(destination[2])
    println(destination.size)
}
