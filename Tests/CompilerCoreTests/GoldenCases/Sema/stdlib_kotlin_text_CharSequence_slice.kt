package golden.sema

fun charSequenceSliceRange(source: CharSequence): CharSequence =
    source.slice(1..3)

fun charSequenceSliceIterable(
    source: CharSequence,
    indices: Iterable<Int>
): CharSequence = source.slice(indices)
