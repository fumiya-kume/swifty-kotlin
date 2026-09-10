package golden.sema

fun charSequenceCount(source: CharSequence): Int = source.count()

fun stringCount(): Int = "A😀".count()

fun stringBuilderCount(): Int = StringBuilder("A😀").count()

fun emptyCount(): Int = "".count()

class CountingCharSequence(private val value: String) : CharSequence {
    var lengthReads: Int = 0

    override val length: Int
        get() {
            lengthReads++
            return value.length
        }

    override operator fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

fun customCount(source: CountingCharSequence): Int = source.count()
