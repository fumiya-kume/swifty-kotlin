package golden.sema

class SingleSequence(private val value: String) : CharSequence {
    override val length: Int get() = value.length
    override fun get(index: Int): Char = value[index]
}

fun singleDirect(source: CharSequence): Char = source.single()

fun singlePredicate(source: CharSequence, wanted: Char): Char =
    source.single { it == wanted }

fun singlePredicateNamed(source: CharSequence, wanted: Char): Char =
    source.single(predicate = { it == wanted })

fun singleOrNullDirect(source: CharSequence): Char? = source.singleOrNull()

fun singleOrNullPredicate(source: CharSequence, wanted: Char): Char? =
    source.singleOrNull { it == wanted }

fun singleOrNullPredicateNamed(source: CharSequence, wanted: Char): Char? =
    source.singleOrNull(predicate = { it == wanted })

fun singleString(): Char {
    val source: CharSequence = "S"
    return source.single()
}

fun singleBuilder(): Char {
    val source: CharSequence = StringBuilder("B")
    return source.single()
}

fun singleCustom(): Char {
    val source: CharSequence = SingleSequence("C")
    return source.single()
}

fun singleOrNullEmpty(source: CharSequence): Char? =
    source.singleOrNull()
