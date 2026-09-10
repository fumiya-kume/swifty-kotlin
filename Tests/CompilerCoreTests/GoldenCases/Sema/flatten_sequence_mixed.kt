// RF-FIXTURE-010 / BUG-237: mixed List/Sequence element inference diverges
// from kotlinc. sequenceOf(listOf(1, 2), sequenceOf(3, 4)) infers
// Sequence<Any> in both compilers, but kotlinc rejects .flatten() on it while
// KSwiftK resolves it leniently. This fixture records the current divergent
// resolution; it must not be copied into a diff case (kotlinc compile error).

fun flattenMixed() {
    val mixed = sequenceOf(listOf(1, 2), sequenceOf(3, 4))
    val flattened = mixed.flatten()
    val checked: Sequence<Any> = flattened
}
