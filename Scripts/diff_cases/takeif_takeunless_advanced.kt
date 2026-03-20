fun main() {
    // Basic takeIf with different types
    println(42.takeIf { it > 0 })
    println(42.takeIf { it < 0 })
    println("hello".takeIf { it.isNotEmpty() })
    println("".takeIf { it.isNotEmpty() })
    println(true.takeIf { it })
    println(false.takeIf { it })

    // Basic takeUnless with different types
    println(42.takeUnless { it < 0 })
    println(42.takeUnless { it > 0 })
    println("hello".takeUnless { it.isEmpty() })
    println("".takeUnless { it.isEmpty() })

    // Nullable receiver
    val nullStr: String? = null
    println(nullStr.takeIf { it != null })
    println(nullStr.takeUnless { it != null })
    val nonNullStr: String? = "world"
    println(nonNullStr.takeIf { it != null })
    println(nonNullStr.takeUnless { it != null })

    // Chaining takeIf with elvis
    val result = 10.takeIf { it > 5 } ?: -1
    println(result)
    val result2 = 3.takeIf { it > 5 } ?: -1
    println(result2)

    // Chaining takeIf/takeUnless
    val chained = "kotlin".takeIf { it.length > 3 }?.uppercase()
    println(chained)
    val chained2 = "hi".takeIf { it.length > 3 }?.uppercase()
    println(chained2)

    // takeIf on numeric boundary
    println(0.takeIf { it == 0 })
    println(Int.MAX_VALUE.takeIf { it > 0 })
    println(Int.MIN_VALUE.takeUnless { it > 0 })

    // takeIf with complex predicate
    val list = listOf(1, 2, 3, 4, 5)
    println(list.takeIf { it.size > 3 })
    println(list.takeIf { it.size > 10 })
    println(list.takeUnless { it.isEmpty() })
}
