package golden.sema

fun charSequenceForEach(source: CharSequence) {
    source.forEach { _ -> }
}

fun charSequenceForEachIndexed(source: CharSequence) {
    source.forEachIndexed { index, _ -> if (index < 0) return@forEachIndexed }
}

fun directNonLocal(source: CharSequence, target: Char): Char {
    source.forEach { if (it == target) return it }
    return '?'
}

fun safeNonLocal(source: CharSequence?, target: Char): Char {
    source?.forEach { if (it == target) return it }
    return '?'
}

fun capturedNonLocal(source: CharSequence, target: Char): Char {
    val expected = target
    source.forEach { if (it == expected) return it }
    return '?'
}

fun namedNonLocal(source: CharSequence, target: Char): Char {
    source.forEach(action = { if (it == target) return it })
    return '?'
}

fun namedIndexedNonLocal(source: CharSequence): Char {
    source.forEachIndexed(action = { index, value -> if (index == 1) return value })
    return '?'
}
