private class CountingCharSequence(private val value: String) : CharSequence {
    var lengthReads: Int = 0

    override val length: Int
        get() {
            lengthReads++
            return value.length
        }

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

private fun describe(label: String, value: CharSequence) {
    val range = value.indices
    println(label + ":" + range.first + "," + range.last + "," + range.isEmpty())
}

fun main() {
    describe("string", "A😀B")
    describe("stringBuilder", StringBuilder("A😀B"))
    describe("empty", "")

    val custom = CountingCharSequence("abc")
    val customRange = custom.indices
    println("custom:" + customRange.first + "," + customRange.last + "," + customRange.isEmpty() + ",reads=" + custom.lengthReads)
}
