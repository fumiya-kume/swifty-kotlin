package golden.sema

class RegionSequence(private val value: String) : CharSequence {
    override val length: Int get() = value.length
    override fun get(index: Int): Char = value[index]
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

fun regionMatchesDirect(source: CharSequence, other: CharSequence): Boolean =
    source.regionMatches(0, other, 2, 2)

fun regionMatchesDefault(source: CharSequence, other: CharSequence): Boolean =
    source.regionMatches(0, other, 0, 2)

fun regionMatchesNamed(source: CharSequence, other: CharSequence): Boolean =
    source.regionMatches(
        thisOffset = 1,
        other = other,
        otherOffset = 1,
        length = 2,
        ignoreCase = true
    )

fun regionMatchesString(): Boolean {
    val source: CharSequence = "A😀BC"
    val other: CharSequence = "a😀bc"
    return source.regionMatches(0, other, 0, 5, true)
}

fun regionMatchesBuilder(): Boolean {
    val source: CharSequence = StringBuilder("Ab")
    return source.regionMatches(0, "aB", 0, 2, true)
}

fun regionMatchesCustom(): Boolean {
    val source: CharSequence = RegionSequence("Ab")
    val other: CharSequence = RegionSequence("aB")
    return source.regionMatches(0, other, 0, 2, true)
}

fun regionMatchesEmpty(source: CharSequence): Boolean =
    source.regionMatches(source.length, source, source.length, 0)
