fun main() {
    val list = listOf(3, 1, 4, 1, 5, 9, 2, 6)

    // sortedDescending
    println(list.sortedDescending())

    // sortedByDescending
    println(list.sortedByDescending { it })

    // sortedWith lambda comparator (ascending)
    println(list.sortedWith { a, b -> a - b })
    // sortedWith lambda comparator (descending)
    println(list.sortedWith { a, b -> b - a })

    // sortedWith compareBy single key
    val strings = listOf("banana", "apple", "cherry", "date")
    println(strings.sortedWith(compareBy { it.length }))
    // sortedWith compareByDescending
    println(strings.sortedWith(compareByDescending { it.length }))

    // sortedWith reverseOrder()
    println(list.sortedWith(reverseOrder()))

    // sortedWith naturalOrder()
    println(list.sortedWith(naturalOrder()))

    // sortedWith compareBy with explicit type parameter
    val comp = compareBy<String> { it.length }
    println(strings.sortedWith(comp))

    // sortedWith on single element
    val single = listOf(42)
    println(single.sortedWith { a, b -> a - b })

    // sortedWith stability: equal elements keep original order
    val pairs = listOf("b2", "a1", "a2", "b1")
    println(pairs.sortedWith(compareBy { it[0] }))
}
