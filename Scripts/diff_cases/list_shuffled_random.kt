import kotlin.random.Random

fun main() {
    val list = listOf(3, 1, 4, 1, 5, 9, 2, 6)
<<<<<<< HEAD

    // shuffled() returns a new list with same size
    val shuffled = list.shuffled()
    println(shuffled.size)

    // shuffled list sorted equals original sorted (same elements)
    println(shuffled.sorted() == list.sorted())

    // original is unchanged
    println(list)

    // shuffled on empty list
    val empty = emptyList<Int>()
    println(empty.shuffled())
    println(empty.shuffled().size)

    // shuffled on single element
    val single = listOf(42)
    println(single.shuffled())

    // shuffled containsAll
    println(shuffled.containsAll(list))
    println(list.containsAll(shuffled))

    // shuffled preserves duplicates
    val dupes = listOf(1, 1, 2, 2, 3, 3)
    val shuffledDupes = dupes.shuffled()
    println(shuffledDupes.size)
    println(shuffledDupes.sorted())

    // shuffled of strings
    val words = listOf("hello", "world")
    val shuffledWords = words.shuffled()
    println(shuffledWords.size)
    println(shuffledWords.sorted())

    val result = list.shuffled(Random)
    println(result.size)
    // Verify the shuffled list contains same elements (sorted)
    println(result.sorted())
}
