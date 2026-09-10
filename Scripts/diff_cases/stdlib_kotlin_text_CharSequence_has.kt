private class CountingCharSequence(private val value: String) : CharSequence {
    var lengthReads = 0
    var indexReads = 0

    override val length: Int
        get() {
            lengthReads += 1
            return value.length
        }

    override fun get(index: Int): Char {
        indexReads += 1
        return value[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)

    override fun toString(): String = "different display"
}

private fun printReads(sequence: CountingCharSequence) {
    println("${sequence.lengthReads}:${sequence.indexReads}")
}

fun main() {
    val pair = "\uD83D\uDE00"
    val pairAtLast = "a$pair"
    val high = "\uD83D"
    val low = "\uDE00"
    val reversed = "\uDE00\uD83D"

    // Valid pairs and ordinary character boundaries.
    println(pair.hasSurrogatePairAt(0))
    println(pairAtLast.hasSurrogatePairAt(1))
    println(pairAtLast.hasSurrogatePairAt(0))

    // Lone, reversed, empty, and out-of-range indices must be false.
    println(high.hasSurrogatePairAt(0))
    println(low.hasSurrogatePairAt(0))
    println(reversed.hasSurrogatePairAt(0))
    println("".hasSurrogatePairAt(0))
    println(pair.hasSurrogatePairAt(-1))
    println(pair.hasSurrogatePairAt(Int.MAX_VALUE))
    println(pair.hasSurrogatePairAt(1))

    // Interface dispatch must use indexed access rather than toString().
    val builder: CharSequence = StringBuilder(pair)
    println(builder.hasSurrogatePairAt(0))

    val custom = CountingCharSequence(pair)
    println(custom.hasSurrogatePairAt(0))
    printReads(custom)

    custom.lengthReads = 0
    custom.indexReads = 0
    println(custom.hasSurrogatePairAt(-1))
    printReads(custom)

    custom.lengthReads = 0
    custom.indexReads = 0
    println(custom.hasSurrogatePairAt(Int.MAX_VALUE))
    printReads(custom)
}
