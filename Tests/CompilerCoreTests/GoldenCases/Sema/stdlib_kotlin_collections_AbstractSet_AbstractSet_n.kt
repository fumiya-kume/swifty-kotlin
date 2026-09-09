package golden.sema

import kotlin.collections.AbstractSet
import kotlin.collections.Set

private class ProbeSet<E>(private val elements: List<E>) : AbstractSet<E>() {
    override val size: Int
        get() = elements.size

    override fun iterator(): Iterator<E> = elements.iterator()
}

fun acceptSet(values: Set<Int>) {}

fun probe(values: ProbeSet<Int>): Boolean {
    acceptSet(values)
    return values.equals(values) && values.hashCode() == values.hashCode()
}
