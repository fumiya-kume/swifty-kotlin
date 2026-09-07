fun inspect(values: Set<Int?>): String {
    return "${values.size}:${values.isEmpty()}:${values.contains(null)}:${values.iterator().hasNext()}"
}

fun main() {
    println(inspect(setOf(1, null, 2)))
    println(inspect(emptySet()))
}
