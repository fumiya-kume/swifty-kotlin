fun main() {
    val words = listOf("a", "bbb", "cc")

    // maxOf / minOf (non-OrNull, throws on empty)
    println(words.maxOf { it.length })
    println(words.minOf { it.length })

    // maxWith / minWith (comparator-based, throws on empty)
    println(words.maxWith(compareBy { it.length }))
    println(words.minWith(compareBy { it.length }))

    // maxWithOrNull / minWithOrNull (comparator-based, returns null on empty)
    println(words.maxWithOrNull(compareBy { it.length }))
    println(words.minWithOrNull(compareBy { it.length }))

    // maxOfWith / minOfWith (comparator + selector, throws on empty)
    println(words.maxOfWith(naturalOrder()) { it.length })
    println(words.minOfWith(naturalOrder()) { it.length })

    // maxOfWithOrNull / minOfWithOrNull (comparator + selector, returns null on empty)
    println(words.maxOfWithOrNull(naturalOrder()) { it.length })
    println(words.minOfWithOrNull(naturalOrder()) { it.length })

    // Empty list cases
    val empty = emptyList<String>()

    // OrNull variants return null on empty
    println(empty.maxWithOrNull(compareBy { it.length }))
    println(empty.minWithOrNull(compareBy { it.length }))
    println(empty.maxOfWithOrNull(naturalOrder()) { it.length })
    println(empty.minOfWithOrNull(naturalOrder()) { it.length })
}
