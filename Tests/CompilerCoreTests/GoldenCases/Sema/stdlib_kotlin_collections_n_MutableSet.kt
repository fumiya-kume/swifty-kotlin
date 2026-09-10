fun acceptSet(values: Set<Int>) {}
fun acceptCollection(values: MutableCollection<Int>) {}
fun acceptIterable(values: MutableIterable<Int>) {}

fun probe(values: MutableSet<Int>) {
    val readonly: Set<Int> = values
    val mutable: MutableCollection<Int> = values
    val iterable: MutableIterable<Int> = values
    acceptSet(readonly)
    acceptCollection(mutable)
    acceptIterable(iterable)

    values.add(1)
    values.addAll(listOf(2))
    values.remove(1)
    values.removeAll(listOf(2))
    values.retainAll(emptySet())
    values.clear()
    values += 3
    values -= 3
    values += listOf(4)
    values -= listOf(4)

    for (element in values) {
        element.hashCode()
    }
    values.iterator()
}
