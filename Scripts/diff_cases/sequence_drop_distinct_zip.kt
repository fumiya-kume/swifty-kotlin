fun main() {
    val d = sequenceOf(1, 2, 3, 4, 5).drop(2).toList()
    println(d)

    val u = sequenceOf(1, 2, 2, 3, 3, 3).distinct().toList()
    println(u)

    val z = sequenceOf("a", "b", "c").zip(sequenceOf(1, 2, 3)).toList()
    println(z)
}
