// SKIP-DIFF: Sequence.subtract is a KSwiftK synthetic sequence surface not available in the JVM kotlinc reference.
fun main() {
    println(sequenceOf(1, 2, 2, 3, 4).subtract(listOf(2, 4, 2)))
    println(sequenceOf("a", "b", "a", "c").subtract(setOf("a")))
    println(emptySequence<Int>().subtract(listOf(1)))
}
