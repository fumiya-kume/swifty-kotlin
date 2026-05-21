fun main() {
    val source: Collection<Int> = listOf(1, 2)

    val arrayList = ArrayList(source)
    println(arrayList.size)
    println(arrayList.joinToString(","))

    val hashSet = HashSet(source)
    println(hashSet.size)
    println(hashSet.contains(1))

    val sourceSet: Set<Int> = setOf(1, 2)
    val linkedHashSet = LinkedHashSet(sourceSet)
    println(linkedHashSet.contains(2))
}
