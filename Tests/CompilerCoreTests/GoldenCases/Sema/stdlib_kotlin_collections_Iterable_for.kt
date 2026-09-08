package golden.sema

class CustomIterable<T>(private val values: List<T>) : Iterable<T> {
    override fun iterator(): Iterator<T> = values.iterator()
}

fun iterableForEach(values: Iterable<String?>) {
    values.forEach { value ->
        println(value ?: "null")
    }
}

fun customIterableForEach(values: CustomIterable<Int>) {
    values.forEach { value ->
        println(value + 1)
    }
}

fun receiverResolution(
    list: List<Int>,
    array: Array<Int>,
    map: Map<String, Int>,
    sequence: Sequence<Int>,
    iterator: Iterator<Int>,
    primitiveArray: IntArray
) {
    list.forEach { println(it) }
    array.forEach { println(it) }
    map.forEach { key, value -> println(key + value) }
    sequence.forEach { println(it) }
    iterator.forEach { println(it) }
    list.forEachIndexed { index, value -> println(index + value) }
    primitiveArray.forEach { println(it) }
}
