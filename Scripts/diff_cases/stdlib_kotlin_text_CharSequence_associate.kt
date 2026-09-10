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

private fun associateNonLocal(source: CharSequence): String {
    source.associate {
        if (it == '!') return "!"
        it to 1
    }
    return "?"
}

fun main() {
    val source: CharSequence = "abca"
    var associateCalls = 0
    val associated = source.associate { ch ->
        associateCalls++
        ch to if (ch == 'a') 1 else 2
    }
    println(associated)
    println(associated['a'])
    println(associated['b'])
    println(associateCalls)
    println(source.associateBy { ch -> if (ch == 'a') 0 else 1 })
    println(source.associateBy(
        { ch -> if (ch == 'a') 0 else 1 },
        { ch -> if (ch == 'a') "A" else "other" }
    ))

    val associateToDestination = mutableMapOf<Char, Int>()
    println(source.associateTo(associateToDestination) { ch -> ch to 1 })

    val associateByToDestination = mutableMapOf<Int, Char>()
    println(source.associateByTo(associateByToDestination) { ch -> if (ch == 'a') 0 else 1 })

    val associateByToTransformDestination = mutableMapOf<Int, String>()
    println(source.associateByTo(
        associateByToTransformDestination,
        { ch -> if (ch == 'a') 0 else 1 },
        { ch -> if (ch == 'a') "A" else "other" }
    ))

    var associateWithCalls = 0
    println(source.associateWith { ch ->
        associateWithCalls++
        if (ch == 'a') 1 else 2
    })
    println(associateWithCalls)
    val associateWithToDestination = mutableMapOf<Char, Int>()
    println(source.associateWithTo(associateWithToDestination) { ch -> if (ch == 'a') 1 else 2 })

    val builder: CharSequence = StringBuilder("xyx")
    println(builder.associateBy { ch -> ch })

    val custom = TrackingCharSequence("abca")
    println(custom.associateWith { ch -> ch.toString() })
    println(custom.lengthReads)

    val empty: CharSequence = ""
    println(empty.associate { ch -> ch to 1 })
    println(empty.associateBy { ch -> ch })
    println(empty.associateWith { ch -> ch.toString() })
    val emptyDestination = mutableMapOf<Char, Int>()
    println(empty.associateTo(emptyDestination) { ch -> ch to 1 })
    println(emptyDestination.size)

    println(associateNonLocal("ab"))
    println(associateNonLocal("!a"))
}
