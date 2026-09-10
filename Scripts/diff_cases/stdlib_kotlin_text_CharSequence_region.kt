private class IndexedSequence(
    private val chars: CharArray,
    private val rendered: String
) : CharSequence {
    var lengthReads: Int = 0
    var getReads: Int = 0

    override val length: Int
        get() {
            lengthReads += 1
            return chars.size
        }

    override fun get(index: Int): Char {
        getReads += 1
        return chars[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        IndexedSequence(chars.copyOfRange(startIndex, endIndex), rendered)

    override fun toString(): String = rendered
}

private fun report(label: String, value: Boolean) {
    println("$label=$value")
}

fun main() {
    val target: CharSequence = IndexedSequence(
        charArrayOf('a', 'B', 'c', '\uD83D', '\uDE00'),
        "wrong-target"
    )
    val other: CharSequence = IndexedSequence(
        charArrayOf('A', 'b', 'C', '\uD83D', '\uDE00'),
        "wrong-other"
    )

    report("case-sensitive", target.regionMatches(0, other, 0, 3))
    report("case-insensitive", target.regionMatches(0, other, 0, 3, true))
    report(
        "named",
        target.regionMatches(
            thisOffset = 1,
            other = other,
            otherOffset = 1,
            length = 2,
            ignoreCase = true
        )
    )
    report("astral", target.regionMatches(3, other, 3, 2))
    report("empty-end", target.regionMatches(5, other, 5, 0))
    report(
        "empty-receiver",
        IndexedSequence(charArrayOf(), "wrong-empty").regionMatches(
            0,
            IndexedSequence(charArrayOf(), "wrong-other-empty"),
            0,
            0
        )
    )

    val builder: CharSequence = StringBuilder("Abc")
    report("builder", builder.regionMatches(0, "ABC", 0, 3, true))
    val string: CharSequence = "Abc😀"
    val stringOther: CharSequence = "aBC😀"
    report("string-utf16", string.regionMatches(0, stringOther, 0, 5, true))
    val unicodeCase: CharSequence = IndexedSequence(charArrayOf('\u03A3'), "wrong-unicode")
    val unicodeOther: CharSequence = IndexedSequence(charArrayOf('\u03C3'), "wrong-unicode-other")
    report("unicode-case", unicodeCase.regionMatches(0, unicodeOther, 0, 1, true))

    report("negative-length", target.regionMatches(0, other, 0, -1))
    report("negative-this", target.regionMatches(-1, other, 0, 1))
    report("negative-other", target.regionMatches(0, other, -1, 1))
    report("past-this", target.regionMatches(5, other, 0, 1))
    report("past-other", target.regionMatches(0, other, 5, 1))
    report("max-length", target.regionMatches(0, other, 0, Int.MAX_VALUE))
    report("max-this", target.regionMatches(Int.MAX_VALUE, other, 0, 0))
    report("min-length", target.regionMatches(0, other, 0, Int.MIN_VALUE))

    val shortTarget = IndexedSequence(charArrayOf('x'), "wrong-short-target")
    val shortOther = IndexedSequence(charArrayOf('x'), "wrong-short-other")
    report("negative-short", shortTarget.regionMatches(-1, shortOther, 0, 1))
    println(
        "negative-short-counters=" +
            "${shortTarget.lengthReads},${shortOther.lengthReads}," +
            "${shortTarget.getReads},${shortOther.getReads}"
    )

    val boundsTarget = IndexedSequence(charArrayOf('x'), "wrong-bounds-target")
    val boundsOther = IndexedSequence(charArrayOf('x'), "wrong-bounds-other")
    report("bounds-short", boundsTarget.regionMatches(Int.MAX_VALUE, boundsOther, 0, 1))
    println(
        "bounds-short-counters=" +
            "${boundsTarget.lengthReads},${boundsOther.lengthReads}," +
            "${boundsTarget.getReads},${boundsOther.getReads}"
    )

    val mismatchTarget = IndexedSequence(charArrayOf('x', 'b'), "wrong-mismatch-target")
    val mismatchOther = IndexedSequence(charArrayOf('y', 'b'), "wrong-mismatch-other")
    report("mismatch-short", mismatchTarget.regionMatches(0, mismatchOther, 0, 2))
    println(
        "mismatch-short-counters=" +
            "${mismatchTarget.lengthReads},${mismatchOther.lengthReads}," +
            "${mismatchTarget.getReads},${mismatchOther.getReads}"
    )
}
