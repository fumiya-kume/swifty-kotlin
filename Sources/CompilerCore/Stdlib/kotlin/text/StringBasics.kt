package kotlin.text

public fun String.repeat(count: Int): String {
    if (count < 0) throw IllegalArgumentException("Count 'n' must be non-negative, but was $count.")
    val sb = StringBuilder()
    var i = 0
    while (i < count) { sb.append(this); i += 1 }
    return sb.toString()
}

public fun String.reversed(): String {
    val len = this.length
    val sb = StringBuilder()
    var i = len - 1
    while (i >= 0) { sb.append(this[i]); i -= 1 }
    return sb.toString()
}

public fun CharSequence.reversed(): CharSequence {
    val source = StringBuilder(this.length)
    source.append(this)
    val content = source.toString()
    val sb = StringBuilder()
    var i = content.length - 1
    while (i >= 0) {
        val current = content[i]
        if (i > 0 && (current.isLowSurrogate() || current.isHighSurrogate())) {
            val previous = content[i - 1]
            if (current.isLowSurrogate() && previous.isHighSurrogate()) {
                val pair = CharArray(2)
                pair[0] = previous
                pair[1] = current
                sb.append(pair)
                i -= 2
                continue
            } else if (current.isHighSurrogate() && previous.isLowSurrogate()) {
                val pair = CharArray(2)
                pair[0] = current
                pair[1] = previous
                sb.append(pair)
                i -= 2
                continue
            }
        }
        sb.append(current)
        i -= 1
    }
    return sb
}

public fun String.padStart(length: Int, padChar: Char = ' '): String {
    val padding = length - this.length
    if (padding <= 0) return this
    val sb = StringBuilder()
    var i = 0
    while (i < padding) { sb.append(padChar); i += 1 }
    sb.append(this)
    return sb.toString()
}

public fun String.padEnd(length: Int, padChar: Char = ' '): String {
    val padding = length - this.length
    if (padding <= 0) return this
    val sb = StringBuilder()
    sb.append(this)
    var i = 0
    while (i < padding) { sb.append(padChar); i += 1 }
    return sb.toString()
}
