fun main() {
    val ints: Iterable<Int> = listOf(1, 2)
    val byElement: List<Int> = ints.plus(3)
    val byIterable: List<Int> = ints.plus(listOf(3, 4))
    val bySequence: List<Int> = ints.plus(sequenceOf(5, 6))
    val byArray: List<Int> = ints.plus(arrayOf(7, 8))
    val byElementOperator: List<Int> = ints + 9
    val bySequenceOperator: List<Int> = ints + sequenceOf(10)
    val byArrayOperator: List<Int> = ints + arrayOf(11)
    val byPlusElement: List<Int> = ints.plusElement(12)

    val longMinusElement: List<Long> = listOf(1L, 2L).minus(3L)
    val doubleMinusElement: List<Double> = listOf(1.0, 2.0).minus(3.0)
    val floatMinusElement: List<Float> = listOf(1.0f, 2.0f).minus(3.0f)
    val charMinusElement: List<Char> = listOf('a', 'b').minus('c')

    val nullable: Iterable<String?> = listOf("a", null)
    val nullableSequence: Sequence<String?> = sequenceOf("b", null)
    val nullableArray: Array<String?> = arrayOf("c", null)
    val nullableBySequence: List<String?> = nullable.plus(nullableSequence)
    val nullableByArray: List<String?> = nullable.plus(nullableArray)

    val widened: Iterable<Any?> = listOf("x", null)
    val subtypeArray: Array<String> = arrayOf("y")
    val widenedByArray: List<Any?> = widened.plus(subtypeArray)

    val sequencePlus: Sequence<Int> = sequenceOf(13) + sequenceOf(14)
}
