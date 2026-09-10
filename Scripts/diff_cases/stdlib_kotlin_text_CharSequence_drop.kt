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

fun main() {
    val custom: CharSequence = RecordingCharSequence("abc")
    show("drop0", custom.drop(0))
    show("dropNamed", custom.drop(n = 1))
    show("drop1", custom.drop(1))
    show("dropMax", custom.drop(Int.MAX_VALUE))
    show("dropLast0", custom.dropLast(0))
    show("dropLast1", custom.dropLast(1))
    show("dropLastMax", custom.dropLast(Int.MAX_VALUE))
    show("dropWhile", custom.dropWhile { it < 'b' })
    show("dropLastWhile", custom.dropLastWhile { it > 'a' })
    show("dropWhileAll", custom.dropWhile { true })
    show("dropLastWhileAll", custom.dropLastWhile { true })

    try {
        custom.drop(-1)
        println("dropNegative-missed")
    } catch (e: IllegalArgumentException) {
        println("dropNegative=${e.message}")
    }
    try {
        custom.dropLast(-2)
        println("dropLastNegative-missed")
    } catch (e: IllegalArgumentException) {
        println("dropLastNegative=${e.message}")
    }

    val mutable = RecordingCharSequence("abc")
    show("mutable-first", mutable.drop(1))
    mutable.value = "abcdef"
    show("mutable-second", mutable.dropLast(2))

    val utf16: CharSequence = RecordingCharSequence("🥦abc")
    val utf16Drop = utf16.drop(0)
    val utf16DropLast = utf16.dropLast(0)
    val utf16DropWhile = utf16.dropWhile { false }
    val utf16DropLastWhile = utf16.dropLastWhile { false }
    println("utf16-drop=$utf16Drop:${charCodes(utf16Drop)}")
    println("utf16-dropLast=$utf16DropLast:${charCodes(utf16DropLast)}")
    println("utf16-dropWhile=$utf16DropWhile:${charCodes(utf16DropWhile)}")
    println("utf16-dropLastWhile=$utf16DropLastWhile:${charCodes(utf16DropLastWhile)}")

    val builder: CharSequence = StringBuilder("🥦abc")
    println("builder-drop=${builder.drop(0)}:${charCodes(builder.drop(0))}")
    println("builder-dropLast=${builder.dropLast(0)}:${charCodes(builder.dropLast(0))}")
    println("string-drop=${"🥦abc".drop(2)}")
    println("string-dropLast=${"🥦abc".dropLast(2)}")
    println("string-dropWhile=${"🥦abc".dropWhile { false }}")
}
