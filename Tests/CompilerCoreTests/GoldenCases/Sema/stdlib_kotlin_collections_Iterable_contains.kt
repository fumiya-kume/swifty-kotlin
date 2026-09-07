fun probeContains(
    values: Iterable<Int>,
    nullable: Iterable<String?>,
    list: List<Int>,
    collection: Collection<Int>,
    set: Set<Int>
) {
    values.contains(2)
    2 in values
    4 !in values
    nullable.contains(null)
    null in nullable
    list.contains(2)
    collection.contains(2)
    set.contains(2)
}
