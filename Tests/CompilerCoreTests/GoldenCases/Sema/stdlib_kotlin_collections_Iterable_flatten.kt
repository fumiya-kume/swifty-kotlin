fun flattenIterable(values: Iterable<Iterable<Int>>): List<Int> = values.flatten()

fun main() {
    val nested: List<List<Int>> = listOf(listOf(1, 2), listOf(3))
    val iterable: Iterable<Iterable<Int>> = nested
    val typedInner: List<Iterable<Int>> = listOf(emptyList<Int>(), listOf(4, 5))

    println(nested.flatten())
    println(iterable.flatten())
    println(flattenIterable(typedInner))
}
