fun acceptsHashSet(values: HashSet<Int>): MutableSet<Int> = values

fun probe() {
    val empty: HashSet<Int> = HashSet<Int>()
    val sized = HashSet<Int>(8)
    val copied = HashSet(empty)
    val asMutable: MutableSet<Int> = copied
    val asSet: Set<Int> = copied

    acceptsHashSet(copied)
    asMutable.add(1)
    asSet.contains(1)
    sized.add(2)
}
