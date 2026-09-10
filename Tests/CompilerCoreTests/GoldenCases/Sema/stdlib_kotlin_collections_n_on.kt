package golden.sema

// KSP-957: generic Iterable and Map on-family calls resolve to source-backed
// extensions and preserve the receiver type.
fun iterableOnEach(values: Iterable<Int>): Iterable<Int> =
    values.onEach { value -> println(value) }

fun iterableOnEachIndexed(values: Iterable<Int>): Iterable<Int> =
    values.onEachIndexed { index, value -> println(index + value) }

fun mapOnEach(values: Map<String, Int>): Map<String, Int> =
    values.onEach { entry -> println(entry.key) }

fun mapOnEachIndexed(values: Map<String, Int>): Map<String, Int> =
    values.onEachIndexed { index, entry -> println("$index:${entry.value}") }
