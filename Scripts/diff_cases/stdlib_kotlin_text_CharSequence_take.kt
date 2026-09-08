private class RecordingCharSequence(var value: String) : CharSequence {
    override val length: Int
        get() {
            println("length")
            return value.length
        }

    override fun get(index: Int): Char {
        println("get:$index")
        return value[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        println("subSequence:$startIndex:$endIndex")
        return value.substring(startIndex, endIndex)
    }

    override fun toString(): String {
        println("toString")
        return value
    }
}

private fun charCodes(value: CharSequence): String {
    var result = ""
    var index = 0
    while (index < value.length) {
        if (index > 0) result += ","
        result += value[index].code.toString()
        index++
    }
    return result
}

private fun show(label: String, value: CharSequence) {
    println("$label=$value")
}

private fun directTakeWhileReturn(source: CharSequence): Int {
    source.takeWhile { return 17 }
    return -1
}

private fun safeTakeLastWhileReturn(source: CharSequence?): Int {
    source?.takeLastWhile { return 18 }
    return -1
}

private fun capturedTakeWhileReturn(source: CharSequence, expected: Char): Int {
    source.takeWhile {
        if (it == expected) return 19
        false
    }
    return -1
}

fun main() {
    val custom: CharSequence = RecordingCharSequence("abc")
    show("take0", custom.take(0))
    show("takeNamed", custom.take(n = 1))
    show("take1", custom.take(1))
    show("takeMax", custom.take(Int.MAX_VALUE))
    show("takeLast0", custom.takeLast(0))
    show("takeLastNamed", custom.takeLast(n = 1))
    show("takeLast1", custom.takeLast(1))
    show("takeLastMax", custom.takeLast(Int.MAX_VALUE))
    show("takeWhile", custom.takeWhile { it < 'c' })
    show("takeLastWhile", custom.takeLastWhile { it > 'a' })
    show("takeWhileAll", custom.takeWhile { true })
    show("takeLastWhileAll", custom.takeLastWhile { true })
    println("nonLocal-direct=${directTakeWhileReturn(custom)}")
    println("nonLocal-safe=${safeTakeLastWhileReturn(custom)}")
    println("nonLocal-captured=${capturedTakeWhileReturn(custom, 'b')}")

    try {
        custom.take(-1)
        println("takeNegative-missed")
    } catch (e: IllegalArgumentException) {
        println("takeNegative=${e.message}")
    }
    try {
        custom.takeLast(-2)
        println("takeLastNegative-missed")
    } catch (e: IllegalArgumentException) {
        println("takeLastNegative=${e.message}")
    }

    val mutable = RecordingCharSequence("abc")
    show("mutable-first", mutable.take(1))
    mutable.value = "abcdef"
    show("mutable-second", mutable.takeLast(2))

    val utf16: CharSequence = RecordingCharSequence("🥦abc")
    val utf16Take = utf16.take(5)
    val utf16TakeLast = utf16.takeLast(5)
    val utf16TakeWhile = utf16.takeWhile { true }
    val utf16TakeLastWhile = utf16.takeLastWhile { false }
    println("utf16-take=$utf16Take:${charCodes(utf16Take)}")
    println("utf16-takeLast=$utf16TakeLast:${charCodes(utf16TakeLast)}")
    println("utf16-takeWhile=$utf16TakeWhile:${charCodes(utf16TakeWhile)}")
    println("utf16-takeLastWhile=$utf16TakeLastWhile:${charCodes(utf16TakeLastWhile)}")

    val builder: CharSequence = StringBuilder("🥦abc")
    println("builder-take=${builder.take(5)}:${charCodes(builder.take(5))}")
    println("builder-takeLast=${builder.takeLast(5)}:${charCodes(builder.takeLast(5))}")
    println("string-take=${"🥦abc".take(2)}")
    println("string-takeLast=${"🥦abc".takeLast(3)}")
    println("string-takeWhile=${"🥦abc".takeWhile { true }}")
}
