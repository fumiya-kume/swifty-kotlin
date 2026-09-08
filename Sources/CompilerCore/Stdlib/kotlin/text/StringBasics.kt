package kotlin.text

public fun String.repeat(count: Int): String {
    if (count < 0) throw IllegalArgumentException("Count 'n' must be non-negative, but was $count.")
    val sb = StringBuilder()
    var i = 0
    while (i < count) { sb.append(this); i += 1 }
    return sb.toString()
}

public fun CharSequence.repeat(n: Int): String {
    if (n < 0) throw IllegalArgumentException("Count 'n' must be non-negative, but was $n.")

    return when (n) {
        0 -> ""
        1 -> this.toString()
        else -> {
            when (length) {
                0 -> ""
                1 -> {
                    val char = this[0]
                    val sb = StringBuilder(n)
                    var i = 0
                    while (i < n) {
                        sb.append(char)
                        i += 1
                    }
                    sb.toString()
                }
                else -> {
                    val sb = StringBuilder(n * length)
                    var i = 1
                    while (i <= n) {
                        sb.append(this)
                        i += 1
                    }
                    sb.toString()
                }
            }
        }
    }
}

public fun String.reversed(): String {
    val len = this.length
    val sb = StringBuilder()
    var i = len - 1
    while (i >= 0) { sb.append(this[i]); i -= 1 }
    return sb.toString()
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
