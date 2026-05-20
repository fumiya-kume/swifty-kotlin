fun main() {
    val hashSet = sequenceOf(3, 1, 2, 1, 3).toHashSet()
    println(hashSet.size)
    println(hashSet.contains(3))
    println(hashSet.contains(99))
    hashSet.add(77)
    println(hashSet.contains(77))
}
