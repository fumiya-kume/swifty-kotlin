fun associateFamily(
    iterable: Iterable<String>,
    custom: Iterable<String>,
    list: List<String>,
    destination: MutableMap<Any?, Any?>
) {
    iterable.associate { Pair(it, it.length) }
    iterable.associateBy { it }
    iterable.associateBy({ it }, { it.length })
    iterable.associateByTo(destination) { it }
    iterable.associateByTo(destination, { it }, { it.length })
    iterable.associateTo(destination) { Pair(it, it.length) }
    iterable.associateWith { it.length }
    iterable.associateWithTo(destination) { it.length }

    custom.associate { Pair(it, it.length) }
    list.associate { Pair(it, it.length) }
}
