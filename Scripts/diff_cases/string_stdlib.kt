fun main() {
    // trim
    println("  hello  ".trim())
    println("".trim())
    println("   ".trim())

    // startsWith / endsWith
    println("hello world".startsWith("hello"))
    println("hello world".endsWith("world"))
    println("hello world".startsWith("world"))
    println("hello world".endsWith("hello"))

    // contains
    println("hello world".contains("lo wo"))
    println("hello world".contains("xyz"))
    println("hello world".contains(""))

    // replace
    println("hello world".replace("world", "kotlin"))
    println("aaa".replace("a", "bb"))
    println("ababa".replace("aba", "x"))

    // toInt
    println("42".toInt())
    println("-123".toInt())
    println("0".toInt())

    // toDouble
    println("3.14".toDouble())
    println("-0.5".toDouble())
    println("42.0".toDouble())

    // format
    println("%s:%d".format("age", 7))
    println("%.2f".format(3.5))
    println("progress=100%%".format())
}
