// SKIP-DIFF: Sequence.takeLast is a KSwiftK synthetic sequence surface not available in the JVM kotlinc reference.
fun main() {
    println(sequenceOf(1, 2, 3, 4).takeLast(2))
    println(sequenceOf(1, 2).takeLast(5))
    println(sequenceOf(1, 2).takeLast(0))
    try {
        println(sequenceOf(1, 2).takeLast(-1))
        println("missing-negative")
    } catch (e: IllegalArgumentException) {
        println("negative-takeLast")
    }
}
