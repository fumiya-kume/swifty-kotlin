private class RecordingCharSequence(private val value: String) : CharSequence {
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

fun main() {
    val custom: CharSequence = RecordingCharSequence("abc")
    println("short-start=${custom.padStart(2, '0')}")
    println("long-start=${custom.padStart(5, '0')}")
    println("short-end=${custom.padEnd(2, '0')}")
    println("long-end=${custom.padEnd(5, '0')}")
    println("default-start=${custom.padStart(5)}")
    println("default-end=${custom.padEnd(5)}")
    println("custom-toString=${custom.toString()}")

    val builder: CharSequence = StringBuilder("abc")
    println("builder-short=${builder.padStart(2, '0')}")
    println("builder-long=${builder.padEnd(5, '0')}")

    println("string-start=${"abc".padStart(5, '0')}")
    println("string-end=${"abc".padEnd(5, '0')}")
    println("string-default=${"abc".padStart(5)}")

    try {
        custom.padStart(-1)
        println("negative-start-missed")
    } catch (e: IllegalArgumentException) {
        println("negative-start=${e.message}")
    }
    try {
        custom.padEnd(-2)
        println("negative-end-missed")
    } catch (e: IllegalArgumentException) {
        println("negative-end=${e.message}")
    }

    val utf16: CharSequence = RecordingCharSequence("🥦")
    println("utf16=${utf16.padStart(3, '0').length}:${utf16.padEnd(3, '0').length}")
}
