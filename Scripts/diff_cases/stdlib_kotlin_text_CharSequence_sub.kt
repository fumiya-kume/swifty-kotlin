private class RecordingCharSequence(private val value: String) : CharSequence {
    override val length: Int
        get() = value.length

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        println("member:$startIndex:$endIndex")
        return value.substring(startIndex, endIndex)
    }

    override fun toString(): String = "wrong-toString"
}

private class PlainSequence(private val value: String) : CharSequence {
    override val length: Int
        get() = value.length

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        return value.substring(startIndex, endIndex)
    }
}

private fun describe(label: String, value: CharSequence) {
    println("$label=${value.toString()}")
}

private fun failure(label: String, block: () -> Unit) {
    try {
        block()
        println("$label=missing")
    } catch (e: IndexOutOfBoundsException) {
        println("$label=IndexOutOfBoundsException")
    }
}

fun main() {
    val custom: CharSequence = RecordingCharSequence("abcdef")
    describe("custom-head", custom.subSequence(1..3))
    describe("custom-empty", custom.subSequence(3 until 3))
    describe("custom-tail", custom.subSequence(4..5))

    val string: CharSequence = "🥦ab"
    describe("string-full", string.subSequence(0..3))
    describe("string-empty", string.subSequence(2 until 2))

    val builder: CharSequence = StringBuilder("abcdef")
    describe("builder-middle", builder.subSequence(2..4))

    val concreteBuilder = StringBuilder("abcdef")
    describe("builder-concrete", concreteBuilder.subSequence(0..1))

    val plain = PlainSequence("abcdef")
    describe("plain-range", plain.subSequence(0..1))

    failure("reversed", { custom.subSequence(3..1) })
    failure("negative", { custom.subSequence(-1..0) })
    failure("past-end", { custom.subSequence(0..6) })
    failure("overflow", { custom.subSequence(Int.MAX_VALUE..Int.MAX_VALUE) })
}
