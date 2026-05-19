// SKIP-DIFF: Sequence.takeLastWhile is a KSwiftK synthetic sequence surface not available in the JVM kotlinc reference.
fun main() {
    println(sequenceOf(1, 3, 4, 2, 5, 6).takeLastWhile { value -> value > 2 })
    println(sequenceOf(1, 2, 3).takeLastWhile { value -> value > 10 })
    println(sequenceOf(4, 5, 6).takeLastWhile { value -> value > 2 })
}
