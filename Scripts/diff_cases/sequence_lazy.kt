fun main() {
    val seq = sequenceOf(1, 2, 3, 4, 5)
    println(seq.filter { it > 2 }.map { it * 10 }.toList())
    println(seq.take(3).toList())
    println(seq.drop(2).toList())
    println(generateSequence(1) { if (it < 10) it * 2 else null }.toList())
}
