// KSP-1070: MutableIterable.iterator is source-backed and must preserve the
// mutable iterator contract for the runtime-backed LinkedHashSet implementation.

fun main() {
    val set: LinkedHashSet<Int> = linkedSetOf(1, 2, 3)
    val iterable: MutableIterable<Int> = set
    val iterator: MutableIterator<Int> = iterable.iterator()

    println(iterator.next())
    iterator.remove()
    println(set)
}
