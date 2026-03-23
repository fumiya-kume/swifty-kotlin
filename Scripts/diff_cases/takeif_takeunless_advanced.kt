fun main() {
    // Basic takeIf with Int
    println(42.takeIf { it > 0 })
    println(42.takeIf { it < 0 })

    // Basic takeIf with String
    println("hello".takeIf { it.isNotEmpty() })
    println("".takeIf { it.isNotEmpty() })

    // Basic takeUnless with Int
    println(42.takeUnless { it < 0 })
    println(42.takeUnless { it > 0 })

    // Basic takeUnless with String
    println("hello".takeUnless { it.isEmpty() })
    println("".takeUnless { it.isEmpty() })

    // Chaining takeIf with elvis
    val result = 10.takeIf { it > 5 } ?: -1
    println(result)
    val result2 = 3.takeIf { it > 5 } ?: -1
    println(result2)

    // takeIf on numeric boundary
    println(0.takeIf { it == 0 })
    println(Int.MAX_VALUE.takeIf { it > 0 })
    println(Int.MIN_VALUE.takeUnless { it > 0 })

    // takeIf with list
    val list = listOf(1, 2, 3, 4, 5)
    println(list.takeIf { it.size > 3 })
    println(list.takeUnless { it.isEmpty() })
}
