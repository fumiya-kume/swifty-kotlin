fun main() {
    val s = sequenceOf(1, 2, 3)
    s.forEach { println(it) }
    val fm = s.flatMap { sequenceOf(it) }
    val d = s.drop(1)
    val u = s.distinct()
    val z = s.zip(sequenceOf(4, 5, 6))
    val g = generateSequence(1) { it + 1 }
    val r = g.take(3).toList()
}
