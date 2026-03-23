typealias StringList = List<String>
typealias Predicate<T> = (T) -> Boolean
typealias IntPair = Pair<Int, Int>

fun main() {
    val names: StringList = listOf("Alice", "Bob", "Charlie")
    println(names.filter { it.length > 3 })
    val pred: Predicate<String> = { it.length > 3 }
    println(pred("Hello"))
    val pair: IntPair = IntPair(1, 2)
    println("${pair.first},${pair.second}")
}
