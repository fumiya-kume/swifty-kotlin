fun main() {
    println(sequenceOf(1, 2, 3, 4).take(2).toList())
    println(sequenceOf(1, 2).take(5).toList())
    println(sequenceOf(1, 2).take(0).toList())
}
