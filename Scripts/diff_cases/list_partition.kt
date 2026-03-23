fun main() {
    // Basic partition: even/odd
    val list = listOf(1, 2, 3, 4, 5, 6)
    val (evens, odds) = list.partition { it % 2 == 0 }
    println(evens)
    println(odds)

    // Empty list
    val empty = listOf<Int>()
    val (a, b) = empty.partition { it > 0 }
    println(a)
    println(b)

    // All match predicate
    val allPos = listOf(1, 2, 3)
    val (matched, unmatched) = allPos.partition { it > 0 }
    println(matched)
    println(unmatched)

    // None match predicate
    val (none, all) = allPos.partition { it < 0 }
    println(none)
    println(all)

    // String partition
    val words = listOf("apple", "banana", "cherry", "date")
    val (long, short) = words.partition { it.length > 5 }
    println(long)
    println(short)

    // Single element list
    val single = listOf(42)
    val (s1, s2) = single.partition { it > 0 }
    println(s1)
    println(s2)

    // Partition preserves order
    val nums = listOf(5, 3, 8, 1, 9, 2, 7)
    val (big, small) = nums.partition { it >= 5 }
    println(big)
    println(small)
}
