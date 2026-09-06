fun removeBySequence(values: Iterable<Int>, elements: Sequence<Int>): List<Int> {
    return values.minus(elements)
}

fun removeByArray(values: Iterable<Int>, elements: Array<out Int>): List<Int> {
    return values.minus(elements)
}

fun removeNullableByArray(
    values: Iterable<String?>,
    elements: Array<out String?>
): List<String?> {
    return values.minus(elements)
}

fun removeByElement(values: Iterable<Int>): List<Int> {
    return values.minus(2)
}

fun removeByIterable(values: Iterable<Int>): List<Int> {
    return values.minus(listOf(2, 3))
}
