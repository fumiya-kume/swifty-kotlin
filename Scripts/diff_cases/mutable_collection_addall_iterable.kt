fun appendList(values: MutableList<Int>, source: Iterable<Int>) {
    println(values.addAll(source))
    println(values)
}

fun appendSet(values: MutableSet<Int>, source: Iterable<Int>) {
    println(values.addAll(source))
    println(values)
}

fun main() {
    val list = mutableListOf(1)
    appendList(list, listOf(2, 3))

    val set = mutableSetOf(1)
    appendSet(set, listOf(1, 2, 2, 3))
    appendSet(set, listOf(1, 2, 3))

    val chars = mutableListOf<Char>()
    println(chars.addAll("ab".asIterable()))
    println(chars.joinToString(""))

    val sequenceValues = mutableListOf<Int>()
    println(sequenceValues.addAll(sequenceOf(4, 5).asIterable()))
    println(sequenceValues)
}
