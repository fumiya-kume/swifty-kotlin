private class ProbeSet<E>(private val elements: List<E>) : AbstractSet<E>() {
    override val size: Int
        get() = elements.size

    override fun iterator(): Iterator<E> = elements.iterator()
}

fun main() {
    val ordered = ProbeSet(listOf(1, 2, 3))
    val reordered = ProbeSet(listOf(3, 1, 2))
    val differentSize = ProbeSet(listOf(1, 2))
    val differentElements = ProbeSet(listOf(1, 2, 4))
    val withNull = ProbeSet(listOf<String?>(null, "a"))

    println(ordered == reordered)
    println(ordered.equals(reordered))
    println(ordered == differentSize)
    println(ordered == differentElements)
    println((ordered as Any) == listOf(1, 2, 3))
    println(ordered.equals(null))
    println(ordered.hashCode() == reordered.hashCode())
    println(withNull.hashCode() == "a".hashCode())
}
