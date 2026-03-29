fun main() {
    // removeAll with list
    val s1 = mutableSetOf(1, 2, 3, 4, 5)
    val removed = s1.removeAll(listOf(2, 4))
    println(removed)
    println(s1)

    // removeAll with set
    val s2 = mutableSetOf(1, 2, 3, 4, 5)
    val removed2 = s2.removeAll(setOf(1, 3, 5))
    println(removed2)
    println(s2)

    // removeAll no overlap → returns false
    val s3 = mutableSetOf(1, 2, 3)
    val removed3 = s3.removeAll(listOf(4, 5))
    println(removed3)
    println(s3)

    // retainAll with list
    val s4 = mutableSetOf(1, 2, 3, 4, 5)
    val retained = s4.retainAll(listOf(2, 4, 6))
    println(retained)
    println(s4)

    // retainAll with set
    val s5 = mutableSetOf(1, 2, 3, 4, 5)
    val retained2 = s5.retainAll(setOf(3, 4, 5, 6, 7))
    println(retained2)
    println(s5)

    // retainAll same elements → returns false
    val s6 = mutableSetOf(1, 2, 3)
    val retained3 = s6.retainAll(listOf(1, 2, 3, 4))
    println(retained3)
    println(s6)
}
