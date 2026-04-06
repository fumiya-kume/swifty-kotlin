// KSWIFTK_DIFF_IGNORE - Sequence flatten not yet implemented
fun main() {
    // Sequence flatten edge cases
    println("=== Sequence flatten edge cases ===")
    
    // Empty sequences
    println(emptySequence<List<Int>>().flatten().toList())  // []
    println(sequenceOf<List<Int>>().flatten().toList())      // []
    
    // Mixed empty and non-empty
    println(sequenceOf(listOf<Int>(), listOf(1), listOf<Int>()).flatten().toList())  // [1]
    
    // Large sequence data
    println("\n=== Large sequence data ===")
    val largeSeq = sequence {
        for (i in 1..100) {
            yield(listOf(i))
        }
    }
    val flattenedSeq = largeSeq.flatten().toList()
    println(flattenedSeq.size)
    println(flattenedSeq.take(5))
    println(flattenedSeq.drop(flattenedSeq.size - 5))
    
    // Nested sequences (flatten only one level)
    println("\n=== Nested sequences ===")
    val nestedSeq = sequenceOf(
        sequenceOf(1, 2),
        sequenceOf(3, 4)
    )
    println(nestedSeq.flatten().toList())  // Should flatten sequences of sequences
    
    // Mixed collection types in sequence
    println("\n=== Mixed collection types ===")
    val mixedSeq = sequenceOf(listOf(1, 2), sequenceOf(3, 4))
    println(mixedSeq.flatten().toList())
    
    // Sequence with null elements (if supported)
    println("\n=== Sequence with special cases ===")
    val singleSeq = sequenceOf(listOf(42))
    println(singleSeq.flatten().toList())  // [42]
}
