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
        charArrayOf('B', 'c'),
        "wrong-other"
    )

    report("sequence", target.contains(other))
    report("sequence-case", target.contains("bC", ignoreCase = true))
    report("sequence-named", target.contains(other = other, ignoreCase = true))
    report("sequence-operator", other in target)
    report("char", target.contains('B'))
    report("char-miss", target.contains('b'))
    report("char-case", target.contains('b', ignoreCase = true))
    report("char-named", target.contains(char = 'C', ignoreCase = true))
    report("char-operator", 'B' in target)

    val regexTarget: CharSequence = IndexedSequence(
        charArrayOf('a', 'B', 'c', 'x', 'x'),
        "wrong-regex-target"
    )
    report("regex", regexTarget.contains(Regex("Bcx+")))
    report("regex-named", regexTarget.contains(regex = Regex("Bcx+")))
    report("regex-operator", Regex("Bcx+") in regexTarget)
    report("string-regex", "abc123".contains(Regex("\\d+")))
    val stringAsCharSequence: CharSequence = "abc123"
    report("string-sequence-regex", stringAsCharSequence.contains(Regex("\\d+")))

    val builder: CharSequence = StringBuilder("Abc😀")
    report("builder-sequence", builder.contains("BC😀", ignoreCase = true))
    report("builder-char", builder.contains('b', ignoreCase = true))

    val surrogate: CharSequence = IndexedSequence(
        charArrayOf('A', '\uD83D', '\uDE00', 'B'),
        "wrong-surrogate"
    )
    report("surrogate", surrogate.contains("😀"))
    report("surrogate-unit", surrogate.contains('\uD83D'))

    val empty: CharSequence = IndexedSequence(charArrayOf(), "wrong-empty")
    report("empty-needle", empty.contains(""))
    report("empty-char", empty.contains('x'))
    report("short", target.contains("too-long"))

    val shortTarget = IndexedSequence(charArrayOf('x'), "wrong-short-target")
    val shortOther = IndexedSequence(charArrayOf('x', 'y'), "wrong-short-other")
    report("short-circuit", shortTarget.contains(shortOther))
    println("short-circuit-gets=${shortTarget.getReads},${shortOther.getReads}")

    val mismatchTarget = IndexedSequence(charArrayOf('x', 'b'), "wrong-mismatch-target")
    val mismatchOther = IndexedSequence(charArrayOf('y', 'b'), "wrong-mismatch-other")
    report("mismatch", mismatchTarget.contains(mismatchOther))
    println("mismatch-gets=${mismatchTarget.getReads},${mismatchOther.getReads}")
}
