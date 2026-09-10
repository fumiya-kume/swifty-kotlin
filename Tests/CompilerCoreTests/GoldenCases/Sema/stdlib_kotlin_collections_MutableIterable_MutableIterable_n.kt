package golden.sema

fun fromMutableIterable(iterable: MutableIterable<Int>): MutableIterator<Int> {
    return iterable.iterator()
}

fun fromLinkedHashSet(set: LinkedHashSet<Int>): MutableIterator<Int> {
    return set.iterator()
}
