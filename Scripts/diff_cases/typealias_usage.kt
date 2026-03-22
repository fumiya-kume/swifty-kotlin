typealias StringList = List<String>
typealias Predicate<T> = (T) -> Boolean
typealias IntPair = Pair<Int, Int>

fun filter(list: StringList, pred: Predicate<String>): StringList = list.filter(pred)
fun main() {
    val names: StringList = listOf("Alice", "Bob", "Charlie")
    println(filter(names) { it.length > 3 })
    val pair: IntPair = IntPair(1, 2)
    println(pair)
}
