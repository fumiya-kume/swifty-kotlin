fun main() {
    // 1. Basic lastOrNull on non-empty list
    val nums = listOf(10, 20, 30)
    println(nums.lastOrNull())          // 30

    // 2. lastOrNull on empty list
    val empty = emptyList<Int>()
    println(empty.lastOrNull())         // null

    // 3. lastOrNull with predicate – match exists
    val letters = listOf("a", "bb", "ccc", "dd")
    println(letters.lastOrNull { it.length == 2 })  // dd

    // 4. lastOrNull with predicate – no match
    println(letters.lastOrNull { it.length > 10 })  // null

    // 5. lastOrNull on single-element list
    val single = listOf(42)
    println(single.lastOrNull())        // 42

    // 6. lastOrNull with predicate on single-element – match
    println(single.lastOrNull { it > 0 })   // 42

    // 7. lastOrNull with predicate on single-element – no match
    println(single.lastOrNull { it < 0 })   // null

    // 8. lastOrNull on mutableListOf
    val mutable = mutableListOf(1, 2, 3)
    println(mutable.lastOrNull())       // 3

    // 9. lastOrNull on list of strings
    val strings = listOf("hello", "world")
    println(strings.lastOrNull())       // world

    // 10. lastOrNull with predicate matching first element only
    val mixed = listOf(1, 2, 3, 4, 5)
    println(mixed.lastOrNull { it == 1 })   // 1

    // 11. lastOrNull with predicate matching last element only
    println(mixed.lastOrNull { it == 5 })   // 5

    // 12. lastOrNull with predicate matching multiple – returns last
    println(mixed.lastOrNull { it % 2 == 0 })  // 4

    // 13. String.lastOrNull() – non-empty
    val str = "Kotlin"
    println(str.lastOrNull())           // n

    // 14. String.lastOrNull() – empty
    val emptyStr = ""
    println(emptyStr.lastOrNull())      // null

    // 15. Chained: map then lastOrNull
    val result = listOf(1, 2, 3).map { it * 10 }.lastOrNull()
    println(result)                     // 30

    // 16. Chained: filter then lastOrNull
    val filtered = listOf(1, 2, 3, 4, 5).filter { it > 3 }.lastOrNull()
    println(filtered)                   // 5

    // 17. lastOrNull on list with null elements
    val withNulls = listOf(1, null, 3, null)
    println(withNulls.lastOrNull())     // null (the element itself is null)

    // 18. lastOrNull with predicate on nullable list – find non-null
    println(withNulls.lastOrNull { it != null })  // 3

    // 19. Boolean result of lastOrNull null-check
    println(nums.lastOrNull() != null)      // true
    println(empty.lastOrNull() != null)     // false
}
