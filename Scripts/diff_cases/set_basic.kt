fun main() {
    val set = setOf(1, 2, 2, 3)
    println(set)
    println(set.size)
    println(set.contains(2))
    println(set.isEmpty())

    val mutable = mutableSetOf(1, 2)
    println(mutable.add(2))
    println(mutable.add(3))
    println(mutable.remove(1))
    println(mutable)
    println(emptySet<Int>().isEmpty())
}
