package golden.sema

fun charSequenceGroupBy(source: CharSequence): Map<Int, List<Char>> =
    source.groupBy { ch -> if (ch == 'a') 0 else 1 }

fun charSequenceGroupByTransform(source: CharSequence): Map<Int, List<String>> =
    source.groupBy(
        { ch -> if (ch == 'a') 0 else 1 },
        { ch -> if (ch == 'a') "A" else ch.toString() }
    )

fun charSequenceGroupByTo(source: CharSequence): MutableMap<Int, MutableList<Char>> {
    val destination = mutableMapOf<Int, MutableList<Char>>()
    return source.groupByTo(destination) { ch -> if (ch == 'a') 0 else 1 }
}

fun charSequenceGroupByToTransform(source: CharSequence): MutableMap<Int, MutableList<String>> {
    val destination = mutableMapOf<Int, MutableList<String>>()
    return source.groupByTo(
        destination,
        { ch -> if (ch == 'a') 0 else 1 },
        { ch -> if (ch == 'a') "A" else ch.toString() }
    )
}
