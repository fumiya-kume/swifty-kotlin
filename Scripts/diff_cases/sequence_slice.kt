fun main() {
    val values = sequenceOf(10, 20, 30, 40, 50)
    println(values.slice(1..3).toList())
    println(sequenceOf(10, 20, 30, 40, 50).slice(listOf(3, 1, 3)).toList())
    println(emptySequence<Int>().slice(0..2).toList())
}
