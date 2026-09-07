class CountingIterable(private val values: List<Int>) : Iterable<Int> {
    var iteratorCalls: Int = 0

    override fun iterator(): Iterator<Int> {
        iteratorCalls += 1
        return values.iterator()
    }
}

class CountingSequence(private val values: List<Int>) : Sequence<Int> {
    var iteratorCalls: Int = 0

    override fun iterator(): Iterator<Int> {
        iteratorCalls += 1
        return values.iterator()
    }
}

fun main() {
    val receiver = CountingIterable(listOf(1, 1))
    val sequence = CountingSequence(listOf(2, 2))
    val fromSequence = receiver.plus(sequence)
    println(fromSequence)
    println(receiver.iteratorCalls)
    println(sequence.iteratorCalls)

    val array = arrayOf(3, 4)
    val fromArray = listOf(1, 1).plus(array)
    array[0] = 99
    println(fromArray)

    println(listOf(1).plus(2))
    println(listOf(1).plus(listOf(2)))
    println(listOf(1).plus(sequenceOf(2)))
    println(listOf(1).plus(arrayOf(2)))
    println(listOf(1L, 2L).minus(3L))
    println(listOf(1.0, 2.0).minus(3.0))
    println(listOf(1.0f, 2.0f).minus(3.0f))
    println(listOf('a', 'b').minus('c'))
    println(sequenceOf(1).plus(sequenceOf(2)).toList())

    println(listOf<String?>(null, "x").plus(sequenceOf<String?>(null, "x")))
    println(listOf<Any?>("a", null).plus(arrayOf("b")))
    println(emptyList<Int>().plus(emptySequence<Int>()))
    println(emptyList<Int>().plus(emptyArray<Int>()))
}
