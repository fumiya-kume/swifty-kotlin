import kotlin.random.Random

fun main() {
    val shuffled = sequenceOf(1, 2, 3, 4).shuffled().toList()
    println(shuffled.size)
    println(shuffled.sorted())

    val shuffledWithRandom = sequenceOf(1, 2, 3, 4).shuffled(Random(7)).toList()
    println(shuffledWithRandom.size)
    println(shuffledWithRandom.sorted())

    println(emptySequence<Int>().shuffled().toList())
    println(sequenceOf(42).shuffled(Random).toList())
}
