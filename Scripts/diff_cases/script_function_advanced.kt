fun<T> List<T>.firstOrNull(predicate: (T) -> Boolean): T? {
    for (item in this) {
        if (predicate(item)) return item
    }
    return null
}

fun printAll(vararg items: Any) {
    items.forEach { println(it) }
}

fun calculate(base: Int, multiplier: Int = 2): Int = base * multiplier

println(listOf(1, 2, 3).firstOrNull { it > 2 })
printAll("Hello", 42, true)
println(calculate(10))
println(calculate(10, 3))
