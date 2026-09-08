private class TrackingCharSequence(private val value: String) : CharSequence {
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

private fun groupNonLocal(source: CharSequence): String {
    source.groupBy { ch ->
        if (ch == '!') return "!"
        0
    }
    return "?"
}

fun main() {
    val source: CharSequence = "abca"
    var groupCalls = 0
    val grouped = source.groupBy { ch ->
        groupCalls++
        if (ch == 'a') 0 else 1
    }
    println(grouped)
    println(grouped[0]!!.size)
    println(grouped[0]!![1])
    println(groupCalls)

    println(source.groupBy(
        { ch -> if (ch == 'a') 0 else 1 },
        { ch -> if (ch == 'a') "A" else ch.toString() }
    ))

    val groupByToDestination = mutableMapOf<Int, MutableList<Char>>()
    groupByToDestination[0] = mutableListOf('z')
    println(source.groupByTo(groupByToDestination) { ch -> if (ch == 'a') 0 else 1 })

    val groupByToTransformDestination = mutableMapOf<Int, MutableList<String>>()
    groupByToTransformDestination[0] = mutableListOf("z")
    println(source.groupByTo(
        groupByToTransformDestination,
        { ch -> if (ch == 'a') 0 else 1 },
        { ch -> if (ch == 'a') "A" else ch.toString() }
    ))

    val builder: CharSequence = StringBuilder("xyx")
    println(builder.groupBy { ch -> if (ch == 'x') 0 else 1 })

    val custom = TrackingCharSequence("abca")
    println(custom.groupBy { ch -> if (ch == 'a') 0 else 1 })
    println(custom.lengthReads)

    val empty: CharSequence = ""
    println(empty.groupBy { ch -> ch })
    val emptyDestination = mutableMapOf<Int, MutableList<Char>>()
    println(empty.groupByTo(emptyDestination) { ch -> ch.code })

    println(groupNonLocal("ab"))
    println(groupNonLocal("!a"))
}
