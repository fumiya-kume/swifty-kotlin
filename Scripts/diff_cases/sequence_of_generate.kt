fun main() {
    val s1 = sequenceOf(1, 2, 3).toList()
    println(s1)

    val s2 = generateSequence(1) { if (it < 16) it * 2 else null }.toList()
    println(s2)

    val s3 = generateSequence(1) { it * 2 }.take(5).toList()
    println(s3)
}
